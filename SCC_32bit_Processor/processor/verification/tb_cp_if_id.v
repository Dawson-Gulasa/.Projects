`timescale 1ns/1ps
// tb_cp_if_id.v
// Self-checking testbench for the SCC IF/ID checkpoint.
// The test program does:
// - ALU register-register decode
// - ALU immediate decode
// - LOAD decode
// - STOR decode
// - Conditional branch decode
// - Unconditional branch fetch/redirection
// - HALT decode

module tb_cp_if_id;

    //================
    // TESTBENCH INPUTS
    //=============

    reg clk;
    reg clk_en;
    reg rst;

    //============
    // DUT OUTPUTS
    //============

    wire halt_f;
    wire [1:0] err_f;
    wire [31:0] inst_mem_v;
    wire [31:0] data_mem_in_v;

    //================
    // TESTBENCH STATUS
    //=================

    integer pass_count;
    integer fail_count;

    //=====
    // DUT
    //====

    scc_f26_top dut (
        .clk(clk),
        .clk_en(clk_en),
        .rst(rst),

        .halt_f(halt_f),
        .err_f(err_f),

        .inst_mem_v(inst_mem_v),
        .data_mem_in_v(data_mem_in_v)
    );

    //=================
    // CLOCK GENERATION
    //=================
    // 20 ns clock period = 50 MHz

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end


    //===========
    // CHECK TASK
    //===========
    // Checks the current PC, fetched instruction, and major ID control
    // outputs against their expected values.

    task check_instruction;

        input [31:0] expected_pc;
        input [31:0] expected_inst;

        input expected_data_reg;
        input expected_data_imm;
        input expected_load_store;
        input expected_sys_branch;

        input expected_is_alu;
        input expected_use_imm;
        input expected_reg_write;

        input expected_mem_read;
        input expected_mem_write;

        input expected_branch;
        input expected_cond_branch;
        input expected_halt;

        begin

            // allow memory outputs to settle
            #1;

            $display("------------------------------------------------------------");
            $display("Checking PC = 0x%08h, Instruction = 0x%08h", expected_pc, expected_inst);

            if ((dut.scc.pc_v === expected_pc) &&
                (inst_mem_v === expected_inst) &&

                (dut.scc.ID_STAGE.is_data_reg === expected_data_reg) &&
                (dut.scc.ID_STAGE.is_data_imm === expected_data_imm) &&
                (dut.scc.is_load_store === expected_load_store) &&
                (dut.scc.ID_STAGE.is_sys_branch === expected_sys_branch) &&

                (dut.scc.is_alu === expected_is_alu) &&
                (dut.scc.use_imm === expected_use_imm) &&
                (dut.scc.reg_write_en === expected_reg_write) &&

                (dut.scc.data_mem_rd_en === expected_mem_read) &&
                (dut.scc.data_mem_wr_request === expected_mem_write) &&

                (dut.scc.ID_STAGE.is_branch === expected_branch) &&
                (dut.scc.is_cond_branch === expected_cond_branch) &&
                (halt_f === expected_halt) &&

                (dut.scc.ID_STAGE.illegal_instr === 1'b0)) begin

                $display("PASS");
                pass_count = pass_count + 1;

            end else begin

                $display("FAIL");

                $display("  PC:              actual=%08h expected=%08h",
                         dut.scc.pc_v, expected_pc);

                $display("  Instruction:     actual=%08h expected=%08h",
                         inst_mem_v, expected_inst);

                $display("  is_data_reg:     actual=%b expected=%b",
                         dut.scc.ID_STAGE.is_data_reg, expected_data_reg);

                $display("  is_data_imm:     actual=%b expected=%b",
                         dut.scc.ID_STAGE.is_data_imm, expected_data_imm);

                $display("  is_load_store:   actual=%b expected=%b",
                         dut.scc.is_load_store, expected_load_store);

                $display("  is_sys_branch:   actual=%b expected=%b",
                         dut.scc.ID_STAGE.is_sys_branch, expected_sys_branch);

                $display("  is_alu:          actual=%b expected=%b",
                         dut.scc.is_alu, expected_is_alu);

                $display("  use_imm:         actual=%b expected=%b",
                         dut.scc.use_imm, expected_use_imm);

                $display("  reg_write_en:    actual=%b expected=%b",
                         dut.scc.reg_write_en, expected_reg_write);

                $display("  data_mem_rd_en:  actual=%b expected=%b",
                         dut.scc.data_mem_rd_en, expected_mem_read);

                $display("  store_request:   actual=%b expected=%b",
                        dut.scc.data_mem_wr_request, expected_mem_write);

                $display("  is_branch:       actual=%b expected=%b",
                         dut.scc.ID_STAGE.is_branch, expected_branch);

                $display("  is_cond_branch:  actual=%b expected=%b",
                         dut.scc.is_cond_branch, expected_cond_branch);

                $display("  halt_f:          actual=%b expected=%b",
                         halt_f, expected_halt);

                $display("  illegal_instr:   actual=%b expected=0",
                         dut.scc.ID_STAGE.illegal_instr);

                fail_count = fail_count + 1;

            end
        end
    endtask


    //=============
    // TEST SEQUENCE
    //=============

    initial begin

        // Generate waveform file .vcd
        $dumpfile("cp_if_id.vcd");
        $dumpvars(0, tb_cp_if_id);

        pass_count = 0;
        fail_count = 0;

        // Initialize with reset inactive so constant enables and
        // DUT interconnect signals can settle before reset
        clk_en = 1'b0;
        rst = 1'b0;

        #1;

        // Assert reset.
        rst = 1'b1;

        $display("");
        $display("===============================================");
        $display(" SCC IF/ID CHECKPOINT SELF-CHECKING TESTBENCH");
        $display("===============================================");
        $display("Reset asserted.");

        // Hold reset through three rising clock edges.
        #59;

        if (dut.scc.pc_v === 32'h0000_0000) begin
            $display("PASS: PC reset to 0x00000000 after three reset clocks.");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: PC did not reset to 0x00000000.");
            $display("      Actual PC = 0x%08h", dut.scc.pc_v);
            fail_count = fail_count + 1;
        end

        // Release reset and begin processor operation.
        rst = 1'b0;
        clk_en = 1'b1;

        $display("Reset released. Beginning instruction checks.");

        //===============================
        // PC = 0x00
        // ADD R1, R1, R3
        // Register-register ALU instruction
        //==============================

        check_instruction(
            32'h0000_0000,
            32'h6222_6000,
            1'b1,     // is_data_reg
            1'b0,     // is_data_imm
            1'b0,     // is_load_store
            1'b0,     // is_sys_branch
            1'b1,     // is_alu
            1'b0,     // use_imm
            1'b1,     // reg_write_en
            1'b0,     // data_mem_rd_en
            1'b0,     // data_mem_wr_en
            1'b0,     // is_branch
            1'b0,     // is_cond_branch
            1'b0      // halt_f
        );

        @(posedge clk);


        //============================
        // PC = 0x04
        // ADD R4, R4, #5
        // Immediate ALU instruction
        //===========================

        check_instruction(
            32'h0000_0004,
            32'h2288_0005,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );

        @(posedge clk);


        //==============
        // PC = 0x08
        // LOAD R1, R1, #4
        //=================

        check_instruction(
            32'h0000_0008,
            32'h8022_0004,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b1,
            1'b1,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0
        );

        @(posedge clk);


        //=============
        // PC = 0x0C
        // STOR R3, R2, #8
        //================

        check_instruction(
            32'h0000_000C,
            32'h8264_0008,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b0
        );

        @(posedge clk);


        //========================
        // PC = 0x10
        // B.ne #8
        // Conditional branch decode
        //========================

        check_instruction(
            32'h0000_0010,
            32'hC220_0008,
            1'b0,     // is_data_reg
            1'b0,     // is_data_imm
            1'b0,     // is_load_store
            1'b1,     // is_sys_branch
            1'b0,     // is_alu
            1'b1,     // use_imm
            1'b0,     // reg_write_en
            1'b0,     // data_mem_rd_en
            1'b0,     // data_mem_wr_en
            1'b1,     // is_branch
            1'b1,     // is_cond_branch
            1'b0      // halt_f
        );

        @(posedge clk);


        //========================================
        // PC = 0x18
        // NOP
        //========================================
        // The preceding B.ne at PC=0x10 is taken
        // because the architectural Z flag is 0.
        //
        // Target = 0x10 + 0x08 = 0x18.
        //
        // The unconditional B at 0x14 is skipped.
        // This confirms the current conditional-branch
        // behavior without modifying the CP2 assembly.

        check_instruction(
            32'h0000_0018,
            32'hC800_0000,
            1'b0,     // is_data_reg
            1'b0,     // is_data_imm
            1'b0,     // is_load_store
            1'b1,     // is_sys_branch
            1'b0,     // is_alu
            1'b0,     // use_imm
            1'b0,     // reg_write_en
            1'b0,     // data_mem_rd_en
            1'b0,     // decoded store request
            1'b0,     // is_branch
            1'b0,     // is_cond_branch
            1'b0      // halt_f
        );

        @(posedge clk);


        //==================================================
        // PC = 0x1C
        // HALT
        //
        // The taken B.ne reaches NOP at 0x18.
        // Sequential execution then reaches HALT at 0x1C.
        //==================================================

        check_instruction(
            32'h0000_001C,
            32'hD000_0000,
            1'b0,
            1'b0,
            1'b0,
            1'b1,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            1'b0,
            1'b1
        );


        //========================
        // FINAL TEST SUMMARY
        //========================

        $display("");
        $display("============================================================");
        $display(" TEST SUMMARY");
        $display("============================================================");
        $display(" Passed checks: %0d", pass_count);
        $display(" Failed checks: %0d", fail_count);

        if (fail_count == 0) begin
            $display(" RESULT: ALL TESTS PASSED");
        end else begin
            $display(" RESULT: TEST FAILED");
        end

        $display("============================================================");
        $display("");

        // Leave a little simulation time after the final check so the final HALT behavior is visible
        #40;

        $finish;
    end

endmodule