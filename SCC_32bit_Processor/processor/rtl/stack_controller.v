// stack_controller.v
// Stack occupancy and boundary controller for the SCC.
//
// Responsibilities:
// - Track the number of valid 32-bit stack entries.
// - Recognize full and empty stack conditions.
// - Prevent occupancy from exceeding 16 entries.
// - Prevent occupancy from decreasing below zero.
// - Preserve occupancy during disabled clock cycles.
// - Provide status information for PUSH/POP execution.
//
// Architectural Requirements:
// - Stack depth is 16 32-bit words.
// - PUSH normally increases the stack occupancy.
// - PUSH on a full stack retains the occupancy at 16.
// - POP normally decreases the stack occupancy.
// - POP on an empty stack retains occupancy at zero.
// - S is asserted when all 16 entries are occupied.
//
// Design Notes:
// - Only the occupancy counter is stored here.
// - R13 remains physically stored in regs.v.
// - Stack data remains in the normal data memory.
// - Stack address generation and PUSH/POP data selection are performed
//   by stack_datapath.v inside EXE_STAGE.
// - The shared memory bus performs stack memory transactions.
// - The architectural register file owns R13 and commits stack-pointer updates.
// - WB_STAGE selects POP destination writeback and updates the S flag.
// - This controller is a leaf module of exe_cluster_stage.v.
// - Synchronous reset has priority over clock enable.
// - Conflicting PUSH and POP requests leave occupancy unchanged.


module stack_controller (
    input wire clk,
    input wire rst,
    input wire clk_en,

    // Decoded stack instruction requests
    input wire push_en,
    input wire pop_en,

    // Current stack occupancy and status
    output wire [4:0] stack_depth_v,
    output wire stack_full,
    output wire stack_empty
);

//===================
// STACK CAPACITY
//===================
// Five bits are required to represent all
// occupancy values from zero through sixteen

localparam [4:0] STACK_CAPACITY = 5'd16;

//=====================
// OCCUPANCY STORAGE
//======================
// Occupancy is independent of memory contents
//
// A full PUSH overwrites the top stack element later in the datapath, but does not increment
// this occupancy counter
//
// An empty POP returns zero in the datapath and does not decrement this counter.

reg [4:0] depth_reg;

//=================================
// COMBINATIONAL STATUS OUTPUTS
//================================
// The counter itself is the reported depth.
//
// Full and empty status are based on exact
// comparisons against the architectural limits

assign stack_depth_v = depth_reg;
assign stack_full = (depth_reg == STACK_CAPACITY);
assign stack_empty = (depth_reg == 5'd0);

//=================================
// SYNCHRONOUS OCCUPANCY UPDATE
//=================================
// Update Priority:
// 1. Reset initializes the stack to empty.
// 2. A valid PUSH increments occupancy.
// 3. A valid POP decrements occupancy.
// 4. Otherwise occupancy is preserved.
//
// PUSH and POP are distinct ISA instructions,
// so both should never be requested together.
//
// If both controls are accidentally asserted,
// neither operation changes occupancy.
//
// This explicit conflict behavior prevents
// an accidental increase or decrease

always @(posedge clk) begin

    //===================
    // RESET
    //=====================
    // The stack initially contains no
    // valid architectural entries.

    if (rst) begin
        depth_reg <= 5'd0;
    end

    //=============================
    // ENABLED STACK OPERATIONS
    //=============================

    else if (clk_en) begin

        //=========
        // PUSH
        //=========
        // A PUSH increments occupancy only while the stack is not full.
        //
        // At full capacity, occupancy remains at 16; stack-memory overwrite behavior
        // is handled by the later EXE/MEM logic.

        if (push_en && !pop_en) begin
            if (!stack_full) begin
                depth_reg <= depth_reg + 5'd1;
            end
            // Otherwise hold full occupancy
        end

        //==========
        // POP
        //===========
        // A POP decreases occupancy only while at least one entry exists.
        //
        // When empty, the count remains zero. Zero-result writeback will be handled
        // by the later EXE/WB integration.

        else if (pop_en && !push_en) begin
            if (!stack_empty) begin
                depth_reg <= depth_reg - 5'd1;
            end
            // Otherwise hold empty occupancy
        end

        // No instruction or conflicting requests:
        // preserve the current occupancy
    end

    // With clk_en disabled, the occupancy
    // counter retains its previous value

end

endmodule
