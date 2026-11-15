// id_control_stage.v
// Structural stage wrapper. Preserves original leaf module behavior.
// All internal signals are wires; architectural state remains in leaf modules.

module id_control_stage (
    output wire [2:0] alu_op_v,
    input wire c_f,
    output wire condition_met,
    output wire data_mem_rd_en,
    output wire data_mem_wr_request,
    output wire [1:0] err_f,
    output wire halt_f,

    // Asserted by the division controller after
    // a DIV/DIVS instruction encounters a zero divisor.
    // This is an internal processor signal, not an additional class-defined top-level port.
    // A division exception reports status 2'b10 and requests processor termination.
    input wire div_error,

    output wire [31:0] imm_v,
    input wire [31:0] inst_mem_v,
    output wire is_alu,
    output wire is_clr,
    output wire is_cond_branch,
    output wire is_load_store,
    output wire is_lsl,
    output wire is_lsr,
    output wire is_mov,
    output wire is_movt,

    // CP5 flag-transfer instructions.
    // These controls are decoded by id_stage.v and forwarded to the writeback stage
    output wire is_movf,
    output wire is_savf,

    // Forward MUL/MULS and DIV/DIVS recognition from the combinational instruction decoder.
    // These are instruction-identification signals. Multicycle execution and architectural
    // writeback are handled by later stages.
    //
    // Keep multiplication and division separate so the execution controller can distinguish
    // between the two arithmetic operations.

    output wire is_mul,
    output wire is_div,

    output wire is_set,

    // Forward PUSH and POP recognition from the existing id_stage.v decoder.
    // These signals identify the current architectural stack instruction.
    //
    // PUSH requests a stack-memory write.
    // POP requests a stack-memory read and
    // destination-register writeback.
    //
    // Stack occupancy, pointer updates, and memory timing remain the responsibility
    // of the later execution stages.

    output wire is_push,
    output wire is_pop,

    input wire n_f,
    output wire [3:0] rd_addr_v,
    output wire reg_write_en,
    output wire [3:0] rs1_addr_v,
    output wire [3:0] rs2_addr_v,
    output wire set_flags,
    output wire use_imm,
    input wire v_f,
    input wire z_f
);

// Keep instruction decoding separate from architectural status and exception handling.
// decoded_halt_f is asserted only by the architectural HALT instruction.
// div_error originates from the division FSM. A divide-by-zero exception must also request
// termination and produce error status 2'b10.

wire [3:0] branch_cond_v;
wire illegal_instr;
wire decoded_halt_f;
wire status_error_request;
wire is_branch;
wire is_data_imm;
wire is_data_reg;
wire is_nop;
wire is_sys_branch;


// A normal HALT instruction requests termination.
// Division by zero also requests termination, but must be reported as an error rather than
// as a successful HALT.
//
// The error_status module retains responsibility for encoding the architectural status.

assign halt_f = decoded_halt_f || div_error;

assign status_error_request = illegal_instr || div_error;

// Original id_stage instance
id_stage ID (
    .inst_v (inst_mem_v),
    .rd_addr_v (rd_addr_v),
    .rs1_addr_v (rs1_addr_v),
    .rs2_addr_v (rs2_addr_v),
    .imm_v (imm_v),
    .is_data_imm (is_data_imm),
    .is_data_reg (is_data_reg),
    .is_load_store (is_load_store),
    .is_sys_branch (is_sys_branch),
    .is_alu (is_alu),
    .alu_op_v (alu_op_v),
    .set_flags (set_flags),
    .use_imm (use_imm),

    // Forward the decoded multiplication and division controls without modifying them.
    //
    // The leaf decoder owns instruction classification. This wrapper only
    // connects the corresponding signals.

    .is_mul (is_mul),
    .is_div (is_div),

    .reg_write_en (reg_write_en),
    .data_mem_rd_en (data_mem_rd_en),
    .data_mem_wr_en (data_mem_wr_request),
    .is_branch (is_branch),
    .is_cond_branch (is_cond_branch),
    .branch_cond_v (branch_cond_v),

    // HALT from instruction decoding only.
    // Division exceptions are combined outside ID.
    .halt_f (decoded_halt_f),

    .is_nop (is_nop),
    .is_mov (is_mov),
    .is_movt (is_movt),
    .is_movf (is_movf),
    .is_savf (is_savf),
    .is_clr (is_clr),
    .is_set (is_set),
    .is_lsl (is_lsl),
    .is_lsr (is_lsr),
    .is_push (is_push),
    .is_pop (is_pop),
    .illegal_instr (illegal_instr)
);

// Original branch_control instance
branch_control BRANCH_CONTROL (
    .branch_cond_v (branch_cond_v),
    .n_f (n_f),
    .z_f (z_f),
    .c_f (c_f),
    .v_f (v_f),
    .condition_met (condition_met)
);

//===============================
// ARCHITECTURAL PROCESSOR STATUS
//================================
// Reuse the original combinational status encoder
//
// Priority within error_status.v:
// 1. Error condition: err_f = 2'b10.
// 2. Normal HALT: err_f = 2'b01.
// 3. Normal execution:err_f = 2'b00.
//
// Division by zero is treated as an error even though halt_f is also asserted.
// The existing error_status module does not require a new port or additional state.

error_status ERROR_STATUS (
    .illegal_instr (status_error_request),
    .halt_f (halt_f),
    .err_f (err_f)
);

endmodule
