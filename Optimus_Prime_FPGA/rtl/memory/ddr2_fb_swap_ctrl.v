`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ddr2_fb_swap_ctrl.v
//
// Purpose:
//   Manages front/back framebuffer ownership and performs tear-free buffer swaps
//   between the renderer and the VGA display path.
//
//   The renderer draws into the back buffer while the VGA path reads from the
//   front buffer. When the renderer finishes a frame, it sends a frame-done
//   event. This module waits until the next safe VSYNC boundary before swapping
//   the front and back buffers.
//
// Buffer swap algorithm:
//   1) Renderer finishes drawing and toggles frame_done_req.
//   2) ddr2_fb_cdc converts that toggle into fd_pulse in ui_clk.
//   3) This module records that a completed frame is pending.
//   4) On the next vsync_pulse, if DDR is ready, front_buf toggles.
//   5) frame_done_ack toggles back toward the renderer.
//   6) back_buf_base updates so the renderer writes into the old front buffer.
//
// Example:
//   If FRAME0 is currently front and FRAME1 is back, the renderer fills FRAME1.
//   When the next VSYNC arrives after frame completion, FRAME1 becomes front and
//   FRAME0 becomes the new back buffer for the renderer.
//
// Notes:
//   - This module runs fully in the MIG ui_clk domain.
//   - The swap is delayed until VSYNC to prevent visible tearing.
//   - This is not an encoded multi-state FSM; state is represented by
//     front_buf, frame_done_pending_ff, and the handshake toggles.
//------------------------------------------------------------------------------

module ddr2_fb_swap_ctrl (
    input  wire        ui_clk,          // MIG user-interface clock
    input  wire        ui_rst,          // Synchronous reset in ui_clk domain
    input  wire        ready,           // DDR/framebuffer system ready flag
    input  wire        vsync_pulse,     // One-clock synchronized VSYNC pulse
    input  wire        fd_pulse,        // One-clock renderer frame-done pulse

    output reg         front_buf,       // 0 = FRAME0 front, 1 = FRAME1 front
    output reg         frame_done_ack,  // Toggle acknowledgment back to renderer
    output reg  [26:0] back_buf_base,   // Base address of buffer renderer should fill
    output reg         ready_toggle,    // One-time toggle when ready first rises
    output wire        debug_front_buf  // Debug copy of current front buffer select
);

    //--------------------------------------------------------------------------
    // Framebuffer base addresses
    //
    // Each frame occupies 153600 64-bit DDR words in this design.
    //--------------------------------------------------------------------------
    localparam [26:0] FRAME0_BASE = 27'd0;      // Base address of framebuffer 0
    localparam [26:0] FRAME1_BASE = 27'd153600; // Base address of framebuffer 1

    //--------------------------------------------------------------------------
    // Internal swap/ready tracking registers
    //--------------------------------------------------------------------------
    reg frame_done_pending_ff; // High after renderer finishes frame, before VSYNC swap
    reg ready_prev_ff;         // Previous ready value for rising-edge detection

    assign debug_front_buf = front_buf;

    //--------------------------------------------------------------------------
    // Front/back buffer swap control
    //
    // This block records completed renderer frames, waits for VSYNC, then swaps
    // the displayed buffer and renderer target buffer.
    //--------------------------------------------------------------------------
    always @(posedge ui_clk) begin
        // Reset buffer ownership and handshake state.
        if (ui_rst) begin
            front_buf             <= 1'b0;
            frame_done_ack        <= 1'b0;
            back_buf_base         <= FRAME1_BASE;
            ready_toggle          <= 1'b0;
            frame_done_pending_ff <= 1'b0;
            ready_prev_ff         <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Track ready so the first ready rising edge can start rendering.
            //------------------------------------------------------------------
            ready_prev_ff <= ready;

            //------------------------------------------------------------------
            // Generate a one-time ready toggle when DDR first becomes ready.
            //------------------------------------------------------------------
            if (ready && !ready_prev_ff) begin
                ready_toggle <= ~ready_toggle;
            end
            else begin
                ready_toggle <= ready_toggle;
            end

            //------------------------------------------------------------------
            // Record that the renderer has completed a back-buffer frame.
            //------------------------------------------------------------------
            if (fd_pulse) begin
                frame_done_pending_ff <= 1'b1;
            end
            else begin
                frame_done_pending_ff <= frame_done_pending_ff;
            end

            //------------------------------------------------------------------
            // Swap only on VSYNC when a completed frame is waiting.
            //------------------------------------------------------------------
            if (vsync_pulse && ready && frame_done_pending_ff) begin
                front_buf             <= ~front_buf;
                frame_done_pending_ff <= 1'b0;
                frame_done_ack        <= ~frame_done_ack;

                // After the swap, the old front buffer becomes the new back buffer.
                if (front_buf) begin
                    back_buf_base <= FRAME1_BASE;
                end
                else begin
                    back_buf_base <= FRAME0_BASE;
                end
            end
            else begin
                front_buf      <= front_buf;
                frame_done_ack <= frame_done_ack;
                back_buf_base  <= back_buf_base;
            end
        end
    end

endmodule