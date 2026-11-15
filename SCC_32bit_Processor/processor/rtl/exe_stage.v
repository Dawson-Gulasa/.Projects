// exe_stage.v
//
// Description:
// Combinational Execution (EXE) stage for the SCC processor.
//
// Responsibilities:
// - Select register or immediate operands for the ALU.
// - Instantiate the ALU for arithmetic and logical operations.
// - Execute MOV, MOVT, CLR, SET, LSL, and LSR instructions.
// - Calculate effective addresses for LOAD and STOR.
// - Select architectural register-writeback data.
// - Supply store data and calculated memory addresses.
// - Expose calculated ALU flags to the flag-control logic.
//
// Design Notes:
// - This module contains combinational logic only.
// - No architectural registers or flip-flops are stored here.
// - Register writes occur in regs.v using a synchronous write port.
// - Architectural NZCV flags are maintained separately.
// - Multiplication writeback is handled by the microcode system.
// - Memory-write timing is controlled by a separate module.
//

module exe_stage (
    // Register-file operand data.
    // The first two inputs provide arithmetic/source operands.
    // store_read_data_v provides the current Rd value needed
    // by MOVT and the store-data value needed by STOR.
    input [31:0] reg_read_data_1_v,
    input [31:0] reg_read_data_2_v,
    input [31:0] store_read_data_v,

    // Decoded instruction information.
    // imm_v contains the sign-extended immediate produced by ID.
    // use_imm determines whether operand B is immediate or register.
    input [31:0] imm_v,
    input [3:0] rd_addr_v,
    input [2:0] alu_op_v,
    input is_alu,
    input use_imm,
    input reg_write_en,

    // Special instruction and memory-class identifiers.
    input is_mov,
    input is_movt,
    input is_load_store,

    // Data-memory read interface.
    // data_mem_rd_en distinguishes LOAD from STOR when the
    // current instruction belongs to the load/store class.
    input [31:0] data_mem_in_v,
    input data_mem_rd_en,

    // Additional special-instruction identification.
    input is_clr,
    input is_set,
    input is_lsl,
    input is_lsr,

    // Register-file writeback request and data.
    // These are combinational outputs; the register file
    // performs the actual write on an enabled clock edge.
    output reg reg_write_en_out,
    output reg [3:0] reg_write_addr_v,
    output reg [31:0] reg_write_data_v,

    // Data-memory address and write-data outputs.
    // The memory control logic determines when data is written.
    output reg [31:0] data_mem_addr_v,
    output reg [31:0] data_mem_out_v,

    // Combinational ALU status outputs.
    // Architectural flags are stored outside this module.
    output alu_n_f,
    output alu_z_f,
    output alu_c_f,
    output alu_v_f
);

//=====================
// INTERNAL ALU SIGNALS
//=======================
// The operands are selected before reaching the ALU.
// The ALU result is supplied to the writeback selection logic

reg [31:0] alu_operand_a_v;
reg [31:0] alu_operand_b_v;
wire [31:0] alu_result_v;

//====================================
// COMBINATIONAL ALU OPERAND SELECTION
//====================================
// Operand A always receives the first register source.
//
// Operand B uses one of two sources:
// - If use_imm is asserted, select the decoded immediate.
// - Otherwise, select the second register source.
//
// Both operands are assigned for every input combination,
// so no combinational latch is inferred.
//
// Blocking assignments (=) are used because this block
// contains no clocked storage.

always @(*) begin

    // Always use the first source register as operand A.
    alu_operand_a_v = reg_read_data_1_v;

    // If ID selects immediate addressing, supply the
    // sign-extended immediate as ALU operand B
    if (use_imm) begin
        alu_operand_b_v = imm_v;
    end

    // Otherwise, use the second source-register value.
    else begin
        alu_operand_b_v = reg_read_data_2_v;
    end

end

//===========================
// ALU MODULE INSTANTIATION
//==========================
// The ALU performs the selected arithmetic or logical
// operation using the operands prepared above.
//
// Its result is used for ordinary ALU register writeback.
//
// Its N, Z, C, and V outputs represent calculated flags.
// Separate architectural flag logic determines when
// those values are stored.

alu ALU (
    .operand_a_v (alu_operand_a_v),
    .operand_b_v (alu_operand_b_v),
    .alu_op_v (alu_op_v),

    .result_v (alu_result_v),

    .n_f (alu_n_f),
    .z_f (alu_z_f),
    .c_f (alu_c_f),
    .v_f (alu_v_f)
);

//==================================================
// COMBINATIONAL EXECUTION AND WRITEBACK SELECTION
//=====================================================
// Select the value written to the architectural register
// file and generate LOAD/STOR memory address/data outputs.
//
// All outputs receive safe default values first.
// Instruction-specific logic overrides only those defaults
// required by the decoded operation.
//
// Selection priority:
// 1. Standard ALU operation.
// 2. MOV.
// 3. MOVT.
// 4. CLR.
// 5. SET.
// 6. LSL.
// 7. LSR.
// 8. LOAD/STOR.
//
// For legal instructions, decode should assert the
// appropriate instruction classification/control signals.
//
// If no supported execution condition is selected,
// register writing remains disabled and the data-memory
// outputs remain at their default values.
//
// All procedural assignments use blocking (=) because
// this module implements combinational execution logic.

always @(*) begin

    //--------------------------------------
    // DEFAULT REGISTER-WRITEBACK CONTROLS
    //--------------------------------------
    // Disable architectural register writing unless the
    // current decoded instruction explicitly requests it.
    //
    // Preserve the decoded destination address so each
    // supported instruction writes to the expected register.
    //
    // Initialize writeback data to zero for operations
    // that do not produce an architectural register result.

    reg_write_en_out = 1'b0;
    reg_write_addr_v = rd_addr_v;
    reg_write_data_v = 32'h0000_0000;

    //-----------------------------
    // DEFAULT DATA-MEMORY SIGNALS
    //-----------------------------
    // Memory address and write data default to zero.
    // These values are replaced for LOAD/STOR instructions.

    data_mem_addr_v = 32'h0000_0000;
    data_mem_out_v = 32'h0000_0000;

    //=============================
    // STANDARD ALU INSTRUCTIONS
    //=============================
    // If the decoded instruction is a standard ALU
    // operation, select the ALU result for register writeback.
    //
    // reg_write_en originates in ID and determines whether
    // the result is committed to the register file.
    //
    // For microcoded multiplication, ID disables ordinary
    // register writing; the microcode system performs
    // the required lower-word and upper-word writebacks

    if (is_alu) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = alu_result_v;
    end

    //===========================
    // MOV AND MOVR INSTRUCTIONS
    //==========================
    // The ISA distinguishes immediate MOV from register-source MOVR.
    // MOV:
    // - use_imm is asserted.
    // - Zero-extend the 16-bit immediate into the 32-bit destination.
    // MOVR:
    // - use_imm is deasserted.
    // - Copy the first source-register value into the destination.
    //
    // Both instructions share the existing is_mov execution control.
    // The ISA mnemonic was renamed to MOVR without changing its encoding.

    else if (is_mov) begin
        reg_write_en_out = reg_write_en;

        // If use_imm is asserted, zero-extend the immediate
        // field instead of using its sign-extended upper bits
        if (use_imm) begin
            reg_write_data_v = {16'h0000, imm_v[15:0]};
        end

        // Otherwise, copy the selected source-register value
        else begin
            reg_write_data_v = reg_read_data_1_v;
        end
    end

    //====================
    // MOVT INSTRUCTION
    //==================
    // Otherwise, if MOVT is decoded, replace the upper
    // sixteen bits of Rd with the immediate's lower 16 bits.
    //
    // The lower sixteen bits of Rd must remain unchanged.
    // store_read_data_v supplies the current destination
    // register value through the dedicated register-file port.
    //
    // Result = {immediate[15:0], original_Rd[15:0]}.

    else if (is_movt) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = {imm_v[15:0], store_read_data_v[15:0]};
    end

    //=================
    // CLR INSTRUCTION
    //================
    // Otherwise, if CLR is decoded, write zero to all
    // thirty-two bits of the destination register

    else if (is_clr) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = 32'h0000_0000;
    end

    //================
    // SET INSTRUCTION
    //==================
    // Otherwise, if SET is decoded, write ones to all
    // thirty-two bits of the destination register

    else if (is_set) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = 32'hFFFF_FFFF;
    end

    //==================
    // LSL INSTRUCTION
    //==================
    // Otherwise, if logical shift left is decoded, shift
    // the source-register value left by the immediate amount
    //
    // Bits shifted out of the upper end are discarded.
    // Vacated lower bits are filled with zero.

    else if (is_lsl) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = reg_read_data_1_v << imm_v;
    end

    //====================
    // LSR INSTRUCTION
    //==================
    // Otherwise, if logical shift right is decoded, shift
    // the source-register value right by the immediate amount.
    //
    // Vacated upper bits are filled with zero, regardless
    // of the sign bit of the source register

    else if (is_lsr) begin
        reg_write_en_out = reg_write_en;
        reg_write_data_v = reg_read_data_1_v >> imm_v;
    end

    //============================
    // LOAD / STORE INSTRUCTIONS
    //============================
    // Otherwise, if a memory instruction is decoded,
    // calculate the effective memory address:
    //
    // Effective Address = Base Register + Signed Immediate
    //
    // Both LOAD and STOR use the same address calculation.
    //
    // The data_mem_rd_en control distinguishes the operation:
    // - 1: LOAD from memory into the destination register.
    // - 0: STOR a register value into data memory.
    //
    // STACK_MEMORY_BUS receives the decoded STOR request and the
    // effective address/write data calculated by this module.
    //
    // The shared memory bus arbitrates ordinary and stack accesses
    // and qualifies the external write enable during the low clock phase.
    //
    // This execution module only calculates address and data values;
    // it does not generate the external memory-write strobe.

    else if (is_load_store) begin

        // Calculate the effective address for either
        // LOAD or STOR using the first source register
        // and the decoded signed immediate offset.
        data_mem_addr_v = reg_read_data_1_v + imm_v;

        // If data-memory read enable is asserted, perform
        // the LOAD data path by selecting returned memory
        // data for destination-register writeback.
        if (data_mem_rd_en) begin
            reg_write_en_out = reg_write_en;
            reg_write_data_v = data_mem_in_v;
        end

        // Otherwise, select STOR behavior.
        // Supply the destination-register value to memory
        // without requesting architectural register writeback
        else begin
            data_mem_out_v = store_read_data_v;
        end
    end

    // If no instruction condition is asserted, the safe
    // default output values remain in effect.

end

endmodule
