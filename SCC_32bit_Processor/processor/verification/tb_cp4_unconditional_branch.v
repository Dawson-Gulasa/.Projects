
`timescale 1ns/1ps
// tb_cp4_unconditional_branch.v
//
// SCC CP4 unconditional-branch timing verification.
//
// Verifies that an unconditional B instruction redirects
// the PC on the immediately following rising clock edge.
//
// Expected instruction sequence:
//   PC=0x00 : B #8
//   PC=0x08 : HALT
//
// PC=0x04 contains NOP and must be skipped.

module tb_cp4_unconditional_branch;

    //=====================
    // TESTBENCH SIGNALS
    //========================

    reg clk;
    reg clk_en;
    reg rst;

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    integer check_count;
    integer test_errors;

    //========================
    // DEVICE UNDER TEST
    //======================

    scc_f26_top DUT (
        .clk (clk),
        .clk_en (clk_en),
        .rst (rst),
        .halt_f (halt_f),
        .err_f (err_f),
        .inst_mem_v (inst_mem_v),
        .data_mem_in_v (data_mem_in_v)
    );

    //========================
    // CLOCK GENERATION
    //=======================
    // 10 ns clock period

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //===========
    // CHECK TASK
    //=============

    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] description;

        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display(
                    "FAIL: %0s expected=%08h actual=%08h",
                    description, expected, actual
                );
                test_errors = test_errors + 1;
            end else begin
                $display(
                    "PASS: %0s = %08h",
                    description, actual
                );
            end
        end
    endtask

    //========================
    // MAIN TEST SEQUENCE
    //========================

    initial begin
        $dumpfile("tb_cp4_unconditional_branch.vcd");
        $dumpvars(0, tb_cp4_unconditional_branch);

        clk_en = 1'b1;
        rst = 1'b1;

        check_count = 0;
        test_errors = 0;

        $display("");
        $display("========================================");
        $display("SCC CP4 UNCONDITIONAL BRANCH VERIFICATION");
        $display("========================================");

        // Hold reset for three active clock edges
        repeat (3) @(posedge clk);

        // Release reset away from the active edge
        @(negedge clk);
        rst = 1'b0;

        // Allow instruction memory to settle
        #1;

        //=======================
        // INITIAL INSTRUCTION
        //========================
        // B #8 must be fetched at PC=0x00

        check_word(
            DUT.scc.pc_v,
            32'h0000_0000,
            "Initial branch PC"
        );

        check_word(
            inst_mem_v,
            32'hC000_0008,
            "Unconditional B instruction"
        );

        check_word(
            {31'd0, DUT.scc.ucode_stall},
            32'd0,
            "No microcode stall"
        );

        //========================
        // BRANCH EXECUTION
        //========================
        // The very next rising clock edge must advance
        // directly to PC=0x08.
        //
        // Any intermediate PC=0x04 or retained PC=0x00
        // would indicate incorrect branch timing

        @(posedge clk);
        #1;

        check_word(
            DUT.scc.pc_v,
            32'h0000_0008,
            "Branch target reached in one clock"
        );

        check_word(
            inst_mem_v,
            32'hD000_0000,
            "HALT fetched immediately"
        );

        check_word(
            {31'd0, halt_f},
            32'd1,
            "HALT asserted at branch target"
        );

        check_word(
            {30'd0, err_f},
            32'd1,
            "HALT status"
        );

        //==================
        // FINAL RESULTS
        //====================

        $display("");
        $display("========================================");
        $display("UNCONDITIONAL BRANCH FINAL RESULTS");
        $display("========================================");

        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0) begin
            $display("CP4 UNCONDITIONAL BRANCH TEST PASSED");
        end else begin
            $display("CP4 UNCONDITIONAL BRANCH TEST FAILED");
        end

        $display("========================================");
        $finish;
    end

    //=====================
    // SIMULATION TIMEOUT
    //====================

    initial begin
        #1000;

        $display("FAIL: Unconditional branch timeout");
        $finish;
    end

endmodule
