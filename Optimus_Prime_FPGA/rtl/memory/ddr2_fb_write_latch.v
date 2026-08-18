`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ddr2_fb_write_latch.v
//
// Purpose:
//   Captures a renderer framebuffer write request in the DDR ui_clk domain and
//   holds it until the DDR engine completes the write.
//
//   The renderer write request is received as a one-clock pulse. Since the DDR
//   engine may not be ready to service that write immediately, this module saves
//   the write address and data in registers and keeps wr_pending high until the
//   engine reports completion.
//
// Write-latch algorithm:
//   1) Wait for wr_req_pulse while no write is currently pending.
//   2) Latch wr_addr and wr_data.
//   3) Assert wr_pending so the DDR engine can service the held write.
//   4) When wr_done_pulse arrives, clear wr_pending.
//   5) Toggle wr_ack so the source side can detect that the write completed.
//
// Example:
//   If the renderer requests a write to address 100 with data 64'hABCD, this
//   module stores that request and holds wr_pending high. The DDR engine later
//   completes the write and pulses wr_done_pulse, causing wr_ack to toggle.
//
// Notes:
//   - This module runs fully in the MIG ui_clk domain.
//   - Only one renderer write is held at a time.
//   - This is not an encoded FSM; state is represented by wr_pending and the
//     latched write address/data.
//------------------------------------------------------------------------------
module ddr2_fb_write_latch (
    input  wire        ui_clk,           // MIG user-interface clock
    input  wire        ui_rst,           // Synchronous reset in ui_clk domain
    input  wire        wr_req_pulse,     // One-clock synchronized renderer write request
    input  wire [26:0] wr_addr,          // Renderer write address to capture
    input  wire [63:0] wr_data,          // Renderer write data to capture
    input  wire        wr_done_pulse,    // One-clock pulse when DDR engine completes held write

    output reg  [26:0] wr_addr_lat,      // Latched write address sent to DDR engine
    output reg  [63:0] wr_data_lat,      // Latched write data sent to DDR engine
    output reg         wr_pending,       // High while one write is waiting/in progress
    output reg         wr_ack,           // Toggle acknowledgment back toward renderer side
    output wire        debug_wr_pending  // Debug copy of wr_pending
);

    //--------------------------------------------------------------------------
    // Debug output assignment
    //--------------------------------------------------------------------------
    assign debug_wr_pending = wr_pending;

    //--------------------------------------------------------------------------
    // Renderer write request latch
    //
    // This block captures one write request, holds it for the DDR engine, and
    // toggles the acknowledge bit after the write completes.
    //--------------------------------------------------------------------------
    always @(posedge ui_clk) begin
        // Clear any held write and reset the acknowledge toggle.
        if (ui_rst) begin
            wr_addr_lat <= 27'd0;
            wr_data_lat <= 64'd0;
            wr_pending  <= 1'b0;
            wr_ack      <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Capture a new renderer write only when no write is already pending.
            //------------------------------------------------------------------
            if (wr_req_pulse && !wr_pending) begin
                wr_addr_lat <= wr_addr;
                wr_data_lat <= wr_data;
                wr_pending  <= 1'b1;
                wr_ack      <= wr_ack;
            end
            //------------------------------------------------------------------
            // The DDR engine completed the held write, so clear pending and
            // toggle the acknowledge back to the request source.
            //------------------------------------------------------------------
            else if (wr_done_pulse) begin
                wr_pending <= 1'b0;
                wr_ack     <= ~wr_ack;
            end
            //------------------------------------------------------------------
            // No new request or completion this cycle, so hold the current state.
            //------------------------------------------------------------------
            else begin
                wr_addr_lat <= wr_addr_lat;
                wr_data_lat <= wr_data_lat;
                wr_pending  <= wr_pending;
                wr_ack      <= wr_ack;
            end
        end
    end

endmodule