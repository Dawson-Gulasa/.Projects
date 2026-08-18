`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// mouse_cursor_cdc.v
//
// Purpose:
//   Safely transfers mouse cursor position and mouse button state from the
//   system/mouse clock domain into the VGA/render clock domain.
//
// Why this module is needed:
//   The mouse decoder and cursor controller run in src_clk, while the VGA cursor
//   overlay uses dst_clk. Directly connecting multi-bit cursor values across
//   clock domains can produce invalid mixed values. This module avoids that by
//   using a toggle-based request/acknowledge handshake.
//
// CDC algorithm:
//   1) Source domain watches for cursor/button changes.
//   2) When no previous transfer is pending, the source captures a stable
//      snapshot into holding registers.
//   3) The source toggles req_toggle_ff to request a transfer.
//   4) Destination domain synchronizes the request toggle.
//   5) Destination captures the stable held snapshot and toggles ack_toggle_ff.
//   6) Source domain synchronizes the acknowledge toggle and may launch the next
//      update.
//
// Example:
//   If the source cursor changes from (320,240) to (325,240), the source stores
//   (325,240) in the hold registers and toggles the request. The VGA domain then
//   captures that entire stable snapshot together, preventing a mixed coordinate
//   such as X from the new update and Y from the old update.
//
// Notes:
//   - Reset is synchronous in each clock domain.
//   - This is intended for slow control/state updates, not high-throughput data.
//   - If source values change while a transfer is pending, the next transfer will
//     send the most recent value after the acknowledge returns.
//------------------------------------------------------------------------------

module mouse_cursor_cdc #(
    parameter integer CURSOR_X_INIT = 320, // Initial cursor X after reset
    parameter integer CURSOR_Y_INIT = 240  // Initial cursor Y after reset
)(
    //--------------------------------------------------------------------------
    // Source domain: system / mouse update clock
    //--------------------------------------------------------------------------
    input  wire       src_clk,             // Source clock for mouse cursor logic
    input  wire       src_resetn,          // Active-low reset synchronized to src_clk

    input  wire [9:0] src_cursor_x,        // Cursor X from mouse_cursor_ctrl
    input  wire [9:0] src_cursor_y,        // Cursor Y from mouse_cursor_ctrl
    input  wire       src_left_btn_state,  // Left button state in source domain
    input  wire       src_right_btn_state, // Right button state in source domain

    //--------------------------------------------------------------------------
    // Destination domain: VGA / render clock
    //--------------------------------------------------------------------------
    input  wire       dst_clk,             // Destination clock for VGA/render logic
    input  wire       dst_resetn,          // Active-low reset synchronized to dst_clk

    output reg  [9:0] dst_cursor_x,        // Cursor X synchronized to destination domain
    output reg  [9:0] dst_cursor_y,        // Cursor Y synchronized to destination domain
    output reg        dst_left_btn_state,  // Left button state synchronized to destination domain
    output reg        dst_right_btn_state  // Right button state synchronized to destination domain
);

    //--------------------------------------------------------------------------
    // Source-domain holding registers
    //
    // These registers store the stable cursor/button snapshot while a transfer
    // is crossing to the destination domain.
    //--------------------------------------------------------------------------
    reg [9:0] src_cursor_x_hold_ff;        // Held cursor X snapshot
    reg [9:0] src_cursor_y_hold_ff;        // Held cursor Y snapshot
    reg       src_left_btn_hold_ff;        // Held left-button snapshot
    reg       src_right_btn_hold_ff;       // Held right-button snapshot

    reg       req_toggle_ff;               // Source request toggle

    //--------------------------------------------------------------------------
    // Acknowledge toggle synchronized back into the source domain
    //
    // Two flip-flops reduce metastability risk when the destination acknowledge
    // crosses back into src_clk.
    //--------------------------------------------------------------------------
    reg ack_toggle_src_meta_ff;            // First stage of ack synchronizer
    reg ack_toggle_src_sync_ff;            // Second stage of ack synchronizer

    //--------------------------------------------------------------------------
    // Request toggle synchronized into the destination domain
    //
    // The destination uses these registers to detect when the source has
    // launched a new snapshot transfer.
    //--------------------------------------------------------------------------
    reg req_toggle_dst_meta_ff;            // First stage of request synchronizer
    reg req_toggle_dst_sync_ff;            // Second stage of request synchronizer
    reg req_toggle_dst_seen_ff;            // Last request toggle already handled

    reg ack_toggle_ff;                     // Destination acknowledge toggle

    //--------------------------------------------------------------------------
    // Source-domain request logic
    //
    // This block synchronizes the acknowledge back from the destination domain,
    // waits until the previous transfer is complete, and launches a new transfer
    // only when the source cursor/button values have changed.
    //--------------------------------------------------------------------------
    always @(posedge src_clk) begin
        // Bring destination acknowledge toggle safely into the source domain.
        ack_toggle_src_meta_ff <= ack_toggle_ff;
        ack_toggle_src_sync_ff <= ack_toggle_src_meta_ff;

        // Initialize source-side holding registers and handshake state.
        if (!src_resetn) begin
            src_cursor_x_hold_ff   <= CURSOR_X_INIT[9:0];
            src_cursor_y_hold_ff   <= CURSOR_Y_INIT[9:0];
            src_left_btn_hold_ff   <= 1'b0;
            src_right_btn_hold_ff  <= 1'b0;

            req_toggle_ff          <= 1'b0;

            ack_toggle_src_meta_ff <= 1'b0;
            ack_toggle_src_sync_ff <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // A new transfer may start only after the previous request has been
            // acknowledged by the destination domain.
            //------------------------------------------------------------------
            if (req_toggle_ff == ack_toggle_src_sync_ff) begin
                //--------------------------------------------------------------
                // Capture and send a new snapshot only if something changed.
                //--------------------------------------------------------------
                if ((src_cursor_x        != src_cursor_x_hold_ff)  ||
                    (src_cursor_y        != src_cursor_y_hold_ff)  ||
                    (src_left_btn_state  != src_left_btn_hold_ff)  ||
                    (src_right_btn_state != src_right_btn_hold_ff)) begin

                    src_cursor_x_hold_ff  <= src_cursor_x;
                    src_cursor_y_hold_ff  <= src_cursor_y;
                    src_left_btn_hold_ff  <= src_left_btn_state;
                    src_right_btn_hold_ff <= src_right_btn_state;

                    req_toggle_ff         <= ~req_toggle_ff;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Destination-domain capture logic
    //
    // This block synchronizes the source request toggle, detects new transfers,
    // captures the stable held snapshot, and toggles acknowledge back to source.
    //--------------------------------------------------------------------------
    always @(posedge dst_clk) begin
        // Bring source request toggle safely into the destination domain.
        req_toggle_dst_meta_ff <= req_toggle_ff;
        req_toggle_dst_sync_ff <= req_toggle_dst_meta_ff;

        // Initialize destination outputs and handshake tracking.
        if (!dst_resetn) begin
            dst_cursor_x           <= CURSOR_X_INIT[9:0];
            dst_cursor_y           <= CURSOR_Y_INIT[9:0];
            dst_left_btn_state     <= 1'b0;
            dst_right_btn_state    <= 1'b0;

            req_toggle_dst_meta_ff <= 1'b0;
            req_toggle_dst_sync_ff <= 1'b0;
            req_toggle_dst_seen_ff <= 1'b0;

            ack_toggle_ff          <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // A changed request toggle means the source has a new stable
            // cursor/button snapshot ready to capture.
            //------------------------------------------------------------------
            if (req_toggle_dst_sync_ff != req_toggle_dst_seen_ff) begin
                dst_cursor_x        <= src_cursor_x_hold_ff;
                dst_cursor_y        <= src_cursor_y_hold_ff;
                dst_left_btn_state  <= src_left_btn_hold_ff;
                dst_right_btn_state <= src_right_btn_hold_ff;

                req_toggle_dst_seen_ff <= req_toggle_dst_sync_ff;
                ack_toggle_ff          <= ~ack_toggle_ff;
            end
        end
    end

endmodule