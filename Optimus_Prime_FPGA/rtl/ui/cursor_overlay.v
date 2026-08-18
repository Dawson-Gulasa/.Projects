`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// cursor_overlay.v
//
// Purpose:
//   Overlay a cursor bitmap on top of an existing RGB pixel stream.
//
// Intended use:
//   - Place this module late in the display/render path
//   - Feed it the already-rendered RGB values
//   - Give it the live cursor position
//   - Let it replace pixels where the cursor bitmap is active
//
// Cursor bitmap:
//   - 16 rows x 16 columns
//   - 1-bit per pixel
//   - Loaded from a .mem file using $readmemb
//   - A '1' bit means draw cursor color
//   - A '0' bit means pass through background pixel
//
// Coordinate convention:
//   - cursor_x and cursor_y represent the CENTER of the 16x16 cursor box
//   - Therefore, the cursor occupies:
//       x in [cursor_x - 8, cursor_x + 7]
//       y in [cursor_y - 8, cursor_y + 7]
//
// Layer priority:
//   - Cursor is highest priority inside this module
//
// Notes:
//   - Pure combinational overlay logic
//   - No clocks are used in this module
//   - This module does not move the cursor; it only draws it
//------------------------------------------------------------------------------

module cursor_overlay #(
    parameter        CURSOR_MEM_FILE = "cursor_dot_16x16.mem",
    parameter [3:0]  CURSOR_R        = 4'hF,
    parameter [3:0]  CURSOR_G        = 4'hF,
    parameter [3:0]  CURSOR_B        = 4'hF
)(
    input  wire        video_active,   // High only inside visible video region
    input  wire [9:0]  pixel_x,        // Current pixel X
    input  wire [9:0]  pixel_y,        // Current pixel Y

    input  wire [9:0]  cursor_x,       // Cursor center X
    input  wire [9:0]  cursor_y,       // Cursor center Y

    input  wire [3:0]  rgb_r_in,       // Existing pixel red
    input  wire [3:0]  rgb_g_in,       // Existing pixel green
    input  wire [3:0]  rgb_b_in,       // Existing pixel blue

    output reg  [3:0]  rgb_r_out,      // Output pixel red
    output reg  [3:0]  rgb_g_out,      // Output pixel green
    output reg  [3:0]  rgb_b_out,      // Output pixel blue

    output reg         cursor_on       // High when cursor is drawn at this pixel
);

    //--------------------------------------------------------------------------
    // Cursor ROM
    //--------------------------------------------------------------------------
    reg [15:0] cursor_rom [0:15];

    initial begin
        $readmemb(CURSOR_MEM_FILE, cursor_rom);
    end

    //--------------------------------------------------------------------------
    // Combinational helpers
    //--------------------------------------------------------------------------
    reg        within_cursor_box_r;
    reg [4:0]  cursor_row_r;
    reg [4:0]  cursor_col_r;
    reg        cursor_bit_r;

    integer cursor_left_i;
    integer cursor_top_i;

    //--------------------------------------------------------------------------
    // Cursor box / ROM lookup
    //--------------------------------------------------------------------------
    // This always block computes:
    //   - whether the current pixel lies inside the 16x16 cursor box
    //   - which row/column of the ROM that pixel maps to
    //   - whether the cursor bitmap is active at that location
    //--------------------------------------------------------------------------
    always @(*) begin
        // Default values
        within_cursor_box_r = 1'b0;
        cursor_row_r        = 5'd0;
        cursor_col_r        = 5'd0;
        cursor_bit_r        = 1'b0;

        cursor_left_i       = $signed({1'b0, cursor_x}) - 10'sd8;
        cursor_top_i        = $signed({1'b0, cursor_y}) - 10'sd8;

        if (video_active) begin
            if (($signed({1'b0, pixel_x}) >= cursor_left_i) &&
                ($signed({1'b0, pixel_x}) <  (cursor_left_i + 16)) &&
                ($signed({1'b0, pixel_y}) >= cursor_top_i)  &&
                ($signed({1'b0, pixel_y}) <  (cursor_top_i + 16))) begin

                within_cursor_box_r = 1'b1;
                cursor_col_r        = pixel_x - cursor_left_i[9:0];
                cursor_row_r        = pixel_y - cursor_top_i[9:0];

                // Row data is stored MSB->leftmost pixel
                cursor_bit_r        = cursor_rom[cursor_row_r][15 - cursor_col_r];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Final pixel overlay
    //--------------------------------------------------------------------------
    // Cursor pixels replace the incoming pixel color only where the ROM bit = 1.
    // Otherwise the incoming pixel passes through unchanged.
    //--------------------------------------------------------------------------
    always @(*) begin
        // Default pass-through
        rgb_r_out = rgb_r_in;
        rgb_g_out = rgb_g_in;
        rgb_b_out = rgb_b_in;
        cursor_on = 1'b0;

        if (within_cursor_box_r && cursor_bit_r) begin
            rgb_r_out = CURSOR_R;
            rgb_g_out = CURSOR_G;
            rgb_b_out = CURSOR_B;
            cursor_on = 1'b1;
        end
    end

endmodule