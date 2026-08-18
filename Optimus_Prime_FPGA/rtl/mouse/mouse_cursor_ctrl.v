`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// mouse_cursor_ctrl.v
//
// Purpose:
//   Maintains the live mouse cursor position from decoded PS/2 mouse packets.
//
//   This module receives complete decoded mouse packets from
//   mouse_packet_decoder and updates the cursor position in the system clock
//   domain. It also tracks left/right button states and generates one-clock
//   press pulses on rising button edges.
//
// Cursor update algorithm:
//   1) Wait for packet_valid_pulse.
//   2) Update button state and detect new button presses.
//   3) Compute candidate cursor coordinates from the signed X/Y deltas.
//   4) Ignore movement on any axis whose overflow flag is set.
//   5) Clamp X and Y independently to the configured cursor bounds.
//
// Example:
//   If cursor_x = 320 and x_delta = +5, the X candidate becomes 325.
//   If 325 is inside the configured X limits, cursor_x updates to 325.
//   If the candidate were below CURSOR_X_MIN, cursor_x would clamp to
//   CURSOR_X_MIN instead.
//
// PS/2 coordinate note:
//   - X positive means move right.
//   - Y positive means move up.
//   - VGA screen coordinates increase downward.
//   - Therefore, the Y update uses:
//
//       cursor_y_next = cursor_y_current - y_delta
//
// Boundary behavior:
//   X and Y are clamped independently. This allows normal computer-like cursor
//   motion at screen edges. For example, if the cursor is clamped at the left
//   edge, vertical movement can still continue.
//
// Notes:
//   - Reset is synchronous.
//   - Overflow packets are ignored on the affected axis to prevent large jumps.
//   - This module is intended to run in the system / compute clock domain.
//------------------------------------------------------------------------------

module mouse_cursor_ctrl #(
    parameter integer SCREEN_W      = 640, // Visible screen width in pixels
    parameter integer SCREEN_H      = 480, // Visible screen height in pixels

    //--------------------------------------------------------------------------
    // Cursor movement bounds
    //
    // The cursor is a 16x16 sprite centered on (cursor_x, cursor_y). These bounds
    // allow the reported cursor position to travel near the screen edges while
    // keeping the visual cursor usable and aligned with button hit-test regions.
    //--------------------------------------------------------------------------
    parameter integer CURSOR_X_MIN  = 8,   // Minimum allowed cursor center X
    parameter integer CURSOR_X_MAX  = 631, // Maximum allowed cursor center X
    parameter integer CURSOR_Y_MIN  = 8,   // Minimum allowed cursor center Y
    parameter integer CURSOR_Y_MAX  = 471  // Maximum allowed cursor center Y
)(
    input  wire              clk,                  // System clock
    input  wire              resetn,               // Synchronized active-low reset

    input  wire              packet_valid_pulse,   // One-clock pulse for a complete decoded packet
    input  wire              left_btn,             // Left button state from current packet
    input  wire              right_btn,            // Right button state from current packet
    input  wire              middle_btn,           // Middle button state, unused but kept for completeness
    input  wire              x_overflow,           // X overflow flag from current packet
    input  wire              y_overflow,           // Y overflow flag from current packet
    input  wire signed [8:0] x_delta,              // Signed X movement delta from current packet
    input  wire signed [8:0] y_delta,              // Signed Y movement delta from current packet

    output reg  [9:0]        cursor_x,             // Current cursor X position
    output reg  [9:0]        cursor_y,             // Current cursor Y position

    output reg               left_press_pulse,     // One-clock pulse on left-button rising edge
    output reg               right_press_pulse,    // One-clock pulse on right-button rising edge

    output reg               left_btn_state,       // Registered left-button state from packet stream
    output reg               right_btn_state       // Registered right-button state from packet stream
);

    //--------------------------------------------------------------------------
    // Previous button-state registers
    //
    // These store the previous packet's button states so rising edges can be
    // detected when a new packet arrives.
    //--------------------------------------------------------------------------
    reg left_btn_prev_ff;              // Previous left-button state
    reg right_btn_prev_ff;             // Previous right-button state

    //--------------------------------------------------------------------------
    // Candidate next-position wires
    //
    // These signed values calculate the unclamped next cursor position before
    // boundary checks are applied.
    //--------------------------------------------------------------------------
    wire signed [10:0] x_candidate_w;  // Proposed X position before clamping
    wire signed [10:0] y_candidate_w;  // Proposed Y position before clamping

    assign x_candidate_w = $signed({1'b0, cursor_x}) + x_delta;
    assign y_candidate_w = $signed({1'b0, cursor_y}) - y_delta;

    //--------------------------------------------------------------------------
    // Initial cursor position
    //
    // The cursor starts at the visual center of the screen after reset.
    //--------------------------------------------------------------------------
    localparam integer CURSOR_X_INIT = SCREEN_W / 2;
    localparam integer CURSOR_Y_INIT = SCREEN_H / 2;

    //--------------------------------------------------------------------------
    // Cursor update and button-edge logic
    //
    // This sequential block updates only when a complete decoded packet arrives.
    // Button press pulses are one-clock outputs, while cursor_x/cursor_y and
    // button states remain registered until the next packet.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Default one-clock press pulses low unless a new rising edge is detected.
        left_press_pulse  <= 1'b0;
        right_press_pulse <= 1'b0;

        // Reset cursor to center and clear button state.
        if (!resetn) begin
            cursor_x          <= CURSOR_X_INIT[9:0];
            cursor_y          <= CURSOR_Y_INIT[9:0];

            left_press_pulse  <= 1'b0;
            right_press_pulse <= 1'b0;

            left_btn_state    <= 1'b0;
            right_btn_state   <= 1'b0;

            left_btn_prev_ff  <= 1'b0;
            right_btn_prev_ff <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Process only complete decoded packets.
            //------------------------------------------------------------------
            if (packet_valid_pulse) begin
                //--------------------------------------------------------------
                // Button state update and rising-edge detection.
                //--------------------------------------------------------------
                left_btn_state  <= left_btn;
                right_btn_state <= right_btn;

                // Generate one pulse when left button changes from released to pressed.
                if (left_btn && !left_btn_prev_ff) begin
                    left_press_pulse <= 1'b1;
                end

                // Generate one pulse when right button changes from released to pressed.
                if (right_btn && !right_btn_prev_ff) begin
                    right_press_pulse <= 1'b1;
                end

                left_btn_prev_ff  <= left_btn;
                right_btn_prev_ff <= right_btn;

                //--------------------------------------------------------------
                // X-axis movement with overflow rejection and boundary clamp.
                //--------------------------------------------------------------
                if (!x_overflow) begin
                    // Clamp to the minimum X boundary if the candidate is too far left.
                    if (x_candidate_w < CURSOR_X_MIN) begin
                        cursor_x <= CURSOR_X_MIN[9:0];
                    end
                    // Clamp to the maximum X boundary if the candidate is too far right.
                    else if (x_candidate_w > CURSOR_X_MAX) begin
                        cursor_x <= CURSOR_X_MAX[9:0];
                    end
                    // Candidate is in range, so accept the new X position.
                    else begin
                        cursor_x <= x_candidate_w[9:0];
                    end
                end

                //--------------------------------------------------------------
                // Y-axis movement with overflow rejection and boundary clamp.
                //
                // PS/2 positive Y means upward motion, but VGA Y increases
                // downward, so y_candidate_w was computed using subtraction.
                //--------------------------------------------------------------
                if (!y_overflow) begin
                    // Clamp to the minimum Y boundary if the candidate is too high.
                    if (y_candidate_w < CURSOR_Y_MIN) begin
                        cursor_y <= CURSOR_Y_MIN[9:0];
                    end
                    // Clamp to the maximum Y boundary if the candidate is too low.
                    else if (y_candidate_w > CURSOR_Y_MAX) begin
                        cursor_y <= CURSOR_Y_MAX[9:0];
                    end
                    // Candidate is in range, so accept the new Y position.
                    else begin
                        cursor_y <= y_candidate_w[9:0];
                    end
                end
            end
        end
    end

endmodule