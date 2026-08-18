// vga_output.v
`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// vga_output.v
//
// Purpose:
//   Generates 640x480@60Hz VGA timing and turns a stream of 4-bit pixel values
//   (packed 16-per-64b word) into RGB outputs.
//
// Data path summary:
//   - An external async FIFO provides 64-bit words (fifo_data).
//   - One 64-bit word contains 16 pixels, each pixel is a 4-bit nibble.
//   - During the visible region, the module requests a new FIFO word at the
//     start of each 16-pixel group (x = 0,16,32,...,624).
//   - For each pixel, it selects the corresponding nibble from the latched word
//     and maps it through a small palette to 12-bit RGB.
//
// Timing summary:
//   - h_count/v_count create the raw VGA timing counters.
//   - A registered copy (h_count_d/v_count_d/visible_d/HSYNC_d/VSYNC_d) aligns
//     sync/visible with the pixel pipeline.
//   - vsync_pulse is asserted for 1 clk_vga cycle on the falling edge of VSYNC.
//------------------------------------------------------------------------------

module vga_output #(
    parameter DEBUG_OVERLAY_ONLY = 1'b0
)(
    //--------------------------------------------------------------------------
    // VGA pixel clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk_vga,
    input  wire        resetn,        // active-low reset

    //--------------------------------------------------------------------------
    // FIFO interface (pixel stream input)
    //--------------------------------------------------------------------------
    input  wire [63:0] fifo_data,     // 16 pixels packed as 16 nibbles
    input  wire        fifo_empty,    // 1 means no word available
    output reg         fifo_rd_en,    // 1-cycle pulse to pop one word

    //--------------------------------------------------------------------------
    // VGA outputs
    //--------------------------------------------------------------------------
    output reg  [3:0]  RED,
    output reg  [3:0]  GRN,
    output reg  [3:0]  BLU,
    output wire        HSYNC,
    output wire        VSYNC,
    output wire        visible,       // 1 while inside 640x480 visible area
    output wire        vsync_pulse     // 1-cycle pulse on VSYNC falling edge
);

    //--------------------------------------------------------------------------
    // VGA 640x480@60 timing constants (pixel clocks)
    //--------------------------------------------------------------------------
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    //--------------------------------------------------------------------------
    // Raw horizontal/vertical counters
    //--------------------------------------------------------------------------
    reg [9:0]  h_count;
    reg [9:0]  v_count;

    //--------------------------------------------------------------------------
    // VGA Timing Counter Update (major always block)
    //
    // Behavior:
    //   - h_count increments every clk_vga cycle.
    //   - When h_count wraps, v_count increments.
    //   - When v_count wraps, a new frame begins.
    //--------------------------------------------------------------------------
    always @(posedge clk_vga or negedge resetn) begin
        if (!resetn) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            // End-of-line check
            if (h_count == H_TOTAL-1) begin
                h_count <= 10'd0;

                // End-of-frame check
                if (v_count == V_TOTAL-1) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 10'd1;
                end
            end else begin
                h_count <= h_count + 10'd1;
                v_count <= v_count; // hold v_count during the line
            end
        end
    end

    //--------------------------------------------------------------------------
    // Registered timing (align sync/visible with the pixel pipeline)
    //
    // These registers create a one-cycle delayed version of the timing signals.
    // The pixel shifter uses the delayed counters (h_count_d/v_count_d) so the
    // nibble selection and palette outputs line up cleanly with visible/sync.
    //--------------------------------------------------------------------------
    reg [9:0] h_count_d;
    reg [9:0] v_count_d;
    reg       visible_d;
    reg       HSYNC_d;
    reg       VSYNC_d;

    always @(posedge clk_vga or negedge resetn) begin
        if (!resetn) begin
            h_count_d <= 10'd0;
            v_count_d <= 10'd0;
            visible_d <= 1'b0;
            HSYNC_d   <= 1'b1;
            VSYNC_d   <= 1'b1;
        end else begin
            h_count_d <= h_count;
            v_count_d <= v_count;

            // Visible region is the top-left 640x480 area
            visible_d <= (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

            // HSYNC is active-low during the sync interval
            if ((h_count >= H_VISIBLE + H_FRONT) &&
                (h_count <  H_VISIBLE + H_FRONT + H_SYNC)) begin
                HSYNC_d <= 1'b0;
            end else begin
                HSYNC_d <= 1'b1;
            end

            // VSYNC is active-low during the sync interval
            if ((v_count >= V_VISIBLE + V_FRONT) &&
                (v_count <  V_VISIBLE + V_FRONT + V_SYNC)) begin
                VSYNC_d <= 1'b0;
            end else begin
                VSYNC_d <= 1'b1;
            end
        end
    end

    assign HSYNC   = HSYNC_d;
    assign VSYNC   = VSYNC_d;
    assign visible = visible_d;

    //--------------------------------------------------------------------------
    // VSYNC pulse generator (major always block)
    //
    // vsync_pulse is asserted for 1 clk_vga cycle on the falling edge of VSYNC.
    // This is useful for "start of frame" events in other modules.
    //--------------------------------------------------------------------------
    reg vsync_prev;

    always @(posedge clk_vga or negedge resetn) begin
        if (!resetn) begin
            vsync_prev <= 1'b1;
        end else begin
            vsync_prev <= VSYNC_d;
        end
    end

    assign vsync_pulse = vsync_prev & ~VSYNC_d;

    //--------------------------------------------------------------------------
    // Pixel shifter (word-locked to h_count_d)
    //
    // Packing rule:
    //   fifo_data holds 16 pixels as 16 nibbles:
    //     pixel[0]  = fifo_data[3:0]
    //     pixel[1]  = fifo_data[7:4]
    //     ...
    //     pixel[15] = fifo_data[63:60]
    //
    // word_boundary:
    //   True at the start of each 16-pixel group while visible:
    //     x = 0,16,32,...,624  (h_count_d[3:0] == 0)
    //
    // Important:
    //   We still request at x=624 so the next line's first word is ready.
    //--------------------------------------------------------------------------
    reg [63:0] word_reg;     // holds the current 16-pixel word
    reg [3:0]  pix_nib;      // current pixel nibble for palette lookup

    wire word_boundary = visible_d && (h_count_d[3:0] == 4'd0);

    // Pixel shifter / FIFO read control (major always block)
    always @(posedge clk_vga or negedge resetn) begin
        if (!resetn) begin
            fifo_rd_en <= 1'b0;
            word_reg   <= 64'd0;
            pix_nib    <= 4'd0;
        end else begin
            // Default: no FIFO pop unless we explicitly request one
            fifo_rd_en <= 1'b0;

            // Debug mode: ignore FIFO entirely so timing can be validated alone
            if (DEBUG_OVERLAY_ONLY) begin
                word_reg <= 64'd0;
                pix_nib  <= 4'd0;
            end else begin

                // Outside visible region: don't care about pixel nibble
                if (!visible_d) begin
                    word_reg <= word_reg;  // hold the last word
                    pix_nib  <= 4'd0;
                end else begin

                    // At a 16-pixel boundary, latch a new FIFO word (if available)
                    if (word_boundary) begin
                        if (!fifo_empty) begin
                            word_reg   <= fifo_data;
                            pix_nib    <= fifo_data[3:0];
                            fifo_rd_en <= 1'b1;
                        end else begin
                            // FIFO underflow: output black for this group
                            word_reg <= 64'd0;
                            pix_nib  <= 4'd0;
                        end
                    end else begin
                        // Mid-group: select the nibble for the current x position
                        // (x[3:0] selects which of the 16 nibbles to use)
                        pix_nib <= word_reg[(h_count_d[3:0] * 4) +: 4];
                        word_reg <= word_reg; // hold the latched word
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Palette lookup (major always block)
    //
    // Maps pix_nib to 12-bit RGB:
    //   0 -> black
    //   1 -> white
    //   2 -> red
    //   3 -> green
    //   4 -> blue
    //
    // Any other value defaults to black.
    //--------------------------------------------------------------------------
    always @(posedge clk_vga or negedge resetn) begin
        if (!resetn) begin
            RED <= 4'd0;
            GRN <= 4'd0;
            BLU <= 4'd0;
        end else begin
            // If not visible, force black (blanking interval)
            if (!visible_d) begin
                RED <= 4'd0;
                GRN <= 4'd0;
                BLU <= 4'd0;
            end else begin
                // Debug-only mode: force black output while still generating sync
                if (DEBUG_OVERLAY_ONLY) begin
                    {RED,GRN,BLU} <= 12'h000;
                end else begin
                    // Pixel palette selection
                    case (pix_nib)
                            4'h0: {RED,GRN,BLU} <= 12'h000; // background
                            4'h1: {RED,GRN,BLU} <= 12'hF33; // red accent / title
                            4'h2: {RED,GRN,BLU} <= 12'h456; // dark blue menu text
                            4'h3: {RED,GRN,BLU} <= 12'h7AC; // light blue highlight
                            4'h4: {RED,GRN,BLU} <= 12'h021; // dark navy background
                            4'h5: {RED,GRN,BLU} <= 12'h012; // dark navy background
                            4'h6: {RED,GRN,BLU} <= 12'hFFF; // white (subtitles, labels, hints)
                            4'h7: {RED,GRN,BLU} <= 12'h345; // dim menu text / shadow
                            4'h8: {RED,GRN,BLU} <= 12'h013; // barber-pole stripe (subtle navy)
                            4'h9: {RED,GRN,BLU} <= 12'h2D2; // green (Start Finding button)
                            4'hA: {RED,GRN,BLU} <= 12'hACE; // optional accent
                            4'hB: {RED,GRN,BLU} <= 12'h246; // optional accent
                            4'hC: {RED,GRN,BLU} <= 12'h789; // optional accent
                            4'hD: {RED,GRN,BLU} <= 12'h1CE; // optional accent
                            4'hE: {RED,GRN,BLU} <= 12'hF9A; // optional accent
                            4'hF: {RED,GRN,BLU} <= 12'h013; // invisible dividers (matches navy bg)
                        default: {RED,GRN,BLU} <= 12'h000;
                    endcase
                end
            end
        end
    end

endmodule