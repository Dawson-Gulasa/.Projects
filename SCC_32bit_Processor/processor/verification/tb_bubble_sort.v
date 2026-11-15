
`timescale 1ns/1ps
// tb_bubble_sort.v
// Self-checking integration testbench for SCC CP4 bubble sort.
// Uses the class BubbleSort.asm program assembled into output.mem
//
// Verifies:
// - The processor reaches HALT without an illegal instruction
// - All ten array elements are sorted in ascending order
// - The final array contains the expected values 1 through 10
// - Memory accesses do not exceed the simulation timeout
// - Store activity occurs during the sort
//
// Array location: 0x0000D500
// Array length: 10 words (32 bits per word)

module tb_bubble_sort;

    //================
    // TEST CONSTANTS
    //================

    localparam [31:0] ARRAY_BASE = 32'h0000_D500;
    localparam integer ARRAY_LENGTH = 10;
    localparam integer TIMEOUT_NS = 100000;

    localparam [1:0] STATUS_HALT  = 2'b01;
    localparam [1:0] STATUS_ERROR = 2'b10;

    //==================
    // TESTBENCH SIGNALS
    //=================

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    //=======================
    // VERIFICATION COUNTERS
    //========================

    integer test_errors;
    integer check_count;
    integer write_count;
    integer cycle_count;
    integer i;

    //=====================
    // DEVICE UNDER TEST
    //=====================

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),

        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    //==================
    // CLOCK GENERATION
    //=================
    // 10 ns clock period

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //==============================
    // STORE INSTRUCTION MONITOR
    //============================
    // Count each STOR instruction issued by the processor
    //
    // The memory-write controller samples the decoded store
    // request on the falling clock edge. Two consecutive STOR
    // instructions can keep data_mem_wr_en continuously high,
    // producing only one rising edge on the write-enable signal.
    //
    // Counting the decoded request once per falling clock edge
    // correctly distinguishes consecutive STOR instructions.
    //
    // This counter measures issued store instructions, while
    // the final memory checks verify their functional results

    always @(negedge clk) begin
        if (!rst && clk_en && DUT.scc.data_mem_wr_request) begin
            write_count = write_count + 1;
        end
    end

    //================
    // CYCLE MONITOR
    //==============

    always @(posedge clk) begin
        if (rst) begin
            cycle_count = 0;
        end else if (clk_en)
            cycle_count = cycle_count + 1;
    end

    //==================
    // MEMORY CHECK TASK
    //===================
    // Reconstruct a 32-bit word from four consecutive bytes in the class 
    // memory model
    //
    // The class memory stores words in big-endian order

    task check_array_word;
        input integer index;
        input [31:0] expected;

        integer address;
        reg [31:0] actual;

        begin
            address = ARRAY_BASE + (index * 4);

            actual = {
                DUT.memory.memory[address],
                DUT.memory.memory[address + 1],
                DUT.memory.memory[address + 2],
                DUT.memory.memory[address + 3]
            };

            check_count = check_count + 1;

            if (actual !== expected) begin
                $display(
                    "FAIL: Array[%0d] address=0x%08h expected=%08h actual=%08h", index, address, expected, actual
                );

                test_errors = test_errors + 1;
            end else begin
                $display(
                    "PASS: Array[%0d] address=0x%08h value=%08h", index, address, actual
                );
            end
        end
    endtask

    //===============
    // TEST SEQUENCE
    //==============

    initial begin
        $dumpfile("cp4_bubble_sort.vcd");
        $dumpvars(0, tb_bubble_sort);

        clk_en = 1'b1;
        rst = 1'b1;

        test_errors = 0;
        check_count = 0;
        write_count = 0;
        cycle_count = 0;

        $display("");
        $display("========================================");
        $display("SCC CP4 BUBBLE SORT VERIFICATION");
        $display("========================================");

        // Hold reset for three rising clock edges
        repeat (3) @(posedge clk);

        // Release reset away from the rising edge
        @(negedge clk);
        rst = 1'b0;

        // Wait for the program to finish
        @(posedge halt_f);

        // Allow final combinational/memory events to settle
        #1;

        //===============
        // STATUS CHECK
        //==============

        check_count = check_count + 1;

        if (err_f !== STATUS_HALT) begin
            $display("FAIL: Expected HALT status 01");
            test_errors = test_errors + 1;
        end else begin
            $display("PASS: Processor reached HALT");
        end

        //===================
        // SORTED ARRAY CHECK
        //====================
        // Expected ascending values: 1 through 10

        for (i = 0; i < ARRAY_LENGTH; i = i + 1) begin
            check_array_word(i, i + 1);
        end

        //========================
        // MEMORY WRITE CHECK
        //======================
        // The initial array contains 16 inversions
        // Bubble sort performs one adjacent swap per inversion.
        // Each swap executes two consecutive STOR instructions.
        //
        // Expected store instructions = 16 swaps * 2 = 32.
        //
        // The memory-content checks above independently verify that the 
        // array was correctly updated

        check_count = check_count + 1;

        if (write_count != 32) begin
            $display(
                "FAIL: Expected 32 STOR instructions, observed %0d", write_count
            );
            test_errors = test_errors + 1;
        end else begin
            $display("PASS: 32 STOR instructions executed");
        end

        //===============
        // FINAL RESULTS
        //============

        $display("");
        $display("========================================");
        $display("CP4 BUBBLE SORT FINAL RESULTS");
        $display("========================================");

        $display("HALT time           = %0t", $time);
        $display("Clock cycles        = %0d", cycle_count);
        $display("STOR instructions   = %0d", write_count);
        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);
        $display("Error status        = %02b", err_f);

        if (test_errors == 0) begin
            $display("========================================");
            $display("CP4 BUBBLE SORT TEST PASSED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("CP4 BUBBLE SORT TEST FAILED");
            $display("========================================");
        end

        $finish;
    end

    //====================
    // ERROR MONITOR
    //================
    // Detect an illegal instruction immediately rather than
    // waiting for a HALT that may never occur

    always @(posedge clk) begin
        if (!rst && err_f === STATUS_ERROR) begin
            $display("");
            $display("FAIL: Processor encountered an illegal instruction");
            $display("PC = 0x%08h", DUT.scc.pc_v);
            $display("Instruction = 0x%08h", inst_mem_v);
            $finish;
        end
    end

    //======================
    // SIMULATION TIMEOUT
    //====================
    // Protect against infinite loops, stuck branches,
    // and failure to reach HALT

    initial begin
        #TIMEOUT_NS;

        $display("");
        $display("FAIL: Bubble sort simulation timeout");
        $display("PC = 0x%08h", DUT.scc.pc_v);
        $display("Instruction = 0x%08h", inst_mem_v);
        $display("Cycles executed = %0d", cycle_count);
        $finish;
    end

endmodule
