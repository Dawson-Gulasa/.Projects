// alu.v
// Combinational Arithmetic Logic Unit (ALU) for the SCC processor.
//
// Responsibilities:
// - Perform 32-bit arithmetic and logical operations.
// - Select the operation using the decoded alu_op_v signal.
// - Generate the 32-bit result of the selected operation.
// - Calculate the associated Negative, Zero, Carry, and
//   signed-oVerflow (NZCV) status values.
//
// ALU Operation Encoding:
// - 3'b000: MUL - executed by the separate microcode system.
// - 3'b001: ADD - 32-bit addition.
// - 3'b010: SUB - 32-bit subtraction.
// - 3'b011: AND - bitwise logical AND.
// - 3'b100: OR  - bitwise logical OR.
// - 3'b101: XOR - bitwise exclusive OR.
// - 3'b110: NOT - bitwise inversion of operand A.
// - 3'b111: DIV - reserved and unsupported in CP4.
//
// Design Notes:
// - This module implements combinational logic only.
// - No registers or flip-flops are maintained in the ALU.
// - Signed multiplication is handled by ucode_controller.v
//   and the associated multiplication integration logic.
// - MUL and MULS results are not produced by this ALU.
// - DIV remains unsupported in the current CP4 design.
// - The ALU calculates candidate NZCV flag values.
// - Architectural flag storage and write-enable decisions
//   are handled separately by the processor's flag logic.

module alu (
    // First 32-bit arithmetic or logical operand
    input [31:0] operand_a_v,

    // Second 32-bit operand used by binary ALU operations.
    // NOT uses operand A and does not require operand B
    input [31:0] operand_b_v,

    // Three-bit operation selection from the instruction decoder.
    input [2:0] alu_op_v,

    // Combinational 32-bit result of the selected operation
    output reg [31:0] result_v,

    // Calculated ALU status flags.
    // These values do not directly update architectural flags.
    output reg n_f,  // Negative: most significant result bit
    output reg z_f,  // Zero: result equals zero
    output reg c_f,  // Carry-out or no-borrow indication
    output reg v_f  // Signed arithmetic overflow
);

//==============================
// INTERNAL ARITHMETIC SIGNALS
//===============================
// A 33-bit intermediate result is used for ADD so the
// carry-out beyond the 32-bit datapath is preserved.
//
// The lower 32 bits provide the architectural ADD result.
// Bit 32 provides the unsigned carry-out flag

reg [32:0] arithmetic_result_v;

//==========================
// ALU OPERATION ENCODINGS
//============================
// These constants identify the operations implemented by
// the combinational ALU.
//
// MUL and DIV are intentionally excluded from these
// local parameters because they are not executed here.
//
// MUL is implemented by the processor's microcode system.
// DIV is currently rejected by the instruction decoder

localparam ADD = 3'b001;
localparam SUB = 3'b010;
localparam AND = 3'b011;
localparam OR = 3'b100;
localparam XOR = 3'b101;
localparam NOT = 3'b110;

//==================================================
// COMBINATIONAL ALU OPERATION AND FLAG CALCULATION
//===================================================
// The ALU performs the selected operation immediately
// when operands or the operation code change.
//
// Every output is assigned a default value before
// evaluating the operation selection.
//
// This prevents unintended latch inference and ensures
// that unsupported operations have defined local outputs.
//
// Carry and overflow are calculated only for arithmetic
// operations in this implementation.
//
// Negative and Zero are calculated from the final
// 32-bit result, regardless of the selected operation.
//
// The flag-control module separately determines whether
// these calculated values update architectural NZCV.

always @(*) begin

    //-----------------------------------------
    // DEFAULT RESULT AND INTERMEDIATE VALUES
    //-------------------------------------------
    // Initialize the result and 33-bit arithmetic
    // intermediate to zero before selecting an operation

    result_v = 32'h0000_0000;
    arithmetic_result_v = 33'h0;

    //---------------------
    // DEFAULT NZCV VALUES
    //----------------------
    // Clear all candidate flags before the operation.
    //
    // ADD and SUB can override Carry and Overflow.
    // Negative and Zero are calculated after the case
    // statement using the final 32-bit result

    n_f = 1'b0;
    z_f = 1'b0;
    c_f = 1'b0;
    v_f = 1'b0;

    //----------------------------------
    // SELECT THE DECODED ALU OPERATION
    //-----------------------------------
    // The ALU operation code determines which result
    // and arithmetic flags are generated

    case (alu_op_v)

        //=============
        // ADDITION
        //==============
        // Perform unsigned 33-bit addition of two 32-bit
        // operands with leading zeros.
        //
        // The lower 32 bits provide the wrapped result.
        // Bit 32 indicates a carry beyond the datapath.
        //
        // Signed overflow occurs when both operands have
        // the same sign but the result has the opposite sign.

        ADD: begin

            // Extend both operands before addition to
            // preserve the carry-out from bit 31
            arithmetic_result_v = {1'b0, operand_a_v} + {1'b0, operand_b_v};

            // Return the lower 32 bits of the sum
            result_v = arithmetic_result_v[31:0];

            // Carry is the extra bit produced by addition
            c_f = arithmetic_result_v[32];

            // If operands have equal signs and the result
            // has a different sign, assert signed overflow.
            v_f = (~(operand_a_v[31] ^ operand_b_v[31])) & (operand_a_v[31] ^ result_v[31]);

        end

        //==============
        // SUBTRACTION
        //===============
        // Subtract operand B from operand A.
        //
        // Result = A - B, modulo 2^32.
        //
        // The Carry flag follows the no-borrow convention:
        // - C = 1 when A >= B as unsigned values.
        // - C = 0 when subtraction requires a borrow.
        //
        // Signed overflow occurs when operands have
        // different signs and the result's sign differs
        // from the original sign of operand A

        SUB: begin

            // Calculate the 32-bit subtraction result
            result_v = operand_a_v - operand_b_v;

            // Set Carry if no unsigned borrow is needed.
            c_f = (operand_a_v >= operand_b_v);

            // Detect signed subtraction overflow using
            // the operand and result sign bits.
            v_f = (operand_a_v[31] ^ operand_b_v[31]) & (operand_a_v[31] ^ result_v[31]);

        end

        //=============
        // BITWISE AND
        //==============
        // Perform a bit-by-bit logical AND.
        //
        // A result bit is one only when the corresponding
        // bits of both operands are one.
        //
        // Carry and Overflow remain at their defaults.

        AND: begin
            result_v = operand_a_v & operand_b_v;
        end

        //============
        // BITWISE OR
        //=============
        // Perform a bit-by-bit logical OR.
        //
        // A result bit is one when either corresponding
        // operand bit is one.
        //
        // Carry and Overflow remain at their defaults

        OR: begin
            result_v = operand_a_v | operand_b_v;
        end

        //==============
        // BITWISE XOR
        //==============
        // Perform a bit-by-bit exclusive OR.
        //
        // A result bit is one when the corresponding
        // operand bits are different.
        //
        // Carry and Overflow remain at their defaults.

        XOR: begin
            result_v = operand_a_v ^ operand_b_v;
        end

        //================
        // BITWISE NOT
        //================
        // Invert every bit of operand A.
        //
        // Operand B is not used by this operation.
        // Carry and Overflow remain at their defaults.

        NOT: begin
            result_v = ~operand_a_v;
        end

        //===================================
        // UNSUPPORTED / NON-ALU OPERATIONS
        //=====================================
        // The ordinary combinational ALU does not execute
        // MUL or DIV.
        //
        // MUL is handled by the microcode controller.
        // DIV is unsupported in the current checkpoint.
        //
        // Return the default zero result for these codes.
        // This is only a local ALU default, not a valid
        // architectural multiplication or division result.
        //
        // The instruction decoder and control logic
        // determine whether an instruction is permitted

        default: begin
            result_v = 32'h0000_0000;
        end

    endcase

    //-----------------
    // NEGATIVE FLAG
    //-------------------
    // Set N when the most significant bit of the final
    // 32-bit result is one.
    //
    // In two's-complement interpretation, this indicates
    // a negative 32-bit result

    n_f = result_v[31];

    //--------------
    // ZERO FLAG
    //-------------
    // Set Z when every bit of the final result is zero.
    //
    // The Zero flag is therefore asserted for the
    // default zero result of unsupported operation codes.
    // Such codes must not commit these candidate flags
    // unless permitted by the processor control logic

    z_f = (result_v == 32'h0000_0000);

end

endmodule
