// mul_integration.v
// Combinational datapath integration for normal SCC execution
// and microcoded signed multiplication.
//
// Responsibilities:
// - Select the second MUL operand from a register or immediate.
// - Select ordinary EXE or microcode register writeback.
// - Select ordinary ALU or microcode architectural flag values.
// - Prevent ordinary EXE writeback while MUL/MULS is active.
// - Provide a single register-file writeback interface.
// - Provide a single architectural NZCV update interface.
//
// Design Notes:
// - No architectural state is stored in this module.
// - All outputs are driven by continuous combinational assignments.
// - The microcode controller manages multicycle MUL/MULS timing.
// - Ordinary EXE handles normal single-cycle instructions.
// - The register file performs architectural writes on clock edges.
// - The flags module stores architectural NZCV on clock edges.
// - This module selects between execution paths but does not
//   independently generate register-write timing.

module mul_integration (
    // Decoded multiplication and execution-control inputs
    input wire is_mul,
    input wire use_imm,
    input wire ucode_stall,

    // MUL operand B sources and selected operand output
    input wire [31:0] reg_operand_b_v,
    input wire [31:0] imm_v,
    output wire [31:0] mul_operand_b_v,

    // Ordinary EXE register-writeback interface
    input wire exe_reg_write_en,
    input wire [3:0] exe_reg_write_addr_v,
    input wire [31:0] exe_reg_write_data_v,

    // Microcode register-writeback interface
    input wire ucode_reg_write_en,
    input wire [3:0] ucode_reg_write_addr_v,
    input wire [31:0] ucode_reg_write_data_v,

    // Selected architectural register-writeback interface
    output wire reg_write_en_out,
    output wire [3:0] reg_write_addr_v,
    output wire [31:0] reg_write_data_v,

    // Ordinary ALU flag-update request and calculated NZCV
    input wire set_flags,
    input wire alu_n_f,
    input wire alu_z_f,
    input wire alu_c_f,
    input wire alu_v_f,

    // Microcode MULS flag-update request and calculated NZCV
    input wire ucode_set_flags,
    input wire ucode_n_f,
    input wire ucode_z_f,
    input wire ucode_c_f,
    input wire ucode_v_f,

    // Selected architectural flag-update interface
    output wire set_flags_out,
    output wire n_f_out,
    output wire z_f_out,
    output wire c_f_out,
    output wire v_f_out
);

//====================================
// MULTIPLICATION OPERAND B SELECTION
//=====================================
// The instruction decoder supports register and immediate
// operand forms of the MUL/MULS instructions.
//
// If use_imm is asserted, select the 32-bit sign-extended
// immediate produced by the instruction decoder.
//
// Otherwise, select the second source-register value.
//
// The multiplication controller interprets the selected
// operand according to the signed MUL instruction semantics.
//
// This multiplexer is combinational and does not introduce
// an additional clock cycle or register

assign mul_operand_b_v = use_imm ? imm_v : reg_operand_b_v;

//==============================================
// NORMAL EXECUTION / MICROCODE SOURCE SELECTION
//================================================
// Select between the ordinary single-cycle EXE datapath
// and the multicycle microcode execution path.
//
// Microcode selection conditions:
// 1. is_mul = 1:
//    The current architectural instruction is MUL or MULS.
//    Select microcode even during the initial instruction
//    capture phase before the controller enters a stall.
// 2. ucode_stall = 1:
//    The controller is holding normal instruction
//    advancement while a multicycle operation is active.
//    Continue selecting microcode during this interval.
//
// If both signals are low, select ordinary EXE
//
// Including both conditions avoids returning to the
// ordinary execution datapath prematurely while the
// current PC still identifies a multiplication instruction.
//
// This signal controls both the register-writeback and flag-result multiplexers below.

wire select_ucode;

assign select_ucode = is_mul || ucode_stall;

//===============================================
// ARCHITECTURAL REGISTER WRITEBACK MULTIPLEXER
//================================================
// The register file has one synchronous architectural
// write port shared by ordinary EXE and microcode.
//
// If select_ucode is asserted, select the microcode
// register-write enable, destination, and result.
//
// Otherwise, select the corresponding ordinary EXE values.
//
// The selection applies to all three writeback signals
// together so the enable, address, and data originate
// from the same execution source
//
// The microcode controller is responsible for generating
// the correct write-enable pulses during MUL/MULS.
//
// This module does not directly update register storage

assign reg_write_en_out = select_ucode ? ucode_reg_write_en : exe_reg_write_en;

assign reg_write_addr_v = select_ucode ? ucode_reg_write_addr_v : exe_reg_write_addr_v;

assign reg_write_data_v = select_ucode ? ucode_reg_write_data_v : exe_reg_write_data_v;

//=============================================
// ARCHITECTURAL NZCV FLAG-UPDATE MULTIPLEXER
//==============================================
// Ordinary flag-setting ALU instructions use the
// calculated NZCV values supplied by EXE.
//
// MULS uses calculated flag values generated by the
// microcode multiplication system.
//
// Plain MUL must preserve the previously stored NZCV
// values by keeping ucode_set_flags deasserted.
//
// If select_ucode is asserted, choose the microcode
// flag-update request and calculated NZCV values.
//
// Otherwise, choose the ordinary ALU flag-update request
// and corresponding calculated NZCV values.
//
// The flags module performs the actual synchronous
// architectural update when the selected write enable
// and processor clock enable are both active.
//
// Selecting the values does not itself modify the
// architectural flags

assign set_flags_out = select_ucode ? ucode_set_flags : set_flags;

assign n_f_out = select_ucode ? ucode_n_f : alu_n_f;

assign z_f_out = select_ucode ? ucode_z_f : alu_z_f;

assign c_f_out = select_ucode ? ucode_c_f : alu_c_f;

assign v_f_out = select_ucode ? ucode_v_f : alu_v_f;

endmodule
