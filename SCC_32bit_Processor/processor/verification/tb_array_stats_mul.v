
`timescale 1ns/1ps
// tb_array_stats_mul.v
//
// SCC CP4 meaningful-program integration testbench.
//
// Executes array_stats_mul.asm through the complete processor.
//
// Verifies:
// - Array sum, minimum, maximum, and even count
// - Position-weighted checksum using microcoded MUL
// - Eight low-word and eight high-word MUL writebacks
// - Correct R12 upper-product result

module tb_array_stats_mul;

    localparam [31:0] RESULT_BASE = 32'h0000_D640;
    localparam integer TIMEOUT_NS = 100000;

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer check_count;
    integer test_errors;
    integer low_write_count;
    integer high_write_count;
    integer cycle_count;

    //===================
    // COMPLETE PROCESSOR
    //====================

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
    //====================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //==============
    // CHECK TASKS
    //==============

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] description;
        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s expected=%08h actual=%08h",
                         description, expected, actual);
                test_errors = test_errors + 1;
            end else begin
                $display("PASS: %0s = %08h",
                         description, actual);
            end
        end
    endtask

    // Read a 32-bit big-endian word from the actual
    // byte-addressed class memory model

    task check_result;
        input integer index;
        input [31:0] expected;
        input [8*48-1:0] description;

        integer address;
        reg [31:0] actual;

        begin
            address = RESULT_BASE + (index * 4);

            actual = {
                DUT.memory.memory[address],
                DUT.memory.memory[address + 1],
                DUT.memory.memory[address + 2],
                DUT.memory.memory[address + 3]
            };

            check_word(actual, expected, description);
        end
    endtask

    //===================
    // EXECUTION MONITORS
    //=====================

    always @(posedge clk) begin
        if (rst)
            cycle_count = 0;
        else if (clk_en)
            cycle_count = cycle_count + 1;
    end

    // Count the actual rising-clock-edge write requests.
    // R10 receives the low result and R12 the upper result

    always @(posedge clk) begin
        if (!rst && clk_en && DUT.scc.ucode_reg_write_en) begin

            if (DUT.scc.ucode_stall !== 1'b1) begin
                $display("FAIL: MUL write without instruction stall");
                test_errors = test_errors + 1;
            end

            if (DUT.scc.ucode_reg_write_addr_v == 4'd10)
                low_write_count = low_write_count + 1;
            else if (DUT.scc.ucode_reg_write_addr_v == 4'd12)
                high_write_count = high_write_count + 1;
            else begin
                $display("FAIL: Unexpected MUL destination R%0d", DUT.scc.ucode_reg_write_addr_v);
                test_errors = test_errors + 1;
            end
        end
    end

    //=====================
    // MAIN TEST SEQUENCE
    //======================

    initial begin
        $dumpfile("tb_array_stats_mul.vcd");
        $dumpvars(0, tb_array_stats_mul);

        rst = 1'b1;
        clk_en = 1'b1;

        check_count = 0;
        test_errors = 0;
        low_write_count = 0;
        high_write_count = 0;
        cycle_count = 0;

        $display("");
        $display("========================================");
        $display("SCC CP4 ARRAY STATISTICS VERIFICATION");
        $display("========================================");

        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        // Wait for the architectural HALT instruction
        @(posedge halt_f);
        #2;

        //======================
        // FINAL MEMORY RESULTS
        //=======================

        check_result(0, 32'd40,  "Array sum");
        check_result(1, 32'd1,   "Array minimum");
        check_result(2, 32'd9,   "Array maximum");
        check_result(3, 32'd4,   "Even element count");
        check_result(4, 32'd172, "Weighted checksum");

        //==========================
        // MULTIPLICATION COVERAGE
        //============================

        check_word(low_write_count,  32'd8, "MUL low-word write count");

        check_word(high_write_count, 32'd8, "MUL upper-word write count");

        check_word(DUT.scc.REGS.registers[12], 32'd0, "Final upper product R12");

        check_word(DUT.scc.REGS.registers[9], 32'd172, "Checksum register R9");

        //====================
        // COMPLETION CHECKS
        //===================

        check_word(DUT.scc.pc_v, 32'h0000_0094, "Final HALT PC");

        check_word({30'd0, err_f}, 32'd1, "Processor HALT status");

        //==============
        // FINAL RESULTS
        //===============

        $display("");
        $display("========================================");
        $display("ARRAY STATISTICS FINAL RESULTS");
        $display("========================================");

        $display("HALT time           = %0t", $time);
        $display("Clock cycles        = %0d", cycle_count);
        $display("MUL low writes      = %0d", low_write_count);
        $display("MUL high writes     = %0d", high_write_count);
        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0)
            $display("ARRAY STATISTICS TEST PASSED");
        else
            $display("ARRAY STATISTICS TEST FAILED");

        $display("========================================");
        $finish;
    end

    //================
    // ERROR MONITOR
    //==================

    always @(posedge clk) begin
        if (!rst && err_f === 2'b10) begin
            $display("FAIL: Illegal instruction at PC=%08h",
                     DUT.scc.pc_v);
            $finish;
        end
    end

    //=========
    // TIMEOUT
    //=========

    initial begin
        #TIMEOUT_NS;

        $display("FAIL: Array statistics simulation timeout");
        $display("PC=%08h instruction=%08h",
                 DUT.scc.pc_v, inst_mem_v);
        $display("MUL low=%0d high=%0d",
                 low_write_count, high_write_count);

        $finish;
    end

endmodule
