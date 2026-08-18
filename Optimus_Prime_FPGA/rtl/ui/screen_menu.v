`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// screen_menu.v  —  Main menu screen for Optimus Prime UI
//
// All elements use 1x font (8×16) and are aligned to a 16×16 display grid.
// 2x title support can be re-enabled by changing the marked constants.
//
// Grid layout (40 cols × 30 rows, each 16×16):
//   Corners    : 32x32 Autobots logo in each of the four corners,
//                inset 16 px from each screen edge
//                (X=16..47 / 592..623, Y=16..47 / 432..463)
//   Row  2 (Y= 32): Title logo 256x32 bitmap (logo_rom)
//   Row  4 (Y= 64): Subtitle "Prime Number Discovery System"
//   Row  6 (Y= 96): Top divider
//   Row  8 (Y=128): Button 0 "Range Mode"
//   Row 10 (Y=160): Button 1 "Time Mode"
//   Row 12 (Y=192): Button 2 "Single Test"
//   Row 14 (Y=224): Button 3 "Test Mode"
//   Row 26 (Y=416): Bottom divider
//   Row 27 (Y=432): Hint "Point and click to select"
//------------------------------------------------------------------------------
module screen_menu (
    input  wire        clk_vga,
    input  wire        resetn,
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,
    output reg  [1:0]  selected_mode_ff,
    output wire [2:0]  hover_index_w,
    output reg         click_pulse_ff,
    output reg         controls_click_ff,
    output reg  [3:0]  pixel_color_ff
);

    // ---- Palette ----
    localparam COL_NAVY  = 4'h5;
    localparam COL_WHITE = 4'h1;
    localparam COL_GRAY  = 4'h6;
    localparam COL_CYAN  = 4'hA;
    localparam COL_DGRAY = 4'hF;
    localparam COL_RED   = 4'h2;

    // ---- Button hit regions (all share same X range) ----
    localparam BTN_X_LO  = 10'd160;
    localparam BTN_X_HI  = 10'd480;
    localparam BTN0_Y_LO = 10'd128;  localparam BTN0_Y_HI = 10'd143;
    localparam BTN1_Y_LO = 10'd160;  localparam BTN1_Y_HI = 10'd175;
    localparam BTN2_Y_LO = 10'd192;  localparam BTN2_Y_HI = 10'd207;
    localparam BTN3_Y_LO = 10'd224;  localparam BTN3_Y_HI = 10'd239;
    localparam BTN4_Y_LO = 10'd256;  localparam BTN4_Y_HI = 10'd271;

    // ---- Layout (grid-aligned, all multiples of 16) ----
    // Menu title is a 256x32 bitmap logo (replaces former "OPTIMUS PRIME" text)
    localparam LOGO_X    = 10'd192;   // (640 - 256) / 2
    localparam LOGO_Y    = 10'd32;
    localparam LOGO_W    = 10'd256;
    localparam LOGO_H    = 10'd32;
    localparam SUB_X     = 10'd208;   // 29 chars × 8 = 232 px
    localparam SUB_Y     = 10'd64;
    localparam HINT_X    = 10'd224;   // 25 chars × 8 = 200 px
    localparam HINT_Y    = 10'd432;
    localparam BTN_LBL_X = 10'd272;
    localparam ICON_X    = 10'd248;   // 16px icon, ends at 264, 8px gap to text

    // ---- Autobot corner-logo positions (32x32 each) ----
    // Corners are inset 16 px from each screen edge. They still don't collide
    // with title (Y=32..63), subtitle (Y=64..79), buttons (Y=128..271), or
    // hint (Y=432..447, X=224..423) — top corners clear the title in X
    // (corners X=16..47 / 592..623 vs title X=192..447), and bottom corners
    // clear the hint in X.
    //
    // Origins are no longer multiples of 32, so we can't use pixel_x[4:0] /
    // pixel_y[4:0] as a shortcut for the bitmap column/row. The bitmap
    // column/row are computed by explicit subtraction from each corner's
    // origin (see corner_row_off_w / corner_col_off_w below).
    localparam CORNER_INSET = 10'd16;
    localparam CORNER_SIZE  = 10'd32;
    localparam LOGO_TL_X    = CORNER_INSET;                          //  16
    localparam LOGO_TL_Y    = CORNER_INSET;                          //  16
    localparam LOGO_TR_X    = 10'd640 - CORNER_INSET - CORNER_SIZE;  // 592
    localparam LOGO_TR_Y    = CORNER_INSET;                          //  16
    localparam LOGO_BL_X    = CORNER_INSET;                          //  16
    localparam LOGO_BL_Y    = 10'd480 - CORNER_INSET - CORNER_SIZE;  // 432
    localparam LOGO_BR_X    = 10'd640 - CORNER_INSET - CORNER_SIZE;  // 592
    localparam LOGO_BR_Y    = 10'd480 - CORNER_INSET - CORNER_SIZE;  // 432

    // ---- Element types ----
    localparam ELEM_BG      = 4'd0;
    localparam ELEM_TITLE   = 4'd1;
    localparam ELEM_SUB     = 4'd2;
    localparam ELEM_DIV     = 4'd3;
    localparam ELEM_BTN0    = 4'd4;
    localparam ELEM_BTN1    = 4'd5;
    localparam ELEM_BTN2    = 4'd6;
    localparam ELEM_BTN3    = 4'd7;
    localparam ELEM_BTN4    = 4'd8;
    localparam ELEM_HINT    = 4'd9;
    localparam ELEM_AUTOBOT = 4'd10;

    // ---- Hover detection ----
    reg [2:0] hover_comb;

    always @(*) begin
        if ((cursor_x >= BTN_X_LO) && (cursor_x <= BTN_X_HI)) begin
            if      ((cursor_y >= BTN0_Y_LO) && (cursor_y <= BTN0_Y_HI)) hover_comb = 3'd0;
            else if ((cursor_y >= BTN1_Y_LO) && (cursor_y <= BTN1_Y_HI)) hover_comb = 3'd1;
            else if ((cursor_y >= BTN2_Y_LO) && (cursor_y <= BTN2_Y_HI)) hover_comb = 3'd2;
            else if ((cursor_y >= BTN3_Y_LO) && (cursor_y <= BTN3_Y_HI)) hover_comb = 3'd3;
            else if ((cursor_y >= BTN4_Y_LO) && (cursor_y <= BTN4_Y_HI)) hover_comb = 3'd5;
            else                                                            hover_comb = 3'd4;
        end
        else begin
            hover_comb = 3'd4;
        end
    end

    assign hover_index_w = hover_comb;

    // ---- Click pulse ----
    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff  <= 1'b0;
            click_pulse_ff    <= 1'b0;
            controls_click_ff <= 1'b0;
            selected_mode_ff  <= 2'd0;
        end
        else begin
            left_btn_prev_ff  <= left_btn;
            click_pulse_ff    <= 1'b0;
            controls_click_ff <= 1'b0;
            if (left_btn_prev_ff && !left_btn) begin
                if (hover_comb == 3'd5) begin
                    // Controls button
                    controls_click_ff <= 1'b1;
                end
                else if (hover_comb != 3'd4) begin
                    // Mode buttons 0-3
                    click_pulse_ff   <= 1'b1;
                    selected_mode_ff <= hover_comb[1:0];
                end
            end
        end
    end

    // ---- Character lookup functions ----
    // (title is now a bitmap logo — see logo_rom instantiation below)

    // "Prime Number Discovery System" (29 chars)
    function [6:0] sub_char;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  sub_char = 7'h50; 5'd1:  sub_char = 7'h72;
                5'd2:  sub_char = 7'h69; 5'd3:  sub_char = 7'h6D;
                5'd4:  sub_char = 7'h65; 5'd5:  sub_char = 7'h20;
                5'd6:  sub_char = 7'h4E; 5'd7:  sub_char = 7'h75;
                5'd8:  sub_char = 7'h6D; 5'd9:  sub_char = 7'h62;
                5'd10: sub_char = 7'h65; 5'd11: sub_char = 7'h72;
                5'd12: sub_char = 7'h20; 5'd13: sub_char = 7'h44;
                5'd14: sub_char = 7'h69; 5'd15: sub_char = 7'h73;
                5'd16: sub_char = 7'h63; 5'd17: sub_char = 7'h6F;
                5'd18: sub_char = 7'h76; 5'd19: sub_char = 7'h65;
                5'd20: sub_char = 7'h72; 5'd21: sub_char = 7'h79;
                5'd22: sub_char = 7'h20; 5'd23: sub_char = 7'h53;
                5'd24: sub_char = 7'h79; 5'd25: sub_char = 7'h73;
                5'd26: sub_char = 7'h74; 5'd27: sub_char = 7'h65;
                5'd28: sub_char = 7'h6D;
                default: sub_char = 7'h20;
            endcase
        end
    endfunction

    // Button labels
    function [6:0] btn_char;
        input [1:0] btn;
        input [3:0] col;
        begin
            case (btn)
                2'd0: case (col)
                    4'd0: btn_char=7'h52; 4'd1: btn_char=7'h61;
                    4'd2: btn_char=7'h6E; 4'd3: btn_char=7'h67;
                    4'd4: btn_char=7'h65; 4'd5: btn_char=7'h20;
                    4'd6: btn_char=7'h4D; 4'd7: btn_char=7'h6F;
                    4'd8: btn_char=7'h64; 4'd9: btn_char=7'h65;
                    default: btn_char=7'h20;
                endcase
                2'd1: case (col)
                    4'd0: btn_char=7'h54; 4'd1: btn_char=7'h69;
                    4'd2: btn_char=7'h6D; 4'd3: btn_char=7'h65;
                    4'd4: btn_char=7'h20; 4'd5: btn_char=7'h4D;
                    4'd6: btn_char=7'h6F; 4'd7: btn_char=7'h64;
                    4'd8: btn_char=7'h65;
                    default: btn_char=7'h20;
                endcase
                2'd2: case (col)
                    4'd0: btn_char=7'h53; 4'd1: btn_char=7'h69;
                    4'd2: btn_char=7'h6E; 4'd3: btn_char=7'h67;
                    4'd4: btn_char=7'h6C; 4'd5: btn_char=7'h65;
                    4'd6: btn_char=7'h20; 4'd7: btn_char=7'h54;
                    4'd8: btn_char=7'h65; 4'd9: btn_char=7'h73;
                    4'd10: btn_char=7'h74;
                    default: btn_char=7'h20;
                endcase
                default: case (col)
                    4'd0: btn_char=7'h54; 4'd1: btn_char=7'h65;
                    4'd2: btn_char=7'h73; 4'd3: btn_char=7'h74;
                    4'd4: btn_char=7'h20; 4'd5: btn_char=7'h4D;
                    4'd6: btn_char=7'h6F; 4'd7: btn_char=7'h64;
                    4'd8: btn_char=7'h65;
                    default: btn_char=7'h20;
                endcase
            endcase
        end
    endfunction

    // "Controls" (8 chars) — button 4 label
    function [6:0] btn4_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: btn4_char=7'h43; 4'd1: btn4_char=7'h6F;  // Co
                4'd2: btn4_char=7'h6E; 4'd3: btn4_char=7'h74;  // nt
                4'd4: btn4_char=7'h72; 4'd5: btn4_char=7'h6F;  // ro
                4'd6: btn4_char=7'h6C; 4'd7: btn4_char=7'h73;  // ls
                default: btn4_char=7'h20;
            endcase
        end
    endfunction

    // "Point and click to select" (25 chars)
    function [6:0] hint_char;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  hint_char=7'h50; 5'd1:  hint_char=7'h6F;
                5'd2:  hint_char=7'h69; 5'd3:  hint_char=7'h6E;
                5'd4:  hint_char=7'h74; 5'd5:  hint_char=7'h20;
                5'd6:  hint_char=7'h61; 5'd7:  hint_char=7'h6E;
                5'd8:  hint_char=7'h64; 5'd9:  hint_char=7'h20;
                5'd10: hint_char=7'h63; 5'd11: hint_char=7'h6C;
                5'd12: hint_char=7'h69; 5'd13: hint_char=7'h63;
                5'd14: hint_char=7'h6B; 5'd15: hint_char=7'h20;
                5'd16: hint_char=7'h74; 5'd17: hint_char=7'h6F;
                5'd18: hint_char=7'h20; 5'd19: hint_char=7'h73;
                5'd20: hint_char=7'h65; 5'd21: hint_char=7'h6C;
                5'd22: hint_char=7'h65; 5'd23: hint_char=7'h63;
                5'd24: hint_char=7'h74;
                default: hint_char=7'h20;
            endcase
        end
    endfunction

    // ---- Icon bitmap ROM (5 icons × 16 rows → 16-bit pixel data) ----
    // MSB = leftmost pixel, LSB = rightmost pixel
    function [15:0] icon_row_data;
        input [2:0] icon;
        input [3:0] row;
        begin
            icon_row_data = 16'h0000;
            case (icon)
                // Icon 0: Range Mode — signal4 (IoT Icon Set)
                3'd0: case (row)
                    4'd0:  icon_row_data = 16'h0000;
                    4'd1:  icon_row_data = 16'h0004;
                    4'd2:  icon_row_data = 16'h000C;
                    4'd3:  icon_row_data = 16'h001C;
                    4'd4:  icon_row_data = 16'h001C;
                    4'd5:  icon_row_data = 16'h005C;
                    4'd6:  icon_row_data = 16'h00DC;
                    4'd7:  icon_row_data = 16'h01DC;
                    4'd8:  icon_row_data = 16'h01DC;
                    4'd9:  icon_row_data = 16'h05DC;
                    4'd10: icon_row_data = 16'h0DDC;
                    4'd11: icon_row_data = 16'h1DDC;
                    4'd12: icon_row_data = 16'h1DDC;
                    4'd13: icon_row_data = 16'h5DDC;
                    4'd14: icon_row_data = 16'hDDDC;
                    4'd15: icon_row_data = 16'hDDDC;
                    default: icon_row_data = 16'h0000;
                endcase
                // Icon 1: Time Mode — timer (IoT Icon Set)
                3'd1: case (row)
                    4'd2:  icon_row_data = 16'h03E0;
                    4'd3:  icon_row_data = 16'h07F0;
                    4'd4:  icon_row_data = 16'h0C98;
                    4'd5:  icon_row_data = 16'h183C;
                    4'd6:  icon_row_data = 16'h3076;
                    4'd7:  icon_row_data = 16'h30E6;
                    4'd8:  icon_row_data = 16'h39CE;
                    4'd9:  icon_row_data = 16'h3086;
                    4'd10: icon_row_data = 16'h3006;
                    4'd11: icon_row_data = 16'h180C;
                    4'd12: icon_row_data = 16'h0C98;
                    4'd13: icon_row_data = 16'h07F0;
                    4'd14: icon_row_data = 16'h03E0;
                    default: icon_row_data = 16'h0000;
                endcase
                // Icon 2: Single Test — check (IoT Icon Set)
                3'd2: case (row)
                    4'd4:  icon_row_data = 16'h0007;
                    4'd5:  icon_row_data = 16'h000F;
                    4'd6:  icon_row_data = 16'h001F;
                    4'd7:  icon_row_data = 16'h703E;
                    4'd8:  icon_row_data = 16'h787C;
                    4'd9:  icon_row_data = 16'h7CF8;
                    4'd10: icon_row_data = 16'h1FF0;
                    4'd11: icon_row_data = 16'h0FE0;
                    4'd12: icon_row_data = 16'h07C0;
                    4'd13: icon_row_data = 16'h0380;
                    default: icon_row_data = 16'h0000;
                endcase
                // Icon 3: Test Mode — bulb_on (IoT Icon Set)
                3'd3: case (row)
                    4'd1:  icon_row_data = 16'h23E2;
                    4'd2:  icon_row_data = 16'h1414;
                    4'd3:  icon_row_data = 16'h0808;
                    4'd4:  icon_row_data = 16'h1004;
                    4'd5:  icon_row_data = 16'h1004;
                    4'd6:  icon_row_data = 16'h1004;
                    4'd7:  icon_row_data = 16'h1004;
                    4'd8:  icon_row_data = 16'h1004;
                    4'd9:  icon_row_data = 16'h0808;
                    4'd10: icon_row_data = 16'h1414;
                    4'd11: icon_row_data = 16'h23E2;
                    4'd12: icon_row_data = 16'h0220;
                    4'd13: icon_row_data = 16'h03E0;
                    4'd14: icon_row_data = 16'h0220;
                    4'd15: icon_row_data = 16'h03E0;
                    default: icon_row_data = 16'h0000;
                endcase
                // Icon 4: Controls (info "i")
                3'd4: case (row)
                    4'd1:  icon_row_data = 16'h0380;
                    4'd2:  icon_row_data = 16'h0380;
                    4'd5:  icon_row_data = 16'h0780;
                    4'd6:  icon_row_data = 16'h0300;
                    4'd7:  icon_row_data = 16'h0300;
                    4'd8:  icon_row_data = 16'h0300;
                    4'd9:  icon_row_data = 16'h0300;
                    4'd10: icon_row_data = 16'h0300;
                    4'd11: icon_row_data = 16'h0300;
                    4'd12: icon_row_data = 16'h07C0;
                    default: icon_row_data = 16'h0000;
                endcase
                default: icon_row_data = 16'h0000;
            endcase
        end
    endfunction

    // ---- Pre-computed offsets ----
    wire [9:0] logo_dy_w;
    wire [9:0] sub_dx_w;    wire [9:0] sub_dy_w;
    wire [9:0] btn_dx_w;
    wire [9:0] btn0_dy_w;   wire [9:0] btn1_dy_w;
    wire [9:0] btn2_dy_w;   wire [9:0] btn3_dy_w;
    wire [9:0] btn4_dy_w;
    wire [9:0] hint_dx_w;   wire [9:0] hint_dy_w;

    assign logo_dy_w  = pixel_y - LOGO_Y;
    assign sub_dx_w   = pixel_x - SUB_X;
    assign sub_dy_w   = pixel_y - SUB_Y;
    assign btn_dx_w   = pixel_x - BTN_LBL_X;
    assign btn0_dy_w  = pixel_y - BTN0_Y_LO;
    assign btn1_dy_w  = pixel_y - BTN1_Y_LO;
    assign btn2_dy_w  = pixel_y - BTN2_Y_LO;
    assign btn3_dy_w  = pixel_y - BTN3_Y_LO;
    assign btn4_dy_w  = pixel_y - BTN4_Y_LO;
    assign hint_dx_w  = pixel_x - HINT_X;
    assign hint_dy_w  = pixel_y - HINT_Y;

    // ---- Autobot corner detection ----
    // Top/bottom strips and left/right columns are tested independently;
    // a pixel is in a corner when one of each pair is true.
    wire in_corner_left_w  = (pixel_x >= LOGO_TL_X) && (pixel_x < LOGO_TL_X + CORNER_SIZE);
    wire in_corner_right_w = (pixel_x >= LOGO_TR_X) && (pixel_x < LOGO_TR_X + CORNER_SIZE);
    wire in_corner_top_w   = (pixel_y >= LOGO_TL_Y) && (pixel_y < LOGO_TL_Y + CORNER_SIZE);
    wire in_corner_bot_w   = (pixel_y >= LOGO_BL_Y) && (pixel_y < LOGO_BL_Y + CORNER_SIZE);
    wire in_corner_w       = (in_corner_left_w || in_corner_right_w) &&
                             (in_corner_top_w  || in_corner_bot_w);

    // Bitmap row/column = pixel offset from the matching corner origin
    wire [9:0] corner_row_off_w = in_corner_top_w  ? (pixel_y - LOGO_TL_Y)
                                                   : (pixel_y - LOGO_BL_Y);
    wire [9:0] corner_col_off_w = in_corner_left_w ? (pixel_x - LOGO_TL_X)
                                                   : (pixel_x - LOGO_TR_X);

    // ---- Stage 0: combinational element decode ----
    reg [3:0] cur_elem;
    reg [3:0] cur_fg;
    reg [6:0] cur_char;
    reg [3:0] cur_row;
    reg [4:0] cur_logo_row;
    reg [4:0] cur_logo_col;
    reg        cur_is_icon;
    reg  [2:0] cur_icon_idx;

    always @(*) begin
        cur_elem     = ELEM_BG;
        cur_fg       = COL_WHITE;
        cur_char     = 7'h20;
        cur_row      = 4'd0;
        cur_logo_row = 5'd0;
        cur_logo_col = 5'd0;
        cur_is_icon  = 1'b0;
        cur_icon_idx = 3'd0;

        if (pixel_active) begin

            // Autobot corner logos (32x32 in all four corners, rendered via autobot_rom).
            // Corners are non-overlapping with every other UI element; checked first.
            if (in_corner_w) begin
                cur_elem     = ELEM_AUTOBOT;
                cur_fg       = COL_RED;
                cur_logo_row = corner_row_off_w[4:0];
                cur_logo_col = corner_col_off_w[4:0];
            end

            // Title logo (256x32 bitmap, rendered via logo_rom)
            else if ((pixel_y >= LOGO_Y) && (pixel_y < LOGO_Y + LOGO_H)) begin
                if ((pixel_x >= LOGO_X) && (pixel_x < LOGO_X + LOGO_W)) begin
                    cur_elem     = ELEM_TITLE;
                    cur_fg       = COL_WHITE;
                    cur_logo_row = logo_dy_w[4:0];
                end
            end

            // Subtitle 1x  y=64..79  (29 chars × 8 = 232 px)
            else if ((pixel_y >= SUB_Y) && (pixel_y < SUB_Y + 10'd16)) begin
                if ((pixel_x >= SUB_X) && (pixel_x < SUB_X + 10'd232)) begin
                    cur_elem = ELEM_SUB;
                    cur_fg   = COL_GRAY;
                    cur_char = sub_char(sub_dx_w[7:3]);
                    cur_row  = sub_dy_w[3:0];
                end
            end

            // (Top divider removed – background stripes show through)

            // Button 0  y=128..143
            else if ((pixel_y >= BTN0_Y_LO) && (pixel_y <= BTN0_Y_HI)) begin
                if ((pixel_x >= BTN_X_LO) && (pixel_x <= BTN_X_HI)) begin
                    cur_elem = ELEM_BTN0;
                    cur_fg   = (hover_comb == 3'd0) ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BTN_LBL_X) && (pixel_x < BTN_LBL_X + 10'd80)) begin
                        cur_char = btn_char(2'd0, btn_dx_w[6:3]);
                    end
                    if ((pixel_x >= ICON_X) && (pixel_x < ICON_X + 10'd16)) begin
                        cur_is_icon  = 1'b1;
                        cur_icon_idx = 3'd0;
                    end
                    cur_row = btn0_dy_w[3:0];
                end
            end

            // Button 1  y=160..175
            else if ((pixel_y >= BTN1_Y_LO) && (pixel_y <= BTN1_Y_HI)) begin
                if ((pixel_x >= BTN_X_LO) && (pixel_x <= BTN_X_HI)) begin
                    cur_elem = ELEM_BTN1;
                    cur_fg   = (hover_comb == 3'd1) ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BTN_LBL_X) && (pixel_x < BTN_LBL_X + 10'd72)) begin
                        cur_char = btn_char(2'd1, btn_dx_w[6:3]);
                    end
                    if ((pixel_x >= ICON_X) && (pixel_x < ICON_X + 10'd16)) begin
                        cur_is_icon  = 1'b1;
                        cur_icon_idx = 3'd1;
                    end
                    cur_row = btn1_dy_w[3:0];
                end
            end

            // Button 2  y=192..207
            else if ((pixel_y >= BTN2_Y_LO) && (pixel_y <= BTN2_Y_HI)) begin
                if ((pixel_x >= BTN_X_LO) && (pixel_x <= BTN_X_HI)) begin
                    cur_elem = ELEM_BTN2;
                    cur_fg   = (hover_comb == 3'd2) ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BTN_LBL_X) && (pixel_x < BTN_LBL_X + 10'd88)) begin
                        cur_char = btn_char(2'd2, btn_dx_w[6:3]);
                    end
                    if ((pixel_x >= ICON_X) && (pixel_x < ICON_X + 10'd16)) begin
                        cur_is_icon  = 1'b1;
                        cur_icon_idx = 3'd2;
                    end
                    cur_row = btn2_dy_w[3:0];
                end
            end

            // Button 3  y=224..239
            else if ((pixel_y >= BTN3_Y_LO) && (pixel_y <= BTN3_Y_HI)) begin
                if ((pixel_x >= BTN_X_LO) && (pixel_x <= BTN_X_HI)) begin
                    cur_elem = ELEM_BTN3;
                    cur_fg   = (hover_comb == 3'd3) ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BTN_LBL_X) && (pixel_x < BTN_LBL_X + 10'd72)) begin
                        cur_char = btn_char(2'd3, btn_dx_w[6:3]);
                    end
                    if ((pixel_x >= ICON_X) && (pixel_x < ICON_X + 10'd16)) begin
                        cur_is_icon  = 1'b1;
                        cur_icon_idx = 3'd3;
                    end
                    cur_row = btn3_dy_w[3:0];
                end
            end

            // Button 4  y=256..271  "Controls"
            else if ((pixel_y >= BTN4_Y_LO) && (pixel_y <= BTN4_Y_HI)) begin
                if ((pixel_x >= BTN_X_LO) && (pixel_x <= BTN_X_HI)) begin
                    cur_elem = ELEM_BTN4;
                    cur_fg   = (hover_comb == 3'd5) ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BTN_LBL_X) && (pixel_x < BTN_LBL_X + 10'd64)) begin
                        cur_char = btn4_char(btn_dx_w[5:3]);
                    end
                    if ((pixel_x >= ICON_X) && (pixel_x < ICON_X + 10'd16)) begin
                        cur_is_icon  = 1'b1;
                        cur_icon_idx = 3'd4;
                    end
                    cur_row = btn4_dy_w[3:0];
                end
            end

            // (Bottom divider removed – background stripes show through)

            // Hint 1x  y=432..447  (25 chars × 8 = 200 px)
            else if ((pixel_y >= HINT_Y) && (pixel_y < HINT_Y + 10'd16)) begin
                if ((pixel_x >= HINT_X) && (pixel_x < HINT_X + 10'd200)) begin
                    cur_elem = ELEM_HINT;
                    cur_fg   = COL_GRAY;
                    cur_char = hint_char(hint_dx_w[7:3]);
                    cur_row  = hint_dy_w[3:0];
                end
            end

        end
    end

    always @(*) begin
        font_char_ff = cur_char;
        font_row_ff  = cur_row;
    end

    // ---- Stage 1: pipeline latches ----
    reg [3:0]  elem_d1_ff;
    reg [3:0]  fg_d1_ff;
    reg [9:0]  px_d1_ff;
    reg        active_d1_ff;
    reg [2:0]  hover_d1_ff;
    reg        is_icon_d1_ff;
    reg [2:0]  icon_idx_d1_ff;
    reg [3:0]  icon_row_d1_ff;
    reg [4:0]  logo_row_d1_ff;
    reg [4:0]  logo_col_d1_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            elem_d1_ff     <= ELEM_BG;
            fg_d1_ff       <= COL_NAVY;
            px_d1_ff       <= 10'd0;
            active_d1_ff   <= 1'b0;
            hover_d1_ff    <= 3'd4;
            is_icon_d1_ff  <= 1'b0;
            icon_idx_d1_ff <= 3'd0;
            icon_row_d1_ff <= 4'd0;
            logo_row_d1_ff <= 5'd0;
            logo_col_d1_ff <= 5'd0;
        end
        else begin
            elem_d1_ff     <= cur_elem;
            fg_d1_ff       <= cur_fg;
            px_d1_ff       <= pixel_x;
            active_d1_ff   <= pixel_active;
            hover_d1_ff    <= hover_comb;
            is_icon_d1_ff  <= cur_is_icon;
            icon_idx_d1_ff <= cur_icon_idx;
            icon_row_d1_ff <= cur_row;
            logo_row_d1_ff <= cur_logo_row;
            logo_col_d1_ff <= cur_logo_col;
        end
    end

    // ---- Logo bitmap lookup ----
    wire [255:0] logo_data_w;
    logo_rom u_logo_rom (
        .row (logo_row_d1_ff),
        .data(logo_data_w)
    );
    wire [9:0] logo_dx_pipe_w = px_d1_ff - LOGO_X;
    wire [7:0] logo_col_w     = logo_dx_pipe_w[7:0];
    wire       logo_px_w      = logo_data_w[8'd255 - logo_col_w];

    // ---- Autobot corner-logo bitmap lookup ----
    // Shares logo_row_d1_ff with the title ROM (both ROMs are stateless and
    // only one is selected per pixel via elem_d1_ff). Column comes from a
    // separately-pipelined offset because corner origins are no longer
    // multiples of 32 (16-px inset from edges), so px_d1_ff[4:0] would be
    // wrong for the right-side and bottom corners.
    wire [31:0] autobot_data_w;
    autobot_rom u_autobot_rom (
        .row (logo_row_d1_ff),
        .data(autobot_data_w)
    );
    wire [4:0] autobot_col_w = logo_col_d1_ff;
    wire       autobot_px_w  = autobot_data_w[5'd31 - autobot_col_w];

    // ---- Stage 2: output color ----
    // All elements use 1x bit select: bit 7 = leftmost pixel in char cell
    wire [2:0] bit_sel_w;
    assign bit_sel_w = 3'd7 - px_d1_ff[2:0];

    // Icon bitmap lookup
    wire [15:0] icon_data_w = icon_row_data(icon_idx_d1_ff, icon_row_d1_ff);
    wire [3:0]  icon_col_w  = px_d1_ff[3:0] - 4'd8;   // ICON_X[3:0] = 8
    wire        icon_px_w   = icon_data_w[4'd15 - icon_col_w];

    always @(posedge clk_vga) begin
        if (!resetn) begin
            pixel_color_ff <= COL_NAVY;
        end
        else if (!active_d1_ff) begin
            pixel_color_ff <= COL_NAVY;
        end
        else begin
            case (elem_d1_ff)
                ELEM_BG: begin
                    pixel_color_ff <= COL_NAVY;
                end
                ELEM_TITLE: begin
                    pixel_color_ff <= logo_px_w ? COL_WHITE : COL_NAVY;
                end
                ELEM_AUTOBOT: begin
                    pixel_color_ff <= autobot_px_w ? COL_RED : COL_NAVY;
                end
                ELEM_SUB,
                ELEM_HINT: begin
                    pixel_color_ff <= font_pixel_row[bit_sel_w] ? fg_d1_ff : COL_NAVY;
                end
                ELEM_BTN4: begin
                    if (is_icon_d1_ff) begin
                        if (hover_d1_ff == 3'd5)
                            pixel_color_ff <= icon_px_w ? COL_NAVY : COL_CYAN;
                        else
                            pixel_color_ff <= icon_px_w ? COL_WHITE : COL_NAVY;
                    end
                    else if (hover_d1_ff == 3'd5) begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_NAVY : COL_CYAN;
                    end
                    else begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_WHITE : COL_NAVY;
                    end
                end
                ELEM_BTN0,
                ELEM_BTN1,
                ELEM_BTN2,
                ELEM_BTN3: begin
                    if (is_icon_d1_ff) begin
                        if (hover_d1_ff == (elem_d1_ff - ELEM_BTN0))
                            pixel_color_ff <= icon_px_w ? COL_NAVY : COL_CYAN;
                        else
                            pixel_color_ff <= icon_px_w ? COL_WHITE : COL_NAVY;
                    end
                    else if (hover_d1_ff == (elem_d1_ff - ELEM_BTN0)) begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_NAVY : COL_CYAN;
                    end
                    else begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_WHITE : COL_NAVY;
                    end
                end
                default: begin
                    pixel_color_ff <= COL_NAVY;
                end
            endcase
        end
    end

endmodule
