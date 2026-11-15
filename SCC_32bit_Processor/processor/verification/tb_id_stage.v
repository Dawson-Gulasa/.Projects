`timescale 1ns/1ps
// tb_id_stage.v
// Self-checking testbench for the SCC Instruction Decode stage.
//
// Tests:
// - Major instruction classification
// - Register address extraction
// - Immediate sign extension
// - ALU operation and flag controls
// - Register-file write controls
// - LOAD and STOR controls
// - Branch, NOP, and HALT decoding
// - MUL/MULS microcode decode and ordinary-writeback suppression
// - Unsupported instruction detection
//
// This testbench checks CP4 MUL/MULS recognition and reserved DIV codes.
// It verifies decode outputs only.
// It does not execute instructions or access memory.

module tb_id_stage;

    //=============
    // TB SIGNALS
    //===========

    reg [31:0] inst_v;

    wire [3:0] rd_addr_v;
    wire [3:0] rs1_addr_v;
    wire [3:0] rs2_addr_v;

    wire [31:0] imm_v;

    wire is_data_imm;
    wire is_data_reg;
    wire is_load_store;
    wire is_sys_branch;

    wire is_alu;

    // Multicycle instruction recognition.
    // These operations use their dedicated controllers rather than
    // the ordinary single-cycle ALU register-writeback path.
    wire is_mul;
    wire is_div;

    wire [2:0] alu_op_v;
    wire set_flags;
    wire use_imm;

    wire reg_write_en;
    wire data_mem_rd_en;
    wire data_mem_wr_en;

    wire is_branch;
    wire is_cond_branch;
    wire [3:0] branch_cond_v;
    wire halt_f;
    wire is_nop;

    wire is_mov;
    wire is_movt;
    wire is_movf;
    wire is_savf;
    wire is_clr;
    wire is_set;
    wire is_lsl;
    wire is_lsr;
    wire is_push;
    wire is_pop;

    wire illegal_instr;

    //===============
    // TEST COUNTERS
    //=================

    integer test_count;
    integer check_count;
    integer test_errors;

    //===============
    // INSTANTIATE DUT
    //=================

    id_stage DUT (
        .inst_v(inst_v),

        .rd_addr_v(rd_addr_v),
        .rs1_addr_v(rs1_addr_v),
        .rs2_addr_v(rs2_addr_v),

        .imm_v(imm_v),

        .is_data_imm(is_data_imm),
        .is_data_reg(is_data_reg),
        .is_load_store(is_load_store),
        .is_sys_branch(is_sys_branch),

        .is_alu(is_alu),
        .is_mul(is_mul),
        .is_div(is_div),
        .alu_op_v(alu_op_v),
        .set_flags(set_flags),
        .use_imm(use_imm),

        .reg_write_en(reg_write_en),
        .data_mem_rd_en(data_mem_rd_en),
        .data_mem_wr_en(data_mem_wr_en),

        .is_branch(is_branch),
        .is_cond_branch(is_cond_branch),
        .branch_cond_v(branch_cond_v),
        .halt_f(halt_f),
        .is_nop(is_nop),

        .is_mov(is_mov),
        .is_movt(is_movt),
        .is_movf(is_movf),
        .is_savf(is_savf),
        .is_clr(is_clr),
        .is_set(is_set),
        .is_lsl(is_lsl),
        .is_lsr(is_lsr),
        .is_push(is_push),
        .is_pop(is_pop),

        .illegal_instr(illegal_instr)
    );

    //=============
    // CHECK TASKS
    //==============

    // Check a single-bit control signal
    task check_bit;
        input actual;
        input expected;
        input [8*48-1:0] signal_name;

        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("  FAIL: %0s expected=%b actual=%b", signal_name, expected, actual);
                test_errors = test_errors + 1;
            end
        end
    endtask

    // Check a 32-bit value
    task check_word;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] signal_name;

        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("  FAIL: %0s expected=%08h actual=%08h", signal_name, expected, actual);
                test_errors = test_errors + 1;
            end
        end
    endtask

    // Check a 4-bit register or condition field
    task check_field;
        input [3:0] actual;
        input [3:0] expected;
        input [8*48-1:0] signal_name;

        begin
            check_count = check_count + 1;

            if (actual !== expected) begin
                $display("  FAIL: %0s expected=%h actual=%h", signal_name, expected, actual);
                test_errors = test_errors + 1;
            end
        end
    endtask

    //====================
    // APPLY INSTRUCTION
    //===================

    // Apply an instruction and allow the combinational
    // decoder to settle before checking its outputs
    task apply_instruction;
        input [31:0] instruction;
        input [8*48-1:0] test_name;

        begin
            test_count = test_count + 1;
            inst_v = instruction;
            #2;

            $display("TEST %0d: %0s (%08h)", test_count, test_name, inst_v);
        end
    endtask

    //==============
    // TEST SEQUENCE
    //================

    initial begin

        $dumpfile("tb_id_stage.vcd");
        $dumpvars(0, tb_id_stage);

        inst_v = 32'h0000_0000;

        test_count = 0;
        check_count = 0;
        test_errors = 0;

        $display("");
        $display("========================================");
        $display("ID STAGE VERIFICATION");
        $display("========================================");


        //========================================
        // TEST 1: MOV IMMEDIATE
        //========================================
        // Verify that immediate MOV selects its immediate operand
        // rather than an architectural source-register value.
        //
        // A nonzero immediate is used to make the test more meaningful.
        // MOV zero-extends the immediate during EXE execution.

        apply_instruction(32'h0040_1234, "MOV R2, #0x1234");

        check_bit(is_data_imm, 1'b1, "Data immediate class");
        check_bit(is_mov, 1'b1, "Immediate MOV recognized");
        check_bit(use_imm, 1'b1, "Immediate operand selected");
        check_bit(reg_write_en, 1'b1, "MOV register write enabled");
        check_bit(illegal_instr, 1'b0, "Immediate MOV legal");
        check_field(rd_addr_v, 4'd2, "Destination R2");
        check_word(imm_v, 32'h0000_1234, "Decoded immediate value");


        //======================
        // TEST 2: ADD IMMEDIATE
        //======================
        // ADD R0, R0, #1 from the CP3 program

        apply_instruction(32'h2200_0001, "ADD R0, R0, #1");

        check_bit(is_data_imm, 1'b1, "Data immediate class");
        check_bit(is_alu, 1'b1, "ALU instruction");
        check_bit(use_imm, 1'b1, "Immediate selection");
        check_bit(reg_write_en, 1'b1, "Register write");
        check_bit(set_flags, 1'b0, "Flags not updated");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd0, "Destination R0");
        check_field(rs1_addr_v, 4'd0, "Source R0");
        check_word(imm_v, 32'h0000_0001, "Immediate +1");

        check_count = check_count + 1;
        if (alu_op_v !== 3'b001) begin
            $display("  FAIL: ADD opcode incorrect");
            test_errors = test_errors + 1;
        end

        //========================
        // TEST 3: CMP REGISTER
        //=======================
        // CMP R0, R1 compiles to a flag-setting SUB

        apply_instruction(32'h75C0_2000, "CMP R0, R1");

        check_bit(is_data_reg, 1'b1, "Data register class");
        check_bit(is_alu, 1'b1, "ALU instruction");
        check_bit(use_imm, 1'b0, "Register operand selection");
        check_bit(set_flags, 1'b1, "Flag update enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rs1_addr_v, 4'd0, "Source R0");
        check_field(rs2_addr_v, 4'd1, "Source R1");

        check_count = check_count + 1;
        if (alu_op_v !== 3'b010) begin
            $display("  FAIL: CMP must decode as SUB");
            test_errors = test_errors + 1;
        end

        //======================
        // TEST 4: ADD REGISTER
        //=====================
        // Constructed register-format ADD encoding

        apply_instruction(32'h6200_2000, "ADD register format");

        check_bit(is_data_reg, 1'b1, "Data register class");
        check_bit(is_alu, 1'b1, "ALU instruction");
        check_bit(use_imm, 1'b0, "Register operand selection");
        check_bit(reg_write_en, 1'b1, "Register write");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rs2_addr_v, 4'd1, "Second source R1");

        check_count = check_count + 1;
        if (alu_op_v !== 3'b001) begin
            $display("  FAIL: Register ADD opcode incorrect");
            test_errors = test_errors + 1;
        end

        //===========================
        // TEST 5: NEGATIVE IMMEDIATE
        //==============================
        // Verify sign extension of immediate 0xFFFF

        apply_instruction(32'h2200_FFFF, "ADD immediate -1");

        check_bit(is_alu, 1'b1, "ALU instruction");
        check_bit(use_imm, 1'b1, "Immediate selection");
        check_word(imm_v, 32'hFFFF_FFFF, "Negative sign extension");

        //==============
        // TEST 6: STOR
        //=============
        // STOR R2, R3, #0 from the CP3 program

        apply_instruction(32'h8246_0000, "STOR R2, R3, #0");

        check_bit(is_load_store, 1'b1, "Load/store class");
        check_bit(data_mem_wr_en, 1'b1, "Memory write enabled");
        check_bit(data_mem_rd_en, 1'b0, "Memory read disabled");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(use_imm, 1'b1, "Address offset selected");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Store data register R2");
        check_field(rs1_addr_v, 4'd3, "Address base R3");

        //===============
        // TEST 7: LOAD
        //================
        // LOAD using the same register fields as STOR

        apply_instruction(32'h8046_0000, "LOAD R2, R3, #0");

        check_bit(is_load_store, 1'b1, "Load/store class");
        check_bit(data_mem_rd_en, 1'b1, "Memory read enabled");
        check_bit(data_mem_wr_en, 1'b0, "Memory write disabled");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //============================
        // TEST 8: UNCONDITIONAL B
        //=============================
        // B outer from the CP3 program

        apply_instruction(32'hC000_FFD8, "B outer");

        check_bit(is_sys_branch, 1'b1, "System/branch class");
        check_bit(is_branch, 1'b1, "Branch enabled");
        check_bit(is_cond_branch, 1'b0, "Unconditional branch");
        check_bit(reg_write_en, 1'b0, "No register write");
        check_bit(data_mem_wr_en, 1'b0, "No memory write");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //=============================
        // TEST 9: CONDITIONAL BRANCH
        //================================
        // B.NE inner from the CP3 program

        apply_instruction(32'hC220_FFF8, "B.NE inner");

        check_bit(is_sys_branch, 1'b1, "System/branch class");
        check_bit(is_branch, 1'b1, "Branch enabled");
        check_bit(is_cond_branch, 1'b1, "Conditional branch");
        check_bit(reg_write_en, 1'b0, "No register write");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(branch_cond_v, 4'd1, "NE condition field");

        //=============
        // TEST 10: HALT
        //================

        apply_instruction(32'hD000_0000, "HALT");

        check_bit(is_sys_branch, 1'b1, "System/branch class");
        check_bit(halt_f, 1'b1, "HALT asserted");
        check_bit(reg_write_en, 1'b0, "No register write");
        check_bit(data_mem_wr_en, 1'b0, "No memory write");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //=============
        // TEST 11: NOP
        //=============

        apply_instruction(32'hC800_0000, "NOP");

        check_bit(is_nop, 1'b1, "NOP decode");
        check_bit(halt_f, 1'b0, "HALT disabled");
        check_bit(reg_write_en, 1'b0, "No register write");
        check_bit(data_mem_wr_en, 1'b0, "No memory write");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //===================================
        // TEST 12: CP4 MUL IMMEDIATE
        //===================================
        // MUL is legal in CP4 and is executed by microcode.
        // Ordinary EXE writeback must remain disabled.

        apply_instruction(32'h2000_0000, "MUL immediate (microcoded)");

        check_bit(is_alu, 1'b1, "ALU classification");
        check_bit(is_mul, 1'b1, "MUL microcode decode");
        check_bit(use_imm, 1'b1, "Immediate operand selected");
        check_bit(set_flags, 1'b0, "MUL does not update flags");
        check_bit(illegal_instr, 1'b0, "MUL is legal in CP4");
        check_bit(reg_write_en, 1'b0, "Ordinary writeback disabled");


        //========================================
        // TEST 13: DIV IMMEDIATE
        //========================================
        // DIV is a valid multicycle instruction.
        // The decoder must select the immediate operand and
        // prevent ordinary EXE register writeback.
        //
        // The division controller performs the architectural
        // quotient and remainder writes after execution.

        apply_instruction(32'h2E00_0005, "DIV immediate");

        check_bit(is_data_imm, 1'b1, "Data immediate class");
        check_bit(is_alu, 1'b1, "ALU instruction class");
        check_bit(is_div, 1'b1, "DIV controller selected");
        check_bit(is_mul, 1'b0, "MUL controller not selected");
        check_bit(use_imm, 1'b1, "Immediate divisor selected");
        check_bit(reg_write_en, 1'b0, "Ordinary writeback disabled");
        check_bit(illegal_instr, 1'b0, "DIV immediate legal");
        check_word(imm_v, 32'd5, "Immediate divisor");


        //========================================
        // TEST 14: CP4 MUL REGISTER
        //========================================
        // Register-form MUL is legal but uses microcoded writeback.

        apply_instruction(32'h6000_0000, "MUL register (microcoded)");

        check_bit(is_data_reg, 1'b1, "Data register class");
        check_bit(is_alu, 1'b1, "ALU classification");
        check_bit(is_mul, 1'b1, "MUL microcode decode");
        check_bit(set_flags, 1'b0, "MUL does not update flags");
        check_bit(illegal_instr, 1'b0, "MUL is legal in CP4");
        check_bit(reg_write_en, 1'b0, "Ordinary writeback disabled");

        //======================================
        // TEST 15: UNDEFINED SYSTEM INSTRUCTION
        //========================================

        apply_instruction(32'hDE00_0000, "Undefined system opcode");

        check_bit(is_sys_branch, 1'b1, "System/branch class");
        check_bit(illegal_instr, 1'b1, "Illegal instruction");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(data_mem_wr_en, 1'b0, "Memory write disabled");


        //=======================
        // TEST 16: MOVT IMMEDIATE
        //=======================

        apply_instruction(32'h0240_1234, "MOVT R2, #0x1234");

        check_bit(is_data_imm, 1'b1, "Data immediate class");
        check_bit(is_movt, 1'b1, "MOVT decode");
        check_bit(use_imm, 1'b1, "Immediate selected");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Destination R2");
        check_word(imm_v, 32'h0000_1234, "Immediate value");

        //===============
        // TEST 17: CLR
        //===============

        apply_instruction(32'h0440_0000, "CLR R2");

        check_bit(is_clr, 1'b1, "CLR decode");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Destination R2");

        //================
        // TEST 18: SET
        //===============

        apply_instruction(32'h0640_0000, "SET R2");

        check_bit(is_set, 1'b1, "SET decode");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Destination R2");

        //=========================
        // TEST 19: LSL IMMEDIATE
        //===========================

        apply_instruction(32'h0842_0003, "LSL R2, R1, #3");

        check_bit(is_lsl, 1'b1, "LSL decode");
        check_bit(use_imm, 1'b1, "Immediate selected");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Destination R2");
        check_field(rs1_addr_v, 4'd1, "Source R1");
        check_word(imm_v, 32'd3, "Shift amount");

        //==========================
        // TEST 20: LSR IMMEDIATE
        //========================

        apply_instruction(32'h0A42_0002, "LSR R2, R1, #2");

        check_bit(is_lsr, 1'b1, "LSR decode");
        check_bit(use_imm, 1'b1, "Immediate selected");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rd_addr_v, 4'd2, "Destination R2");
        check_field(rs1_addr_v, 4'd1, "Source R1");

        //==============
        // TEST 21: MOVF
        //================

        apply_instruction(32'h0C40_0000, "MOVF R2");

        check_bit(is_movf, 1'b1, "MOVF decode");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //=================
        // TEST 22: SAVF
        //===================

        apply_instruction(32'h1C02_0000, "SAVF R1");

        check_bit(is_savf, 1'b1, "SAVF decode");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");
        check_field(rs1_addr_v, 4'd1, "Source R1");


        //========================================
        // TEST 23: MOVR REGISTER
        //========================================
        // MOVR is the register-to-register move instruction.
        // It retains the original register-move encoding.
        //
        // Unlike immediate MOV, MOVR must leave use_imm low
        // so EXE selects the first source-register value.

        apply_instruction(32'h4042_0000, "MOVR R2, R1");

        check_bit(is_data_reg, 1'b1, "Data register class");
        check_bit(is_mov, 1'b1, "MOVR recognized");
        check_bit(use_imm, 1'b0, "Register operand selected");
        check_bit(reg_write_en, 1'b1, "MOVR write enabled");
        check_bit(illegal_instr, 1'b0, "MOVR legal");
        check_field(rd_addr_v, 4'd2, "Destination R2");
        check_field(rs1_addr_v, 4'd1, "Source R1");



        //==================
        // TEST 24: PUSH
        //================

        apply_instruction(32'h4202_0000, "PUSH R1");

        check_bit(is_push, 1'b1, "PUSH decode");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //==============
        // TEST 25: POP
        //=============

        apply_instruction(32'h4440_0000, "POP R2");

        check_bit(is_pop, 1'b1, "POP decode");
        check_bit(reg_write_en, 1'b1, "Register write enabled");
        check_bit(illegal_instr, 1'b0, "Instruction valid");

        //===================
        // TEST 26: BR REGISTER
        //=====================

        apply_instruction(32'hC402_0000, "BR R1");

        check_bit(is_sys_branch, 1'b1, "System/branch class");
        check_bit(is_branch, 1'b1, "Branch enabled");
        check_bit(is_cond_branch, 1'b0, "Unconditional branch");
        check_bit(illegal_instr, 1'b0, "Instruction valid");


        //========================================
        // TEST 27: DIV REGISTER
        //========================================
        // Register-form DIV selects the second register source.
        // The instruction is legal and must not trigger ordinary
        // ALU register writeback.
        //
        // Its quotient and remainder are written through the
        // multicycle division controller.

        apply_instruction(32'h6E00_0000, "DIV register");

        check_bit(is_data_reg, 1'b1, "Data register class");
        check_bit(is_alu, 1'b1, "ALU instruction class");
        check_bit(is_div, 1'b1, "DIV controller selected");
        check_bit(is_mul, 1'b0, "MUL controller not selected");
        check_bit(use_imm, 1'b0, "Register divisor selected");
        check_bit(reg_write_en, 1'b0, "Ordinary writeback disabled");
        check_bit(illegal_instr, 1'b0, "DIV register legal");


        //=======================================
        // TEST 28: CP4 MULS IMMEDIATE
        //=======================================
        // MULS is legal in CP4. The decoder requests a flag
        // update; the microcode integration supplies the final NZCV.

        apply_instruction(32'h3000_0000, "MULS immediate (microcoded)");

        check_bit(is_alu, 1'b1, "ALU classification");
        check_bit(is_mul, 1'b1, "MULS microcode decode");
        check_bit(use_imm, 1'b1, "Immediate operand selected");
        check_bit(illegal_instr, 1'b0, "MULS is legal in CP4");
        check_bit(reg_write_en, 1'b0, "Ordinary writeback disabled");
        check_bit(set_flags, 1'b1, "MULS requests flag update");

        //========================================
        // TEST 29: UNDEFINED IMMEDIATE OPCODE
        //======================================

        apply_instruction(32'h0E00_0000, "Undefined immediate special");

        check_bit(illegal_instr, 1'b1, "Illegal instruction");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(is_mov, 1'b0, "MOV not asserted");
        check_bit(is_movt, 1'b0, "MOVT not asserted");

        //=======================================
        // TEST 30: UNDEFINED REGISTER OPCODE
        //=====================================

        apply_instruction(32'h4600_0000, "Undefined register special");

        check_bit(illegal_instr, 1'b1, "Illegal instruction");
        check_bit(reg_write_en, 1'b0, "Register write disabled");
        check_bit(is_mov, 1'b0, "MOV not asserted");
        check_bit(is_push, 1'b0, "PUSH not asserted");

        //=================
        // FINAL RESULTS
        //===============

        $display("");
        $display("========================================");
        $display("ID STAGE FINAL RESULTS");
        $display("========================================");
        $display("Tests executed      = %0d", test_count);
        $display("Signal checks       = %0d", check_count);
        $display("Verification errors = %0d", test_errors);

        if (test_errors == 0) begin
            $display("========================================");
            $display("ID STAGE TEST PASSED");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("ID STAGE TEST FAILED");
            $display("========================================");

            // Return a nonzero simulator exit status when any assertion fails.
            // The regression runner must not accept a failed test as passing.
            $fatal(1, "ID_STAGE verification failed");
        end

        $finish;
    end

    //====================
    // SIMULATION TIMEOUT
    //===================
    // Stop the simulation if the test sequence fails to finish.
    // The timeout indicates that verification did not complete
    initial begin
        #1000;
        // An unfinished test is a verification failure, not normal completion.
        $fatal(1, "ID_STAGE verification timeout");
    end

endmodule
