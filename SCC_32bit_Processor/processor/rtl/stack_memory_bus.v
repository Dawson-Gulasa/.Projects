// stack_memory_bus.v
// Shared data-memory interface for the SCC.
//
// Responsibilities:
// - Select ordinary LOAD/STOR memory signals.
// - Select PUSH/POP stack-memory signals.
// - Give read requests priority over writes.
// - Enable memory writes during the low clock phase.
// - Disable memory writes before rising-edge
//   architectural state updates.
//
// Architectural State Ownership:
// - IF owns the program counter.
// - regs.v owns R13 and general registers.
// - stack_controller.v owns stack occupancy.
// - Instruction_and_data.v owns memory contents.
//
// Timing Convention:
// - The current instruction is stable before
//   its architectural rising-edge commit.
// - Data-memory writes occur during the preceding
//   low clock phase.
// - The write-enable signal is inactive when
//   the clock is high.

module stack_memory_bus (
    input wire clk,
    input wire rst,
    input wire clk_en,

    //=============================
    // ORDINARY MEMORY INTERFACE
    //=============================

    input wire normal_mem_rd_request,
    input wire normal_mem_wr_request,

    input wire [31:0] normal_mem_addr_v,
    input wire [31:0] normal_mem_out_v,

    //==========================
    // STACK MEMORY INTERFACE
    //============================

    input wire stack_mem_rd_request,
    input wire stack_mem_wr_request,

    input wire [31:0] stack_mem_addr_v,
    input wire [31:0] stack_mem_out_v,

    //========================================
    // SHARED ARCHITECTURAL MEMORY OUTPUTS
    //======================================

    output wire data_mem_rd_en,
    output wire data_mem_wr_en,

    output wire [31:0] data_mem_addr_v,
    output wire [31:0] data_mem_out_v
);

//================================
// MEMORY REQUEST QUALIFICATION
//===============================
// Reset and clock enable suppress architectural memory transactions.
//
// Read requests remain combinational so LOAD/POP can obtain data before the
// destination register is updated.
//
// Memory write requests are also decoded combinationally, but the actual strobe
// is restricted to the low clock phase.

wire normal_read_active;
wire stack_read_active;
wire any_read_active;

wire normal_write_active;
wire stack_write_active;
wire any_write_active;

assign normal_read_active = !rst && clk_en && normal_mem_rd_request;

assign stack_read_active = !rst && clk_en && stack_mem_rd_request;

assign any_read_active = normal_read_active || stack_read_active;

assign normal_write_active = !rst && clk_en && normal_mem_wr_request;

assign stack_write_active = !rst && clk_en && stack_mem_wr_request;

assign any_write_active = normal_write_active || stack_write_active;

//=============================
// MEMORY ADDRESS SELECTION
//============================
// Priority:
// 1. Stack POP read.
// 2. Ordinary LOAD read.
// 3. Stack PUSH write.
// 4. Ordinary STOR / inactive.
//
// A read always takes priority over a write request.
//
// Properly decoded instructions should produce mutually exclusive operations;
// the priority also provides deterministic behavior for conflicting requests.

assign data_mem_addr_v =
    stack_read_active  ? stack_mem_addr_v  :
    normal_read_active ? normal_mem_addr_v :
    stack_write_active ? stack_mem_addr_v  :
                         normal_mem_addr_v;

//==============================
// MEMORY WRITE-DATA SELECTION
//================================
// PUSH uses its source-register value.
// STOR uses the ordinary EXE output.
// The selected value is ignored when the write enable is inactive.

assign data_mem_out_v = stack_write_active ? stack_mem_out_v : normal_mem_out_v;

//====================
// MEMORY READ ENABLE
//======================
// The existing course memory responds to its address and read-enable signals.
// POP and ordinary LOAD share this path.

assign data_mem_rd_en = any_read_active;

//=====================
// MEMORY WRITE ENABLE
//===================
// Writes are permitted only when:
// - Reset is inactive.
// - The processor is enabled.
// - A valid write request is present.
// - No read has priority.
// - The clock is LOW.
//
// This last condition ensures write enable is deasserted at the rising edge
// before PC/R13 updates propagate.
//
// Unlike a registered strobe that remains active into the following instruction,
// this write enable is phase-limited.
//
// IMPORTANT:
// The data-memory model is sensitive to address changes while writing is active.
// The final SCC test must verify the address remains stable through the low clock phase.

assign data_mem_wr_en =
    !clk && !any_read_active && any_write_active;

endmodule
