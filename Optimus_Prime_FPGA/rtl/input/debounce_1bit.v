`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// debounce_1bit.v
//
// Purpose:
//   Debounces one raw single-bit input and converts it into a clean stable level
//   plus one-clock edge pulses.
//
//   This module is intended for mechanical inputs such as pushbuttons, where the
//   raw signal may rapidly toggle for a short time during press or release.
//
// Debounce algorithm:
//   1) Synchronize the raw input into clk using two flip-flops.
//   2) On each sample_tick, shift the synchronized input into a 4-bit history.
//   3) If the history becomes 4'b1111, accept the input as stably high.
//   4) If the history becomes 4'b0000, accept the input as stably low.
//   5) Generate a one-clock rise or fall pulse only when the debounced level
//      actually changes.
//
// Example:
//   If the synchronized input samples as:
//
//       0, 1, 0, 1, 1, 1, 1
//
//   the output does not go high during the early bouncing samples. It only goes
//   high once the sampled history becomes 1111. At that moment sig_level becomes
//   1 and sig_rise pulses for one clk cycle.
//
// Interface summary:
//   - clk:
//       Clock for all debounce logic.
//   - rst_n:
//       Synchronized active-low reset.
//   - sample_tick:
//       Slow one-clock enable pulse controlling when the input is sampled.
//   - sig_in_raw:
//       Raw asynchronous/mechanical input.
//   - sig_level:
//       Debounced stable output level.
//   - sig_rise:
//       One-clock pulse when sig_level changes from 0 to 1.
//   - sig_fall:
//       One-clock pulse when sig_level changes from 1 to 0.
//
// Notes:
//   - This module uses separate combinational next-state and sequential
//     flip-flop blocks.
//   - There is no multi-state FSM here; the debounce "state" is held by the
//     history register and the debounced level register.
//------------------------------------------------------------------------------

module debounce_1bit (
    input  wire clk,         // Clock for synchronizer and debounce registers
    input  wire rst_n,       // Synchronized active-low reset
    input  wire sample_tick, // One-clock pulse enabling a new debounce sample
    input  wire sig_in_raw,  // Raw asynchronous/mechanical input signal
    output wire sig_level,   // Debounced stable signal level
    output wire sig_rise,    // One-clock pulse on accepted rising transition
    output wire sig_fall     // One-clock pulse on accepted falling transition
);

    //--------------------------------------------------------------------------
    // Input synchronizer registers
    //
    // The raw input may not be aligned to clk, so it first passes through a
    // two-flop synchronizer before entering the debounce history.
    //--------------------------------------------------------------------------
    reg sync1_ff;            // First synchronizer stage
    reg sync2_ff;            // Second synchronizer stage used by debounce logic

    reg sync1_n;             // Next value for first synchronizer stage
    reg sync2_n;             // Next value for second synchronizer stage

    //--------------------------------------------------------------------------
    // Debounce state registers
    //
    // hist_ff stores the most recent four sampled input values. level_ff stores
    // the accepted debounced output level. rise_ff and fall_ff are registered
    // one-clock edge pulses.
    //--------------------------------------------------------------------------
    reg [3:0] hist_ff;       // Four-sample debounce history
    reg [3:0] hist_n;        // Next debounce history

    reg level_ff;            // Debounced stable level register
    reg level_n;             // Next debounced stable level

    reg rise_ff;             // Registered rising-edge pulse
    reg rise_n;              // Next rising-edge pulse

    reg fall_ff;             // Registered falling-edge pulse
    reg fall_n;              // Next falling-edge pulse

    //--------------------------------------------------------------------------
    // Synchronizer next-state logic
    //
    // This block computes the next values for the two synchronizer stages.
    //--------------------------------------------------------------------------
    always @(*) begin
        sync1_n = sync1_ff;
        sync2_n = sync2_ff;

        // Clear synchronizer stages during reset.
        if (!rst_n) begin
            sync1_n = 1'b0;
            sync2_n = 1'b0;
        end
        // Shift the raw input through the two-flop synchronizer.
        else begin
            sync1_n = sig_in_raw;
            sync2_n = sync1_ff;
        end
    end

    //--------------------------------------------------------------------------
    // Debounce next-state logic
    //
    // This block implements the four-sample debounce algorithm. Edge pulses
    // default low every cycle and are asserted only when a new stable level is
    // accepted.
    //--------------------------------------------------------------------------
    always @(*) begin
        hist_n  = hist_ff;
        level_n = level_ff;
        rise_n  = 1'b0;
        fall_n  = 1'b0;

        // Reset all debounce state and clear both edge pulses.
        if (!rst_n) begin
            hist_n  = 4'b0000;
            level_n = 1'b0;
            rise_n  = 1'b0;
            fall_n  = 1'b0;
        end
        else begin
            // Only update the debounce history on the slower sample tick.
            if (sample_tick) begin
                hist_n = {hist_ff[2:0], sync2_ff};

                // Four high samples in a row means the input is stably pressed.
                if ({hist_ff[2:0], sync2_ff} == 4'b1111) begin
                    // Accept a new rising transition only if the level was low.
                    if (!level_ff) begin
                        level_n = 1'b1;
                        rise_n  = 1'b1;
                    end
                    // If the level was already high, keep it high with no pulse.
                    else begin
                        level_n = level_ff;
                        rise_n  = 1'b0;
                    end
                end
                // Four low samples in a row means the input is stably released.
                else if ({hist_ff[2:0], sync2_ff} == 4'b0000) begin
                    // Accept a new falling transition only if the level was high.
                    if (level_ff) begin
                        level_n = 1'b0;
                        fall_n  = 1'b1;
                    end
                    // If the level was already low, keep it low with no pulse.
                    else begin
                        level_n = level_ff;
                        fall_n  = 1'b0;
                    end
                end
                // Mixed history means the input is still bouncing or changing.
                else begin
                    level_n = level_ff;
                    rise_n  = 1'b0;
                    fall_n  = 1'b0;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // All synchronizer and debounce state registers update together on clk.
    // Reset behavior is already encoded in the next-state logic above.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        sync1_ff <= sync1_n;
        sync2_ff <= sync2_n;

        hist_ff  <= hist_n;
        level_ff <= level_n;
        rise_ff  <= rise_n;
        fall_ff  <= fall_n;
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // Outputs are driven from registered values so downstream modules receive
    // clean synchronous levels and pulses.
    //--------------------------------------------------------------------------
    assign sig_level = level_ff;
    assign sig_rise  = rise_ff;
    assign sig_fall  = fall_ff;

endmodule