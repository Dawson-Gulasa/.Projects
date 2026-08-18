`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// prime_check_core.v
//
// Purpose:
//   Synchronously determines whether one 32-bit candidate number is prime using
//   trial division with repeated subtraction instead of the modulus operator.
//
//   This is the lowest-level prime-checking building block in the project. It
//   checks one candidate at a time and is controlled by higher-level logic for
//   SINGLE, RANGE, and TIME prime-computation modes.
//
// Prime-check algorithm:
//   1) If candidate < 2, the number is not prime.
//   2) If candidate == 2, the number is prime.
//   3) If candidate is even and greater than 2, the number is not prime.
//   4) Otherwise, test odd divisors starting at 3.
//   5) Stop testing divisors once divisor * divisor > candidate.
//   6) For each divisor, use repeated subtraction to determine divisibility.
//
// Repeated-subtraction example:
//   To check whether 17 is divisible by 5:
//
//       17 - 5 = 12
//       12 - 5 = 7
//        7 - 5 = 2
//
//   The loop stops because 2 < 5. Since the remainder is not 0, 17 is not
//   divisible by 5. If the running remainder ever becomes exactly 0, the
//   candidate is divisible by that divisor and is therefore composite.
//
// Interface behavior:
//   - start should be pulsed while the core is idle.
//   - busy stays high while the core is actively computing.
//   - done pulses high for one clock cycle when the result is ready.
//   - is_prime holds the most recently computed result.
//   - abort returns the module to idle and clears the active calculation.
//
// Notes:
//   - Reset is synchronous through rst_n.
//   - No synthesis for-loops are used.
//   - The FSM is written with a separate state register and combinational
//     next-state/datapath block.
//------------------------------------------------------------------------------

module prime_check_core (
    input  wire        clk,        // System clock
    input  wire        rst_n,      // Active-low synchronized reset
    input  wire        start,      // One-cycle start pulse accepted while idle
    input  wire        abort,      // Abort current calculation and return to idle
    input  wire [31:0] candidate,  // Candidate number to classify as prime/non-prime

    output wire        busy,       // High while prime check is actively running
    output wire        done,       // One-clock pulse when is_prime result is valid
    output wire        is_prime    // Result: 1 = prime, 0 = not prime
);

    //--------------------------------------------------------------------------
    // Prime-check FSM state encoding
    //
    // The FSM classifies simple cases first, then tests odd divisors using a
    // repeated-subtraction loop.
    //--------------------------------------------------------------------------
    localparam [2:0] S_IDLE            = 3'd0; // Waiting for start
    localparam [2:0] S_CLASSIFY_INPUT  = 3'd1; // Handle <2, 2, and even cases
    localparam [2:0] S_PREPARE_DIVISOR = 3'd2; // Check divisor^2 bound and reset remainder
    localparam [2:0] S_SUBTRACT_LOOP   = 3'd3; // Repeatedly subtract divisor from remainder
    localparam [2:0] S_CHECK_REMAINDER = 3'd4; // Decide whether candidate was divisible
    localparam [2:0] S_DONE_PULSE      = 3'd5; // One-cycle completion pulse

    //--------------------------------------------------------------------------
    // State and datapath registers
    //
    // Each *_ff register stores the current value. Each *_n signal is the next
    // value computed by the combinational next-state logic.
    //--------------------------------------------------------------------------
    reg [2:0]  state_ff;       // Current FSM state
    reg [2:0]  state_n;        // Next FSM state

    reg [31:0] candidate_ff;   // Latched candidate being checked
    reg [31:0] candidate_n;    // Next latched candidate value

    reg [31:0] divisor_ff;     // Current trial divisor
    reg [31:0] divisor_n;      // Next trial divisor

    reg [31:0] remainder_ff;   // Running remainder used for subtraction test
    reg [31:0] remainder_n;    // Next running remainder

    reg        is_prime_ff;    // Registered prime/non-prime result
    reg        is_prime_n;     // Next prime/non-prime result

    //--------------------------------------------------------------------------
    // Registered-result output
    //
    // The result remains available after done pulses, until a reset, abort, or
    // new computation updates it.
    //--------------------------------------------------------------------------
    assign is_prime = is_prime_ff;

    //--------------------------------------------------------------------------
    // Busy/done status outputs
    //
    // busy is high during useful work states. done is a one-cycle Moore-style
    // pulse while the FSM is in S_DONE_PULSE.
    //--------------------------------------------------------------------------
    assign busy = (state_ff != S_IDLE) && (state_ff != S_DONE_PULSE);
    assign done = (state_ff == S_DONE_PULSE);

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // All state and datapath registers update on the rising edge of clk.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Clear the FSM and datapath during synchronized active-low reset.
        if (!rst_n) begin
            state_ff     <= S_IDLE;
            candidate_ff <= 32'd0;
            divisor_ff   <= 32'd0;
            remainder_ff <= 32'd0;
            is_prime_ff  <= 1'b0;
        end else begin
            // Normal operation loads the next-state values.
            state_ff     <= state_n;
            candidate_ff <= candidate_n;
            divisor_ff   <= divisor_n;
            remainder_ff <= remainder_n;
            is_prime_ff  <= is_prime_n;
        end
    end

    //--------------------------------------------------------------------------
    // Prime-check FSM next-state and datapath logic
    //
    // Defaults hold the current values so every output of this combinational
    // block is defined. Individual FSM states then override only the registers
    // that need to change.
    //--------------------------------------------------------------------------
    always @(*) begin
        state_n     = state_ff;
        candidate_n = candidate_ff;
        divisor_n   = divisor_ff;
        remainder_n = remainder_ff;
        is_prime_n  = is_prime_ff;

        // Abort has priority over normal FSM operation.
        if (abort) begin
            state_n     = S_IDLE;
            candidate_n = 32'd0;
            divisor_n   = 32'd0;
            remainder_n = 32'd0;
            is_prime_n  = 1'b0;
        end else begin

            case (state_ff)

                // -------------------------------------------------------------
                // S_IDLE
                //
                // Wait for a new start pulse. Once start arrives, latch the
                // candidate and move to the special-case classification state.
                // -------------------------------------------------------------
                S_IDLE: begin
                    // Accept a new candidate only while idle.
                    if (start) begin
                        candidate_n = candidate;
                        divisor_n   = 32'd0;
                        remainder_n = 32'd0;
                        is_prime_n  = 1'b0;
                        state_n     = S_CLASSIFY_INPUT;
                    end else begin
                        state_n = S_IDLE;
                    end
                end

                // -------------------------------------------------------------
                // S_CLASSIFY_INPUT
                //
                // Handle prime definition edge cases before trial division.
                // -------------------------------------------------------------
                S_CLASSIFY_INPUT: begin
                    // 0 and 1 are not prime by definition.
                    if (candidate_ff < 32'd2) begin
                        is_prime_n = 1'b0;
                        state_n    = S_DONE_PULSE;
                    end
                    // 2 is prime and is the only even prime.
                    else if (candidate_ff == 32'd2) begin
                        is_prime_n = 1'b1;
                        state_n    = S_DONE_PULSE;
                    end
                    // Any even number greater than 2 is composite.
                    else if (candidate_ff[0] == 1'b0) begin
                        is_prime_n = 1'b0;
                        state_n    = S_DONE_PULSE;
                    end
                    // Odd candidates greater than 2 require trial division.
                    else begin
                        divisor_n   = 32'd3;
                        remainder_n = candidate_ff;
                        state_n     = S_PREPARE_DIVISOR;
                    end
                end

                // -------------------------------------------------------------
                // S_PREPARE_DIVISOR
                //
                // Check the divisor-squared stopping condition. If divisor^2 is
                // greater than the candidate, no possible factor remains.
                // -------------------------------------------------------------
                S_PREPARE_DIVISOR: begin
                    // Trial division is complete once divisor^2 exceeds candidate.
                    if ((divisor_ff * divisor_ff) > candidate_ff) begin
                        is_prime_n = 1'b1;
                        state_n    = S_DONE_PULSE;
                    end
                    // Otherwise reset the remainder and begin divisibility testing.
                    else begin
                        remainder_n = candidate_ff;
                        state_n     = S_SUBTRACT_LOOP;
                    end
                end

                // -------------------------------------------------------------
                // S_SUBTRACT_LOOP
                //
                // Repeatedly subtract the current divisor from the running
                // remainder until the remainder becomes smaller than the divisor.
                // -------------------------------------------------------------
                S_SUBTRACT_LOOP: begin
                    // Continue subtracting while divisor still fits in remainder.
                    if (remainder_ff >= divisor_ff) begin
                        remainder_n = remainder_ff - divisor_ff;
                        state_n     = S_SUBTRACT_LOOP;
                    end
                    // Remainder is now less than divisor, so check divisibility.
                    else begin
                        state_n = S_CHECK_REMAINDER;
                    end
                end

                // -------------------------------------------------------------
                // S_CHECK_REMAINDER
                //
                // A zero remainder means the candidate is exactly divisible by
                // the current divisor. Otherwise, move to the next odd divisor.
                // -------------------------------------------------------------
                S_CHECK_REMAINDER: begin
                    // Exact divisibility means the candidate is composite.
                    if (remainder_ff == 32'd0) begin
                        is_prime_n = 1'b0;
                        state_n    = S_DONE_PULSE;
                    end
                    // Not divisible by this divisor, so try the next odd divisor.
                    else begin
                        divisor_n = divisor_ff + 32'd2;
                        state_n   = S_PREPARE_DIVISOR;
                    end
                end

                // -------------------------------------------------------------
                // S_DONE_PULSE
                //
                // Hold the result stable, assert done for one cycle, and return
                // to idle on the next clock.
                // -------------------------------------------------------------
                S_DONE_PULSE: begin
                    state_n = S_IDLE;
                end

                // -------------------------------------------------------------
                // Unknown state recovery
                //
                // Safely clear datapath values and return to idle.
                // -------------------------------------------------------------
                default: begin
                    state_n     = S_IDLE;
                    candidate_n = 32'd0;
                    divisor_n   = 32'd0;
                    remainder_n = 32'd0;
                    is_prime_n  = 1'b0;
                end

            endcase
        end
    end

endmodule