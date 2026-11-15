// div_datapath.v
// Combinational signed division datapath for the SCC.
//
// Responsibilities:
// - Calculate a signed 32-bit quotient and remainder.
// - Detect division by zero.
// - Detect signed division overflow.
// - Generate candidate DIVS NZCV flag values.
//
// Architectural behavior:
// - Quotient is written to Rd by the controller.
// - Remainder is written to R12 by the controller.
// - Quotient truncates toward zero.
// - Remainder follows the sign of the dividend.
// - Division by zero must prevent architectural writes.
// - Signed overflow produces quotient 0x80000000 and remainder 0x00000000.
//
// Design notes:
// - This module contains no sequential state.
// - Arithmetic inputs are explicitly signed.
// - All combinational outputs receive default values.
// - The division controller captures the combinational results on an enabled
//   rising clock edge and retains them throughout the writeback sequence.
// - The quotient and remainder are committed on separate clock cycles
//   through WB_STAGE and the architectural register file.
// - The controller checks the live divisor before starting division;
//   the datapath also provides divide_by_zero for exception indication.// - Only DIVS updates NZCV; that selection is handled outside this module.
// - The architectural S flag is not modified here.

module div_datapath (
    input wire signed [31:0] dividend_v,
    input wire signed [31:0] divisor_v,

    // Signed division results.
    output reg [31:0] quotient_v,
    output reg [31:0] remainder_v,

    // Exception indications.
    output wire divide_by_zero,
    output wire signed_overflow,

    // Candidate DIVS status values
    output wire div_n_f,
    output wire div_z_f,
    output wire div_c_f,
    output wire div_v_f
);

//===============================
// DIVISION EXCEPTION DETECTION
//================================
// Division by zero is an architectural error.
//
// The controller must halt execution and suppress both destination-register writes
// when this condition is detected.
//
// Signed overflow occurs only for:
// 0x80000000 / 0xFFFFFFFF
//
// The mathematical quotient is +2147483648, which cannot be represented as a signed
// 32-bit two's-complement integer.

assign divide_by_zero = (divisor_v == 32'sd0);

assign signed_overflow = (dividend_v == 32'sh8000_0000) && (divisor_v == -32'sd1);

//=================================
// COMBINATIONAL SIGNED DIVISION
//==================================
// All outputs are assigned defaults to
// avoid unintended latch inference.
//
// Division by zero is checked before evaluating the division operators.
//
// Verilog signed division truncates the quotient toward zero.
// Signed remainder uses the sign of the dividend when the remainder is nonzero.
// The special overflow case is handled explicitly for deterministic behavior.

always @(*) begin

    // Safe default results.
    quotient_v  = 32'd0;
    remainder_v = 32'd0;

    if (!divide_by_zero) begin

        if (signed_overflow) begin

            // Minimum signed integer divided
            // by negative one.
            // The ISA specifies the wrapped signed quotient and zero remainder.

            quotient_v  = 32'h8000_0000;
            remainder_v = 32'h0000_0000;

        end else begin

            // Signed arithmetic.
            // Both operands are declared signed, so the / and % operators implement
            // the required signed behavior.

            quotient_v  = dividend_v / divisor_v;
            remainder_v = dividend_v % divisor_v;

        end
    end

end

//=======================
// DIVS FLAG CALCULATION
//========================
// The candidate flags are calculated from
// the 32-bit quotient
//
// N = sign bit of quotient.
// Z = quotient equals zero.
// C = cleared for division.
// V = signed division overflow.
//
// Ordinary DIV preserves architectural NZCV.
// DIVS commits these values.
// The multicycle controller determines when these values can be committed.
// A divide-by-zero exception must suppress all architectural flag and register writes.

assign div_n_f = quotient_v[31];
assign div_z_f = (quotient_v == 32'd0);
assign div_c_f = 1'b0;
assign div_v_f = signed_overflow;

endmodule
