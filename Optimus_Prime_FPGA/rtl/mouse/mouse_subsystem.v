`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// mouse_subsystem.v
//
// Purpose:
//   Hierarchical wrapper for the full PS/2 mouse path used by the project.
//
//   This module groups all mouse-related logic behind one clean interface so
//   top.v can remain wiring-oriented. It handles mouse initialization, packet
//   decoding, cursor movement, boundary clamping, and clock-domain crossing into
//   the VGA domain.
//
// Mouse data flow:
//   1) mouse_ps2_ctrl enables mouse streaming and receives raw PS/2 bytes.
//   2) mouse_packet_decoder groups those bytes into standard 3-byte mouse
//      packets.
//   3) mouse_cursor_ctrl converts packet deltas into cursor X/Y position and
//      button states.
//   4) mouse_cursor_cdc transfers the cursor and button state into clk_vga for
//      display overlay.
//
// Example:
//   A PS/2 packet with x_delta = +5 and y_delta = -3 moves the cursor right by
//   5 pixels and down by 3 pixels, unless that movement would pass the configured
//   screen bounds. If a boundary would be exceeded, the cursor clamps to the
//   nearest allowed coordinate.
//
// Clock domains:
//   - clk_sys:
//       PS/2 receive, packet decode, and cursor update.
//   - clk_vga:
//       Cursor/button state used by the VGA display pipeline.
//
// Notes:
//   - This wrapper contains no FSM directly; FSM behavior exists inside the
//     PS/2 controller and packet/cursor submodules.
//   - PS/2 inout ownership remains at top level. This module only exposes
//     drive-low controls and samples the raw PS/2 line states.
//   - Reset is synchronous within each clock domain.
//------------------------------------------------------------------------------

module mouse_subsystem #(
    parameter integer CLK_SYS_HZ     = 100_000_000, // System clock frequency
    parameter integer CLK_VGA_HZ     = 25_000_000,  // VGA clock frequency
    parameter integer SCREEN_W       = 640,         // Visible screen width in pixels
    parameter integer SCREEN_H       = 480,         // Visible screen height in pixels

    //--------------------------------------------------------------------------
    // Cursor movement bounds
    //
    // These values keep the cursor slightly inside the visible screen area so
    // the full cursor sprite remains usable at the borders.
    //--------------------------------------------------------------------------
    parameter integer CURSOR_X_MIN   = 16,          // Minimum allowed cursor X
    parameter integer CURSOR_X_MAX   = 623,         // Maximum allowed cursor X
    parameter integer CURSOR_Y_MIN   = 16,          // Minimum allowed cursor Y
    parameter integer CURSOR_Y_MAX   = 463          // Maximum allowed cursor Y
)(
    //--------------------------------------------------------------------------
    // System clock domain
    //--------------------------------------------------------------------------
    input  wire       clk_sys,             // System clock for mouse receive/control
    input  wire       resetn_sys,          // Active-low reset synchronized to clk_sys

    //--------------------------------------------------------------------------
    // VGA clock domain
    //--------------------------------------------------------------------------
    input  wire       clk_vga,             // VGA pixel/display clock
    input  wire       resetn_vga,          // Active-low reset synchronized to clk_vga

    //--------------------------------------------------------------------------
    // PS/2 physical line samples from top-level
    //--------------------------------------------------------------------------
    input  wire       ps2_clk_raw,         // Sampled PS/2 clock line
    input  wire       ps2_data_raw,        // Sampled PS/2 data line

    //--------------------------------------------------------------------------
    // PS/2 open-collector drive-low controls to top-level
    //--------------------------------------------------------------------------
    output wire       ps2_clk_drive_low,   // Pull PS/2 clock low when 1, release when 0
    output wire       ps2_data_drive_low,  // Pull PS/2 data low when 1, release when 0

    //--------------------------------------------------------------------------
    // Cursor/button state in VGA domain
    //--------------------------------------------------------------------------
    output wire [9:0] cursor_x_vga,        // Cursor X coordinate synchronized to clk_vga
    output wire [9:0] cursor_y_vga,        // Cursor Y coordinate synchronized to clk_vga
    output wire       left_btn_vga,        // Left mouse button state in clk_vga
    output wire       right_btn_vga,       // Right mouse button state in clk_vga

    //--------------------------------------------------------------------------
    // Mouse debug/status outputs
    //--------------------------------------------------------------------------
    output wire       mouse_init_done,     // High after the mouse is placed in stream mode
    output wire       mouse_rx_error_pulse,// One-clock pulse when a PS/2 receive error occurs
    output wire       mouse_tx_error_pulse // One-clock pulse when a PS/2 transmit error occurs
);

    //--------------------------------------------------------------------------
    // Internal byte stream from PS/2 controller
    //
    // mouse_ps2_ctrl converts serial PS/2 frames into clean 8-bit bytes.
    //--------------------------------------------------------------------------
    wire [7:0] mouse_byte_w;               // Received PS/2 data byte
    wire       mouse_byte_valid_pulse_w;   // One-clock pulse when mouse_byte_w is valid

    //--------------------------------------------------------------------------
    // Internal decoded mouse packet signals
    //
    // The packet decoder converts three PS/2 bytes into button states and signed
    // motion deltas.
    //--------------------------------------------------------------------------
    wire       packet_valid_pulse_w;       // One-clock pulse when a full packet is decoded
    wire       left_btn_w;                 // Left button state from decoded packet
    wire       right_btn_w;                // Right button state from decoded packet
    wire       middle_btn_w;               // Middle button state from decoded packet
    wire       x_overflow_w;               // X overflow flag from decoded packet
    wire       y_overflow_w;               // Y overflow flag from decoded packet
    wire signed [8:0] x_delta_w;           // Signed X movement delta
    wire signed [8:0] y_delta_w;           // Signed Y movement delta

    //--------------------------------------------------------------------------
    // Internal cursor/button state in system domain
    //
    // mouse_cursor_ctrl updates these values in clk_sys before they cross into
    // the VGA domain.
    //--------------------------------------------------------------------------
    wire [9:0] cursor_x_sys_w;             // Cursor X coordinate in clk_sys
    wire [9:0] cursor_y_sys_w;             // Cursor Y coordinate in clk_sys
    wire       left_btn_state_sys_w;       // Left button state in clk_sys
    wire       right_btn_state_sys_w;      // Right button state in clk_sys

    //--------------------------------------------------------------------------
    // PS/2 mouse controller
    //
    // Responsibilities:
    //   - Wait briefly after reset for the mouse interface to settle.
    //   - Send the PS/2 enable-streaming command, 8'hF4.
    //   - Receive serial PS/2 frames and output clean bytes.
    //   - Report receive/transmit errors for debugging.
    //
    // Example:
    //   After initialization, normal mouse motion causes the controller to emit
    //   a stream of bytes that the packet decoder groups into 3-byte packets.
    //--------------------------------------------------------------------------
    mouse_ps2_ctrl #(
        .CLK_HZ(100_000_000),
        .STARTUP_WAIT_MS(20)
    ) u_mouse_ps2_ctrl (
        .clk                   (clk_sys),
        .resetn                (resetn_sys),
        .ps2_clk_raw           (ps2_clk_raw),
        .ps2_data_raw          (ps2_data_raw),
        .ps2_clk_drive_low     (ps2_clk_drive_low),
        .ps2_data_drive_low    (ps2_data_drive_low),
        .init_done             (mouse_init_done),
        .mouse_byte            (mouse_byte_w),
        .mouse_byte_valid_pulse(mouse_byte_valid_pulse_w),
        .rx_error_pulse_dbg    (mouse_rx_error_pulse),
        .tx_error_pulse_dbg    (mouse_tx_error_pulse)
    );

    //--------------------------------------------------------------------------
    // Mouse packet decoder
    //
    // Responsibilities:
    //   - Collect standard 3-byte PS/2 mouse packets.
    //   - Check packet alignment using the required status byte bit.
    //   - Decode button states, overflow flags, and signed X/Y deltas.
    //
    // PS/2 packet format:
    //   Byte 0: button bits, sign bits, overflow bits, and fixed alignment bit
    //   Byte 1: X movement delta
    //   Byte 2: Y movement delta
    //--------------------------------------------------------------------------
    mouse_packet_decoder u_mouse_packet_decoder (
        .clk                   (clk_sys),
        .resetn                (resetn_sys),
        .mouse_byte            (mouse_byte_w),
        .mouse_byte_valid_pulse(mouse_byte_valid_pulse_w),
        .packet_valid_pulse    (packet_valid_pulse_w),
        .left_btn              (left_btn_w),
        .right_btn             (right_btn_w),
        .middle_btn            (middle_btn_w),
        .x_overflow            (x_overflow_w),
        .y_overflow            (y_overflow_w),
        .x_delta               (x_delta_w),
        .y_delta               (y_delta_w)
    );

    //--------------------------------------------------------------------------
    // Cursor position controller
    //
    // Responsibilities:
    //   - Initialize the cursor near the center of the screen.
    //   - Add decoded mouse movement deltas to the cursor position.
    //   - Clamp the cursor inside the configured boundaries.
    //   - Forward the current left/right button states.
    //
    // Movement note:
    //   PS/2 positive Y means upward motion, while VGA Y increases downward.
    //   The cursor controller handles that coordinate convention internally.
    //--------------------------------------------------------------------------
    mouse_cursor_ctrl #(
        .SCREEN_W     (SCREEN_W),
        .SCREEN_H     (SCREEN_H),
        .CURSOR_X_MIN (CURSOR_X_MIN),
        .CURSOR_X_MAX (CURSOR_X_MAX),
        .CURSOR_Y_MIN (CURSOR_Y_MIN),
        .CURSOR_Y_MAX (CURSOR_Y_MAX)
    ) u_mouse_cursor_ctrl (
        .clk               (clk_sys),
        .resetn            (resetn_sys),
        .packet_valid_pulse(packet_valid_pulse_w),
        .left_btn          (left_btn_w),
        .right_btn         (right_btn_w),
        .middle_btn        (middle_btn_w),
        .x_overflow        (x_overflow_w),
        .y_overflow        (y_overflow_w),
        .x_delta           (x_delta_w),
        .y_delta           (y_delta_w),
        .cursor_x          (cursor_x_sys_w),
        .cursor_y          (cursor_y_sys_w),
        .left_press_pulse  (),
        .right_press_pulse (),
        .left_btn_state    (left_btn_state_sys_w),
        .right_btn_state   (right_btn_state_sys_w)
    );

    //--------------------------------------------------------------------------
    // Cursor/button clock-domain crossing
    //
    // Responsibilities:
    //   - Transfer slow-changing cursor coordinates and button states from
    //     clk_sys into clk_vga.
    //   - Provide stable cursor values to the VGA cursor overlay path.
    //
    // The cursor changes only when decoded packets arrive, so a simple dedicated
    // CDC block is sufficient for this slow control-style data.
    //--------------------------------------------------------------------------
    mouse_cursor_cdc #(
        .CURSOR_X_INIT(320),
        .CURSOR_Y_INIT(240)
    ) u_mouse_cursor_cdc (
        .src_clk            (clk_sys),
        .src_resetn         (resetn_sys),
        .src_cursor_x       (cursor_x_sys_w),
        .src_cursor_y       (cursor_y_sys_w),
        .src_left_btn_state (left_btn_state_sys_w),
        .src_right_btn_state(right_btn_state_sys_w),
        .dst_clk            (clk_vga),
        .dst_resetn         (resetn_vga),
        .dst_cursor_x       (cursor_x_vga),
        .dst_cursor_y       (cursor_y_vga),
        .dst_left_btn_state (left_btn_vga),
        .dst_right_btn_state(right_btn_vga)
    );

endmodule