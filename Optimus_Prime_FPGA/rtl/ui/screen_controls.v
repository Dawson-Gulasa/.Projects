`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// screen_controls.v  —  Controls/help screen for Optimus Prime UI
//
// All elements 1x (8×16), grid-aligned to 16×16.
//
// Grid layout:
//   Row  2 (Y= 32): Title "Controls"
//   Row  5 (Y= 80): "Center Button: Reset Program"
//   Row  8 (Y=128): "Keypad 0-9 : Number Entry"
//   Row 10 (Y=160): "Keypad B   : Backspace"
//   Row 12 (Y=192): "Keypad C   : Clear"
//   Row 15 (Y=240): "Click input text to use keypad.  Try it out!"  +
//                   Practice input box (8 digits) at X=368..431,
//                   8 px gap to the right of "Try it out!"
//   Row 16 (Y=256): Underline (blinks when active, just below box)
//   Row 28 (Y=448): Back to Menu button
//------------------------------------------------------------------------------
module screen_controls (
    input  wire        clk_vga,
    input  wire        resetn,

    // Mouse
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,

    // Pixel scan
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,

    // Font ROM
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,

    // Practice field display (driven by param_entry)
    input  wire [26:0] practice_val,
    input  wire        practice_active,   // field is selected for editing
    input  wire        cursor_blink,

    // Navigation
    output reg         back_click_ff,

    // Pixel color
    output reg  [3:0]  pixel_color_ff
);

    // ---- Palette ----
    localparam COL_NAVY   = 4'h5;
    localparam COL_WHITE  = 4'h1;
    localparam COL_GRAY   = 4'h6;
    localparam COL_YELLOW = 4'h7;
    localparam COL_CYAN   = 4'hA;

    // ---- Back button hit region ----
    localparam BACK_X_LO  = 10'd224;
    localparam BACK_X_HI  = 10'd416;
    localparam BACK_Y_LO  = 10'd448;
    localparam BACK_Y_HI  = 10'd463;

    wire back_hover_w;
    assign back_hover_w = (cursor_x >= BACK_X_LO) && (cursor_x <= BACK_X_HI) &&
                          (cursor_y >= BACK_Y_LO) && (cursor_y <= BACK_Y_HI);

    // ---- Click detection ----
    // Note: practice-field click hit region lives in param_entry.v
    // (PRAC_X_LO=368, PRAC_X_HI=431, PRAC_Y_LO=240, PRAC_Y_HI=255). The
    // visual rendered below at PRAC_VAL_X/PRAC_VAL_Y is placed to match.
    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            back_click_ff    <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;
            if (left_btn_prev_ff && !left_btn && back_hover_w)
                back_click_ff <= 1'b1;
            else
                back_click_ff <= 1'b0;
        end
    end

    // ---- Layout ----
    // Body content left-aligned at X=16 to match LBL_X on the
    // generating / results screens. Title stays centered. Back button stays
    // centered (universal fixed location across every screen). The practice
    // input box sits on the same row as "Try it out!" with an 8 px gap to
    // its right (X=368..431), matching its clickable hit region in
    // param_entry.v (PRAC_X_LO=368..PRAC_X_HI=431, PRAC_Y_LO=240..PRAC_Y_HI=255).
    localparam TITLE_Y    = 10'd32;
    localparam TITLE_X    = 10'd288;    // "Controls" 8 chars (64px), centered: (640-64)/2=288
    localparam LINE1_Y    = 10'd80;     // "Center Button: Reset Program"
    localparam LINE1_X    = 10'd16;     // 28 chars (224px)
    localparam LINE2_Y    = 10'd128;    // "Keypad 0-9 : Number Entry"
    localparam LINE2_X    = 10'd16;     // 25 chars (200px)
    localparam LINE3_Y    = 10'd160;    // "Keypad B   : Backspace"
    localparam LINE3_X    = 10'd16;
    localparam LINE4_Y    = 10'd192;    // "Keypad C   : Clear"
    localparam LINE4_X    = 10'd16;
    localparam LINE5_Y    = 10'd240;    // "Click input text to use keypad."
    localparam LINE5_X    = 10'd16;     // 31 chars (248px): 16..263
    localparam LINE6_Y    = 10'd240;    // "Try it out!" on same row, one space after keypad.
    localparam LINE6_X    = 10'd272;    // 11 chars (88px): 272..359  (16 + 32*8)
    localparam PRAC_VAL_Y = 10'd240;    // same row as "Try it out!"
    localparam PRAC_VAL_X = 10'd368;    // 8 digits (64px), 8 px gap right of "Try it out!" (368..431)
    localparam ULINE_Y    = 10'd256;    // single-pixel underline, just below box
    localparam BACK_LBL_X = 10'd272;

    // ---- Element types ----
    localparam ELEM_BG     = 4'd0;
    localparam ELEM_TITLE  = 4'd1;
    localparam ELEM_LINE1  = 4'd2;
    localparam ELEM_LINE2  = 4'd3;
    localparam ELEM_LINE3  = 4'd4;
    localparam ELEM_LINE4  = 4'd5;
    localparam ELEM_LINE5  = 4'd6;
    localparam ELEM_LINE6  = 4'd7;
    localparam ELEM_PRAC   = 4'd8;
    localparam ELEM_ULINE  = 4'd9;
    localparam ELEM_BACK   = 4'd10;

    // ---- Character lookup functions ----

    // "Controls" (8 chars)
    function [6:0] title_char;
        input [3:0] col;
        begin
            case(col)
                4'd0:title_char=7'h43; 4'd1:title_char=7'h6F;  // Co
                4'd2:title_char=7'h6E; 4'd3:title_char=7'h74;  // nt
                4'd4:title_char=7'h72; 4'd5:title_char=7'h6F;  // ro
                4'd6:title_char=7'h6C; 4'd7:title_char=7'h73;  // ls
                default: title_char=7'h20;
            endcase
        end
    endfunction

    // "Center Button: Reset Program" (28 chars)
    function [6:0] line1_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: line1_char=7'h43; 5'd1: line1_char=7'h65;  // Ce
                5'd2: line1_char=7'h6E; 5'd3: line1_char=7'h74;  // nt
                5'd4: line1_char=7'h65; 5'd5: line1_char=7'h72;  // er
                5'd6: line1_char=7'h20; 5'd7: line1_char=7'h42;  //  B
                5'd8: line1_char=7'h75; 5'd9: line1_char=7'h74;  // ut
                5'd10:line1_char=7'h74; 5'd11:line1_char=7'h6F;  // to
                5'd12:line1_char=7'h6E; 5'd13:line1_char=7'h3A;  // n:
                5'd14:line1_char=7'h20; 5'd15:line1_char=7'h52;  //  R
                5'd16:line1_char=7'h65; 5'd17:line1_char=7'h73;  // es
                5'd18:line1_char=7'h65; 5'd19:line1_char=7'h74;  // et
                5'd20:line1_char=7'h20; 5'd21:line1_char=7'h50;  //  P
                5'd22:line1_char=7'h72; 5'd23:line1_char=7'h6F;  // ro
                5'd24:line1_char=7'h67; 5'd25:line1_char=7'h72;  // gr
                5'd26:line1_char=7'h61; 5'd27:line1_char=7'h6D;  // am
                default: line1_char=7'h20;
            endcase
        end
    endfunction

    // "Keypad 0-9 : Number Entry" (25 chars)
    function [6:0] line2_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: line2_char=7'h4B; 5'd1: line2_char=7'h65;  // Ke
                5'd2: line2_char=7'h79; 5'd3: line2_char=7'h70;  // yp
                5'd4: line2_char=7'h61; 5'd5: line2_char=7'h64;  // ad
                5'd6: line2_char=7'h20; 5'd7: line2_char=7'h30;  //  0
                5'd8: line2_char=7'h2D; 5'd9: line2_char=7'h39;  // -9
                5'd10:line2_char=7'h20; 5'd11:line2_char=7'h3A;  //  :
                5'd12:line2_char=7'h20; 5'd13:line2_char=7'h4E;  //  N
                5'd14:line2_char=7'h75; 5'd15:line2_char=7'h6D;  // um
                5'd16:line2_char=7'h62; 5'd17:line2_char=7'h65;  // be
                5'd18:line2_char=7'h72; 5'd19:line2_char=7'h20;  // r
                5'd20:line2_char=7'h45; 5'd21:line2_char=7'h6E;  // En
                5'd22:line2_char=7'h74; 5'd23:line2_char=7'h72;  // tr
                5'd24:line2_char=7'h79;                           // y
                default: line2_char=7'h20;
            endcase
        end
    endfunction

    // "Keypad B   : Backspace" (22 chars)
    function [6:0] line3_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: line3_char=7'h4B; 5'd1: line3_char=7'h65;  // Ke
                5'd2: line3_char=7'h79; 5'd3: line3_char=7'h70;  // yp
                5'd4: line3_char=7'h61; 5'd5: line3_char=7'h64;  // ad
                5'd6: line3_char=7'h20; 5'd7: line3_char=7'h42;  //  B
                5'd8: line3_char=7'h20; 5'd9: line3_char=7'h20;  //
                5'd10:line3_char=7'h20; 5'd11:line3_char=7'h3A;  //    :
                5'd12:line3_char=7'h20; 5'd13:line3_char=7'h42;  //  B
                5'd14:line3_char=7'h61; 5'd15:line3_char=7'h63;  // ac
                5'd16:line3_char=7'h6B; 5'd17:line3_char=7'h73;  // ks
                5'd18:line3_char=7'h70; 5'd19:line3_char=7'h61;  // pa
                5'd20:line3_char=7'h63; 5'd21:line3_char=7'h65;  // ce
                default: line3_char=7'h20;
            endcase
        end
    endfunction

    // "Keypad C   : Clear" (19 chars)
    function [6:0] line4_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: line4_char=7'h4B; 5'd1: line4_char=7'h65;  // Ke
                5'd2: line4_char=7'h79; 5'd3: line4_char=7'h70;  // yp
                5'd4: line4_char=7'h61; 5'd5: line4_char=7'h64;  // ad
                5'd6: line4_char=7'h20; 5'd7: line4_char=7'h43;  //  C
                5'd8: line4_char=7'h20; 5'd9: line4_char=7'h20;  //
                5'd10:line4_char=7'h20; 5'd11:line4_char=7'h3A;  //    :
                5'd12:line4_char=7'h20; 5'd13:line4_char=7'h43;  //  C
                5'd14:line4_char=7'h6C; 5'd15:line4_char=7'h65;  // le
                5'd16:line4_char=7'h61; 5'd17:line4_char=7'h72;  // ar
                default: line4_char=7'h20;
            endcase
        end
    endfunction

    // "Click input text to use keypad." (31 chars)
    function [6:0] line5_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: line5_char=7'h43; 5'd1: line5_char=7'h6C;  // Cl
                5'd2: line5_char=7'h69; 5'd3: line5_char=7'h63;  // ic
                5'd4: line5_char=7'h6B; 5'd5: line5_char=7'h20;  // k
                5'd6: line5_char=7'h69; 5'd7: line5_char=7'h6E;  // in
                5'd8: line5_char=7'h70; 5'd9: line5_char=7'h75;  // pu
                5'd10:line5_char=7'h74; 5'd11:line5_char=7'h20;  // t
                5'd12:line5_char=7'h74; 5'd13:line5_char=7'h65;  // te
                5'd14:line5_char=7'h78; 5'd15:line5_char=7'h74;  // xt
                5'd16:line5_char=7'h20; 5'd17:line5_char=7'h74;  //  t
                5'd18:line5_char=7'h6F; 5'd19:line5_char=7'h20;  // o
                5'd20:line5_char=7'h75; 5'd21:line5_char=7'h73;  // us
                5'd22:line5_char=7'h65; 5'd23:line5_char=7'h20;  // e
                5'd24:line5_char=7'h6B; 5'd25:line5_char=7'h65;  // ke
                5'd26:line5_char=7'h79; 5'd27:line5_char=7'h70;  // yp
                5'd28:line5_char=7'h61; 5'd29:line5_char=7'h64;  // ad
                5'd30:line5_char=7'h2E;                           // .
                default: line5_char=7'h20;
            endcase
        end
    endfunction

    // "Try it out!" (11 chars)
    function [6:0] line6_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: line6_char=7'h54; 4'd1: line6_char=7'h72;  // Tr
                4'd2: line6_char=7'h79; 4'd3: line6_char=7'h20;  // y
                4'd4: line6_char=7'h69; 4'd5: line6_char=7'h74;  // it
                4'd6: line6_char=7'h20; 4'd7: line6_char=7'h6F;  //  o
                4'd8: line6_char=7'h75; 4'd9: line6_char=7'h74;  // ut
                4'd10:line6_char=7'h21;                           // !
                default: line6_char=7'h20;
            endcase
        end
    endfunction

    // "Back to Menu" (12 chars)
    function [6:0] back_char;
        input [3:0] col;
        begin
            case(col)
                4'd0:back_char=7'h42; 4'd1:back_char=7'h61;  // Ba
                4'd2:back_char=7'h63; 4'd3:back_char=7'h6B;  // ck
                4'd4:back_char=7'h20; 4'd5:back_char=7'h74;  //  t
                4'd6:back_char=7'h6F; 4'd7:back_char=7'h20;  // o
                4'd8:back_char=7'h4D; 4'd9:back_char=7'h65;  // Me
                4'd10:back_char=7'h6E; 4'd11:back_char=7'h75; // nu
                default: back_char=7'h20;
            endcase
        end
    endfunction

    // ---- BCD display for practice field ----
    // Reuse same double-dabble/sequential approach as other screens
    reg [6:0] prac_bcd_ff [0:7];

    reg [2:0] dd_step_ff;
    reg       dd_go_ff;
    reg [26:0] dd_acc_ff;
    wire [31:0] dd_bcd_w;
    wire        dd_done_w;
    wire        dd_ready_w;

    bin2bcd_seq u_bcd (
        .clk   (clk_vga),
        .rst_n (resetn),
        .bin   (practice_val),
        .start (dd_go_ff),
        .bcd   (dd_bcd_w),
        .done  (dd_done_w),
        .ready (dd_ready_w)
    );

    //--------------------------------------------------------------------------
    // BCD-result capture (unrolled, no runtime for-loop)
    //
    // On dd_done, latch all 8 ASCII digits from dd_bcd_w in parallel.
    // Bit layout of dd_bcd_w: MSD at [31:28], LSD at [3:0]; array index 0 is
    // the leftmost (MSD) digit, index 7 is the rightmost (LSD).
    //--------------------------------------------------------------------------
    always @(posedge clk_vga) begin
        if (!resetn) begin
            dd_go_ff <= 1'b0;
        end else begin
            dd_go_ff <= 1'b0;
            if (dd_done_w) begin
                prac_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[28 +: 4]};
                prac_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[24 +: 4]};
                prac_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[20 +: 4]};
                prac_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[16 +: 4]};
                prac_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[12 +: 4]};
                prac_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[ 8 +: 4]};
                prac_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[ 4 +: 4]};
                prac_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[ 0 +: 4]};
                dd_go_ff <= 1'b1;
            end else if (dd_ready_w && !dd_go_ff) begin
                dd_go_ff <= 1'b1;
            end
        end
    end

    // ---- Pre-computed offsets ----
    wire [9:0] title_dx_w  = pixel_x - TITLE_X;
    wire [9:0] title_dy_w  = pixel_y - TITLE_Y;
    wire [9:0] line1_dx_w  = pixel_x - LINE1_X;
    wire [9:0] line2_dx_w  = pixel_x - LINE2_X;
    wire [9:0] line3_dx_w  = pixel_x - LINE3_X;
    wire [9:0] line4_dx_w  = pixel_x - LINE4_X;
    wire [9:0] line5_dx_w  = pixel_x - LINE5_X;
    wire [9:0] line6_dx_w  = pixel_x - LINE6_X;
    wire [9:0] prac_dx_w   = pixel_x - PRAC_VAL_X;
    wire [9:0] prac_dy_w   = pixel_y - PRAC_VAL_Y;
    wire [9:0] row_dy_w    = pixel_y - LINE1_Y;   // generic row offset (reused)
    wire [9:0] back_dx_w   = pixel_x - BACK_LBL_X;
    wire [9:0] back_dy_w   = pixel_y - BACK_Y_LO;

    // ---- Stage 0: combinational element decode ----
    reg [3:0] cur_elem;
    reg [3:0] cur_fg;
    reg [6:0] cur_char;
    reg [3:0] cur_row;

    always @(*) begin
        cur_elem = ELEM_BG;
        cur_fg   = COL_WHITE;
        cur_char = 7'h20;
        cur_row  = 4'd0;

        if (pixel_active) begin

            // Title "Controls" 1x y=32..47 (8*8=64px)
            if ((pixel_y >= TITLE_Y) && (pixel_y < TITLE_Y + 10'd16)) begin
                if ((pixel_x >= TITLE_X) && (pixel_x < TITLE_X + 10'd64)) begin
                    cur_elem = ELEM_TITLE;
                    cur_fg   = COL_WHITE;
                    cur_char = title_char(title_dx_w[5:3]);
                    cur_row  = title_dy_w[3:0];
                end
            end

            // Line 1: "Center Button: Reset Program" y=80..95 (28*8=224px)
            else if ((pixel_y >= LINE1_Y) && (pixel_y < LINE1_Y + 10'd16)) begin
                if ((pixel_x >= LINE1_X) && (pixel_x < LINE1_X + 10'd224)) begin
                    cur_elem = ELEM_LINE1;
                    cur_fg   = COL_GRAY;
                    cur_char = line1_char(line1_dx_w[7:3]);
                    cur_row  = (pixel_y - LINE1_Y);
                end
            end

            // Line 2: "Keypad 0-9 : Number Entry" y=128..143 (25*8=200px)
            else if ((pixel_y >= LINE2_Y) && (pixel_y < LINE2_Y + 10'd16)) begin
                if ((pixel_x >= LINE2_X) && (pixel_x < LINE2_X + 10'd200)) begin
                    cur_elem = ELEM_LINE2;
                    cur_fg   = COL_GRAY;
                    cur_char = line2_char(line2_dx_w[7:3]);
                    cur_row  = (pixel_y - LINE2_Y);
                end
            end

            // Line 3: "Keypad B   : Backspace" y=160..175 (22*8=176px)
            else if ((pixel_y >= LINE3_Y) && (pixel_y < LINE3_Y + 10'd16)) begin
                if ((pixel_x >= LINE3_X) && (pixel_x < LINE3_X + 10'd200)) begin
                    cur_elem = ELEM_LINE3;
                    cur_fg   = COL_GRAY;
                    cur_char = line3_char(line3_dx_w[7:3]);
                    cur_row  = (pixel_y - LINE3_Y);
                end
            end

            // Line 4: "Keypad C   : Clear" y=192..207 (19*8=152px)
            else if ((pixel_y >= LINE4_Y) && (pixel_y < LINE4_Y + 10'd16)) begin
                if ((pixel_x >= LINE4_X) && (pixel_x < LINE4_X + 10'd200)) begin
                    cur_elem = ELEM_LINE4;
                    cur_fg   = COL_GRAY;
                    cur_char = line4_char(line4_dx_w[7:3]);
                    cur_row  = (pixel_y - LINE4_Y);
                end
            end

            // Line 5 + Line 6 + Practice box share row y=240..255:
            //   Line 5 "Click input text to use keypad." at X=16..263 (31*8=248px)
            //   Line 6 "Try it out!"                    at X=272..359 (11*8=88px)
            //   Practice input box (8 digits)           at X=368..431 (8*8 =64px)
            else if ((pixel_y >= LINE5_Y) && (pixel_y < LINE5_Y + 10'd16)) begin
                if ((pixel_x >= LINE5_X) && (pixel_x < LINE5_X + 10'd248)) begin
                    cur_elem = ELEM_LINE5;
                    cur_fg   = COL_GRAY;
                    cur_char = line5_char(line5_dx_w[7:3]);
                    cur_row  = (pixel_y - LINE5_Y);
                end
                else if ((pixel_x >= LINE6_X) && (pixel_x < LINE6_X + 10'd88)) begin
                    cur_elem = ELEM_LINE6;
                    cur_fg   = COL_GRAY;
                    cur_char = line6_char(line6_dx_w[6:3]);
                    cur_row  = (pixel_y - LINE6_Y);
                end
                else if ((pixel_x >= PRAC_VAL_X) && (pixel_x < PRAC_VAL_X + 10'd64)) begin
                    cur_elem = ELEM_PRAC;
                    cur_fg   = practice_active ? COL_YELLOW : COL_WHITE;
                    cur_char = prac_bcd_ff[prac_dx_w[5:3]];
                    cur_row  = prac_dy_w[3:0];
                end
            end

            // Underline y=256 (single-pixel row just below the practice box,
            // blinks when practice is active)
            else if ((pixel_y == ULINE_Y) && practice_active && cursor_blink) begin
                if ((pixel_x >= PRAC_VAL_X) && (pixel_x < PRAC_VAL_X + 10'd64)) begin
                    cur_elem = ELEM_ULINE;
                end
            end

            // Back to Menu button y=448..463
            else if ((pixel_y >= BACK_Y_LO) && (pixel_y <= BACK_Y_HI)) begin
                if ((pixel_x >= BACK_X_LO) && (pixel_x <= BACK_X_HI)) begin
                    cur_elem = ELEM_BACK;
                    cur_fg   = back_hover_w ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BACK_LBL_X) && (pixel_x < BACK_LBL_X + 10'd96)) begin
                        cur_char = back_char(back_dx_w[6:3]);
                        cur_row  = back_dy_w[3:0];
                    end
                    else begin
                        cur_char = 7'h20;
                        cur_row  = back_dy_w[3:0];
                    end
                end
            end

        end
    end

    always @(*) begin
        font_char_ff = cur_char;
        font_row_ff  = cur_row;
    end

    // ---- Stage 1: pipeline latches ----
    reg [3:0] elem_d1_ff;
    reg [3:0] fg_d1_ff;
    reg [9:0] px_d1_ff;
    reg       active_d1_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            elem_d1_ff   <= ELEM_BG;
            fg_d1_ff     <= COL_NAVY;
            px_d1_ff     <= 10'd0;
            active_d1_ff <= 1'b0;
        end
        else begin
            elem_d1_ff   <= cur_elem;
            fg_d1_ff     <= cur_fg;
            px_d1_ff     <= pixel_x;
            active_d1_ff <= pixel_active;
        end
    end

    // ---- Stage 2: output color ----
    wire [2:0] bit_sel_w;
    assign bit_sel_w = 3'd7 - px_d1_ff[2:0];

    always @(posedge clk_vga) begin
        if (!resetn) begin
            pixel_color_ff <= COL_NAVY;
        end
        else if (!active_d1_ff) begin
            pixel_color_ff <= COL_NAVY;
        end
        else begin
            case (elem_d1_ff)
                ELEM_BG:    pixel_color_ff <= COL_NAVY;
                ELEM_ULINE: pixel_color_ff <= COL_CYAN;
                ELEM_BACK: begin
                    if (back_hover_w)
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_NAVY : COL_CYAN;
                    else
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_WHITE : COL_NAVY;
                end
                default: begin
                    pixel_color_ff <= font_pixel_row[bit_sel_w] ? fg_d1_ff : COL_NAVY;
                end
            endcase
        end
    end

endmodule
