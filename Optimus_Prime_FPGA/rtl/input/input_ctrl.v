`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// input_ctrl.v
//
// Purpose:
//   Top-level reusable input-conditioning wrapper for the project.
//
//   This module groups the two physical input paths used by the system:
//     1) Onboard pushbuttons
//     2) Digilent Pmod KYPD keypad
//
//   The raw mechanical inputs are not used directly by the UI. Instead, this
//   wrapper outputs debounced stable levels and clean one-clock press pulses.
//   This keeps the rest of the project independent from button bounce, keypad
//   scan timing, and raw electrical input behavior.
//
// Interface summary:
//   - clk / rst_n:
//       Main system clock and synchronized active-low reset.
//   - btn*_raw:
//       Raw onboard pushbutton inputs from the FPGA board.
//   - kp_row / kp_col:
//       Matrix keypad row inputs and column drive outputs.
//   - btn*_level:
//       Debounced stable button levels.
//   - btn*_press:
//       One-clock button press pulses.
//   - key_valid / key_code / key_press:
//       Debounced keypad state, decoded hex value, and one-clock key press.
//
// Notes:
//   - This module contains no project-specific UI decisions.
//   - It only performs input cleanup and event generation.
//   - rst_n must already be synchronized to clk before entering this module.
//   - No FSM is implemented directly in this wrapper; FSM/scan behavior is
//     contained inside btn_input_ctrl and keypad_input_ctrl.
//------------------------------------------------------------------------------

module input_ctrl (
    input  wire       clk,        // Main system clock for input conditioning
    input  wire       rst_n,      // Synchronized active-low reset

    //--------------------------------------------------------------------------
    // Raw onboard pushbutton inputs
    //--------------------------------------------------------------------------
    input  wire       btnc_raw,   // Raw center pushbutton input
    input  wire       btnu_raw,   // Raw up pushbutton input
    input  wire       btnd_raw,   // Raw down pushbutton input
    input  wire       btnl_raw,   // Raw left pushbutton input
    input  wire       btnr_raw,   // Raw right pushbutton input

    //--------------------------------------------------------------------------
    // Raw keypad matrix interface
    //--------------------------------------------------------------------------
    input  wire [3:0] kp_row,     // Keypad row inputs sampled by keypad scanner
    output wire [3:0] kp_col,     // Keypad column drive outputs from scanner

    //--------------------------------------------------------------------------
    // Debounced pushbutton stable levels
    //
    // These outputs stay high while the corresponding button is held after
    // debounce filtering accepts the press.
    //--------------------------------------------------------------------------
    output wire       btnc_level, // Debounced stable level for BTNC
    output wire       btnu_level, // Debounced stable level for BTNU
    output wire       btnd_level, // Debounced stable level for BTND
    output wire       btnl_level, // Debounced stable level for BTNL
    output wire       btnr_level, // Debounced stable level for BTNR

    //--------------------------------------------------------------------------
    // Debounced pushbutton press pulses
    //
    // These outputs pulse for one clk cycle when the corresponding debounced
    // button level rises from 0 to 1.
    //--------------------------------------------------------------------------
    output wire       btnc_press, // One-clock press pulse for BTNC
    output wire       btnu_press, // One-clock press pulse for BTNU
    output wire       btnd_press, // One-clock press pulse for BTND
    output wire       btnl_press, // One-clock press pulse for BTNL
    output wire       btnr_press, // One-clock press pulse for BTNR

    //--------------------------------------------------------------------------
    // Debounced keypad outputs
    //
    // key_valid stays high while a decoded key is held stable.
    // key_code contains the decoded hexadecimal key value.
    // key_press pulses once when a new stable key press is accepted.
    //--------------------------------------------------------------------------
    output wire       key_valid,  // Debounced keypad key is currently valid
    output wire [3:0] key_code,   // Decoded keypad value, 0 through F
    output wire       key_press   // One-clock pulse for a new keypad press
);

    //--------------------------------------------------------------------------
    // Onboard pushbutton conditioning
    //
    // btn_input_ctrl handles synchronization/debounce behavior for each raw
    // mechanical pushbutton and converts each accepted press into:
    //   - a stable level output
    //   - a one-cycle rising-edge pulse
    //
    // Example:
    //   If BTNC bounces for several cycles and then remains high, btnc_level
    //   eventually becomes 1 and btnc_press pulses for exactly one clk cycle.
    //--------------------------------------------------------------------------
    btn_input_ctrl u_btn_input_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),

        .btnc_raw  (btnc_raw),
        .btnu_raw  (btnu_raw),
        .btnd_raw  (btnd_raw),
        .btnl_raw  (btnl_raw),
        .btnr_raw  (btnr_raw),

        .btnc_level(btnc_level),
        .btnu_level(btnu_level),
        .btnd_level(btnd_level),
        .btnl_level(btnl_level),
        .btnr_level(btnr_level),

        .btnc_rise (btnc_press),
        .btnu_rise (btnu_press),
        .btnd_rise (btnd_press),
        .btnl_rise (btnl_press),
        .btnr_rise (btnr_press)
    );

    //--------------------------------------------------------------------------
    // Keypad conditioning
    //
    // keypad_input_ctrl scans the 4x4 matrix keypad by driving one column at a
    // time and reading the row inputs. Once a key remains stable long enough, it
    // produces the decoded hex value and a one-cycle key_press pulse.
    //
    // Example:
    //   When the user presses key '5', the scanner eventually detects the row
    //   and column intersection for that key, sets key_code = 4'h5, asserts
    //   key_valid while held, and pulses key_press once.
    //--------------------------------------------------------------------------
    keypad_input_ctrl u_keypad_input_ctrl (
        .clk      (clk),
        .rst_n    (rst_n),
        .kp_row   (kp_row),
        .kp_col   (kp_col),
        .key_valid(key_valid),
        .key_code (key_code),
        .key_press(key_press)
    );

endmodule