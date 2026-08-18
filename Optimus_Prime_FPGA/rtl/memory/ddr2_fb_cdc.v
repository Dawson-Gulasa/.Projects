`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ddr2_fb_cdc.v
//
// Purpose:
//   Synchronizes external/asynchronous control inputs into the DDR2 MIG ui_clk
//   domain and converts them into one-clock pulses used by the framebuffer
//   controller.
//
//   The DDR2 controller runs in ui_clk, while VSYNC, frame_done_req, and wr_req
//   may originate from other logic domains. This module provides the safe input
//   cleanup layer before those events control DDR framebuffer behavior.
//
// Input handling:
//   - vsync_in:
//       Treated as a level signal. It is synchronized with two flip-flops and
//       converted into a one-cycle pulse on the falling edge.
//   - frame_done_req:
//       Treated as a toggle-style request. A synchronized toggle change produces
//       one fd_pulse.
//   - wr_req:
//       Treated as a toggle-style request. A synchronized toggle change produces
//       one wr_req_pulse.
//
// CDC / pulse algorithm:
//   1) Pass each async input through a two-flop synchronizer.
//   2) Store the previous synchronized value.
//   3) For VSYNC, detect a falling edge:
//          previous = 1 and current = 0
//   4) For toggle requests, XOR the current synchronized value with the previous
//      synchronized value.
//   5) Stretch VSYNC debug visibility so it can be seen on LEDs or waveform
//      inspection more easily.
//
// Example:
//   If wr_req toggles from 0 to 1 in the renderer domain, the ui_clk domain
//   eventually sees wr_sync_ff change. Since wr_sync_ff differs from wr_prev_ff,
//   wr_req_pulse becomes high for one ui_clk cycle.
//
// Notes:
//   - This module contains synchronizers and edge/toggle detection, not a
//     multi-state FSM.
//   - ASYNC_REG attributes are used on synchronizer stages.
//   - All output pulses are generated in the ui_clk domain.
//------------------------------------------------------------------------------
module ddr2_fb_cdc (
    input  wire ui_clk,         // MIG user-interface clock
    input  wire ui_rst,         // Synchronous reset in ui_clk domain
    input  wire vsync_in,       // Asynchronous VGA VSYNC level
    input  wire frame_done_req, // Async/toggle frame-done request from renderer
    input  wire wr_req,         // Async/toggle renderer write request

    output wire vsync_pulse,    // One ui_clk pulse on synchronized VSYNC falling edge
    output wire fd_pulse,       // One ui_clk pulse when frame_done_req toggles
    output wire wr_req_pulse,   // One ui_clk pulse when wr_req toggles
    output wire debug_vsync_seen// Stretched indicator after a VSYNC pulse is seen
);

    //--------------------------------------------------------------------------
    // VSYNC synchronizer and falling-edge detector
    //
    // vsync_in is a level signal crossing into ui_clk. After synchronization,
    // a falling edge is detected by comparing the previous and current synced
    // levels.
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg vsync_meta_ff; // First VSYNC synchronizer stage
    (* ASYNC_REG = "TRUE" *) reg vsync_sync_ff; // Second VSYNC synchronizer stage
    reg                      vsync_prev_ff; // Previous synchronized VSYNC level

    //--------------------------------------------------------------------------
    // Frame-done toggle synchronizer
    //
    // frame_done_req is expected to toggle when the renderer completes a frame.
    // The XOR of current and previous synchronized toggle values creates a
    // one-clock pulse.
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg fd_meta_ff; // First frame-done synchronizer stage
    (* ASYNC_REG = "TRUE" *) reg fd_sync_ff; // Second frame-done synchronizer stage
    reg                      fd_prev_ff; // Previous synchronized frame-done toggle

    //--------------------------------------------------------------------------
    // Write-request toggle synchronizer
    //
    // wr_req is expected to toggle when the renderer has a write request ready.
    // The synchronized toggle edge becomes wr_req_pulse.
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg wr_meta_ff; // First write-request synchronizer stage
    (* ASYNC_REG = "TRUE" *) reg wr_sync_ff; // Second write-request synchronizer stage
    reg                      wr_prev_ff; // Previous synchronized write-request toggle

    //--------------------------------------------------------------------------
    // Debug visibility stretcher for VSYNC pulse
    //
    // A one-clock VSYNC pulse can be difficult to observe, so this counter stays
    // nonzero for many cycles after VSYNC is detected.
    //--------------------------------------------------------------------------
    reg [23:0] vsync_stretch_ff; // Current stretched VSYNC debug counter
    reg [23:0] vsync_stretch_in; // Next stretched VSYNC debug counter

    //--------------------------------------------------------------------------
    // Pulse and debug output assignments
    //--------------------------------------------------------------------------
    assign vsync_pulse      = vsync_prev_ff & ~vsync_sync_ff;
    assign fd_pulse         = fd_sync_ff ^ fd_prev_ff;
    assign wr_req_pulse     = wr_sync_ff ^ wr_prev_ff;
    assign debug_vsync_seen = (vsync_stretch_ff != 24'd0);

    //--------------------------------------------------------------------------
    // VSYNC debug stretcher next-state logic
    //
    // Loads a large value when VSYNC is seen, then counts down toward zero.
    //--------------------------------------------------------------------------
    always @(*) begin
        // Hold the current stretch value by default.
        vsync_stretch_in = vsync_stretch_ff;

        // A new VSYNC pulse reloads the debug stretch counter.
        if (vsync_pulse) begin
            vsync_stretch_in = 24'hFFFFFF;
        end
        // Count down while the debug indicator is active.
        else if (vsync_stretch_ff != 24'd0) begin
            vsync_stretch_in = vsync_stretch_ff - 24'd1;
        end
        // Once the counter reaches zero, keep it at zero.
        else begin
            vsync_stretch_in = vsync_stretch_ff;
        end
    end

    //--------------------------------------------------------------------------
    // Sequential synchronizers and state registers
    //
    // All CDC synchronizer stages, previous-value registers, and debug stretch
    // state update in the ui_clk domain.
    //--------------------------------------------------------------------------
    always @(posedge ui_clk) begin
        // Reset all synchronizer flops and debug state to known values.
        if (ui_rst) begin
            vsync_meta_ff    <= 1'b1;
            vsync_sync_ff    <= 1'b1;
            vsync_prev_ff    <= 1'b1;

            fd_meta_ff       <= 1'b0;
            fd_sync_ff       <= 1'b0;
            fd_prev_ff       <= 1'b0;

            wr_meta_ff       <= 1'b0;
            wr_sync_ff       <= 1'b0;
            wr_prev_ff       <= 1'b0;

            vsync_stretch_ff <= 24'd0;
        end
        // Normal operation synchronizes inputs and updates edge/toggle history.
        else begin
            vsync_meta_ff    <= vsync_in;
            vsync_sync_ff    <= vsync_meta_ff;
            vsync_prev_ff    <= vsync_sync_ff;

            fd_meta_ff       <= frame_done_req;
            fd_sync_ff       <= fd_meta_ff;
            fd_prev_ff       <= fd_sync_ff;

            wr_meta_ff       <= wr_req;
            wr_sync_ff       <= wr_meta_ff;
            wr_prev_ff       <= wr_sync_ff;

            vsync_stretch_ff <= vsync_stretch_in;
        end
    end

endmodule