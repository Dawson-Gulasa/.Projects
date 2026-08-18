`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// keypad_debounce.v
//
// Purpose:
//   Debounces a decoded keypad candidate at the scan-frame level.
//
//   A matrix keypad is scanned one column at a time, so a key should not be
//   accepted from a single instant of row/column data. Instead, this module
//   observes the decoded key across complete scan frames and only accepts it
//   after the same observation repeats for FRAMES_REQUIRED frames.
//
// Debounce algorithm:
//   1) During a scan frame, capture any decoded key candidate seen from the
//      key_decoder.
//   2) At frame_tick, compare the current frame's observation against the
//      previously sampled frame observation.
//   3) If the observations match, increment the match counter.
//   4) Once enough matching frames have been seen, update the stable key output.
//   5) key_press pulses for one clk cycle only when a new stable key is accepted.
//
// Example:
//   With FRAMES_REQUIRED = 4, if key "5" is observed for four complete scan
//   frames in a row, key_valid becomes 1, key_code becomes 4'h5, and key_press
//   pulses once. If the key bounces or changes before four matching frames, the
//   counter restarts with the new observation.
//
// Interface summary:
//   - clk / rst_n:
//       Main keypad clock and synchronized active-low reset.
//   - frame_tick:
//       One-cycle pulse from col_scanner marking the end of a full scan frame.
//   - candidate_valid / candidate_code:
//       Raw decoded key observation from key_decoder.
//   - key_valid / key_code:
//       Stable debounced keypad output.
//   - key_press:
//       One-cycle pulse when a new stable key press is accepted.
//
// Notes:
//   - This module assumes one key at a time for project bring-up.
//   - There is no explicit encoded FSM. The debounce state is represented by
//     frame observation registers, the sampled observation, and match_count.
//------------------------------------------------------------------------------

module keypad_debounce #(
    parameter integer FRAMES_REQUIRED = 4  // Matching scan frames required before accepting a key
)(
    input  wire       clk,             // Main clock for keypad debounce logic
    input  wire       rst_n,           // Synchronized active-low reset
    input  wire       frame_tick,      // Pulse marking the end of one full keypad scan frame
    input  wire       candidate_valid, // Raw decoded candidate valid from key_decoder
    input  wire [3:0] candidate_code,  // Raw decoded hexadecimal candidate code
    output wire       key_valid,       // High while a debounced key is held
    output wire [3:0] key_code,        // Debounced hexadecimal key code
    output wire       key_press        // One-clock pulse when a new stable key is accepted
);

    //--------------------------------------------------------------------------
    // Per-frame observation registers
    //
    // These registers collect what was seen during the current scan frame. If a
    // candidate appears at any point before frame_tick, it is remembered until
    // the frame is evaluated.
    //--------------------------------------------------------------------------
    reg       frame_found_ff;          // Current frame saw at least one key candidate
    reg       frame_found_n;           // Next current-frame found flag

    reg [3:0] frame_code_ff;           // Candidate code captured during current frame
    reg [3:0] frame_code_n;            // Next captured current-frame candidate code

    //--------------------------------------------------------------------------
    // Debounce tracking registers
    //
    // sample_valid_ff/sample_code_ff store the previous frame observation being
    // compared against. match_count_ff counts how many consecutive scan frames
    // have matched that observation.
    //--------------------------------------------------------------------------
    reg       sample_valid_ff;         // Previous sampled frame had a valid key
    reg       sample_valid_n;          // Next sampled-frame valid flag

    reg [3:0] sample_code_ff;          // Previous sampled frame key code
    reg [3:0] sample_code_n;           // Next sampled-frame key code

    reg [2:0] match_count_ff;          // Number of consecutive matching frames
    reg [2:0] match_count_n;           // Next matching-frame count

    //--------------------------------------------------------------------------
    // Stable output registers
    //
    // These registers are the debounced outputs consumed by the rest of the
    // project. key_press_ff is intentionally a one-cycle pulse.
    //--------------------------------------------------------------------------
    reg       key_valid_ff;            // Registered stable key-valid output
    reg       key_valid_n;             // Next stable key-valid output

    reg [3:0] key_code_ff;             // Registered stable key code
    reg [3:0] key_code_n;              // Next stable key code

    reg       key_press_ff;            // Registered one-cycle key-press pulse
    reg       key_press_n;             // Next key-press pulse

    //--------------------------------------------------------------------------
    // Current frame observation used for this combinational evaluation
    //
    // obs_valid_c/obs_code_c represent the best observation for the current scan
    // frame after including the current candidate_valid/candidate_code inputs.
    //--------------------------------------------------------------------------
    reg       obs_valid_c;             // Combined current-frame valid observation
    reg [3:0] obs_code_c;              // Combined current-frame code observation

    //--------------------------------------------------------------------------
    // Keypad debounce next-state logic
    //
    // This block captures raw candidates during a scan frame and evaluates the
    // complete frame only when frame_tick arrives. The stable output changes
    // only after enough matching frames have been observed.
    //--------------------------------------------------------------------------
    always @(*) begin
        frame_found_n  = frame_found_ff;
        frame_code_n   = frame_code_ff;

        sample_valid_n = sample_valid_ff;
        sample_code_n  = sample_code_ff;
        match_count_n  = match_count_ff;

        key_valid_n    = key_valid_ff;
        key_code_n     = key_code_ff;
        key_press_n    = 1'b0;

        obs_valid_c    = frame_found_ff;
        obs_code_c     = frame_code_ff;

        // Capture any key candidate seen during the current scan frame.
        if (candidate_valid) begin
            obs_valid_c   = 1'b1;
            obs_code_c    = candidate_code;
            frame_found_n = 1'b1;
            frame_code_n  = candidate_code;
        end

        // Reset all observation, debounce, and output state.
        if (!rst_n) begin
            frame_found_n  = 1'b0;
            frame_code_n   = 4'h0;
            sample_valid_n = 1'b0;
            sample_code_n  = 4'h0;
            match_count_n  = 3'd0;
            key_valid_n    = 1'b0;
            key_code_n     = 4'h0;
            key_press_n    = 1'b0;
        end
        else begin
            // Only make debounce decisions at the end of a full scan frame.
            if (frame_tick) begin
                // Current frame matches the previous sampled observation.
                if ((obs_valid_c == sample_valid_ff) &&
                    ((obs_valid_c == 1'b0) || (obs_code_c == sample_code_ff))) begin

                    // Increase the consecutive-match count until it saturates.
                    if (match_count_ff < FRAMES_REQUIRED[2:0]) begin
                        match_count_n = match_count_ff + 3'd1;
                    end
                    // Hold the count once the required frame count is reached.
                    else begin
                        match_count_n = match_count_ff;
                    end

                    // Accept the observation when the required frame threshold is met.
                    if (match_count_ff == (FRAMES_REQUIRED - 1)) begin
                        // A stable key is present, so update the debounced key output.
                        if (obs_valid_c) begin
                            key_valid_n = 1'b1;
                            key_code_n  = obs_code_c;

                            // Pulse only for a newly accepted key or a changed key.
                            if ((!key_valid_ff) || (key_code_ff != obs_code_c)) begin
                                key_press_n = 1'b1;
                            end
                        end
                        // A stable no-key observation means the key has been released.
                        else begin
                            key_valid_n = 1'b0;
                        end
                    end
                end
                // New observation differs from the previous frame sample, so restart.
                else begin
                    sample_valid_n = obs_valid_c;
                    sample_code_n  = obs_code_c;
                    match_count_n  = 3'd1;
                end

                // Clear the per-frame capture registers for the next scan frame.
                frame_found_n = 1'b0;
                frame_code_n  = 4'h0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // All frame observation, debounce tracking, and stable output registers
    // update together on the rising edge of clk.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        frame_found_ff  <= frame_found_n;
        frame_code_ff   <= frame_code_n;

        sample_valid_ff <= sample_valid_n;
        sample_code_ff  <= sample_code_n;
        match_count_ff  <= match_count_n;

        key_valid_ff    <= key_valid_n;
        key_code_ff     <= key_code_n;
        key_press_ff    <= key_press_n;
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // Outputs are registered so downstream UI and parameter-entry logic receive
    // clean synchronous keypad events.
    //--------------------------------------------------------------------------
    assign key_valid = key_valid_ff;
    assign key_code  = key_code_ff;
    assign key_press = key_press_ff;

endmodule