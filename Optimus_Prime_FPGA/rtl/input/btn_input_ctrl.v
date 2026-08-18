`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// btn_input_ctrl.v
//
// Purpose:
//   Front-end conditioning wrapper for the five onboard Nexys A7 pushbuttons.
//
//   Raw mechanical pushbuttons can bounce when pressed or released, so the rest
//   of the project should not use the raw button signals directly. This module
//   debounces each button and provides:
//     1) A stable debounced level while the button is held
//     2) A one-clock rising-edge pulse when a new press is accepted
//
// Buttons handled:
//   - BTNC: center button
//   - BTNU: up button
//   - BTND: down button
//   - BTNL: left button
//   - BTNR: right button
//
// Debounce algorithm:
//   A shared sample tick is generated every 5 ms. Each button is sampled only on
//   that tick. The debounce_1bit modules require four matching samples before
//   accepting a new stable value.
//
// Example:
//   If BTNC bounces high/low for a few milliseconds and then stays high, the
//   debouncer waits until four consecutive 5 ms samples agree. Then btnc_level
//   becomes 1 and btnc_rise pulses for one clk cycle.
//
// Timing:
//   - clk assumed to be 100 MHz
//   - sample tick = 500,000 cycles = 5 ms
//   - 4 stable samples required inside debounce_1bit
//   - effective debounce time is approximately 20 ms
//
// Notes:
//   - This module contains no application-specific UI behavior.
//   - All five buttons share the same sample_tick for consistent timing.
//   - No FSM is implemented directly in this wrapper; debounce sequencing is
//     handled inside debounce_1bit.
//------------------------------------------------------------------------------

module btn_input_ctrl (
    input  wire clk,        // Main system clock, expected 100 MHz
    input  wire rst_n,      // Synchronized active-low reset

    input  wire btnc_raw,   // Raw center pushbutton input
    input  wire btnu_raw,   // Raw up pushbutton input
    input  wire btnd_raw,   // Raw down pushbutton input
    input  wire btnl_raw,   // Raw left pushbutton input
    input  wire btnr_raw,   // Raw right pushbutton input

    output wire btnc_level, // Debounced stable level for center button
    output wire btnu_level, // Debounced stable level for up button
    output wire btnd_level, // Debounced stable level for down button
    output wire btnl_level, // Debounced stable level for left button
    output wire btnr_level, // Debounced stable level for right button

    output wire btnc_rise,  // One-clock pulse when center button press is accepted
    output wire btnu_rise,  // One-clock pulse when up button press is accepted
    output wire btnd_rise,  // One-clock pulse when down button press is accepted
    output wire btnl_rise,  // One-clock pulse when left button press is accepted
    output wire btnr_rise   // One-clock pulse when right button press is accepted
);

    //--------------------------------------------------------------------------
    // Shared debounce sample tick
    //
    // tick_gen creates a slow enable pulse used by all five button debouncers.
    // This avoids each button having its own independent counter and keeps all
    // button sampling aligned to the same 5 ms cadence.
    //--------------------------------------------------------------------------
    wire sample_tick;       // One-clock pulse every 5 ms at 100 MHz

    tick_gen #(
        .TICKS_PER_PULSE(500_000)   // 500,000 cycles / 100 MHz = 5 ms
    ) u_tick_gen (
        .clk   (clk),
        .rst_n (rst_n),
        .tick  (sample_tick)
    );

    //--------------------------------------------------------------------------
    // Center button debounce
    //
    // Converts raw BTNC input into a stable level and one-cycle press pulse.
    //--------------------------------------------------------------------------
    debounce_1bit u_btnc_db (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_tick(sample_tick),
        .sig_in_raw (btnc_raw),
        .sig_level  (btnc_level),
        .sig_rise   (btnc_rise),
        .sig_fall   ()
    );

    //--------------------------------------------------------------------------
    // Up button debounce
    //
    // Converts raw BTNU input into a stable level and one-cycle press pulse.
    //--------------------------------------------------------------------------
    debounce_1bit u_btnu_db (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_tick(sample_tick),
        .sig_in_raw (btnu_raw),
        .sig_level  (btnu_level),
        .sig_rise   (btnu_rise),
        .sig_fall   ()
    );

    //--------------------------------------------------------------------------
    // Down button debounce
    //
    // Converts raw BTND input into a stable level and one-cycle press pulse.
    //--------------------------------------------------------------------------
    debounce_1bit u_btnd_db (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_tick(sample_tick),
        .sig_in_raw (btnd_raw),
        .sig_level  (btnd_level),
        .sig_rise   (btnd_rise),
        .sig_fall   ()
    );

    //--------------------------------------------------------------------------
    // Left button debounce
    //
    // Converts raw BTNL input into a stable level and one-cycle press pulse.
    //--------------------------------------------------------------------------
    debounce_1bit u_btnl_db (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_tick(sample_tick),
        .sig_in_raw (btnl_raw),
        .sig_level  (btnl_level),
        .sig_rise   (btnl_rise),
        .sig_fall   ()
    );

    //--------------------------------------------------------------------------
    // Right button debounce
    //
    // Converts raw BTNR input into a stable level and one-cycle press pulse.
    //--------------------------------------------------------------------------
    debounce_1bit u_btnr_db (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_tick(sample_tick),
        .sig_in_raw (btnr_raw),
        .sig_level  (btnr_level),
        .sig_rise   (btnr_rise),
        .sig_fall   ()
    );

endmodule