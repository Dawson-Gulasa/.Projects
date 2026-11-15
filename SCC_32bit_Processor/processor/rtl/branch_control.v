// branch_control.v
// Combinational conditional-branch evaluation for the SCC.
//
// Responsibilities:
// - Receive the decoded 4-bit B.cond condition field.
// - Read the stored architectural NZCV flags.
// - Evaluate whether the requested branch condition is met.
// - Produce condition_met for the instruction-fetch stage.
//
// Design Notes:
// - No sequential state is stored in this module.
// - Architectural NZCV flags are maintained by flags.v.
// - The instruction decoder extracts the branch condition.
// - The IF stage calculates branch destinations and updates PC.
// - This module does not directly modify the Program Counter.
//
// Supported Condition Codes:
// - EQ: Equal                         (Z = 1)
// - NE: Not Equal                     (Z = 0)
// - HS: Unsigned Higher or Same       (C = 1)
// - LO: Unsigned Lower                (C = 0)
// - MI: Minus / Negative              (N = 1)
// - PL: Plus / Positive or Zero       (N = 0)
// - VS: Signed Overflow Set           (V = 1)
// - VC: Signed Overflow Clear         (V = 0)
// - HI: Unsigned Higher               (C = 1 and Z = 0)
// - LS: Unsigned Lower or Same        (C = 0 or Z = 1)
// - GE: Signed Greater or Equal       (N = V)
// - LT: Signed Less Than              (N != V)
// - GT: Signed Greater Than           (Z = 0 and N = V)
// - LE: Signed Less or Equal          (Z = 1 or N != V)

module branch_control (
    // Four-bit condition field from the instruction decoder
    input [3:0] branch_cond_v,

    // Stored architectural flags.
    // These inputs reflect the most recently committed NZCV state
    input n_f,
    input z_f,
    input c_f,
    input v_f,

    // Combinational branch decision.
    // 1: Selected condition is satisfied
    // 0: Selected condition is not satisfied
    output reg condition_met
);

//============================
// BRANCH CONDITION ENCODINGS
//==============================
// These local parameters correspond to the supported
// B.cond condition encodings in the SCC ISA.
//
// Encodings 1110 and 1111 are not defined here and
// produce a not-taken result through the default case.

localparam EQ = 4'b0000;
localparam NE = 4'b0001;
localparam HS = 4'b0010;
localparam LO = 4'b0011;
localparam MI = 4'b0100;
localparam PL = 4'b0101;
localparam VS = 4'b0110;
localparam VC = 4'b0111;
localparam HI = 4'b1000;
localparam LS = 4'b1001;
localparam GE = 4'b1010;
localparam LT = 4'b1011;
localparam GT = 4'b1100;
localparam LE = 4'b1101;

//=============================================
// COMBINATIONAL BRANCH CONDITION EVALUATION
//==============================================
// Determine whether the decoded conditional-branch
// condition is satisfied by the stored architectural flags.
//
// The default output is zero, so a branch is not taken
// unless one of the defined conditions evaluates true.
//
// The case statement explicitly covers every supported
// condition code and provides a default for all others.
//
// Blocking assignments are used because the module
// performs combinational evaluation without storing state.
//
// The IF stage uses condition_met along with the decoded
// conditional-branch control to select the next PC

always @(*) begin

    // Default to condition not satisfied
    // This also prevents unintended latch inference.
    condition_met = 1'b0;

    // Evaluate the selected branch condition using NZCV.
    case (branch_cond_v)

        //====================
        // EQUALITY CONDITIONS
        //=====================

        // EQ: Take the branch when the Zero flag is set.
        // Typically follows a comparison that produced zero
        EQ: begin
            condition_met = z_f;
        end

        // NE: Take the branch when the Zero flag is clear.
        // Typically indicates that compared values differ
        NE: begin
            condition_met = ~z_f;
        end

        //===========================
        // BASIC UNSIGNED CONDITIONS
        //===========================

        // HS: Unsigned Higher or Same.
        // Take the branch when Carry is set.
        // With the ALU's subtraction convention, C = 1
        // indicates that no unsigned borrow occurred
        HS: begin
            condition_met = c_f;
        end

        // LO: Unsigned Lower.
        // Take the branch when Carry is clear, indicating
        // that unsigned subtraction required a borrow.
        LO: begin
            condition_met = ~c_f;
        end

        //===============================
        // SIGN AND OVERFLOW CONDITIONS
        //===============================

        // MI: Minus.
        // Take the branch when the Negative flag is set
        MI: begin
            condition_met = n_f;
        end

        // PL: Plus.
        // Take the branch when the Negative flag is clear
        PL: begin
            condition_met = ~n_f;
        end

        // VS: Overflow Set.
        // Take the branch when signed arithmetic overflow
        // is indicated by the architectural V flag
        VS: begin
            condition_met = v_f;
        end

        // VC: Overflow Clear.
        // Take the branch when no signed arithmetic
        // overflow is indicated by the V flag
        VC: begin
            condition_met = ~v_f;
        end

        //===============================
        // COMBINED UNSIGNED CONDITIONS
        //===============================

        // HI: Unsigned Higher.
        // Take the branch only when no borrow occurred
        // and the values were not equal
        HI: begin
            condition_met = c_f & ~z_f;
        end

        // LS: Unsigned Lower or Same.
        // Take the branch when a borrow occurred or
        // the operands were equal
        LS: begin
            condition_met = ~(c_f & ~z_f);
        end

        //==============================
        // SIGNED COMPARISON CONDITIONS
        //================================

        // GE: Signed Greater or Equal.
        // Take the branch when Negative and Overflow match.
        // Matching N and V indicates a nonnegative signed
        // comparison result after accounting for overflow.
        GE: begin
            condition_met = (n_f == v_f);
        end

        // LT: Signed Less Than.
        // Take the branch when Negative and Overflow differ.
        // Different N and V indicate a signed less-than result.
        LT: begin
            condition_met = (n_f != v_f);
        end

        // GT: Signed Greater Than.
        // Require a nonzero comparison result and matching
        // Negative and Overflow flags.
        GT: begin
            condition_met = ~z_f & (n_f == v_f);
        end

        // LE: Signed Less Than or Equal.
        // Take the branch when the comparison is equal
        // or indicates a signed less-than result.
        LE: begin
            condition_met = ~(~z_f & (n_f == v_f));
        end

        //===============================
        // UNDEFINED CONDITION ENCODINGS
        //================================

        // Condition fields 1110 and 1111 are not supported.
        // For any undefined condition, do not take the branch.
        // This safely preserves the initial default behavior
        default: begin
            condition_met = 1'b0;
        end

    endcase

end

endmodule
