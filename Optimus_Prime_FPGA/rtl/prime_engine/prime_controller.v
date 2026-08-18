`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// prime_controller.v
//
// Purpose:
//   Higher-level controller for the prime-finding subsystem.
//
//   This module sits above prime_check_core and turns the single-candidate
//   primality checker into the three project compute modes:
//
//     00 = SINGLE   Check whether one entered number is prime.
//     01 = RANGE    Find all primes from range_start through range_limit.
//     10 = TIME     Find primes until the entered second limit is reached.
//     11 = RESERVED Complete immediately with no active run.
//
// Design approach:
//   - prime_check_core handles the actual primality test for one candidate.
//   - prime_controller sequences candidates and decides which candidate to check
//     next.
//   - The controller tracks prime count, largest prime, elapsed time, recent
//     prime history, and storage-facing prime_found events.
//
// Candidate-skip algorithm:
//   After checking 2, the controller checks only odd values. This avoids wasting
//   time on even candidates greater than 2.
//
//   Example:
//     2 -> 3 -> 5 -> 7 -> 9 -> 11 ...
//
//   Even values such as 4, 6, 8, and 10 are skipped because they cannot be prime.
//
// Time-mode policy:
//   TIME mode uses a strict no-overshoot rule. When the requested time limit is
//   reached, the controller aborts the current prime_check_core operation and
//   completes the mode so the run does not continue past the entered limit.
//
// Recent-prime history:
//   The module maintains the most recent 20 discovered primes in a packed bus:
//     recent_primes_flat[ 31:  0] = newest prime
//     recent_primes_flat[ 63: 32] = second newest
//     ...
//     recent_primes_flat[639:608] = oldest of the last 20
//
// Storage-facing event outputs:
//   prime_found_pulse, prime_found_value, and prime_found_index allow storage
//   logic to write each discovered prime without needing to inspect controller
//   internals.
//
// Notes:
//   - rst_n is a synchronized active-low reset.
//   - abort immediately clears the controller and returns it to IDLE.
//   - abort does not produce a normal done pulse.
//   - This module contains the main prime-computation FSM.
//------------------------------------------------------------------------------

module prime_controller (
    input  wire        clk,                // System clock
    input  wire        rst_n,              // Active-low synchronized reset
    input  wire        start,              // One-clock pulse to start a new run
    input  wire        abort,              // Abort current run and return to idle
    input  wire [1:0]  mode,               // Compute mode: 00=SINGLE, 01=RANGE, 10=TIME
    input  wire [31:0] single_value,       // SINGLE-mode candidate value
    input  wire [31:0] range_start,        // RANGE-mode lower bound
    input  wire [31:0] range_limit,        // RANGE-mode upper bound
    input  wire [31:0] time_limit_sec,     // TIME-mode limit in seconds
    input  wire        tick_1hz,           // One-clock pulse every second

    output wire        busy,               // High while the controller is running
    output wire        done,               // One-clock pulse at normal completion
    output wire        mode_complete,      // High after completion until restart/reset
    output wire [31:0] prime_count,        // Number of primes found in current/completed run
    output wire [31:0] largest_prime,      // Largest discovered prime in the run
    output wire [31:0] current_candidate,  // Candidate currently being checked or last checked
    output wire [31:0] last_prime_found,   // Most recently discovered prime
    output wire        single_is_prime,    // SINGLE-mode result flag
    output wire [31:0] elapsed_seconds,    // Elapsed whole seconds while active
    output wire        prime_found_pulse,  // One-clock pulse when a prime is accepted
    output wire [31:0] prime_found_value,  // Prime value associated with prime_found_pulse
    output wire [31:0] prime_found_index,  // Zero-based index associated with the found prime
    output wire [639:0] recent_primes_flat,// Packed most-recent-20 prime history
    output wire [4:0]  recent_valid_count  // Number of valid entries in recent_primes_flat
);

    //--------------------------------------------------------------------------
    // Mode encoding
    //
    // These values match the mode input provided by the UI/top-level wrapper.
    //--------------------------------------------------------------------------
    localparam [1:0] MODE_SINGLE   = 2'b00; // Check one number
    localparam [1:0] MODE_RANGE    = 2'b01; // Generate primes in a range
    localparam [1:0] MODE_TIME     = 2'b10; // Generate primes until time expires
    localparam [1:0] MODE_RESERVED = 2'b11; // Reserved/no-op mode

    //--------------------------------------------------------------------------
    // Controller FSM state encoding
    //
    // The FSM launches one prime_check_core operation at a time, waits for the
    // result, records it, and then either launches the next candidate or
    // completes the selected mode.
    //--------------------------------------------------------------------------
    localparam [3:0] S_IDLE              = 4'd0; // Waiting for start
    localparam [3:0] S_INIT              = 4'd1; // Latch inputs and initialize run state
    localparam [3:0] S_LAUNCH_CHECK      = 4'd2; // Pulse start into prime_check_core
    localparam [3:0] S_WAIT_CHECK        = 4'd3; // Wait for prime_check_core done
    localparam [3:0] S_HANDLE_RESULT     = 4'd4; // Record checker result and choose next action
    localparam [3:0] S_TIME_ABORT_CHECK  = 4'd5; // Abort checker when TIME limit is reached
    localparam [3:0] S_DONE_PULSE        = 4'd6; // Generate one-cycle done pulse
    localparam [3:0] S_HOLD_COMPLETE     = 4'd7; // Hold completion status until restart/reset

    //--------------------------------------------------------------------------
    // Controller state and datapath registers
    //
    // Each *_ff register stores the current controller state. Each *_n signal is
    // the combinational next value computed by the next-state block.
    //--------------------------------------------------------------------------
    reg [3:0]   state_ff;                 // Current FSM state
    reg [3:0]   state_n;                  // Next FSM state

    reg [1:0]   mode_ff;                  // Latched compute mode for active run
    reg [1:0]   mode_n;                   // Next latched compute mode

    reg [31:0]  single_value_ff;          // Latched SINGLE-mode input value
    reg [31:0]  single_value_n;           // Next SINGLE-mode input value

    reg [31:0]  range_limit_ff;           // Latched RANGE-mode upper bound
    reg [31:0]  range_limit_n;            // Next RANGE-mode upper bound

    reg [31:0]  time_limit_sec_ff;        // Latched TIME-mode second limit
    reg [31:0]  time_limit_sec_n;         // Next TIME-mode second limit

    reg [31:0]  prime_count_ff;           // Current number of accepted primes
    reg [31:0]  prime_count_n;            // Next number of accepted primes

    reg [31:0]  largest_prime_ff;         // Current largest accepted prime
    reg [31:0]  largest_prime_n;          // Next largest accepted prime

    reg [31:0]  current_candidate_ff;     // Candidate currently sent to checker
    reg [31:0]  current_candidate_n;      // Next candidate to send to checker

    reg [31:0]  last_prime_found_ff;      // Most recent accepted prime
    reg [31:0]  last_prime_found_n;       // Next most recent accepted prime

    reg         single_is_prime_ff;       // SINGLE-mode result register
    reg         single_is_prime_n;        // Next SINGLE-mode result

    reg [31:0]  elapsed_seconds_ff;       // Elapsed seconds during active run
    reg [31:0]  elapsed_seconds_n;        // Next elapsed second count

    reg [639:0] recent_primes_flat_ff;    // Packed recent-prime history
    reg [639:0] recent_primes_flat_n;     // Next packed recent-prime history

    reg [4:0]   recent_valid_count_ff;    // Number of valid recent-prime entries
    reg [4:0]   recent_valid_count_n;     // Next number of valid recent entries

    reg         checker_result_ff;        // Latched prime_check_core result
    reg         checker_result_n;         // Next latched checker result

    //--------------------------------------------------------------------------
    // Internal connection to the lower-level single-candidate checker
    //
    // prime_check_core performs one primality test at a time. The controller
    // starts it in S_LAUNCH_CHECK and waits for checker_done.
    //--------------------------------------------------------------------------
    wire checker_start;                   // One-cycle start pulse to checker
    wire checker_abort;                   // One-cycle abort pulse to checker
    wire checker_busy;                    // Checker busy flag
    wire checker_done;                    // Checker done pulse
    wire checker_is_prime;                // Checker result for current candidate

    assign checker_start = (state_ff == S_LAUNCH_CHECK);
    assign checker_abort = (state_ff == S_TIME_ABORT_CHECK);

    prime_check_core u_prime_check_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (checker_start),
        .abort     (checker_abort),
        .candidate (current_candidate_ff),
        .busy      (checker_busy),
        .done      (checker_done),
        .is_prime  (checker_is_prime)
    );

    //--------------------------------------------------------------------------
    // Candidate stepping helper
    //
    // Computes the next candidate while skipping even numbers after 2.
    //
    // Example:
    //   candidate_in = 0  -> next = 2
    //   candidate_in = 2  -> next = 3
    //   candidate_in = 3  -> next = 5
    //   candidate_in = 11 -> next = 13
    //--------------------------------------------------------------------------
    function [31:0] next_candidate_value;
        input [31:0] candidate_in;
        begin
            // Values below 2 advance to the first prime candidate.
            if (candidate_in < 32'd2) begin
                next_candidate_value = 32'd2;
            end else if (candidate_in == 32'd2) begin
                next_candidate_value = 32'd3;
            end else begin
                next_candidate_value = candidate_in + 32'd2;
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Convenience wires for readable status outputs and TIME-mode stopping
    //--------------------------------------------------------------------------
    wire running_state;                   // High when the controller is actively running
    wire time_limit_reached_this_tick;    // High when TIME mode reaches its limit this cycle

    assign running_state = (state_ff == S_INIT)             ||
                           (state_ff == S_LAUNCH_CHECK)     ||
                           (state_ff == S_WAIT_CHECK)       ||
                           (state_ff == S_HANDLE_RESULT)    ||
                           (state_ff == S_TIME_ABORT_CHECK);

    assign time_limit_reached_this_tick =
        (mode_ff == MODE_TIME) &&
        (tick_1hz == 1'b1) &&
        ((elapsed_seconds_ff + 32'd1) >= time_limit_sec_ff);

    //--------------------------------------------------------------------------
    // External output assignments
    //
    // Most outputs directly expose registered datapath state so display and
    // storage logic receive stable values.
    //--------------------------------------------------------------------------
    assign busy              = running_state;
    assign done              = (state_ff == S_DONE_PULSE);
    assign mode_complete     = (state_ff == S_DONE_PULSE) || (state_ff == S_HOLD_COMPLETE);
    assign prime_count       = prime_count_ff;
    assign largest_prime     = largest_prime_ff;
    assign current_candidate = current_candidate_ff;
    assign last_prime_found  = last_prime_found_ff;
    assign single_is_prime   = single_is_prime_ff;
    assign elapsed_seconds   = elapsed_seconds_ff;

    assign prime_found_pulse = (state_ff == S_HANDLE_RESULT) && (checker_result_ff == 1'b1);
    assign prime_found_value = current_candidate_ff;
    assign prime_found_index = prime_count_ff;

    assign recent_primes_flat = recent_primes_flat_ff;
    assign recent_valid_count = recent_valid_count_ff;

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // Updates all FSM and datapath registers on the rising edge of clk.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Clear controller state and all tracked results during reset.
        if (!rst_n) begin
            state_ff              <= S_IDLE;
            mode_ff               <= MODE_SINGLE;
            single_value_ff       <= 32'd0;
            range_limit_ff        <= 32'd0;
            time_limit_sec_ff     <= 32'd0;
            prime_count_ff        <= 32'd0;
            largest_prime_ff      <= 32'd0;
            current_candidate_ff  <= 32'd0;
            last_prime_found_ff   <= 32'd0;
            single_is_prime_ff    <= 1'b0;
            elapsed_seconds_ff    <= 32'd0;
            recent_primes_flat_ff <= 640'd0;
            recent_valid_count_ff <= 5'd0;
            checker_result_ff     <= 1'b0;
        end else begin
            // Normal operation loads the next-state values computed below.
            state_ff              <= state_n;
            mode_ff               <= mode_n;
            single_value_ff       <= single_value_n;
            range_limit_ff        <= range_limit_n;
            time_limit_sec_ff     <= time_limit_sec_n;
            prime_count_ff        <= prime_count_n;
            largest_prime_ff      <= largest_prime_n;
            current_candidate_ff  <= current_candidate_n;
            last_prime_found_ff   <= last_prime_found_n;
            single_is_prime_ff    <= single_is_prime_n;
            elapsed_seconds_ff    <= elapsed_seconds_n;
            recent_primes_flat_ff <= recent_primes_flat_n;
            recent_valid_count_ff <= recent_valid_count_n;
            checker_result_ff     <= checker_result_n;
        end
    end

    //--------------------------------------------------------------------------
    // Prime controller next-state/datapath logic
    //
    // This block decides the next FSM state, updates run counters, handles
    // checker results, and implements TIME-mode stopping.
    //--------------------------------------------------------------------------
    always @(*) begin
        state_n              = state_ff;
        mode_n               = mode_ff;
        single_value_n       = single_value_ff;
        range_limit_n        = range_limit_ff;
        time_limit_sec_n     = time_limit_sec_ff;
        prime_count_n        = prime_count_ff;
        largest_prime_n      = largest_prime_ff;
        current_candidate_n  = current_candidate_ff;
        last_prime_found_n   = last_prime_found_ff;
        single_is_prime_n    = single_is_prime_ff;
        elapsed_seconds_n    = elapsed_seconds_ff;
        recent_primes_flat_n = recent_primes_flat_ff;
        recent_valid_count_n = recent_valid_count_ff;
        checker_result_n     = checker_result_ff;

        // Count elapsed whole seconds only while a compute run is active.
        if (running_state && tick_1hz) begin
            elapsed_seconds_n = elapsed_seconds_ff + 32'd1;
        end

        // Abort has priority over all normal operation and returns to IDLE.
        if (abort) begin
            state_n              = S_IDLE;
            mode_n               = MODE_SINGLE;
            single_value_n       = 32'd0;
            range_limit_n        = 32'd0;
            time_limit_sec_n     = 32'd0;
            prime_count_n        = 32'd0;
            largest_prime_n      = 32'd0;
            current_candidate_n  = 32'd0;
            last_prime_found_n   = 32'd0;
            single_is_prime_n    = 1'b0;
            elapsed_seconds_n    = 32'd0;
            recent_primes_flat_n = 640'd0;
            recent_valid_count_n = 5'd0;
            checker_result_n     = 1'b0;
        end else begin
            case (state_ff)

                //------------------------------------------------------------------
                // IDLE
                //
                // Wait for a start pulse from the UI/top-level.
                //------------------------------------------------------------------
                S_IDLE: begin
                    // Start a new run when requested.
                    if (start) begin
                        state_n = S_INIT;
                    end else begin
                        state_n = S_IDLE;
                    end
                end

                //------------------------------------------------------------------
                // INIT
                //
                // Latch run inputs, clear results/history, and choose the first
                // candidate for the selected compute mode.
                //------------------------------------------------------------------
                S_INIT: begin
                    mode_n               = mode;
                    single_value_n       = single_value;
                    range_limit_n        = range_limit;
                    time_limit_sec_n     = time_limit_sec;
                    prime_count_n        = 32'd0;
                    largest_prime_n      = 32'd0;
                    last_prime_found_n   = 32'd0;
                    single_is_prime_n    = 1'b0;
                    elapsed_seconds_n    = 32'd0;
                    recent_primes_flat_n = 640'd0;
                    recent_valid_count_n = 5'd0;
                    checker_result_n     = 1'b0;

                    // SINGLE mode checks exactly the entered value.
                    if (mode == MODE_SINGLE) begin
                        current_candidate_n = single_value;
                    end else if (mode == MODE_RANGE) begin
                        // RANGE mode starts at 2, range_start, or the next odd value.
                        if (range_start <= 32'd2)
                            current_candidate_n = 32'd2;
                        else if (range_start[0])
                            current_candidate_n = range_start;
                        else
                            current_candidate_n = range_start + 32'd1;
                    end else begin
                        // TIME mode and reserved mode start from candidate 2.
                        current_candidate_n = 32'd2;
                    end

                    // RANGE mode completes immediately for empty or invalid ranges.
                    if (mode == MODE_RANGE) begin
                        if (range_start > range_limit) begin
                            state_n = S_DONE_PULSE;
                        end else if (range_limit < 32'd2) begin
                            state_n = S_DONE_PULSE;
                        end else if (current_candidate_n > range_limit) begin
                            state_n = S_DONE_PULSE;
                        end else begin
                            state_n = S_LAUNCH_CHECK;
                        end
                    end else if (mode == MODE_TIME) begin
                        // TIME mode with a zero limit completes without checking.
                        if (time_limit_sec == 32'd0) begin
                            state_n = S_DONE_PULSE;
                        end else if (tick_1hz && (32'd1 >= time_limit_sec)) begin
                            // If the first tick arrives during init, complete immediately.
                            elapsed_seconds_n = 32'd1;
                            state_n           = S_DONE_PULSE;
                        end else begin
                            state_n = S_LAUNCH_CHECK;
                        end
                    end else if (mode == MODE_SINGLE) begin
                        // SINGLE mode always launches one checker operation.
                        state_n = S_LAUNCH_CHECK;
                    end else begin
                        // Reserved mode is treated as a no-op complete.
                        state_n = S_DONE_PULSE;
                    end
                end

                //------------------------------------------------------------------
                // LAUNCH_CHECK
                //
                // prime_check_core sees checker_start high in this state.
                //------------------------------------------------------------------
                S_LAUNCH_CHECK: begin
                    // If time expires on the launch boundary, abort before waiting.
                    if (time_limit_reached_this_tick) begin
                        state_n = S_TIME_ABORT_CHECK;
                    end else begin
                        state_n = S_WAIT_CHECK;
                    end
                end

                //------------------------------------------------------------------
                // WAIT_CHECK
                //
                // Wait for prime_check_core to finish the current candidate.
                //------------------------------------------------------------------
                S_WAIT_CHECK: begin
                    // TIME mode stops immediately when the requested limit is reached.
                    if ((mode_ff == MODE_TIME) && time_limit_reached_this_tick) begin
                        state_n = S_TIME_ABORT_CHECK;
                    end else if (checker_done) begin
                        // Latch the checker result before handling it next cycle.
                        checker_result_n = checker_is_prime;
                        state_n          = S_HANDLE_RESULT;
                    end else begin
                        state_n = S_WAIT_CHECK;
                    end
                end

                //------------------------------------------------------------------
                // HANDLE_RESULT
                //
                // Record prime results, update recent-prime history, and decide
                // whether to continue checking or complete the mode.
                //------------------------------------------------------------------
                S_HANDLE_RESULT: begin
                    // If the checker found a prime, update all prime result tracking.
                    if (checker_result_ff) begin
                        prime_count_n        = prime_count_ff + 32'd1;
                        largest_prime_n      = current_candidate_ff;
                        last_prime_found_n   = current_candidate_ff;
                        recent_primes_flat_n = {recent_primes_flat_ff[607:0], current_candidate_ff};

                        // Saturate the recent-valid count at 20 entries.
                        if (recent_valid_count_ff < 5'd20) begin
                            recent_valid_count_n = recent_valid_count_ff + 5'd1;
                        end else begin
                            recent_valid_count_n = recent_valid_count_ff;
                        end
                    end

                    // SINGLE mode completes after one candidate check.
                    if (mode_ff == MODE_SINGLE) begin
                        single_is_prime_n = checker_result_ff;
                        state_n           = S_DONE_PULSE;

                    end else if (mode_ff == MODE_RANGE) begin
                        // RANGE mode stops if the next candidate would exceed the limit.
                        if (next_candidate_value(current_candidate_ff) > range_limit_ff) begin
                            state_n = S_DONE_PULSE;
                        end else begin
                            current_candidate_n = next_candidate_value(current_candidate_ff);
                            state_n             = S_LAUNCH_CHECK;
                        end

                    end else if (mode_ff == MODE_TIME) begin
                        // TIME mode stops if the time limit is reached while handling the result.
                        if (time_limit_reached_this_tick) begin
                            state_n = S_DONE_PULSE;
                        end else begin
                            current_candidate_n = next_candidate_value(current_candidate_ff);
                            state_n             = S_LAUNCH_CHECK;
                        end

                    end else begin
                        // Reserved mode completes safely.
                        state_n = S_DONE_PULSE;
                    end
                end

                //------------------------------------------------------------------
                // TIME_ABORT_CHECK
                //
                // Generate checker_abort for one cycle, then complete TIME mode.
                //------------------------------------------------------------------
                S_TIME_ABORT_CHECK: begin
                    state_n = S_DONE_PULSE;
                end

                //------------------------------------------------------------------
                // DONE_PULSE
                //
                // One-cycle completion state used to assert done.
                //------------------------------------------------------------------
                S_DONE_PULSE: begin
                    state_n = S_HOLD_COMPLETE;
                end

                //------------------------------------------------------------------
                // HOLD_COMPLETE
                //
                // Hold mode_complete high until the next run starts.
                //------------------------------------------------------------------
                S_HOLD_COMPLETE: begin
                    // A new start pulse begins another run from the completed state.
                    if (start) begin
                        state_n = S_INIT;
                    end else begin
                        state_n = S_HOLD_COMPLETE;
                    end
                end

                //------------------------------------------------------------------
                // Unknown state recovery
                //------------------------------------------------------------------
                default: begin
                    state_n              = S_IDLE;
                    mode_n               = MODE_SINGLE;
                    single_value_n       = 32'd0;
                    range_limit_n        = 32'd0;
                    time_limit_sec_n     = 32'd0;
                    prime_count_n        = 32'd0;
                    largest_prime_n      = 32'd0;
                    current_candidate_n  = 32'd0;
                    last_prime_found_n   = 32'd0;
                    single_is_prime_n    = 1'b0;
                    elapsed_seconds_n    = 32'd0;
                    recent_primes_flat_n = 640'd0;
                    recent_valid_count_n = 5'd0;
                    checker_result_n     = 1'b0;
                end

            endcase
        end
    end

endmodule