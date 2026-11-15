// stack_datapath.v
// Combinational PUSH/POP datapath for the SCC.
//
// Responsibilities:
// - Calculate the effective stack-memory address.
// - Supply PUSH data from the selected source register.
// - Supply POP data from the memory read interface.
// - Return zero for POP on an empty stack.
// - Calculate the next architectural R13 value.
// - Generate stack memory and register-write requests.
//
// Architectural State Ownership:
// - regs.v stores R13.
// - stack_controller.v stores stack occupancy.
// - flags.v stores the architectural S flag.
// - Instruction_and_data.v stores stack contents.
//
// Stack Address Convention (F2026.4 ISA):
// - The stack occupies 0x0000FFC0 through 0x0000FFFF.
// - R13 initially points to the first free stack word.
// - PUSH writes at R13, then increments R13 by four bytes.
// - After 16 PUSH operations, R13 equals 0x00010000.
// - A full-stack PUSH overwrites the word at 0x0000FFFC
//   without changing R13 or stack occupancy.
// - A nonempty POP decrements R13 by four bytes before
//   reading the most recently pushed word.
// - An empty POP returns zero without changing R13.
// - stack_controller.v independently tracks occupancy.


module stack_datapath (
    input wire is_push,
    input wire is_pop,

    // Current architectural stack pointer.
    input wire [31:0] stack_sp_v,

    // Current stack occupancy information.
    input wire [4:0] stack_depth_v,
    input wire stack_full,
    input wire stack_empty,

    // PUSH source-register value
    input wire [31:0] push_data_v,

    // Data returned by architectural data memory.
    input wire [31:0] data_mem_in_v,

    // Stack-memory interface requests
    output reg stack_mem_rd_request,
    output reg stack_mem_wr_request,

    // Stack-memory address and write data
    output reg [31:0] stack_mem_addr_v,
    output reg [31:0] stack_mem_out_v,

    // Architectural R13 update request and value
    output reg stack_sp_write_en,
    output reg [31:0] stack_sp_next_v,

    // POP destination-register writeback
    output reg stack_pop_write_en,
    output reg [31:0] stack_pop_data_v
);


 //==========================================
 // STACK ADDRESS AND CAPACITY CONSTANTS
 //========================================
 // Each stack entry occupies four bytes.
 //
 // R13 contains a byte address, so PUSH and POP move the pointer in increments
 // or decrements of four bytes.
 //
 // The final valid stack word is located at 0x0000FFFC. The full stack pointer
 // value is 0x00010000, which is one word beyond the allocated stack region.
 //
 // A full PUSH must use the final valid word address rather than the R13 value,
 // preventing an out-of-range memory access.

 localparam [31:0] WORD_BYTES = 32'd4;
 localparam [31:0] STACK_LAST_WORD_ADDR = 32'h0000_FFFC;


//================================
// COMBINATIONAL STACK EXECUTION
//==================================
// Select the memory transaction and architectural register-update
// requests for the decoded PUSH or POP instruction.
//
// Every output receives a default before instruction selection.
// These defaults suppress memory and register writes when neither
// instruction is active or when requests conflict.
//
// PUSH and POP are mutually exclusive; a conflict results in no
// operation. The stack controller independently applies the same
// conflict rule to occupancy updates.
//
// This module contains no sequential state. R13, stack occupancy,
// and architectural memory are updated by their respective owners.

always @(*) begin

    //=======================
    // SAFE DEFAULTS
    //=================

    stack_mem_rd_request = 1'b0;
    stack_mem_wr_request = 1'b0;

    stack_mem_addr_v = 32'h0000_0000;
    stack_mem_out_v = 32'h0000_0000;

    stack_sp_write_en = 1'b0;
    stack_sp_next_v = stack_sp_v;

    stack_pop_write_en = 1'b0;
    stack_pop_data_v = 32'h0000_0000;


    //========================================
    // PUSH INSTRUCTION
    //========================================
    // PUSH stores the selected source-register value into the architectural stack.
    //
    // Normal PUSH (stack not full):
    // 1. Write the source value at current R13.
    // 2. Request an update of R13 to R13 + 4.
    // 3. The stack controller increments occupancy
    //    on the enabled rising clock edge.
    //
    // Full-stack PUSH:
    // 1. Overwrite the final valid stack word.
    // 2. Keep R13 unchanged at 0x00010000.
    // 3. Keep occupancy at 16 and S asserted.
    //
    // PUSH and POP are mutually exclusive.
    // If both requests are asserted, neither operation is executed by this datapath.

    if (is_push && !is_pop) begin

        // Enable a single stack-memory write
        // using the selected source-register data
        stack_mem_wr_request = 1'b1;
        stack_mem_out_v = push_data_v;

        if (!stack_full) begin

            // Space remains in the stack.
            //
            // Store the new value at the address
            // currently identified by R13.
            stack_mem_addr_v = stack_sp_v;

            // Advance R13 to the next free word.
            //
            // This includes the sixteenth PUSH,
            // which advances R13 from 0x0000FFFC
            // to the full value of 0x00010000.
            stack_sp_write_en = 1'b1;
            stack_sp_next_v = stack_sp_v + WORD_BYTES;

        end
        else begin

            // The stack is already full.
            //
            // R13 equals 0x00010000, which is
            // outside the valid memory region.
            //
            // Overwrite the final allocated word
            // instead of accessing memory at R13.
            stack_mem_addr_v = STACK_LAST_WORD_ADDR;

            // No stack-pointer update is requested.
            // The controller also retains depth 16.
            // S remains asserted.
        end
    end



    //==================
    // POP INSTRUCTION
    //====================
    // POP retrieves the most recently pushed value using last-in, first-out behavior.
    //
    // Nonempty POP:
    // 1. Calculate the address R13 - 4.
    // 2. Request a memory read at that address.
    // 3. Return the memory value for writeback.
    // 4. Update R13 to the decremented address.
    // 5. The stack controller reduces occupancy.
    //
    // Empty POP:
    // 1. Return 0x00000000 to the destination.
    // 2. Do not request a memory read.
    // 3. Do not change R13 or occupancy.
    //
    // All nonempty POP operations use the same pre-decrement addressing behavior,
    // including POP from a completely full stack.

    else if (is_pop && !is_push) begin

        // Every valid POP writes a result
        // to its architectural destination.
        //
        // This includes empty POP, which
        // writes zero to the destination
        stack_pop_write_en = 1'b1;

        if (!stack_empty) begin

            // At least one valid entry exists.
            //
            // R13 points immediately beyond the
            // most recently occupied stack word.
            //
            // Decrement the pointer by one word
            // to select the correct POP address.
            stack_mem_addr_v = stack_sp_v - WORD_BYTES;

            // Request the selected word from
            // the shared architectural memory.
            stack_mem_rd_request = 1'b1;

            // Provide the memory result to the
            // destination-register writeback path.
            stack_pop_data_v = data_mem_in_v;

            // Update R13 to the address of the
            // word that was just removed.
            stack_sp_write_en = 1'b1;
            stack_sp_next_v = stack_sp_v - WORD_BYTES;

        end
        else begin

            // The stack is empty.
            //
            // No memory read is permitted.
            // No R13 update is requested.
            //
            // The default POP result remains zero.
            // The stack controller retains depth 0.
        end
    end


end

endmodule
