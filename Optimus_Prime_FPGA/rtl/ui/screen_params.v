`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// screen_params.v  —  Parameter entry screen
//
// All elements 1x (8×16), grid-aligned to 16×16.
//
// Grid layout:
//   Row  2 (Y= 32): Mode title
//   Row  6 (Y= 96): Field 0 label
//   Row  8 (Y=128): Field 0 value (8 digits)
//   Row  9 (Y=144): Field 0 underline
//   Row 11 (Y=176): Field 1 label (Range only)
//   Row 12 (Y=192): Field 1 value (Range only)
//   Row 13 (Y=208): Field 1 underline
//   Row 26 (Y=416): Divider
//   Row 27 (Y=432): Back button
//------------------------------------------------------------------------------
module screen_params (
    input  wire        clk_vga,
    input  wire        resetn,
    input  wire [1:0]  mode,
    input  wire [26:0] field0_val,
    input  wire [26:0] field1_val,
    input  wire        active_field,
    input  wire        entry_done,
    input  wire        input_error,
    input  wire        entry_active,
    input  wire        cursor_blink,
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,
    output reg         back_click_ff,
    output reg         start_click_ff,
    output reg  [3:0]  pixel_color_ff
);

    localparam COL_NAVY  = 4'h5;
    localparam COL_WHITE = 4'h1;
    localparam COL_GRAY  = 4'h6;
    localparam COL_YELLOW= 4'h7;
    localparam COL_CYAN  = 4'hA;
    localparam COL_RED   = 4'h2;
    localparam COL_GREEN = 4'h9;
    localparam COL_DGRAY = 4'hF;

    // ---- Start button hit region (3 rows above Back) ----
    localparam START_X_LO = 10'd224;
    localparam START_X_HI = 10'd416;
    localparam START_Y_LO = 10'd384;
    localparam START_Y_HI = 10'd399;

    wire start_hover_w;
    assign start_hover_w = (cursor_x >= START_X_LO) && (cursor_x <= START_X_HI) &&
                           (cursor_y >= START_Y_LO) && (cursor_y <= START_Y_HI);

    // ---- Back button hit region ----
    localparam BACK_X_LO  = 10'd224;
    localparam BACK_X_HI  = 10'd416;
    localparam BACK_Y_LO  = 10'd432;
    localparam BACK_Y_HI  = 10'd447;

    wire back_hover_w;
    assign back_hover_w = (cursor_x >= BACK_X_LO) && (cursor_x <= BACK_X_HI) &&
                          (cursor_y >= BACK_Y_LO) && (cursor_y <= BACK_Y_HI);

    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            back_click_ff    <= 1'b0;
            start_click_ff   <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;
            if (left_btn_prev_ff && !left_btn && back_hover_w)
                back_click_ff <= 1'b1;
            else
                back_click_ff <= 1'b0;
            if (left_btn_prev_ff && !left_btn && start_hover_w)
                start_click_ff <= 1'b1;
            else
                start_click_ff <= 1'b0;
        end
    end

    // ---- Title character lookup ----
    function [6:0] title_char;
        input [1:0] md;
        input [3:0] col;
        begin
            case (md)
                2'd0: case (col)
                    4'd0: title_char=7'h52; 4'd1: title_char=7'h61;
                    4'd2: title_char=7'h6E; 4'd3: title_char=7'h67;
                    4'd4: title_char=7'h65; 4'd5: title_char=7'h20;
                    4'd6: title_char=7'h4D; 4'd7: title_char=7'h6F;
                    4'd8: title_char=7'h64; 4'd9: title_char=7'h65;
                    default: title_char=7'h20;
                endcase
                2'd1: case (col)
                    4'd0: title_char=7'h54; 4'd1: title_char=7'h69;
                    4'd2: title_char=7'h6D; 4'd3: title_char=7'h65;
                    4'd4: title_char=7'h20; 4'd5: title_char=7'h4D;
                    4'd6: title_char=7'h6F; 4'd7: title_char=7'h64;
                    4'd8: title_char=7'h65;
                    default: title_char=7'h20;
                endcase
                default: case (col)
                    4'd0: title_char=7'h53; 4'd1: title_char=7'h69;
                    4'd2: title_char=7'h6E; 4'd3: title_char=7'h67;
                    4'd4: title_char=7'h6C; 4'd5: title_char=7'h65;
                    4'd6: title_char=7'h20; 4'd7: title_char=7'h54;
                    4'd8: title_char=7'h65; 4'd9: title_char=7'h73;
                    4'd10: title_char=7'h74;
                    default: title_char=7'h20;
                endcase
            endcase
        end
    endfunction

    // ---- Label lookups ----
    // Field 0 label depends on mode:
    //   mode 0 (Range):  "Start Value:"  (12 chars)
    //   mode 1 (Time):   "Time Limit:"   (11 chars)
    //   mode 2 (Single): "Test Number:"  (12 chars)
    function [6:0] lbl0_char;
        input [1:0] md;
        input [3:0] col;
        begin
            case (md)
                2'd0: case (col) // "Start Value:"
                    4'd0: lbl0_char=7'h53; 4'd1: lbl0_char=7'h74;
                    4'd2: lbl0_char=7'h61; 4'd3: lbl0_char=7'h72;
                    4'd4: lbl0_char=7'h74; 4'd5: lbl0_char=7'h20;
                    4'd6: lbl0_char=7'h56; 4'd7: lbl0_char=7'h61;
                    4'd8: lbl0_char=7'h6C; 4'd9: lbl0_char=7'h75;
                    4'd10: lbl0_char=7'h65; 4'd11: lbl0_char=7'h3A;
                    default: lbl0_char=7'h20;
                endcase
                2'd1: case (col) // "Time Limit:"
                    4'd0: lbl0_char=7'h54; 4'd1: lbl0_char=7'h69;
                    4'd2: lbl0_char=7'h6D; 4'd3: lbl0_char=7'h65;
                    4'd4: lbl0_char=7'h20; 4'd5: lbl0_char=7'h4C;
                    4'd6: lbl0_char=7'h69; 4'd7: lbl0_char=7'h6D;
                    4'd8: lbl0_char=7'h69; 4'd9: lbl0_char=7'h74;
                    4'd10: lbl0_char=7'h3A;
                    default: lbl0_char=7'h20;
                endcase
                default: case (col) // "Test Number:"
                    4'd0: lbl0_char=7'h54; 4'd1: lbl0_char=7'h65;
                    4'd2: lbl0_char=7'h73; 4'd3: lbl0_char=7'h74;
                    4'd4: lbl0_char=7'h20; 4'd5: lbl0_char=7'h4E;
                    4'd6: lbl0_char=7'h75; 4'd7: lbl0_char=7'h6D;
                    4'd8: lbl0_char=7'h62; 4'd9: lbl0_char=7'h65;
                    4'd10: lbl0_char=7'h72; 4'd11: lbl0_char=7'h3A;
                    default: lbl0_char=7'h20;
                endcase
            endcase
        end
    endfunction

    function [6:0] lbl1_char;
        input [3:0] col;
        begin
            case (col)
                4'd0: lbl1_char=7'h45; 4'd1: lbl1_char=7'h6E;
                4'd2: lbl1_char=7'h64; 4'd3: lbl1_char=7'h20;
                4'd4: lbl1_char=7'h56; 4'd5: lbl1_char=7'h61;
                4'd6: lbl1_char=7'h6C; 4'd7: lbl1_char=7'h75;
                4'd8: lbl1_char=7'h65; 4'd9: lbl1_char=7'h3A;
                default: lbl1_char=7'h20;
            endcase
        end
    endfunction

    // "Back To Menu" (12 chars)
    function [6:0] back_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  back_char=7'h42; // B
                4'd1:  back_char=7'h61; // a
                4'd2:  back_char=7'h63; // c
                4'd3:  back_char=7'h6B; // k
                4'd4:  back_char=7'h20; // (space)
                4'd5:  back_char=7'h54; // T
                4'd6:  back_char=7'h6F; // o
                4'd7:  back_char=7'h20; // (space)
                4'd8:  back_char=7'h4D; // M
                4'd9:  back_char=7'h65; // e
                4'd10: back_char=7'h6E; // n
                4'd11: back_char=7'h75; // u
                default: back_char=7'h20;
            endcase
        end
    endfunction

    // "Start Finding!" (14 chars)
    function [6:0] start_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  start_char=7'h53; // S
                4'd1:  start_char=7'h74; // t
                4'd2:  start_char=7'h61; // a
                4'd3:  start_char=7'h72; // r
                4'd4:  start_char=7'h74; // t
                4'd5:  start_char=7'h20; // (space)
                4'd6:  start_char=7'h46; // F
                4'd7:  start_char=7'h69; // i
                4'd8:  start_char=7'h6E; // n
                4'd9:  start_char=7'h64; // d
                4'd10: start_char=7'h69; // i
                4'd11: start_char=7'h6E; // n
                4'd12: start_char=7'h67; // g
                4'd13: start_char=7'h21; // !
                default: start_char=7'h20;
            endcase
        end
    endfunction

    // ---- Pre-computed BCD digit characters (double-dabble, no division) ----
    reg [6:0] f0_bcd_ff [0:7];
    reg [6:0] f1_bcd_ff [0:7];

    reg        seq_idx_ff;   // 0 = field0, 1 = field1
    reg        seq_go_ff;
    wire [26:0] dd_bin_w  = seq_idx_ff ? field1_val : field0_val;
    wire [31:0] dd_bcd_w;
    wire        dd_done_w;
    wire        dd_ready_w;

    bin2bcd_seq u_bcd (
        .clk   (clk_vga),
        .rst_n (resetn),
        .bin   (dd_bin_w),
        .start (seq_go_ff),
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
            seq_idx_ff <= 1'b0;
            seq_go_ff  <= 1'b0;
        end else begin
            seq_go_ff <= 1'b0;
            if (dd_done_w) begin
                if (!seq_idx_ff) begin
                    f0_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[28 +: 4]};
                    f0_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[24 +: 4]};
                    f0_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[20 +: 4]};
                    f0_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[16 +: 4]};
                    f0_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[12 +: 4]};
                    f0_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[ 8 +: 4]};
                    f0_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[ 4 +: 4]};
                    f0_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[ 0 +: 4]};
                end
                else begin
                    f1_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[28 +: 4]};
                    f1_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[24 +: 4]};
                    f1_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[20 +: 4]};
                    f1_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[16 +: 4]};
                    f1_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[12 +: 4]};
                    f1_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[ 8 +: 4]};
                    f1_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[ 4 +: 4]};
                    f1_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[ 0 +: 4]};
                end
                seq_idx_ff <= ~seq_idx_ff;
                seq_go_ff  <= 1'b1;
            end else if (dd_ready_w && !seq_go_ff) begin
                seq_go_ff <= 1'b1;
            end
        end
    end

    // ---- Layout constants (grid-aligned) ----
    localparam TITLE_Y    = 10'd32;
    localparam TITLE_X    = 10'd272;
    localparam LBL0_Y     = 10'd96;
    localparam VAL0_Y     = 10'd128;
    localparam ULINE0_Y   = 10'd144;
    localparam LBL1_Y     = 10'd176;
    localparam VAL1_Y     = 10'd192;
    localparam ULINE1_Y   = 10'd208;
    localparam DIV_Y       = 10'd416;
    localparam FIELD_X     = 10'd160;
    localparam LBL_X       = 10'd160;
    localparam START_LBL_X = 10'd264;  // 14 chars × 8 = 112px, centered in 192px button
    localparam BACK_LBL_X  = 10'd272;

    // ---- Element types ----
    localparam ELEM_BG    = 4'd0;
    localparam ELEM_TITLE = 4'd1;
    localparam ELEM_LBL0  = 4'd2;
    localparam ELEM_LBL1  = 4'd3;
    localparam ELEM_VAL0  = 4'd4;
    localparam ELEM_VAL1  = 4'd5;
    localparam ELEM_ULINE = 4'd6;
    localparam ELEM_DIV   = 4'd7;
    localparam ELEM_BACK  = 4'd8;
    localparam ELEM_START = 4'd9;

    // ---- Pre-computed offsets ----
    wire [9:0] title_dx_w, title_dy_w;
    wire [9:0] lbl_dx_w;
    wire [9:0] lbl0_dy_w, lbl1_dy_w;
    wire [9:0] val0_dx_w, val0_dy_w;
    wire [9:0] val1_dx_w, val1_dy_w;
    wire [9:0] back_dx_w, back_dy_w;
    wire [9:0] start_dx_w, start_dy_w;

    assign title_dx_w = pixel_x - TITLE_X;
    assign title_dy_w = pixel_y - TITLE_Y;
    assign lbl_dx_w   = pixel_x - LBL_X;
    assign lbl0_dy_w  = pixel_y - LBL0_Y;
    assign val0_dx_w  = pixel_x - FIELD_X;
    assign val0_dy_w  = pixel_y - VAL0_Y;
    assign lbl1_dy_w  = pixel_y - LBL1_Y;
    assign val1_dx_w  = pixel_x - FIELD_X;
    assign val1_dy_w  = pixel_y - VAL1_Y;
    assign back_dx_w  = pixel_x - BACK_LBL_X;
    assign back_dy_w  = pixel_y - BACK_Y_LO;
    assign start_dx_w = pixel_x - START_LBL_X;
    assign start_dy_w = pixel_y - START_Y_LO;

    // ---- Stage 0: decode ----
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

            // Title 1x  y=32..47  (11 chars max × 8 = 88 px)
            if ((pixel_y >= TITLE_Y) && (pixel_y < TITLE_Y + 10'd16)) begin
                if ((pixel_x >= TITLE_X) && (pixel_x < TITLE_X + 10'd88)) begin
                    cur_elem = ELEM_TITLE;
                    cur_fg   = COL_WHITE;
                    cur_char = title_char(mode, title_dx_w[6:3]);
                    cur_row  = title_dy_w[3:0];
                end
            end

            // Field 0 label  y=96..111  (12 chars × 8 = 96 px)
            else if ((pixel_y >= LBL0_Y) && (pixel_y < LBL0_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd96)) begin
                    cur_elem = ELEM_LBL0;
                    cur_fg   = COL_GRAY;
                    cur_char = lbl0_char(mode, lbl_dx_w[6:3]);
                    cur_row  = lbl0_dy_w[3:0];
                end
            end

            // Field 0 value 1x  y=128..143  (8 digits × 8 = 64 px)
            else if ((pixel_y >= VAL0_Y) && (pixel_y < VAL0_Y + 10'd16)) begin
                if ((pixel_x >= FIELD_X) && (pixel_x < FIELD_X + 10'd64)) begin
                    cur_elem = ELEM_VAL0;
                    if (entry_active && !active_field)
                        cur_fg = input_error ? COL_RED : COL_YELLOW;
                    else
                        cur_fg = COL_WHITE;
                    cur_char = f0_bcd_ff[val0_dx_w[5:3]];
                    cur_row  = val0_dy_w[3:0];
                end
            end

            // Field 0 underline  y=144  (blinks when entry_active on field 0)
            else if ((pixel_y == ULINE0_Y) && !active_field &&
                     entry_active && cursor_blink) begin
                if ((pixel_x >= FIELD_X) && (pixel_x < FIELD_X + 10'd64)) begin
                    cur_elem = ELEM_ULINE;
                end
            end

            // Field 1 label (Range only)  y=176..191
            else if ((mode == 2'd0) &&
                     (pixel_y >= LBL1_Y) && (pixel_y < LBL1_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd80)) begin
                    cur_elem = ELEM_LBL1;
                    cur_fg   = COL_GRAY;
                    cur_char = lbl1_char(lbl_dx_w[6:3]);
                    cur_row  = lbl1_dy_w[3:0];
                end
            end

            // Field 1 value (Range only) 1x  y=192..207
            else if ((mode == 2'd0) &&
                     (pixel_y >= VAL1_Y) && (pixel_y < VAL1_Y + 10'd16)) begin
                if ((pixel_x >= FIELD_X) && (pixel_x < FIELD_X + 10'd64)) begin
                    cur_elem = ELEM_VAL1;
                    if (entry_active && active_field)
                        cur_fg = input_error ? COL_RED : COL_YELLOW;
                    else
                        cur_fg = COL_WHITE;
                    cur_char = f1_bcd_ff[val1_dx_w[5:3]];
                    cur_row  = val1_dy_w[3:0];
                end
            end

            // Field 1 underline  y=208  (blinks when entry_active on field 1)
            else if ((mode == 2'd0) &&
                     (pixel_y == ULINE1_Y) && active_field &&
                     entry_active && cursor_blink) begin
                if ((pixel_x >= FIELD_X) && (pixel_x < FIELD_X + 10'd64)) begin
                    cur_elem = ELEM_ULINE;
                end
            end

            // Start button  y=384..399
            else if ((pixel_y >= START_Y_LO) && (pixel_y <= START_Y_HI)) begin
                if ((pixel_x >= START_X_LO) && (pixel_x <= START_X_HI)) begin
                    cur_elem = ELEM_START;
                    cur_fg   = start_hover_w ? COL_NAVY : COL_GREEN;
                    if ((pixel_x >= START_LBL_X) && (pixel_x < START_LBL_X + 10'd112)) begin
                        cur_char = start_char(start_dx_w[6:3]);
                        cur_row  = start_dy_w[3:0];
                    end
                    else begin
                        cur_char = 7'h20;
                        cur_row  = start_dy_w[3:0];
                    end
                end
            end

            // (Divider removed – background stripes show through)

            // Back button  y=432..447
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

    // ---- Stage 1 ----
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

    // ---- Stage 2 ----
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
                ELEM_START: begin
                    if (start_hover_w)
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_NAVY : COL_GREEN;
                    else
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_GREEN : COL_NAVY;
                end
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
