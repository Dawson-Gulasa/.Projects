// regs.v
//
// Description:
// 14 x 32-bit physical register storage for the SCC processor.
//
// Architectural Register Organization:
// - R0-R11: General-purpose registers.
// - R12: Temporary register used for MUL/DIV high results
//        and division remainders.
// - R13: Architectural Stack Pointer (SP).
//        Initialized to 0x0000FFC0 on reset.
// - R14: Hardwired zero register; always reads as zero.
// - R15: Program Counter (PC); supplied by the IF stage.
//
// Functionality:
// - Four independent combinational read ports.
// - One synchronous register write port.
// - Synchronous reset of architectural register storage.
// - R0-R12 reset to zero.
// - R13 resets to the architectural stack base address.
// - Clock-enable controlled register writes.
// - Dedicated stack-pointer update interface for PUSH/POP.
// - Writes to R14 and R15 are ignored.
//
// Design Notes:
// - Only R0-R13 require physical register storage.
// - R14 is implemented as a constant, not a flip-flop.
// - R15 PC state is maintained by if_stage.v.
// - This prevents duplicate PC state between IF and the architectural register file.
// - R13 is stored only in the physical register array.
// - Stack occupancy is maintained by stack_controller.v.
// - Stack address and pointer arithmetic are performed outside this module.
// - Stack-pointer and ordinary register writes may occur simultaneously when their destinations differ.
// - A dedicated stack-pointer write takes priority when both write paths target R13.
// - This permits POP to update R13 and its destination register on the same rising clock edge.

module regs (
    // System clock, synchronous reset, and clock enable.
    input wire clk,
    input wire rst,
    input wire clk_en,

    // Current PC value supplied by the IF stage.
    input wire [31:0] pc_v,

    // General-purpose combinational read port 1.
    input wire [3:0] read_addr_1,
    output wire [31:0] read_data_1,

    // General-purpose combinational read port 2.
    input wire [3:0] read_addr_2,
    output wire [31:0] read_data_2,

    // Dedicated read port used to obtain STOR instruction data.
    input wire [3:0] store_read_addr_v,
    output wire [31:0] store_read_data_v,

    // Dedicated read port used by IF for register branches (BR).
    input wire [3:0] branch_read_addr_v,
    output wire [31:0] branch_read_data_v,

    // Synchronous architectural register write port.
    input wire write_en,
    input wire [3:0] write_addr,
    input wire [31:0] write_data,

    //============================================
    // CP5 ARCHITECTURAL STACK-POINTER INTERFACE
    //=================================================
    // The execution datapath calculates the nextR13 value for a PUSH or POP instruction.
    //
    // Stack-pointer updates are performed through
    // these inputs so that R13 continues to have
    // exactly one physical storage location.
    //
    // The stack controller separately maintains the number of valid stack entries.

    input wire stack_sp_write_en,
    input wire [31:0] stack_sp_next_v,

    // Expose the current architectural stack
    // pointer to the stack execution datapath.
    output wire [31:0] stack_sp_v
);


 //=====================================
 // ARCHITECTURAL STACK ADDRESS REGION
 //====================================
 // The SCC uses a fixed 16-word (64-byte) stack.
 //
 // Stack memory layout:
 // - Base address: 0x0000FFC0
 // - Last word address: 0x0000FFFC
 // - Reserved region: 0x0000FFC0 through 0x0000FFFF
 // - Stack capacity:16 words, each 32 bits
 //
 // R13 is the architectural Stack Pointer (SP).
 // On reset, R13 identifies the first available stack location at 0x0000FFC0.
 // PUSH writes to the current stack location and advances R13 by four bytes while space remains.
 // After the sixteenth PUSH, R13 reaches 0x00010000,
 // indicating that the stack is full.
 // The stack datapath handles address calculations, full-stack overwrites, and POP operations.
 // The stack controller separately tracks occupancy and the architectural stack-full (S) flag.

 localparam [31:0] STACK_BASE_ADDR = 32'h0000_FFC0;


//================================
// PHYSICAL REGISTER STORAGE
//==============================
// R0-R13 are physically stored here.
//
// R14 is constant zero and R15 is supplied by the IF-stage program counter.

reg [31:0] registers [0:13];
integer i;

//=====================================
// STACK-POINTER READ OUTPUT
//=====================================
// Provide direct access to architectural R13.
//
// This is a combinational connection to the
// existing register storage, not another
// register or copy of stack-pointer state.

assign stack_sp_v = registers[13];

//===================================
// COMBINATIONAL REGISTER READ PORTS
//==================================
// All four read ports operate asynchronously.
//
// For each read port:
// - If address = 14, return constant zero (R14).
// - Otherwise, if address = 15, return the current PC (R15).
// - Otherwise, return the selected stored register (R0-R13).
//
// The address comparisons prevent out-of-range access to
// the physical register array.
//
// Continuous assignments describe the combinational read
// multiplexers and do not create register storage

// General-purpose read port 1.
assign read_data_1 = (read_addr_1 == 4'd14) ? 32'h0000_0000 : (read_addr_1 == 4'd15) ? pc_v : registers[read_addr_1];

// General-purpose read port 2.
assign read_data_2 = (read_addr_2 == 4'd14) ? 32'h0000_0000 : (read_addr_2 == 4'd15) ? pc_v : registers[read_addr_2];

// Dedicated branch-target read port.
assign branch_read_data_v = (branch_read_addr_v == 4'd14) ? 32'h0000_0000 : (branch_read_addr_v == 4'd15) ? pc_v : registers[branch_read_addr_v];

// Dedicated memory store-data read port.
assign store_read_data_v = (store_read_addr_v == 4'd14) ? 32'h0000_0000 : (store_read_addr_v == 4'd15) ? pc_v : registers[store_read_addr_v];


//========================================
// SYNCHRONOUS REGISTER WRITE / RESET
//=======================================
// Architectural register state is updated only
// on an enabled rising clock edge.
//
// Reset Behavior:
// - R0-R12 reset to zero.
// - R13 resets to the architectural stack base.
// - R14 is hardwired zero and has no storage.
// - R15 is maintained by the IF stage.
//
// Writeback Behavior:
// - The dedicated stack path updates R13.
// - Normal writeback may update R0-R12.
// - Both updates may occur on the same edge.
//
// If both paths attempt to write R13, the
// dedicated stack-pointer update has priority.
//
// Normal writes to R14 and R15 are ignored

always @(posedge clk) begin

    //===============================
    // PRIORITY 1: SYNCHRONOUS RESET
    //================================
    // Reset has priority over all register writes.
    //
    // R0-R12 are cleared to zero using nonblocking assignments because they are sequential state.
    // R13 is initialized to the fixed stack base address required by the F2026.4 ISA.
    //
    // R14 is a constant zero register and requires
    // no physical storage or clocked reset.
    //
    // R15 is maintained independently by IF
    
    if (rst) begin

        for (i = 0; i < 13; i = i + 1) begin
            registers[i] <= 32'h0000_0000;
        end

        registers[13] <= STACK_BASE_ADDR;
    end

    //=============================================
    // PRIORITY 2: ENABLED ARCHITECTURAL WRITES
    //============================================
    // Unlike the previous implementation, the two write paths are independent
    //
    // This permits POP to update the stack pointer and a destination register
    // during the same clock cycle.

    else if (clk_en) begin

        //==============================
        // NORMAL REGISTER WRITEBACK
        //================================
        // A normal write is accepted when:
        // - Its enable is asserted.
        // - Its destination is R0-R13.
        // - It does not conflict with a
        //   dedicated stack write to R13.
        //
        // If stack_sp_write_en is asserted, an ordinary write to R13 is blocked
        // so the dedicated stack path wins

        if (write_en && (write_addr < 4'd14) && !(stack_sp_write_en && (write_addr == 4'd13))) begin
            registers[write_addr] <= write_data;
        end

        //===============================
        // DEDICATED STACK-POINTER WRITE
        //===============================
        // Update R13 independently from normal writeback.
        //
        // If the normal destination is not R13, both physical registers may
        // update on this same rising edge.
        // If both paths select R13, only this assignment is permitted.

        if (stack_sp_write_en) begin
            registers[13] <= stack_sp_next_v;
        end

        // With neither enable asserted, all registers retain state
    end

    // Clock enable disabled: preserve every architectural register

end


endmodule
