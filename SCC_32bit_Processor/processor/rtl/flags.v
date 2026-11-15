// flags.v
// Architectural Stack Full, Negative, Zero, Carry, and
// signed Overflow (SNZCV) flag storage for the SCC.
//
// Responsibilities:
// - Store all five architectural status flags.
// - Clear SNZCV when synchronous reset is asserted.
// - Update NZCV for flag-setting arithmetic instructions.
// - Restore all five flags through SAVF.
// - Update the S flag when the stack-full status changes.
// - Preserve each flag when its update is not requested.
//
// Architectural Flag Definitions:
// - S: Stack Full; indicates the 16-word stack is full.
// - N: Negative result.
// - Z: Zero result.
// - C: Carry/no-borrow for arithmetic operations.
// - V: Signed arithmetic overflow.
//
// Design Notes:
// - Five one-bit flip-flops hold the architectural flags.
// - Combinational result calculation occurs outside
//   this module.
// - ALU and microcode operations update NZCV only.
// - Stack operations update S independently of NZCV.
// - SAVF explicitly restores all five architectural flags.
// - MOVF reads the stored flags without modifying them.
//
// Update Priority:
// 1. Synchronous reset clears all five flags.
// 2. SAVF restores all five flags.
// 3. Otherwise, independent stack-S and NZCV updates
//    may occur on the same enabled rising clock edge.

module flags (
    input wire clk,
    input wire rst,
    input wire clk_en,

    // Normal arithmetic or microcode NZCV update request.
    input wire set_flags,

    // Calculated NZCV values
    input wire alu_n_f,
    input wire alu_z_f,
    input wire alu_c_f,
    input wire alu_v_f,

    //====================================
    // STACK-FULL STATUS UPDATE INTERFACE
    //=======================================
    // WB_STAGE calculates the architectural S-flag update
    // using the decoded PUSH/POP request and stack occupancy.
    //
    // A PUSH that fills the sixteenth entry asserts S.
    // A POP clears S, including an empty-stack POP.
    //
    // The flags register stores the requested value on an
    // enabled rising clock edge, unless reset or SAVF has priority.
    input wire stack_s_write_en,
    input wire stack_s_value,

    // SAVF restores all five flags from the source
    // register's least significant five bits
    input wire savf_write_en,
    input wire [4:0] savf_data_v,

    // Stored architectural status output
    output reg s_f,
    output reg n_f,
    output reg z_f,
    output reg c_f,
    output reg v_f
);

//========================================
// SYNCHRONOUS ARCHITECTURAL FLAG STORAGE
//=======================================
//
// Reset has highest priority and clears SNZCV.
//
// SAVF replaces all five stored status bits.
//
// In normal operation, stack status and arithmetic
// status are independent:
// - The stack controller may update S.
// - An ALU or microcode operation may update NZCV.
//
// If no update is requested for a flag, its flip-flop
// retains the previously stored value.
//
// Clock enable gates all updates except reset

always @(posedge clk) begin

    //====================================
    // PRIORITY 1: SYNCHRONOUS RESET
    //===================================
    // Clear all architectural flags on reset.
    // Reset is effective even when clk_en is low

    if (rst) begin
        s_f <= 1'b0;
        n_f <= 1'b0;
        z_f <= 1'b0;
        c_f <= 1'b0;
        v_f <= 1'b0;
    end

    //=======================================
    // PRIORITY 2: ENABLED FLAG OPERATIONS
    //========================================

    else if (clk_en) begin

        //==============================
        // SAVF: RESTORE ALL FIVE FLAGS
        //==============================
        // A SAVF instruction takes priority over
        // normal arithmetic and stack flag updates.
        //
        // Source register bits [4:0] correspond to
        // S, N, Z, C, and V, respectively

        if (savf_write_en) begin
            s_f <= savf_data_v[4];
            n_f <= savf_data_v[3];
            z_f <= savf_data_v[2];
            c_f <= savf_data_v[1];
            v_f <= savf_data_v[0];
        end

        //=============================
        // NORMAL INDEPENDENT UPDATES
        //==============================
        // Without SAVF, S and NZCV are updated
        // through their separate functional sources

        else begin

            // Update Stack Full status only when
            // the stack controller requests it
            if (stack_s_write_en) begin
                s_f <= stack_s_value;
            end

            // Update NZCV only for instructions
            // that explicitly request new flags
            if (set_flags) begin
                n_f <= alu_n_f;
                z_f <= alu_z_f;
                c_f <= alu_c_f;
                v_f <= alu_v_f;
            end

            // If neither update is requested, all
            // architectural flip-flops retain state
        end
    end

    // With clk_en disabled, no flag update occurs
end

endmodule
