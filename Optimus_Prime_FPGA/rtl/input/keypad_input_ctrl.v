`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// keypad_input_ctrl.v
//
// Purpose:
//   Front-end hierarchical controller for the Digilent Pmod KYPD keypad.
//
//   This module connects the three keypad-conditioning stages used by the
//   project:
//     1) col_scanner:
//          Drives one active-low keypad column at a time.
//     2) key_decoder:
//          Converts the active column and row input pattern into a candidate
//          hexadecimal key value.
//     3) keypad_debounce:
//          Accepts a key only after it is observed consistently across multiple
//          complete scan frames.
//
// Keypad scan algorithm:
//   The keypad is a 4x4 matrix. The FPGA drives one column low at a time and
//   reads the four row inputs. If a key is pressed, the active column and the
//   pulled-low row identify the key.
//
// Example:
//   If the scanner drives COL2 active and ROW3 reads active, key_decoder maps
//   that row/column intersection to the corresponding hex key. The debouncer
//   then waits for the same key to appear across multiple scan frames before
//   asserting key_valid and pulsing key_press.
//
// Bus ordering used in this project:
//   kp_col[3] = COL4
//   kp_col[2] = COL3
//   kp_col[1] = COL2
//   kp_col[0] = COL1
//
//   kp_row[3] = ROW4
//   kp_row[2] = ROW3
//   kp_row[1] = ROW2
//   kp_row[0] = ROW1
//
// Output behavior:
//   - key_valid stays high while a debounced key is held.
//   - key_code contains the decoded hexadecimal value.
//   - key_press pulses once when a new stable key is accepted.
//
// Notes:
//   - This module is a wrapper and does not contain an FSM directly.
//   - The scan sequencing is implemented inside col_scanner.
//   - The debounce acceptance logic is implemented inside keypad_debounce.
//   - No project-specific UI behavior is implemented here.
//------------------------------------------------------------------------------

module keypad_input_ctrl (
    input  wire       clk,        // Main system clock for keypad logic
    input  wire       rst_n,      // Synchronized active-low reset
    input  wire [3:0] kp_row,     // Raw keypad row inputs from Pmod KYPD
    output wire [3:0] kp_col,     // Active-low keypad column drive outputs
    output wire       key_valid,  // High while a debounced key is being held
    output wire [3:0] key_code,   // Debounced hexadecimal key value, 0 through F
    output wire       key_press   // One-clock pulse when a new key is accepted
);

    //--------------------------------------------------------------------------
    // Internal scan and decode signals
    //
    // col_idx and kp_col come from the scanner. The decoder uses col_idx and
    // kp_row to produce a raw candidate key. The debouncer then filters that
    // candidate at the scan-frame level.
    //--------------------------------------------------------------------------
    wire [1:0] col_idx;           // Current column index being scanned
    wire       frame_tick;        // One-clock pulse after a full keypad scan frame
    wire       candidate_valid;   // Raw decoded key candidate is valid
    wire [3:0] candidate_code;    // Raw decoded hexadecimal key candidate

    //--------------------------------------------------------------------------
    // Column scanner
    //
    // Drives the keypad columns one at a time using active-low patterns. A full
    // scan frame is complete once all four columns have been visited.
    //
    // Timing:
    //   TICKS_PER_DWELL = 100,000 at 100 MHz gives 1 ms per column.
    //   Therefore, one complete 4-column scan frame takes about 4 ms.
    //--------------------------------------------------------------------------
    col_scanner #(
        .TICKS_PER_DWELL(100_000)   // 1 ms dwell per column at 100 MHz
    ) u_col_scanner (
        .clk       (clk),
        .rst_n     (rst_n),
        .kp_col    (kp_col),
        .col_idx   (col_idx),
        .frame_tick(frame_tick)
    );

    //--------------------------------------------------------------------------
    // Key decoder
    //
    // Converts the currently selected column and row input pattern into a raw
    // key candidate. This stage does not debounce; it only identifies which key
    // appears to be pressed during the current column scan.
    //--------------------------------------------------------------------------
    key_decoder u_key_decoder (
        .col_idx        (col_idx),
        .kp_row         (kp_row),
        .candidate_valid(candidate_valid),
        .candidate_code (candidate_code)
    );

    //--------------------------------------------------------------------------
    // Keypad debouncer
    //
    // Accepts a decoded key only after the same candidate appears consistently
    // across multiple complete scan frames. This prevents bounce or scan
    // transients from creating false key presses.
    //
    // Example:
    //   With FRAMES_REQUIRED = 4, a key must appear stable for four complete
    //   scan frames before key_valid is asserted and key_press pulses.
    //--------------------------------------------------------------------------
    keypad_debounce #(
        .FRAMES_REQUIRED(4)
    ) u_keypad_debounce (
        .clk           (clk),
        .rst_n         (rst_n),
        .frame_tick    (frame_tick),
        .candidate_valid(candidate_valid),
        .candidate_code(candidate_code),
        .key_valid     (key_valid),
        .key_code      (key_code),
        .key_press     (key_press)
    );

endmodule