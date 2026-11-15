// if_stage.v
//
// Description:
// Instruction Fetch (IF) stage for the SCC processor.
//
// Functionality:
// - Maintains the 32-bit architectural Program Counter (PC).
// - Resets the PC to address 0x00000000.
// - Advances the PC by 4 bytes for sequential instructions.
// - Supplies the current PC to instruction memory.
// - Performs early detection of immediate and register branches.
// - Redirects the PC for unconditional and taken conditional branches.
// - Holds the PC during multicycle microcode execution.
//
// Branch Types:
// - B:      Unconditional PC-relative immediate branch.
// - B.cond: Conditional PC-relative immediate branch.
// - BR:     Unconditional branch to a register-provided address. Plus an optional signed 16-bit byte offset
//
// Design Notes:
// - All SCC instructions are 32 bits (4 bytes).
// - Immediate branch offsets are signed 16-bit byte offsets.
// - Register branches use an absolute 32-bit base address plsu an optional signed 16-bit byte offset
// - Conditional branch decisions come from the branch-control logic.
// - Full instruction decoding is performed by id_stage.v.
// - The PC is stored only in this module; R15 reads this PC
//   through the architectural register-file interface.

module if_stage (
    // System clock, synchronous reset, and clock enable
    input wire clk,
    input wire rst,
    input wire clk_en,

    // Microcode execution control.
    // Prevents PC updates while a multicycle instruction executes
    input wire ucode_stall,

    // Current instruction returned by instruction memory
    input wire [31:0] inst_mem_v,

    // Register value supplied by the register file for BR
    input wire [31:0] branch_reg_v,

    // Conditional branch information from decode/branch control
    input wire is_cond_branch,
    input wire condition_met,

    // Register address required for the BR target read
    output wire [3:0] branch_reg_addr_v,

    // Current architectural Program Counter
    output wire [31:0] pc_v,

    // Instruction-memory enable and address
    output wire inst_mem_en,
    output wire [31:0] inst_mem_addr_v
);

//===============================
// PROGRAM COUNTER STORAGE
//=============================
// The PC contains the address of the current instruction.
//
// This is the only physical PC storage in the processor.
// The register file reads this value when architectural
// register R15 is selected.
//
// The PC changes only on an enabled rising clock edge,
// unless reset has priority and clears it to zero.

reg [31:0] pc_reg;

//=====================================
// EARLY BRANCH INSTRUCTION DETECTION
//=======================================
// The IF stage identifies only the unconditional branch
// encodings needed to determine the next PC immediately.
//
// Both instructions belong to the SYS/BRANCH instruction class:
// - inst_mem_v[31:30] = 2'b11
//
// Instruction-specific fields:
// - B:  inst_mem_v[28:25] = 4'b0000
// - BR: inst_mem_v[28:25] = 4'b0010
//
// Bit 29 is not used to distinguish these two encodings.
//
// Conditional branches are identified separately by ID.
// Their branch condition is evaluated by branch-control logic.
//
// Continuous assignments implement simple combinational
// instruction comparisons without creating storage

wire is_branch_imm;
wire is_branch_reg;

assign is_branch_imm = (inst_mem_v[31:30] == 2'b11) && (inst_mem_v[28:25] == 4'b0000);

assign is_branch_reg = (inst_mem_v[31:30] == 2'b11) && (inst_mem_v[28:25] == 4'b0010);

//======================================
// REGISTER BRANCH TARGET SELECTION
//====================================
// A BR instruction specifies its target register in bits
// [24:21] of the instruction.
//
// This address is sent to the register file's dedicated
// branch read port. The corresponding register value
// returns through branch_reg_v.
//
// The register value supplies the absolute base address
// for BR. A signed immediate offset may also be applied
// when calculating the final branch destination.

assign branch_reg_addr_v = inst_mem_v[24:21];

//====================================
// SIGNED IMMEDIATE BRANCH OFFSET
//=========================================
// Immediate branches use a signed 16-bit byte offset.
//
// Replicating bit 15 sixteen times preserves the sign
// when extending the offset to the 32-bit PC datapath.
//
// A positive offset branches forward.
// A negative offset branches backward.

wire [31:0] branch_offset_v;

assign branch_offset_v = {{16{inst_mem_v[15]}}, inst_mem_v[15:0]};

//=====================================
// NEXT PROGRAM COUNTER CALCULATION
//=====================================
// Sequential execution uses PC + 4.
//
// Branch destinations:
// - B: PC + sign-extended immediate.
// - BR: Register-provided base address plus signed offset.
// - B.cond: PC + sign-extended immediate when taken.
//
// An untaken conditional branch uses the sequential PC + 4.
//
// Branch selection priority:
// 1. Unconditional immediate branch.
// 2. Unconditional register branch.
// 3. Taken conditional immediate branch.
// 4. Sequential execution.
//
// All assignments in this combinational block use blocking
// assignments (=). The initial default assignment ensures
// next_pc_v receives a value for every possible input
// combination and prevents inferred latches.

wire [31:0] pc_plus_4_v;
reg  [31:0] next_pc_v;

// Calculate the sequential address of the next instruction.
assign pc_plus_4_v = pc_reg + 32'd4;

always @(*) begin

    // Default: continue to the next sequential instruction.
    // This also handles an untaken conditional branch.
    next_pc_v = pc_plus_4_v;

    // If the instruction is an unconditional immediate
    // branch, redirect the PC by its signed byte offset.
    if (is_branch_imm) begin
        next_pc_v = pc_reg + branch_offset_v;
    end

    // Otherwise, if the instruction is a register branch,
    // calculate the destination using the register-provided
    // base address and the signed 16-bit immediate offset.
    //
    // The immediate has already been sign-extended to
    // 32 bits through branch_offset_v.
    //
    // An offset of zero preserves the original absolute
    // branch behavior, while positive and negative offsets
    // allow branching relative to the register value.
    else if (is_branch_reg) begin
        next_pc_v = branch_reg_v + branch_offset_v;
    end

    // Otherwise, if a conditional branch was decoded and
    // its condition is satisfied, apply the signed offset.
    else if (is_cond_branch && condition_met) begin
        next_pc_v = pc_reg + branch_offset_v;
    end

    // If none of the above conditions is satisfied,
    // next_pc_v retains the default sequential value.

end

//============================================================
// SYNCHRONOUS PROGRAM COUNTER UPDATE
//============================================================
// The PC is updated using nonblocking assignments (<=)
// because pc_reg represents clocked sequential storage.
//
// Update priority:
// 1. Reset: Set PC to zero.
// 2. Clock enable active and no microcode stall:
//    Update PC with the combinationally calculated address.
// 3. Otherwise: Hold the current PC value.
//
// During multiplication, ucode_stall remains asserted
// while the microcode controller completes the instruction.
// This prevents the architectural PC from advancing before
// the multicycle operation has finished.
//
// No explicit self-assignment is necessary to hold the PC.
// A flip-flop retains its stored value when not assigned.

always @(posedge clk) begin

    // If reset is asserted, restart instruction execution
    // from address zero regardless of other control signals.
    if (rst) begin
        pc_reg <= 32'h0000_0000;
    end

    // If reset is inactive, the processor clock is enabled,
    // and microcode is not requesting a stall, advance or
    // redirect the PC to the address selected above.
    else if (clk_en && !ucode_stall) begin
        pc_reg <= next_pc_v;
    end

    // If clk_en is low or ucode_stall is high, the PC
    // remains unchanged until execution is permitted.

end

//============================================================
// INSTRUCTION MEMORY INTERFACE
//============================================================
// The architectural PC is exposed to the register file
// and instruction-memory interface.
//
// The current PC always supplies the instruction address.
//
// Instruction-memory enable is permanently asserted in
// this SCC implementation. During a microcode stall, the
// instruction address remains stable because PC is held.
//
// These continuous assignments represent direct signal
// connections rather than additional sequential storage.

assign pc_v = pc_reg;
assign inst_mem_addr_v = pc_reg;
assign inst_mem_en = 1'b1;

endmodule
