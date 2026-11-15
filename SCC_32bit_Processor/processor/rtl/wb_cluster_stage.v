// wb_cluster_stage.v
// Structural Writeback (WB) stage for the SCC.
//
// Responsibilities:
// - Select normal EXE or microcoded multiplication writeback.
// - Store all five architectural SNZCV flags.
// - Execute MOVF by copying stored SNZCV to a register.
// - Execute SAVF by restoring SNZCV from a source register.
//
// Hierarchy:
// - mul_integration selects normal/microcode results.
// - flags owns the architectural status flip-flops.
// - MOVF selection is combinational WB control.


module wb_cluster_stage (
    input wire alu_c_f,
    input wire alu_n_f,
    input wire alu_v_f,
    input wire alu_z_f,


    // Selected architectural register writeback to REGS.
    // Priority: DIV/DIVS, then POP, then ordinary EXE/MOVF/MUL.
    output wire [3:0] arch_reg_write_addr_v,
    output wire [31:0] arch_reg_write_data_v,
    output wire arch_reg_write_en,

    // Completed division register-write request.
    // The division controller supplies either Rd (quotient) or R12 (remainder).
    input wire div_reg_write_en,
    input wire [3:0] div_reg_write_addr_v,
    input wire [31:0] div_reg_write_data_v,

    // POP destination-register writeback from the stack datapath.
    // rd_addr_v identifies the decoded destination register.
    input wire [3:0] rd_addr_v,
    input wire stack_pop_write_en,
    input wire [31:0] stack_pop_data_v,

    // The combined multicycle stall prevents POP writeback during MUL/DIV.
    input wire multicycle_stall,

    output wire c_f,

    input wire clk,
    input wire clk_en,

    input wire [3:0] exe_reg_write_addr_v,
    input wire [31:0] exe_reg_write_data_v,
    input wire exe_reg_write_en,

    input wire [31:0] imm_v,

    input wire is_mul,

    // DIVS supplies registered quotient-based NZCV values when division completes.
    // Ordinary DIV preserves NZCV, and both instructions preserve the S flag.
    // Division register writeback is selected by this WB stage.

    input wire div_flags_write_en,
    input wire div_n_f,
    input wire div_z_f,
    input wire div_c_f,
    input wire div_v_f,

    // CP5 special flag-transfer instructions
    input wire is_movf,
    input wire is_savf,

    // PUSH/POP are decoded instruction controls.
    // Stack occupancy is supplied by the controller inside EXE_STAGE.
    // The current occupancy and full indication determine the S value to be committed
    // with the current stack instruction.

    input wire is_push,
    input wire is_pop,

    input wire [4:0] stack_depth_v,
    input wire stack_full,

    output wire [31:0] mul_operand_b_v,
    output wire n_f,

    input wire [31:0] reg_read_data_2_v,

    // Existing register-file read port used for
    // STOR/MOVT and now for the SAVF source value
    input wire [31:0] store_read_data_v,

    input wire rst,
    input wire set_flags,

    input wire ucode_c_f,
    input wire ucode_n_f,
    input wire [3:0] ucode_reg_write_addr_v,
    input wire [31:0] ucode_reg_write_data_v,
    input wire ucode_reg_write_en,
    input wire ucode_set_flags,
    input wire ucode_stall,
    input wire ucode_v_f,
    input wire ucode_z_f,

    input wire use_imm,

    // Architectural stored status outputs
    output wire s_f,
    output wire v_f,
    output wire z_f
);

//============================================
// MULTIPLICATION/EXE WRITEBACK INTERFACE
//==========================================
// Preserve the existing result-selection logic.
//
// These wires receive the original normal EXE or
// microcode writeback selected by mul_integration

wire [3:0] normal_write_addr_v;
wire [31:0] normal_write_data_v;
wire normal_write_en;

// Existing selected ALU/microcode flag values
wire arch_c_f;
wire arch_n_f;
wire arch_set_flags;
wire arch_v_f;
wire arch_z_f;

 // mul_integration already selects between ordinary ALU flags and MULS microcode flags.
 // DIVS introduces one additional source.
 //
 // Priority:
 // 1. DIVS completed-result flags.
 // 2. Existing ALU/MULS flag selection.
 //
 // These are combinational selection signals. Architectural flag state remains exclusively inside flags.v.
 // The S flag is intentionally excluded from this mux because division does not modify S.

 wire final_set_flags;
 wire final_n_f;
 wire final_z_f;
 wire final_c_f;
 wire final_v_f;


 // The division controller asserts its flag write request during STATE_WRITE_REM.
 // Otherwise, retain the existing arithmetic flag-update selection.

 assign final_set_flags = div_flags_write_en ? 1'b1 : arch_set_flags;

 //========================================
 // DIVS FLAG VALUES
 //========================================
 // N: Sign of the registered quotient.
 // Z: Registered quotient equals zero.
 // C: Cleared for DIVS.
 // V: Signed division overflow.
 //
 // For all other instructions, preserve the
 // values selected by mul_integration.

 assign final_n_f =
     div_flags_write_en ? div_n_f : arch_n_f;

 assign final_z_f =
     div_flags_write_en ? div_z_f : arch_z_f;

 assign final_c_f =
     div_flags_write_en ? div_c_f : arch_c_f;

 assign final_v_f =
     div_flags_write_en ? div_v_f : arch_v_f;



//========================================
// CP5 STACK-FULL STATUS CONTROL
//========================================
// The architectural S flag indicates whether
// all 16 stack entries are occupied.
//
// The stack controller owns the occupancy
// register, while FLAGS owns the S flip-flop.
//
// Both modules update on the rising clock
// edge. Therefore, S must be calculated from
// the occupancy expected AFTER the operation,
// not from the current stack_full signal alone.
//
// PUSH:
// - Depth 0 through 14: S becomes zero.
// - Depth 15: the PUSH fills the stack;
//   S becomes one.
// - Depth 16: the PUSH overwrites the top;
//   S remains one.
//
// POP:
// - Any nonempty POP reduces occupancy.
// - An empty POP leaves occupancy at zero.
// - In either case, S becomes zero.
//
// Ordinary instructions do not request an
// automatic S update.
//
// SAVF retains highest priority inside
// flags.v and may explicitly restore S.
//
// Microcode stall suppresses stack updates.
// Clock enable and reset remain controlled
// by the existing flags.v implementation.

wire stack_s_write_en;
wire stack_s_value;

wire stack_push_active;
wire stack_pop_active;

//========================================
// QUALIFY STACK INSTRUCTIONS
//========================================
// The decoder must not request PUSH and POP
// simultaneously during normal operation.
//
// Suppress both requests while a multicycle
// multiplication operation is stalled.

assign stack_push_active = is_push && !ucode_stall;
assign stack_pop_active  = is_pop  && !ucode_stall;

//========================
// S-FLAG WRITE ENABLE
//======================
// A valid PUSH or POP instruction updates S.
// When neither operation is selected, FLAGS preserves the previously stored S value.

assign stack_s_write_en = stack_push_active || stack_pop_active;

//=======================
// NEXT STACK-FULL VALUE
//======================
// A PUSH makes the stack full when occupancy is already 15 or 16.
// A POP always leaves the stack nonfull.
//
// The fallback value is zero because the write enable is inactive without a stack
// instruction; FLAGS will preserve S.
//
// stack_full explicitly covers occupancy 16. The comparison detects the 15-to-16 PUSH
// transition before the rising-edge update.

assign stack_s_value = stack_push_active && (stack_full || (stack_depth_v == 5'd15));


//================================
// CP5 SAVF STATUS RESTORATION
//================================
// SAVF identifies its source register through
// instruction bits [24:21].
//
// The existing dedicated read port supplies that
// register value through store_read_data_v.
//
// Only bits [4:0] are architecturally relevant.
//
// Microcode stall prevents unrelated instructions
// from updating architectural status during a
// multicycle multiplication operation.

wire savf_write_en;
wire [4:0] savf_data_v;

assign savf_write_en = is_savf && !ucode_stall;
assign savf_data_v = store_read_data_v[4:0];

//=============================
// CP5 MOVF REGISTER WRITEBACK
//===========================
// MOVF copies all five stored architectural flags
// into the lowest five bits of the destination.
//
// The upper 27 bits of the result are cleared.
//
// The destination address is already provided by
// ID through the normal EXE destination field.
//
// MOVF must not alter SNZCV or execute during a
// microcode stall.

wire [31:0] movf_result_v;
wire movf_write_en;

assign movf_result_v = {27'b0, s_f, n_f, z_f, c_f, v_f};
assign movf_write_en = is_movf && !ucode_stall;


//========================================
// ARCHITECTURAL REGISTER WRITEBACK
//========================================
// This stage selects the final architectural register write.
//
// Writeback priority:
// 1. DIV/DIVS quotient or remainder from the division controller.
// 2. POP data from the architectural stack.
// 3. MOVF flag snapshot.
// 4. Ordinary EXE or MUL/MULS result from mul_integration.
//
// DIV and POP take priority only when their write requests are active.
// MUL/DIV stalls suppress POP writeback to prevent an unrelated write.
//
// This selection is purely combinational. regs.v remains the only
// physical storage location for architectural registers R0-R13.

wire select_div_writeback;
wire select_pop_writeback;

wire base_reg_write_en;
wire [3:0] base_reg_write_addr_v;
wire [31:0] base_reg_write_data_v;

//========================================
// NORMAL EXE / MOVF / MUL WRITEBACK
//========================================
// Preserve the original MOVF override and MUL integration behavior.
// MOVF uses the decoded destination address already provided by EXE.

assign base_reg_write_en = movf_write_en ? 1'b1 : normal_write_en;

assign base_reg_write_addr_v = normal_write_addr_v;

assign base_reg_write_data_v = movf_write_en ? movf_result_v : normal_write_data_v;

//========================================
// DIVISION WRITEBACK SELECTION
//========================================
// DIV/DIVS write quotient and remainder on separate clock cycles.
// Do not suppress this selection during div_stall: division results
// are intentionally written while instruction fetch is stalled.

assign select_div_writeback = div_reg_write_en;

//========================================
// POP WRITEBACK SELECTION
//========================================
// A valid POP writes the memory result, or zero when the stack is empty.
// Suppress POP selection whenever multicycle arithmetic is active.

assign select_pop_writeback = is_pop && stack_pop_write_en && !multicycle_stall;

//========================================
// FINAL REGISTER WRITE ENABLE
//========================================
// Division has highest priority, followed by POP and normal writeback.

assign arch_reg_write_en =
    select_div_writeback ? 1'b1 :
    select_pop_writeback ? 1'b1 :
    base_reg_write_en;

//========================================
// FINAL DESTINATION REGISTER
//========================================
// DIV selects Rd or R12, POP selects its decoded destination,
// and ordinary instructions use the existing selected address.

assign arch_reg_write_addr_v =
    select_div_writeback ? div_reg_write_addr_v :
    select_pop_writeback ? rd_addr_v :
    base_reg_write_addr_v;

//========================================
// FINAL REGISTER WRITE DATA
//========================================
// Select destination and data with identical priority conditions.
// This prevents a valid write enable from targeting the wrong register.

assign arch_reg_write_data_v =
    select_div_writeback ? div_reg_write_data_v :
    select_pop_writeback ? stack_pop_data_v :
    base_reg_write_data_v;


//========================================
// ORIGINAL MULTIPLICATION INTEGRATION
//=======================================
// The existing module continues to arbitrate
// ordinary execution and MUL/MULS writeback.
//
// Only its outward writeback connections now
// feed the MOVF selection above.

mul_integration MUL_INTEGRATION (
    .is_mul (is_mul),
    .use_imm (use_imm),
    .ucode_stall (ucode_stall),
    .reg_operand_b_v (reg_read_data_2_v),
    .imm_v (imm_v),
    .mul_operand_b_v (mul_operand_b_v),

    .exe_reg_write_en (exe_reg_write_en),
    .exe_reg_write_addr_v (exe_reg_write_addr_v),
    .exe_reg_write_data_v (exe_reg_write_data_v),

    .ucode_reg_write_en (ucode_reg_write_en),
    .ucode_reg_write_addr_v (ucode_reg_write_addr_v),
    .ucode_reg_write_data_v (ucode_reg_write_data_v),

    .reg_write_en_out (normal_write_en),
    .reg_write_addr_v (normal_write_addr_v),
    .reg_write_data_v (normal_write_data_v),

    .set_flags (set_flags),
    .alu_n_f (alu_n_f),
    .alu_z_f (alu_z_f),
    .alu_c_f (alu_c_f),
    .alu_v_f (alu_v_f),

    .ucode_set_flags (ucode_set_flags),
    .ucode_n_f (ucode_n_f),
    .ucode_z_f (ucode_z_f),
    .ucode_c_f (ucode_c_f),
    .ucode_v_f (ucode_v_f),

    .set_flags_out (arch_set_flags),
    .n_f_out (arch_n_f),
    .z_f_out (arch_z_f),
    .c_f_out (arch_c_f),
    .v_f_out (arch_v_f)
);

//====================================
// ARCHITECTURAL SNZCV FLAG STORAGE
//===================================
// The flags module is the only location
// containing architectural flag flip-flops.
//
// Normal flag-setting instructions update NZCV.
// SAVF replaces all five stored flags.
// PUSH/POP update S independently of arithmetic NZCV updates.

flags FLAGS (
    .clk (clk),
    .rst (rst),
    .clk_en (clk_en),

    // Select the completed DIVS result when requested, otherwise use the existing
    // ordinary ALU/MULS flag source.
    // SAVF retains priority inside flags.v. Stack S updates remain independent.

    .set_flags (final_set_flags),

    .alu_n_f (final_n_f),
    .alu_z_f (final_z_f),
    .alu_c_f (final_c_f),
    .alu_v_f (final_v_f),

    .stack_s_write_en (stack_s_write_en),
    .stack_s_value (stack_s_value),

    .savf_write_en (savf_write_en),
    .savf_data_v (savf_data_v),

    .s_f (s_f),
    .n_f (n_f),
    .z_f (z_f),
    .c_f (c_f),
    .v_f (v_f)
);

endmodule
