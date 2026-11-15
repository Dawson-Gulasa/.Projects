// id_stage.v
//
// Description:
// Combinational Instruction Decode (ID) stage for the SCC.
//
// Responsibilities:
// - Classify instructions into the four major ISA groups.
// - Extract destination/source register fields and immediates.
// - Decode ALU operations and flag-update requests.
// - Generate register-write and memory-access controls.
// - Recognize special, branch, NOP, and HALT instructions.
// - Identify MUL/MULS and DIV/DIVS as multicycle operations.
// - Reject genuinely reserved or unsupported encodings.
//
// Design Notes:
// - No sequential state is stored in this module.
// - IF performs unconditional B/BR PC redirection.
// - EXE performs arithmetic and data-address calculation.
// - Multicycle MUL/MULS execution is handled by the existing multiplication controller.
// - DIV/DIVS are decoded here and executed by div_controller.v
//   through the existing multicycle execution stage.
// - MUL/MULS and DIV/DIVS disable ordinary register writeback;
//   their controllers generate separate architectural write requests.
// - Final register and flag writeback selection occurs in WB_STAGE.
// - Blocking assignments are used for combinational controls.
// - Control outputs are initialized on every evaluation,
//   preventing unintended latch inference.

module id_stage (
    // Instruction to decode
    input wire [31:0] inst_v,

    // Register addresses extracted from instruction fields
    output wire [3:0] rd_addr_v,
    output wire [3:0] rs1_addr_v,
    output wire [3:0] rs2_addr_v,

    // Sign-extended immediate
    output wire [31:0] imm_v,

    // Major instruction classifications
    output wire is_data_imm,
    output wire is_data_reg,
    output wire is_load_store,
    output wire is_sys_branch,

    // ALU operation controls
    output wire is_alu,
    output wire [2:0] alu_op_v,
    output wire set_flags,
    output reg use_imm,

    //=======================================
    // MULTICYCLE ARITHMETIC IDENTIFICATION
    //=====================================
    // MUL/MULS use ALU opcode 000.
    // DIV/DIVS use ALU opcode 111.
    // Bit 28 distinguishes the normal instruction from its flag-setting S variant.
    //
    // These signals identify multicycle operations.
    // The microcode controller will eventually perform their architectural writeback.

    output wire is_mul,
    output wire is_div,

    // Register-file write control
    output reg reg_write_en,

    // Data-memory read and write controls
    output reg data_mem_rd_en,
    output reg data_mem_wr_en,

    // Branch and system instruction controls.
    output reg is_branch,
    output reg is_cond_branch,
    output reg [3:0] branch_cond_v,
    output reg halt_f,
    output reg is_nop,

    // Special instruction identification
    output reg is_mov,
    output reg is_movt,
    output reg is_movf,
    output reg is_savf,
    output reg is_clr,
    output reg is_set,
    output reg is_lsl,
    output reg is_lsr,
    output reg is_push,
    output reg is_pop,

    // Asserted for unsupported instruction encodings.
    output reg illegal_instr
);

//==========================================
// FIRST-LEVEL INSTRUCTION CLASSIFICATION
//===========================================
// Bits [31:30] select one of four major instruction classes:
//
// 00: Data immediate
// 01: Data register
// 10: Load/store
// 11: System/branch
//
// These comparisons are mutually exclusive for fully
// defined instruction values.
//
// Continuous assignments implement simple combinational
// comparisons without creating storage elements.

assign is_data_imm = (inst_v[31:30] == 2'b00);
assign is_data_reg = (inst_v[31:30] == 2'b01);
assign is_load_store = (inst_v[31:30] == 2'b10);
assign is_sys_branch = (inst_v[31:30] == 2'b11);

//========================================
// ARCHITECTURAL REGISTER FIELD EXTRACTION
//=========================================
// Common instruction fields:
// - [24:21]: Destination register.
// - [20:17]: First source register.
// - [16:13]: Second source register.
//
// These fields are provided continuously, even when an
// instruction does not use a particular register field.
//
// The consuming execution/control modules determine which
// extracted addresses are relevant to each instruction.

assign rd_addr_v = inst_v[24:21];
assign rs1_addr_v = inst_v[20:17];
assign rs2_addr_v = inst_v[16:13];

//================================
// IMMEDIATE FIELD SIGN EXTENSION
//=================================
// Extend the signed 16-bit immediate to 32 bits by
// replicating bit 15 into the upper sixteen positions.
//
// The execution stage may interpret the immediate field
// differently for instructions such as MOV

assign imm_v = {{16{inst_v[15]}}, inst_v[15:0]};

//====================================
// ALU AND MICROCODE IDENTIFICATION
//====================================
// Data-register and data-immediate ALU instructions use:
// - Bit [29] = 1 to indicate a standard ALU operation.
// - Bit [28] = 1 to request architectural flag updates.
// - Bits [27:25] to select the ALU operation.
//
// ALU operation encodings:
// 000: MUL (microcoded)
// 001: ADD
// 010: SUB
// 011: AND
// 100: OR
// 101: XOR
// 110: NOT
// 111: DIV/DIVS (multicycle division)
//
// MUL and MULS share the multiplication operation field.
// Bit [28] distinguishes the flag-update behavior.
//
// The ordinary ALU decode outputs remain available for
// recognized instruction classes. The controller below
// disables ordinary register writeback for multiplication.
//
// The set_flags signal is suppressed for illegal encodings.
// The downstream multiplication integration controls the
// actual multicycle flag writeback for MULS.

//====================================
// MULTICYCLE INSTRUCTION DECODE
//================================
// Both multiplication and division are valid
// ALU instructions in the immediate/register
// instruction classes.
//
// The flag-setting bit does not affect which
// arithmetic operation is selected.

assign is_mul = (is_data_imm || is_data_reg) && inst_v[29] && (inst_v[27:25] == 3'b000);

assign is_div = (is_data_imm || is_data_reg) && inst_v[29] && (inst_v[27:25] == 3'b111);

//=================================
// ALU INSTRUCTION CLASSIFICATION
//=================================
// is_alu identifies the entire architectural ALU instruction class,
// including the reserved ALU datapath selections used by MUL and DIV.
//
// MUL/MULS and DIV/DIVS remain members of this instruction class,
// but their architectural results are generated by multicycle controllers.
//
// The main decoder disables ordinary register writeback for MUL/DIV.
// The writeback stage selects microcode results in place of ordinary
// ALU results while the corresponding multicycle operation executes.
//
// The flag-setting bit is decoded here. Downstream control prevents
// ordinary ALU flag updates from replacing completed MULS/DIVS flags.
assign is_alu = (is_data_imm || is_data_reg) && (inst_v[29] == 1'b1);

assign set_flags = is_alu && inst_v[28] && !illegal_instr;

assign alu_op_v = inst_v[27:25];

//==========================================
// MAIN COMBINATIONAL INSTRUCTION DECODE
//============================================
// All control outputs receive default values before
// instruction-specific decoding.
//
// Defaults provide safe inactive controls when an
// instruction does not require a particular operation.
//
// Every procedural output is assigned on each evaluation,
// preventing unintended combinational latches.
//
// All assignments in this block are blocking (=) because
// the decoder does not contain clocked state.
//
// A reserved or unsupported encoding asserts illegal_instr.
// Architectural error handling occurs outside this module.

always @(*) begin

    //--------------------------------------
    // DEFAULT DATAPATH AND MEMORY CONTROLS
    //---------------------------------------
    // By default, no register or memory modification occurs.
    // Register operands are selected unless decoding
    // explicitly requests an immediate operand.

    use_imm = 1'b0;
    reg_write_en = 1'b0;
    data_mem_rd_en = 1'b0;
    data_mem_wr_en = 1'b0;

    //-----------------------------------
    // DEFAULT BRANCH AND SYSTEM CONTROLS
    //-------------------------------------
    // Unless a branch or system operation is recognized,
    // no branch indication, HALT, or NOP signal is asserted

    is_branch = 1'b0;
    is_cond_branch = 1'b0;
    branch_cond_v = 4'b0000;
    halt_f = 1'b0;
    is_nop = 1'b0;

    //------------------------------------------
    // DEFAULT SPECIAL-INSTRUCTION CONTROLS
    //----------------------------------------
    // Individual instruction markers remain inactive
    // until their corresponding encodings are recognized

    is_mov = 1'b0;
    is_movt = 1'b0;
    is_movf = 1'b0;
    is_savf = 1'b0;
    is_clr = 1'b0;
    is_set = 1'b0;
    is_lsl = 1'b0;
    is_lsr = 1'b0;
    is_push = 1'b0;
    is_pop = 1'b0;

    // Instructions begin as valid. Reserved encodings
    // explicitly set this signal during decoding
    illegal_instr = 1'b0;

    //===============================
    // DATA IMMEDIATE INSTRUCTIONS
    //================================
    // Major opcode bits [31:30] = 00.
    //
    // These instructions use immediate operands and include:
    // - Standard ALU immediate instructions.
    // - Special immediate operations such as MOV and shifts.

    if (is_data_imm) begin

        // If bit 29 is set, decode a standard ALU instruction
        // whose second operand comes from the immediate field.
        if (inst_v[29] == 1'b1) begin

            // Select the immediate operand for execution
            use_imm = 1'b1;

            // Standard supported ALU instructions write Rd.
            reg_write_en = 1'b1;

            // Multiplication is executed by the microcode
            // controller, not by ordinary EXE writeback
            //
            // If the operation is MUL/MULS, disable the
            // single-cycle architectural register write.
            if (inst_v[27:25] == 3'b000) begin
                reg_write_en = 1'b0;
            end

            // DIV/DIVS are valid multicycle instructions.
            // Disable ordinary single-cycle register writeback. The division execution path
            // will provide its result after completion.
            // Do not assert illegal_instr for a defined division encoding.

            else if (inst_v[27:25] == 3'b111) begin
                reg_write_en = 1'b0;
            end

            // For ADD, SUB, AND, OR, XOR, and NOT, retain
            // the standard ALU register-write behavior.

        end

        // If bit 29 is clear, decode a special immediate
        // instruction using the subopcode in bits [28:25].
        else begin

            case (inst_v[28:25])

                //======================
                // MOV: IMMEDIATE MOVE
                //========================
                // MOV Rd, #imm writes the zero-extended immediate into Rd.
                //
                // This instruction belongs to the data-immediate class.
                // use_imm must be asserted so EXE selects the immediate
                // rather than the source-register value.
                //
                // The immediate MOV encoding is unchanged.
                4'b0000: begin
                    is_mov = 1'b1;
                    use_imm = 1'b1;
                    reg_write_en = 1'b1;
                end

                // MOVT Rd, #imm:
                // Identify the upper-half immediate move.
                4'b0001: begin
                    is_movt = 1'b1;
                    use_imm = 1'b1;
                    reg_write_en = 1'b1;
                end

                // CLR Rd:
                // Select the special clear operation and
                // enable destination-register writeback.
                4'b0010: begin
                    is_clr = 1'b1;
                    reg_write_en = 1'b1;
                end

                // SET Rd:
                // Select the special set operation and
                // enable destination-register writeback.
                4'b0011: begin
                    is_set = 1'b1;
                    reg_write_en = 1'b1;
                end

                // LSL Rd, Rs, #imm:
                // Identify the immediate logical-left shift.
                4'b0100: begin
                    is_lsl = 1'b1;
                    use_imm = 1'b1;
                    reg_write_en = 1'b1;
                end

                // LSR Rd, Rs, #imm:
                // Identify the immediate logical-right shift.
                4'b0101: begin
                    is_lsr = 1'b1;
                    use_imm = 1'b1;
                    reg_write_en = 1'b1;
                end

                // MOVF Rd:
                // Select the move-from-flags operation.
                4'b0110: begin
                    is_movf = 1'b1;
                    reg_write_en = 1'b1;
                end

                // SAVF Rs:
                // Identify the save-flags operation.
                // This instruction does not write Rd.
                4'b1110: begin
                    is_savf = 1'b1;
                    reg_write_en = 1'b0;
                end

                // All remaining special-immediate subopcodes
                // are unsupported by the current decoder.
                //
                // Keep the previously assigned inactive
                // register/memory control defaults.
                default: begin
                    illegal_instr = 1'b1;
                end

            endcase
        end
    end

    //==============================
    // DATA REGISTER INSTRUCTIONS
    //==============================
    // Major opcode bits [31:30] = 01.
    //
    // These instructions use register operands and include:
    // - Standard ALU register instructions.
    // - Special register instructions such as PUSH and POP.

    else if (is_data_reg) begin

        // If bit 29 is set, decode a standard ALU operation
        // using the register-selected source operands
        if (inst_v[29] == 1'b1) begin

            // Select register operands for execution.
            use_imm = 1'b0;

            // Standard supported ALU instructions write Rd.
            reg_write_en = 1'b1;

            // If MUL/MULS is selected, microcode performs
            // both the lower-word and upper-word writebacks.
            // Disable the normal EXE register write.
            if (inst_v[27:25] == 3'b000) begin
                reg_write_en = 1'b0;
            end

            // DIV/DIVS register form.
            // The result comes from the multicycle division execution path, rather than
            // ordinary single-cycle ALU writeback.

            else if (inst_v[27:25] == 3'b111) begin
                reg_write_en = 1'b0;
            end

            // Remaining defined ALU operations retain their
            // ordinary execution and writeback controls.

        end

        // If bit 29 is clear, decode a special register
        // instruction using subopcode bits [28:25].
        else begin

            case (inst_v[28:25])

                //==================================
                // MOVR: REGISTER-TO-REGISTER MOVE
                //=================================
                // MOVR Rd, Rs copies the selected source register into Rd.
                //
                // The ISA renamed this assembly mnemonic from MOV to MOVR.
                // The encoding and execution control remain unchanged.
                //
                // use_imm stays zero for this register-form instruction.
                // EXE therefore selects reg_read_data_1_v.
                4'b0000: begin
                    is_mov = 1'b1;
                    reg_write_en = 1'b1;
                end

                // PUSH Rs:
                // Identify a stack push operation.
                // No ordinary destination-register write.
                4'b0001: begin
                    is_push = 1'b1;
                    reg_write_en = 1'b0;
                end

                // POP Rd:
                // Identify a stack pop operation and enable
                // destination-register writeback
                4'b0010: begin
                    is_pop = 1'b1;
                    reg_write_en = 1'b1;
                end

                // All remaining special-register subopcodes
                // are reserved or unsupported.
                // No register or memory control is enabled.
                default: begin
                    illegal_instr = 1'b1;
                end

            endcase
        end
    end

    //============================
    // LOAD / STORE INSTRUCTIONS
    //=============================
    // Major opcode bits [31:30] = 10.
    //
    // Bit 25 distinguishes memory access direction:
    // - 0: LOAD
    // - 1: STOR
    //
    // Immediate addressing is selected for both operations.

    else if (is_load_store) begin

        // Select the immediate addressing offset.
        use_imm = 1'b1;

        // If bit 25 is zero, request a data-memory read
        // and enable register writeback for the loaded value.
        if (inst_v[25] == 1'b0) begin

            data_mem_rd_en = 1'b1;
            reg_write_en = 1'b1;

        end

        // Otherwise, request a data-memory write.
        // STOR does not write an architectural destination
        // register through the ordinary register-write path
        else begin

            data_mem_wr_en = 1'b1;
            reg_write_en = 1'b0;

        end
    end

    //=============================
    // SYSTEM / BRANCH INSTRUCTIONS
    //==============================
    // Major opcode bits [31:30] = 11.
    //
    // Bits [28:25] identify the system/branch operation.
    //
    // The IF stage handles unconditional branch redirection.
    // Conditional branch evaluation occurs in branch-control
    // logic using the stored architectural flags.

    else if (is_sys_branch) begin

        case (inst_v[28:25])

            // B:
            // Unconditional PC-relative immediate branch.
            // Mark the instruction as a branch and select
            // the immediate offset for target calculation.
            4'b0000: begin
                is_branch = 1'b1;
                is_cond_branch = 1'b0;
                use_imm = 1'b1;
            end

            // B.cond:
            // Conditional PC-relative immediate branch.
            // Extract the condition field and request
            // conditional evaluation in branch-control.
            4'b0001: begin
                is_branch = 1'b1;
                is_cond_branch = 1'b1;
                branch_cond_v = inst_v[24:21];
                use_imm = 1'b1;
            end

            // BR:
            // Unconditional branch to a register value.
            // IF obtains the absolute target address through
            // the dedicated register-file branch read port
            4'b0010: begin
                is_branch = 1'b1;
                is_cond_branch = 1'b0;
                use_imm = 1'b1;
            end

            // NOP:
            // No architectural register or memory updates.
            // Other control outputs retain safe defaults.
            4'b0100: begin
                is_nop = 1'b1;
            end

            // HALT:
            // Request architectural processor termination.
            // No register or data-memory write is enabled.
            4'b1000: begin
                halt_f = 1'b1;
            end

            // Reserved/unsupported system instructions
            // assert the illegal-instruction indicator.
            // No architectural write control is enabled.
            default: begin
                illegal_instr = 1'b1;
            end

        endcase
    end

    // The major-class fields cover all defined 2-bit
    // instruction classes. If no class matches, all control
    // outputs retain their initialized default values

end

endmodule
