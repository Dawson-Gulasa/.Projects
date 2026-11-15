// mul_datapath.v
// Combinational signed multiplication datapath for the SCC.
//
// Responsibilities:
// - Multiply two signed 32-bit operands.
// - Produce the full signed 64-bit product.
//
// The microcode controller owns operand capture, result storage,
// FSM sequencing, and architectural writeback timing.
//
// This module contains no registers or clocked logic.

module mul_datapath (
    input wire signed [31:0] operand_a_v,
    input wire signed [31:0] operand_b_v,

    output wire signed [63:0] product_v
);

    //========================================
    // COMBINATIONAL SIGNED MULTIPLICATION
    //========================================
    // Both input operands are explicitly signed.
    //
    // The 64-bit result retains both halves of the product:
    // - Bits [31:0] are eventually written to Rd.
    // - Bits [63:32] are eventually written to R12.
    //
    // The multiplication operator is permitted by the
    // course's microcode implementation requirements.
    //
    // This continuous assignment is combinational and
    // does not introduce a clocked storage element.

    assign product_v = operand_a_v * operand_b_v;

endmodule
