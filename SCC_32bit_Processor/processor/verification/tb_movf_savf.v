`timescale 1ns/1ps
// tb_movf_savf.v
// SCC CP5 top-level MOVF/SAVF integration verification.
//
// Responsibilities:
// - Execute movf_savf.asm on the complete SCC.
// - Check that the processor reaches normal HALT.
// - Read the standard memory dump produced on HALT.
// - Verify that both flag snapshots match the ISA.
// - Report PASS only when all expected results match.
// - Detect a timeout if execution fails to terminate.
//
// Portability:
// - Instantiates scc_f26_top using public class ports.
// - Does not access private SCC register names.
// - Does not access private flag or microcode signals.
// - Uses scc_out.txt as the observable result.
//
// The standard Instruction_and_data.v memory model
// creates scc_out.txt when HALT is asserted.

module tb_movf_savf;

    //============================
    // EXPECTED PROGRAM RESULTS
    //===========================

    localparam [31:0] RESULT_ADDR_0 = 32'h0000_D700;
    localparam [31:0] RESULT_ADDR_1 = 32'h0000_D704;

    localparam [31:0] EXPECTED_0 = 32'h0000_0015;
    localparam [31:0] EXPECTED_1 = 32'h0000_000A;

    localparam integer TIMEOUT_NS = 20000;

    //===================
    // SYSTEM SIGNALS
    //=================

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    //===================
    // TESTBOOK STATE
    //=================

    integer test_count;
    integer test_errors;
    integer cycle_count;

    integer dump_file;
    integer scan_result;

    reg [8*128-1:0] header_line;

    reg [31:0] scanned_addr;
    reg [31:0] scanned_data;

    reg found_result_0;
    reg found_result_1;

    reg [31:0] actual_result_0;
    reg [31:0] actual_result_1;

    //========================================
    // CAPTURED ARCHITECTURAL HALT STATUS
    //========================================
    // err_f is generated combinationally from
    // the instruction currently being decoded.
    //
    // Capture the status when HALT is detected
    // so that a later PC update cannot change
    // the value used for verification.
    //
    // This is testbench-only storage and does
    // not introduce any processor state

    reg [1:0] status_at_halt;

    //===========================
    // COMPLETE SCC INSTANCE
    //=========================
    // Only class-standard top-level ports are used.

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),
        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    //====================
    // CLOCK GENERATION
    //=====================
    // A 10 ns clock period supplies the SCC

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //===========================
    // EXECUTION CYCLE COUNTER
    //=========================
    // Count enabled rising edges after reset.
    //
    // This is diagnostic information and does
    // not independently determine PASS/FAIL.

    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end
        else if (clk_en && !halt_f) begin
            cycle_count <= cycle_count + 1;
        end
    end

    //==========================
    // EXPECTED VALUE CHECK
    //=========================
    // Compare a complete 32-bit result word.
    //
    // Case inequality detects mismatches and
    // unknown values as verification failures.

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] description;

        begin
            test_count = test_count + 1;

            if (actual !== expected) begin
                $display("FAIL: %0s", description);
                $display("  Expected = %08h", expected);
                $display("  Actual   = %08h", actual);
                test_errors = test_errors + 1;
            end
            else begin
                $display("PASS: %0s = %08h",
                         description, actual);
            end
        end
    endtask

    //=======================================
    // STANDARD MEMORY DUMP VERIFICATION
    //=====================================
    // Read scc_out.txt after the memory model
    // has completed its HALT-triggered output.
    //
    // Expected CSV format:
    // Address,Value
    // 0x0000d700,0x00000015
    //
    // Scan the memory dump to locate the two
    // architectural output addresses.
    //
    // This avoids any private memory-array access.

    task check_memory_results;

        begin
            found_result_0 = 1'b0;
            found_result_1 = 1'b0;

            actual_result_0 = 32'h0000_0000;
            actual_result_1 = 32'h0000_0000;

            dump_file = $fopen("scc_out.txt", "r");

            if (dump_file == 0) begin
                $display("FAIL: Cannot open scc_out.txt");
                test_errors = test_errors + 1;
            end

            else begin

                // Consume the CSV column-header line.
                scan_result = $fgets(header_line, dump_file);

                // Read each address/data pair until EOF.
                // Unknown or malformed lines must not be
                // accepted as valid architectural results.

                while (!$feof(dump_file)) begin

                    scan_result = $fscanf(
                        dump_file,
                        "0x%h,0x%h\n",
                        scanned_addr,
                        scanned_data
                    );

                    if (scan_result == 2) begin

                        if (scanned_addr == RESULT_ADDR_0) begin
                            actual_result_0 = scanned_data;
                            found_result_0 = 1'b1;
                        end

                        else if (scanned_addr == RESULT_ADDR_1) begin
                            actual_result_1 = scanned_data;
                            found_result_1 = 1'b1;
                        end
                    end

                    else if (!$feof(dump_file)) begin
                        $display("FAIL: Malformed memory dump");
                        test_errors = test_errors + 1;

                        // Stop scanning an invalid file
                        // instead of looping indefinitely.
                        $fclose(dump_file);
                        disable check_memory_results;
                    end
                end

                $fclose(dump_file);

                //===================================
                // VERIFY BOTH EXPECTED ADDRESSES
                //=================================

                test_count = test_count + 1;

                if (!found_result_0 || !found_result_1) begin
                    $display("FAIL: Missing expected memory addresses");
                    test_errors = test_errors + 1;
                end
                else begin
                    $display("PASS: Both result addresses found");
                end

                // Only compare data for addresses
                // that actually appeared in the dump.

                if (found_result_0) begin
                    check_word(
                        actual_result_0,
                        EXPECTED_0,
                        "MOVF first SNZCV snapshot"
                    );
                end

                if (found_result_1) begin
                    check_word(
                        actual_result_1,
                        EXPECTED_1,
                        "MOVF second SNZCV snapshot"
                    );
                end
            end
        end
    endtask

    //================================
    // MAIN VERIFICATION SEQUENCE
    //=================================

    initial begin

        $dumpfile("tb_movf_savf.vcd");
        $dumpvars(0, tb_movf_savf);

        // Initialize the top-level system inputs
        rst = 1'b1;
        clk_en = 1'b1;

        test_count = 0;
        test_errors = 0;
        cycle_count = 0;

        $display("");
        $display("========================================");
        $display("SCC CP5 MOVF/SAVF VERIFICATION");
        $display("========================================");

        // Apply reset across multiple active edges
        repeat (3) @(posedge clk);

        // Release reset away from the rising edge
        // to avoid testbench/DUT race conditions
        @(negedge clk);
        rst = 1'b0;

        //========================================
        // CAPTURE NORMAL PROCESSOR TERMINATION
        //=======================================
        // Wait for the standard top-level HALT
        // indication to become asserted.
        //
        // The associated err_f output is
        // combinational and may change after
        // the processor fetches another instruction.
        //
        // Sample the status one nanosecond after the HALT transition. This allows the
        // combinational status logic to settle without waiting for another clock edge.

        @(posedge halt_f);
        #1;

        status_at_halt = err_f;

        //==================================
        // CHECK ARCHITECTURAL HALT STATUS
        //=================================
        // Use the captured status rather than
        // the potentially changed live output

        check_word(
            {30'b0, status_at_halt},
            32'h0000_0001,
            "Normal HALT status"
        );

        //======================================
        // ALLOW MEMORY DUMP TO FINISH
        //===================================
        // The memory model writes scc_out.txt in response to the HALT transition.
        //
        // Wait before opening and reading that file, keeping status verification
        // separate from memory verification.

        #20;

        //================================
        // CHECK ARCHITECTURAL MEMORY
        //===============================

        check_memory_results;

        //================================
        // FINAL VERIFICATION SUMMARY
        //==============================

        $display("");
        $display("========================================");
        $display("MOVF/SAVF FINAL RESULTS");
        $display("========================================");
        $display("Clock cycles        = %0d", cycle_count);
        $display("Signal checks       = %0d", test_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0 && found_result_0 && found_result_1) begin
            $display("MOVF/SAVF TEST PASSED");
        end
        else begin
            $display("MOVF/SAVF TEST FAILED");
        end

        $display("========================================");
        $finish;
    end

    //=====================
    // SIMULATION TIMEOUT
    //======================
    // A missing HALT is always a failure.
    //
    // Prevent a stalled processor or an infinite
    // assembly loop from hanging verification

    initial begin
        #TIMEOUT_NS;
        $display("FAIL: MOVF/SAVF simulation timeout");
        $display("MOVF/SAVF TEST FAILED");
        $finish;
    end

endmodule
