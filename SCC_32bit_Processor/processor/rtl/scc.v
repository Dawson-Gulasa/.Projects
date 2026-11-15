// scc.v
//
// Responsibilities:
// - Connect five functional blocks plus REGS: IF, ID, EXE, MEM, WB,
//   architectural registers, and architectural NZCV flag storage.
// - Connect conditional branch evaluation and processor status.
// - EXE_STAGE groups ordinary execution with MUL microcode control and ROM.
// - WB_STAGE selects all architectural register writeback sources.
// - WB_STAGE also stores SNZCV and handles flag-transfer instructions.
// - ID_STAGE groups decode with branch and status evaluation.
// - STACK_MEMORY_BUS arbitrates ordinary LOAD/STOR and stack PUSH/POP.
// - Memory writes are qualified to the low clock phase.
// - IF and REGS retain their original state ownership.
// - Expose instruction/data memory interfaces to the system top.
//
// Architectural Ownership:
// - IF owns the program counter and changes the fetch address.
// - REGS owns R0-R13; R14 reads as zero and R15 reads IF's PC.
// - WB_STAGE.FLAGS owns the clocked architectural NZCV bits.
// - ID_STAGE.ID produces instruction classification and control signals.
// - EXE_STAGE.EXE produces normal execution and memory signals.
// - EXE_STAGE.UCODE_CONTROLLER owns multiplication state.
// - WB_STAGE.MUL_INTEGRATION selects writeback and flag sources.
// - STACK_MEMORY_BUS owns the external data-memory interface.
// - Architectural register updates remain synchronous to the rising edge.
// No leaf datapath logic or timing expressions were changed in CP4-R15.

module scc(
    // SYSTEM INPUTS
    input clk,  // System clock
    input clk_en,  // System clock enable
    input rst,  // System reset

    // MEMORY INPUTS
    input [31:0] inst_mem_v,  // Instruction value returned by memory
    input [31:0] data_mem_in_v,  // Data value returned by memory

    // STATUS OUTPUTS
    output [1:0] err_f,  // Processor error/status indicator
    output halt_f,  // Indicates that processor execution has halted

    // INSTRUCTION MEMORY OUTPUTS
    output inst_mem_en,  // Enables an instruction memory access
    output [31:0] inst_mem_addr_v,  // Address sent to instruction memory

    // DATA MEMORY OUTPUTS
    output [31:0] data_mem_addr_v,  // Address sent to data memory
    output [31:0] data_mem_out_v,  // Data value sent to memory for a write
    output data_mem_rd_en,  // Enables a data memory read
    output data_mem_wr_en  // Enables a data memory write
);

    //=====================
    // Internal Signals
    //===================

    // IF stage signals
    wire [31:0] pc_v;
    wire [3:0] branch_reg_addr_v;
    wire [31:0] branch_reg_v;

    // ID register-address signals
    wire [3:0] rd_addr_v;
    wire [3:0] rs1_addr_v;
    wire [3:0] rs2_addr_v;

    // Register-file read values
    wire [31:0] reg_read_data_1_v;
    wire [31:0] reg_read_data_2_v;
    wire [31:0] store_read_data_v;

    // ID immediate and instruction classification
    wire [31:0] imm_v;

    wire is_load_store;

    // ID ALU controls
    wire is_alu;
    wire [2:0] alu_op_v;
    wire set_flags;
    wire use_imm;

    // ID_STAGE identifies MUL/MULS and DIV/DIVS.
    // MUL/MULS already use the multiplication microcode controller.
    // DIV/DIVS will use a separate multicycle execution path with coordinated writeback.
    // These wires contain decoded instruction information only; they store no state.

    wire is_mul;
    wire is_div;

    // ID register-file control
    wire reg_write_en;

    // ID branch/system controls
    wire is_cond_branch;

    // Conditional branch decision
    wire condition_met;

    // ID special-instruction controls
    wire is_mov;
    wire is_movt;

    // MOVF reads stored SNZCV into a destination
    // SAVF restores SNZCV from a source register
    wire is_movf;
    wire is_savf;

    wire is_clr;
    wire is_set;
    wire is_lsl;
    wire is_lsr;

    //===============================
    // CP5 STACK CONTROL AND STATUS
    //=================================
    // PUSH and POP are decoded in ID.
    //
    // The stack controller is located inside EXE_STAGE and reports occupancy status.
    // Stack outputs control architectural R13 updates, shared data-memory
    // transactions, POP destination writeback, and the S status flag.
    wire is_push;
    wire is_pop;

    wire [4:0] stack_depth_v;
    wire stack_full;
    wire stack_empty;

    //================================
    // STACK DATAPATH INTERCONNECT
    //============================
    // R13 is physically stored in regs.v.
    // EXE reads R13 and calculates memory addresses and stack-pointer updates.
    //
    // The write requests below remain uncommitted until the memory and
    // writeback timing is integrated.

    wire [31:0] stack_sp_v;

    // Stack-memory read/write requests
    wire stack_mem_rd_request;
    wire stack_mem_wr_request;

    // Stack-memory address and store data
    wire [31:0] stack_mem_addr_v;
    wire [31:0] stack_mem_out_v;

    // Architectural R13 update interface
    wire stack_sp_write_en;
    wire [31:0] stack_sp_next_v;

    // POP destination-register writeback
    wire stack_pop_write_en;
    wire [31:0] stack_pop_data_v;

    // ID validity signal

    // EXE register-file writeback signals
    wire exe_reg_write_en;
    wire [3:0] exe_reg_write_addr_v;
    wire [31:0] exe_reg_write_data_v;

    // EXE calculated ALU flags
    wire alu_n_f;
    wire alu_z_f;
    wire alu_c_f;
    wire alu_v_f;

    // Architectural SNZCV flags.
    // S tracks stack-full status and can also be restored explicitly through SAVF.
    // NZCV retain the original branch/ALU usage.
    wire s_f;
    wire n_f;
    wire z_f;
    wire c_f;
    wire v_f;


    //====================================
    // ORDINARY DATA-MEMORY INTERCONNECT
    //==================================
    // ID supplies ordinary LOAD/STOR requests.
    // EXE supplies ordinary memory address/data.
    //
    // The shared memory bus selects between these ordinary signals and stack memory.
    // The external data-memory outputs are  driven only by STACK_MEMORY_BUS.

    wire normal_mem_rd_request;
    wire data_mem_wr_request;

    wire [31:0] normal_mem_addr_v;
    wire [31:0] normal_mem_out_v;


    //===============================
    // MICROCODE CONTROL SIGNALS
    //=============================

    // ROM address and returned microinstruction

    //========================================
    // MULTICYCLE EXECUTION CONTROL
    //========================================
    // The multiplication microcode controller
    // and division controller have separate
    // execution-stall outputs.
    //
    // IF must hold the current instruction
    // while either operation is incomplete.
    //
    // The combined stall does not introduce
    // additional sequential state.

    wire ucode_stall;
    wire div_stall;
    wire multicycle_stall;

    //====================================
    // DIVISION CONTROLLER INTERCONNECT
    //===================================
    // Division produces two separate register
    // writes: quotient to Rd and remainder to R12.
    //
    // DIVS additionally requests an NZCV update.
    // The S flag remains independently owned by the architectural flags module.
    // A divide-by-zero condition must ultimately halt execution and suppress writeback.

    wire div_error;

    wire div_reg_write_en;
    wire [3:0] div_reg_write_addr_v;
    wire [31:0] div_reg_write_data_v;

    wire div_flags_write_en;
    wire div_n_f;
    wire div_z_f;
    wire div_c_f;
    wire div_v_f;

    // Either multicycle controller can stall instruction fetch.
    // Both requests are combined through a single continuous assignment.

    assign multicycle_stall = ucode_stall || div_stall;

    //================================
    // TERMINAL STATUS FETCH HOLD
    //================================
    // HALT (err_f = 2'b01) and an illegal instruction (err_f = 2'b10)
    // must stop execution. Freezing the PC keeps the terminating
    // instruction in decode, so halt_f and err_f remain asserted and
    // no instruction after HALT can modify registers or memory.
    //
    // Divide-by-zero already holds fetch through its own sticky
    // ERROR state; including it here is harmless.
    //
    // Kept separate from multicycle_stall because that signal also
    // qualifies POP writeback.

    wire terminal_stall;
    wire fetch_stall;

    assign terminal_stall = (err_f != 2'b00);
    assign fetch_stall = multicycle_stall || terminal_stall;

    // Selected register/immediate multiplication operand B
    wire [31:0] mul_operand_b_v;

    // Microcode register writeback
    wire ucode_reg_write_en;
    wire [3:0] ucode_reg_write_addr_v;
    wire [31:0] ucode_reg_write_data_v;

    // Microcode MULS flags
    wire ucode_set_flags;
    wire ucode_n_f;
    wire ucode_z_f;
    wire ucode_c_f;
    wire ucode_v_f;


    //========================================
    // ARCHITECTURAL WRITEBACK INTERFACE
    //========================================
    // WB_STAGE selects the final destination, write data, and write enable
    // for DIV/DIVS, POP, MOVF, ordinary EXE, and MUL/MULS operations.
    //
    // SCC only connects the selected signals between WB_STAGE and REGS.
    // Architectural register storage remains exclusively inside regs.v.
    wire arch_reg_write_en;
    wire [3:0] arch_reg_write_addr_v;
    wire [31:0] arch_reg_write_data_v;


    // Suppress ordinary ALU flag updates during
    // DIV/DIVS. DIVS flags will be committed from the division controller in WB_STAGE.

    wire normal_set_flags;

    //==================================
    // ORDINARY ALU FLAG QUALIFICATION
    //===================================
    // ID_STAGE asserts set_flags for instructions with the S bit enabled.
    // DIVS must not update NZCV through the ordinary single-cycle ALU.
    // Its flag update occurs only when the division controller finishes execution.
    // All other instructions retain their original flag-update behavior.

    assign normal_set_flags = set_flags && !is_div;

    // final architectural flag inputs

    //==========================
    // INSTRUCTION FETCH STAGE
    //===========================
    // Maintains the PC, supplies the instruction-memory address, and
    // performs the limited early decode required for unconditional
    // B and BR instructions

    if_stage IF(
        .clk (clk),
        .rst (rst),
        .clk_en (clk_en),

        //====================================
        // MULTICYCLE INSTRUCTION FETCH STALL
        //==================================
        // Hold the current instruction while MUL/MULS or DIV/DIVS is executing
        //
        // The IF module retains its existing stall input and internal PC logic.
        // The class-defined external interface remains unchanged.

        // Also holds the PC once HALT or an illegal instruction is decoded.
        .ucode_stall (fetch_stall),

        .inst_mem_v (inst_mem_v),

        .branch_reg_v (branch_reg_v),

        .is_cond_branch (is_cond_branch),
        .condition_met (condition_met),

        .branch_reg_addr_v(branch_reg_addr_v),

        .pc_v (pc_v),

        .inst_mem_en (inst_mem_en),
        .inst_mem_addr_v (inst_mem_addr_v)
    );

    //========================
    // INSTRUCTION DECODE STAGE
    //===========================
    // Decodes the instruction currently returned by instruction
    // memory and generates register, ALU, memory, branch, and special
    // instruction control information

    id_control_stage ID_STAGE (
    .alu_op_v (alu_op_v),
    .c_f (c_f),
    .condition_met (condition_met),
    .data_mem_rd_en (normal_mem_rd_request),
    .data_mem_wr_request (data_mem_wr_request),
    .err_f (err_f),
    .halt_f (halt_f),


    // The division controller asserts div_error when a DIV/DIVS instruction divides by zero.
    // ID_STAGE combines this condition with the existing illegal-instruction status logic.
    //
    // Error status has priority over normal HALT:
    //   2'b00 = Normal execution
    //   2'b01 = HALT
    //   2'b10 = Error

    .div_error (div_error),

    .imm_v (imm_v),
    .inst_mem_v (inst_mem_v),
    .is_alu (is_alu),
    .is_clr (is_clr),
    .is_cond_branch (is_cond_branch),
    .is_load_store (is_load_store),
    .is_lsl (is_lsl),
    .is_lsr (is_lsr),
    .is_mov (is_mov),
    .is_movt (is_movt),

    //=======================================
    // SPECIAL INSTRUCTION DECODE OUTPUTS
    //=====================================
    // Decode MOVF/SAVF for architectural flag-transfer operations.

    .is_movf (is_movf),
    .is_savf (is_savf),


    // Forward the decoded operation type from ID_STAGE to the SCC interconnect.
    // Execution stages will consume is_div after division support is integrated.

    .is_mul (is_mul),
    .is_div (is_div),

    .is_set (is_set),

    // ID_STAGE decodes PUSH and POP once.
    //
    // These decoded signals are distributed to EXE_STAGE for stack execution and
    // WB_STAGE for architectural S updates.
    //
    // Stack occupancy is calculated by EXE_STAGE, not by the decoder.

    .is_push (is_push),
    .is_pop (is_pop),

    .n_f (n_f),
    .rd_addr_v (rd_addr_v),
    .reg_write_en (reg_write_en),
    .rs1_addr_v (rs1_addr_v),
    .rs2_addr_v (rs2_addr_v),
    .set_flags (set_flags),
    .use_imm (use_imm),
    .v_f (v_f),
    .z_f (z_f)
);

    //=============================
    // SHARED DATA-MEMORY BUS
    //========================
    // Selects between ordinary LOAD/STOR and stack PUSH/POP transactions.
    //
    // Ordinary memory requests originate from ID and their address/data values
    // are calculated by EXE.
    //
    // Stack memory requests and address/data values originate from the stack datapath
    // inside EXE_STAGE.
    //
    // The shared bus is the only driver of the external data-memory interface.
    //
    // Writes are enabled during the low clock phase and disabled while high.
    //
    // This replaces the previous falling-edge memory_write_control instance without
    // modifying architectural writeback.

    stack_memory_bus STACK_MEMORY_BUS (
        .clk (clk),
        .rst (rst),
        .clk_en (clk_en),

        // Ordinary LOAD/STOR requests.
        .normal_mem_rd_request (normal_mem_rd_request),
        .normal_mem_wr_request (data_mem_wr_request),

        // Ordinary EXE memory address/data.
        .normal_mem_addr_v (normal_mem_addr_v),
        .normal_mem_out_v (normal_mem_out_v),

        // Stack PUSH/POP memory requests.
        .stack_mem_rd_request (stack_mem_rd_request),
        .stack_mem_wr_request (stack_mem_wr_request),

        // Stack datapath address/data.
        .stack_mem_addr_v (stack_mem_addr_v),
        .stack_mem_out_v (stack_mem_out_v),

        // External architectural memory bus.
        .data_mem_rd_en (data_mem_rd_en),
        .data_mem_wr_en (data_mem_wr_en),
        .data_mem_addr_v (data_mem_addr_v),
        .data_mem_out_v (data_mem_out_v)
    );


    //==================
    // EXECUTION STAGE
    //===================
    // Selects register/immediate operands, performs ALU operations,
    // generates data-memory address/write-data values, and produces the
    // register-file writeback information for the current instruction

    exe_cluster_stage EXE_STAGE (
    .alu_c_f (alu_c_f),
    .alu_n_f (alu_n_f),
    .alu_op_v (alu_op_v),
    .alu_v_f (alu_v_f),
    .alu_z_f (alu_z_f),
    .clk (clk),
    .clk_en (clk_en),

    .data_mem_addr_v (normal_mem_addr_v),
    .data_mem_in_v (data_mem_in_v),
    .data_mem_out_v (normal_mem_out_v),
    .data_mem_rd_en (normal_mem_rd_request),

    .exe_reg_write_addr_v (exe_reg_write_addr_v),
    .exe_reg_write_data_v (exe_reg_write_data_v),
    .exe_reg_write_en (exe_reg_write_en),
    .imm_v (imm_v),
    .is_alu (is_alu),
    .is_clr (is_clr),
    .is_load_store (is_load_store),
    .is_lsl (is_lsl),
    .is_lsr (is_lsr),
    .is_mov (is_mov),
    .is_movt (is_movt),

    // MUL/MULS retain their original multiplication-controller path.
    // DIV/DIVS use the new division controller instantiated inside EXE_STAGE.
    // Instruction bit 28 indicates whether division must update NZCV.

    .is_mul (is_mul),
    .is_div (is_div),
    .div_set_flags (inst_mem_v[28]),

    .is_set (is_set),

    // These connections activate the occupancy tracker for decoded PUSH/POP instructions
    // Stack requests, R13 updates, and occupancy are integrated.

    .is_push (is_push),
    .is_pop (is_pop),

    .stack_depth_v (stack_depth_v),
    .stack_full (stack_full),
    .stack_empty (stack_empty),

    // read the current architectural R13
    .stack_sp_v (stack_sp_v),

    .mul_operand_b_v (mul_operand_b_v),
    .mul_set_flags (inst_mem_v[28]),
    .rd_addr_v (rd_addr_v),
    .reg_read_data_1_v (reg_read_data_1_v),
    .reg_read_data_2_v (reg_read_data_2_v),
    .reg_write_en (reg_write_en),
    .rst (rst),
    .store_read_data_v (store_read_data_v),
    .ucode_c_f (ucode_c_f),
    .ucode_n_f (ucode_n_f),
    .ucode_reg_write_addr_v (ucode_reg_write_addr_v),
    .ucode_reg_write_data_v (ucode_reg_write_data_v),
    .ucode_reg_write_en (ucode_reg_write_en),
    .ucode_set_flags (ucode_set_flags),
    .ucode_stall (ucode_stall),
    .ucode_v_f (ucode_v_f),
    .ucode_z_f (ucode_z_f),

    //========================================
    // DIVISION CONTROL AND RESULT INTERFACE
    //==========================================
    // EXE_STAGE supplies the division stall, error status, register writeback,
    // and optional DIVS flag updates through the division controller.
    //
    // WB_STAGE selects the quotient or remainder for the architectural write
    // port. The FLAGS module commits DIVS NZCV when the controller requests it.
    //
    // Architectural register and flag storage remain outside EXE_STAGE.

    .div_stall (div_stall),
    .div_error (div_error),

    .div_reg_write_en (div_reg_write_en),
    .div_reg_write_addr_v (div_reg_write_addr_v),
    .div_reg_write_data_v (div_reg_write_data_v),

    .div_flags_write_en (div_flags_write_en),
    .div_n_f (div_n_f),
    .div_z_f (div_z_f),
    .div_c_f (div_c_f),
    .div_v_f (div_v_f),

    .use_imm (use_imm),

    // EXE calculates the memory requests, stack-pointer update, and POP result.
    // Stack-memory requests are now connected to STACK_MEMORY_BUS.
    //
    // Architectural R13 updates and POP destination-register writeback
    // are connected. Processor-level behavioral verification is pending.
    // This preserves existing LOAD/STOR, MUL/MULS, and MOVF/SAVF behavior.

    // Stack-memory control requests.
    .stack_mem_rd_request (stack_mem_rd_request),
    .stack_mem_wr_request (stack_mem_wr_request),

    // Effective stack-memory address and data
    .stack_mem_addr_v (stack_mem_addr_v),
    .stack_mem_out_v (stack_mem_out_v),

    // Architectural R13 update request
    .stack_sp_write_en (stack_sp_write_en),
    .stack_sp_next_v (stack_sp_next_v),

    // POP destination-register writeback.
    .stack_pop_write_en (stack_pop_write_en),
    .stack_pop_data_v (stack_pop_data_v)
);

    //===============================
    // MULTIPLICATION MICROCODE ROM
    //================================
    // Supplies four assembled microinstructions from ucode.mem.
    // The controller supplies the microinstruction address

    //==========================
    // MULTIPLICATION CONTROLLER
    //============================
    // Captures MUL/MULS operands, sequences ROM operations,
    // and generates the stall, two writebacks, and optional MULS flags

    //==============================
    // EXECUTION DATAPATH SELECTION
    //=============================
    // Selects immediate/register multiplication operands.
    //
    // During MUL/MULS, the controller's writeback
    // and flag signals replace those of the normal EXE stage.
    //
    // Actual architectural writes occur in REGS and FLAGS.

    wb_cluster_stage WB_STAGE (
    .alu_c_f (alu_c_f),
    .alu_n_f (alu_n_f),
    .alu_v_f (alu_v_f),
    .alu_z_f (alu_z_f),
    .arch_reg_write_addr_v (arch_reg_write_addr_v),
    .arch_reg_write_data_v (arch_reg_write_data_v),
    .arch_reg_write_en (arch_reg_write_en),

    //====================================
    // DIVISION REGISTER WRITEBACK INPUTS
    //=====================================
    // DIV_CONTROLLER supplies the destination and result for each completed
    // quotient or remainder write. WB_STAGE gives these writes highest priority.

    .div_reg_write_en (div_reg_write_en),
    .div_reg_write_addr_v (div_reg_write_addr_v),
    .div_reg_write_data_v (div_reg_write_data_v),

    //=================================
    // POP REGISTER WRITEBACK INPUTS
    //=====================================
    // EXE_STAGE supplies the POP result and write request. The decoded Rd
    // identifies the destination for the popped value or empty-stack zero.

    .rd_addr_v (rd_addr_v),
    .stack_pop_write_en (stack_pop_write_en),
    .stack_pop_data_v (stack_pop_data_v),

    // Suppress POP writeback while multicycle arithmetic is active.
    // Division writeback remains enabled independently during its commit states.
    .multicycle_stall (multicycle_stall),
    .c_f (c_f),
    .clk (clk),
    .clk_en (clk_en),
    .exe_reg_write_addr_v (exe_reg_write_addr_v),
    .exe_reg_write_data_v (exe_reg_write_data_v),
    .exe_reg_write_en (exe_reg_write_en),
    .imm_v (imm_v),
    .is_mul (is_mul),

    // DIVS updates NZCV from the registered division result at completion.
    // DIV preserves existing NZCV.
    // Division never directly changes S.

    .div_flags_write_en (div_flags_write_en),
    .div_n_f (div_n_f),
    .div_z_f (div_z_f),
    .div_c_f (div_c_f),
    .div_v_f (div_v_f),

    // MOVF copies stored SNZCV into a register
    // SAVF restores SNZCV from a register
    .is_movf (is_movf),
    .is_savf (is_savf),

    // PUSH/POP are decoded by ID_STAGE.
    //
    // Stack occupancy and stack_full are produced by the stack controller inside EXE_STAGE.
    // WB_STAGE uses these signals to calculate the next architectural S-flag value.
    //
    // The FLAGS module commits S on the rising clock edge, alongside the stack
    // controller's occupancy update.
    // SAVF priority and arithmetic NZCV behavior remain inside flags.v.

    .is_push (is_push),
    .is_pop (is_pop),

    .stack_depth_v (stack_depth_v),
    .stack_full (stack_full),

    // Preserve the existing MUL/MULS path.
    .mul_operand_b_v (mul_operand_b_v),
    .n_f (n_f),
    .reg_read_data_2_v (reg_read_data_2_v),

    // Dedicated register-file read port already  selects instruction bits [24:21].
    // For SAVF, these bits select the source register.
    .store_read_data_v (store_read_data_v),

    .rst (rst),

    //========================================
    // ARCHITECTURAL FLAG UPDATE SELECTION
    //========================================
    // Disable ordinary ALU flag writes during DIV/DIVS.
    // WB_STAGE receives the completed division flags through its dedicated
    // inputs and commits NZCV only when DIVS requests an update.

    .set_flags (normal_set_flags),
    .ucode_c_f (ucode_c_f),
    .ucode_n_f (ucode_n_f),
    .ucode_reg_write_addr_v (ucode_reg_write_addr_v),
    .ucode_reg_write_data_v (ucode_reg_write_data_v),
    .ucode_reg_write_en (ucode_reg_write_en),
    .ucode_set_flags (ucode_set_flags),
    .ucode_stall (ucode_stall),
    .ucode_v_f (ucode_v_f),
    .ucode_z_f (ucode_z_f),
    .use_imm (use_imm),

    // Return all stored architectural flags
    .s_f (s_f),
    .v_f (v_f),
    .z_f (z_f)
);

    //==========================
    // ARCHITECTURAL FLAGS
    //=====================
    // Stores selected NZCV from ordinary EXE or microcoded MULS.
    // The stored flags feed the conditional branch evaluator.

    //============================
    // CONDITIONAL BRANCH CONTROL
    //============================
    // Evaluates the decoded B.cond condition using the stored architectural
    // NZCV flags. The resulting decision is supplied to the IF stage

    //=============
    // REGISTER FILE
    //================
    // - Provides two combinational operand-read ports for execution
    // and one synchronous write port
    // - A dedicated combinational branch-read port supplies the IF stage
    // with the register value required for BR
    // - Execution results are returned through the synchronous write port

    regs REGS (
        .clk (clk),
        .rst (rst),
        .clk_en (clk_en),

        .pc_v (pc_v),

        .read_addr_1 (rs1_addr_v),
        .read_data_1 (reg_read_data_1_v),

        .read_addr_2 (rs2_addr_v),
        .read_data_2 (reg_read_data_2_v),

        .store_read_addr_v (rd_addr_v),
        .store_read_data_v (store_read_data_v),

        .branch_read_addr_v (branch_reg_addr_v),
        .branch_read_data_v (branch_reg_v),

        //========================================
        // FINAL ARCHITECTURAL REGISTER WRITEBACK
        //========================================
        // WB_STAGE has already selected the highest-priority write request.
        // REGS receives one write enable, destination address, and data value.
        //
        // The dedicated stack-pointer interface below remains independent so
        // a POP can update R13 and its destination register on the same clock.

        .write_en (arch_reg_write_en),
        .write_addr (arch_reg_write_addr_v),
        .write_data (arch_reg_write_data_v),

        //==================================
        // ARCHITECTURAL STACK POINTER (R13)
        //===================================
        // REGS is the sole owner of R13 storage
        //
        // The stack datapath inside EXE_STAGE calculates the next stack-pointer value
        // using the current R13 and stack depth.
        //
        // PUSH:
        // - Stores the source-register value at the selected stack address.
        // - Advances R13 according to the stack occupancy rules.
        //
        // POP:
        // - Reads the selected stack address.
        // - Updates R13 according to the stack occupancy rules.
        //
        // REGS commits the requested R13 update on the rising clock edge.
        // Its existing reset and clock-enable logic controls when the write occurs.
        //
        // The stack controller also updates occupancy on the rising edge, keeping
        // stack depth and R13 synchronized.
        //
        // Ordinary register writeback remains independent of the dedicated R13 path.
        // No additional sequential state is introduced in scc.v.

        .stack_sp_write_en (stack_sp_write_en),
        .stack_sp_next_v (stack_sp_next_v),
        .stack_sp_v (stack_sp_v)
    );

    //================
    // ERROR STATUS
    //================
    // Encodes illegal instruction (priority) and HALT status.
    // Status encoding and priority remain inside error_status.v.

  

endmodule