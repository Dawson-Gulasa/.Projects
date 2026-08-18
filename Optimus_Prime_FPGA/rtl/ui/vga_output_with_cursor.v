`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// vga_output_with_cursor.v
//
// Purpose:
//   Wrap the existing vga_output module and add a highest-priority cursor
//   overlay on top of the already-working VGA stream.
//
// Why this wrapper exists:
//   The current design already has a working DDR2 -> FIFO -> vga_output path.
//   This wrapper preserves that path, then overlays the cursor late in the
//   display chain so the existing sprite/text behavior stays intact.
//
// Strategy:
//   1) Instantiate the existing vga_output and capture its RGB/sync outputs
//   2) Recreate the standard 640x480@60Hz pixel counters locally in clk_vga
//   3) Feed the local pixel location into cursor_overlay
//   4) Drive the final VGA RGB from the overlay result
//
// Notes:
//   - Reset is synchronous
//   - This wrapper assumes standard 640x480 VGA timing on clk_vga
//   - If the cursor appears shifted by a few pixels, the first place to debug
//     is the local timing alignment in this wrapper
//------------------------------------------------------------------------------

module vga_output_with_cursor #(
    parameter DEBUG_OVERLAY_ONLY = 1'b0
)(
    input  wire        clk_vga,       // VGA pixel clock
    input  wire        resetn,        // Synchronized active-low reset

    input  wire [63:0] fifo_data,     // FIFO data from DDR2 path
    input  wire        fifo_empty,    // FIFO empty flag
    output wire        fifo_rd_en,    // FIFO read enable to DDR2 path

    input  wire [9:0]  cursor_x,      // Cursor center X in VGA domain
    input  wire [9:0]  cursor_y,      // Cursor center Y in VGA domain

    output wire [3:0]  RED,           // Final VGA red
    output wire [3:0]  GRN,           // Final VGA green
    output wire [3:0]  BLU,           // Final VGA blue
    output wire        HSYNC,         // VGA hsync
    output wire        VSYNC,         // VGA vsync
    output wire        visible,       // Visible-region flag from base VGA output
    output wire        vsync_pulse    // One-cycle vsync pulse from base VGA output
);

    //--------------------------------------------------------------------------
    // Base VGA output signals
    //--------------------------------------------------------------------------
    wire [3:0] red_base_w;
    wire [3:0] grn_base_w;
    wire [3:0] blu_base_w;
    wire       visible_base_w;
    wire       vsync_pulse_base_w;
    wire       hsync_base_w;
    wire       vsync_base_w;

    //--------------------------------------------------------------------------
    // Local VGA timing recreation for cursor pixel address generation
    //
    // Standard 640x480 @ 60 Hz timing:
    //   Horizontal total = 800
    //   Vertical total   = 525
    //--------------------------------------------------------------------------
    reg [9:0] h_count_ff;
    reg [9:0] v_count_ff;

    //--------------------------------------------------------------------------
    // Cursor overlay output signals
    //--------------------------------------------------------------------------
    wire [3:0] red_cursor_w;
    wire [3:0] grn_cursor_w;
    wire [3:0] blu_cursor_w;
    wire       cursor_on_w;

    //--------------------------------------------------------------------------
    // Base VGA output path
    //
    // This is the already-working display path. The wrapper does not disturb
    // its FIFO interface or sync generation.
    //--------------------------------------------------------------------------
    vga_output #(
        .DEBUG_OVERLAY_ONLY(DEBUG_OVERLAY_ONLY)
    ) u_vga_output (
        .clk_vga     (clk_vga),
        .resetn      (resetn),

        .fifo_data   (fifo_data),
        .fifo_empty  (fifo_empty),
        .fifo_rd_en  (fifo_rd_en),

        .RED         (red_base_w),
        .GRN         (grn_base_w),
        .BLU         (blu_base_w),
        .HSYNC       (hsync_base_w),
        .VSYNC       (vsync_base_w),
        .visible     (visible_base_w),
        .vsync_pulse (vsync_pulse_base_w)
    );

    //--------------------------------------------------------------------------
    // Local VGA pixel counters
    //
    // These counters track the current pixel position so the cursor overlay can
    // map the 16x16 cursor bitmap onto the screen.
    //
    // Only non-blocking assignments are used here.
    //--------------------------------------------------------------------------
    always @(posedge clk_vga) begin
        if (!resetn) begin
            h_count_ff <= 10'd0;
            v_count_ff <= 10'd0;
        end
        else begin
            //------------------------------------------------------------------
            // Horizontal and vertical raster counters
            //------------------------------------------------------------------
            if (h_count_ff == 10'd799) begin
                h_count_ff <= 10'd0;

                if (v_count_ff == 10'd524) begin
                    v_count_ff <= 10'd0;
                end
                else begin
                    v_count_ff <= v_count_ff + 10'd1;
                end
            end
            else begin
                h_count_ff <= h_count_ff + 10'd1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Cursor overlay
    //
    // The overlay sits on top of the base RGB stream. Transparent cursor pixels
    // pass through the base image unchanged.
    //--------------------------------------------------------------------------
    cursor_overlay #(
        .CURSOR_MEM_FILE("cursor_dot_16x16.mem"),
        .CURSOR_R       (4'hF),
        .CURSOR_G       (4'hF),
        .CURSOR_B       (4'hF)
    ) u_cursor_overlay (
        .video_active (visible_base_w),
        .pixel_x      (h_count_ff),
        .pixel_y      (v_count_ff),

        .cursor_x     (cursor_x),
        .cursor_y     (cursor_y),

        .rgb_r_in     (red_base_w),
        .rgb_g_in     (grn_base_w),
        .rgb_b_in     (blu_base_w),

        .rgb_r_out    (red_cursor_w),
        .rgb_g_out    (grn_cursor_w),
        .rgb_b_out    (blu_cursor_w),

        .cursor_on    (cursor_on_w)
    );

    //--------------------------------------------------------------------------
    // Final output connections
    //--------------------------------------------------------------------------
    assign RED         = red_cursor_w;
    assign GRN         = grn_cursor_w;
    assign BLU         = blu_cursor_w;
    assign HSYNC       = hsync_base_w;
    assign VSYNC       = vsync_base_w;
    assign visible     = visible_base_w;
    assign vsync_pulse = vsync_pulse_base_w;

endmodule