`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// screen_generating.v  —  Live computation / Results screen
//
// All elements 1x (8x16), grid-aligned to 16x16.
//
// Grid layout (new):
//   Row  1 (Y= 16): Top divider
//   Row  4 (Y= 64): "Primes Found:"  + 8-digit count value (inline)
//   Row  6 (Y= 96): "Time Elapsed:"  + HH:MM:SS value       (inline)
//   Row  8 (Y=128): "Last Prime:"    + 8-digit value        (inline)
//   Row 10 (Y=160): "Status:"        + "generating" (red) / "complete" (green)
//   Row 18 (Y=288): "Last 20 Primes Found:" label
//   Row 20-24 (Y=320..399): 4x5 prime grid (5 rows x 16px)
//   Row 25 (Y=400): Divider 2
//   Row 28 (Y=448): Back to Menu button (aborts compute when clicked during run)
//------------------------------------------------------------------------------
module screen_generating (
    input  wire        clk_vga,
    input  wire        resetn,
    input  wire [1:0]  mode,
    input  wire [23:0] prime_count,
    input  wire [26:0] current_n,       // kept for interface stability; unused
    input  wire [12:0] elapsed_sec,
    input  wire        compute_done,
    input  wire [539:0] last_primes,
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,
    output reg         stop_click_ff,
    output wire        sprite_enable_w,
    output reg  [3:0]  pixel_color_ff
);

    localparam COL_NAVY  = 4'h5;
    localparam COL_WHITE = 4'h1;
    localparam COL_GRAY  = 4'h6;
    localparam COL_YELLOW= 4'h7;
    localparam COL_GREEN = 4'h3;
    localparam COL_CYAN  = 4'hA;
    localparam COL_RED   = 4'h2;
    localparam COL_DGRAY = 4'hF;
    localparam COL_LGRAY = 4'h9;

    assign sprite_enable_w = ~compute_done;

    // ---- Back to Menu button hit region ----
    // Renamed from "Stop" for UI consistency with every other screen. The
    // stop_click_ff output name is unchanged so ui_fsm still receives the same
    // pulse (which already aborts compute and navigates back to menu).
    localparam BACK_X_LO = 10'd224;
    localparam BACK_X_HI = 10'd416;
    localparam BACK_Y_LO = 10'd448;
    localparam BACK_Y_HI = 10'd463;

    wire back_hover_w;
    assign back_hover_w = (cursor_x >= BACK_X_LO) && (cursor_x <= BACK_X_HI) &&
                          (cursor_y >= BACK_Y_LO) && (cursor_y <= BACK_Y_HI);

    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            stop_click_ff    <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;
            if (left_btn_prev_ff && !left_btn && back_hover_w)
                stop_click_ff <= 1'b1;
            else
                stop_click_ff <= 1'b0;
        end
    end

    function [26:0] get_prime;
        input [539:0] bus; input [4:0] idx;
        begin get_prime = bus[idx*27 +: 27]; end
    endfunction

    // ---- Label lookups ----
    // "Primes Found:" (13 chars)
    function [6:0] cnt_lbl_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: cnt_lbl_char=7'h50; 4'd1: cnt_lbl_char=7'h72;
                4'd2: cnt_lbl_char=7'h69; 4'd3: cnt_lbl_char=7'h6D;
                4'd4: cnt_lbl_char=7'h65; 4'd5: cnt_lbl_char=7'h73;
                4'd6: cnt_lbl_char=7'h20; 4'd7: cnt_lbl_char=7'h46;
                4'd8: cnt_lbl_char=7'h6F; 4'd9: cnt_lbl_char=7'h75;
                4'd10:cnt_lbl_char=7'h6E; 4'd11:cnt_lbl_char=7'h64;
                4'd12:cnt_lbl_char=7'h3A;
                default: cnt_lbl_char=7'h20;
            endcase
        end
    endfunction

    // "Time Elapsed:" (13 chars)
    function [6:0] time_lbl_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: time_lbl_char=7'h54; 4'd1: time_lbl_char=7'h69;  // Ti
                4'd2: time_lbl_char=7'h6D; 4'd3: time_lbl_char=7'h65;  // me
                4'd4: time_lbl_char=7'h20; 4'd5: time_lbl_char=7'h45;  // ' E'
                4'd6: time_lbl_char=7'h6C; 4'd7: time_lbl_char=7'h61;  // la
                4'd8: time_lbl_char=7'h70; 4'd9: time_lbl_char=7'h73;  // ps
                4'd10:time_lbl_char=7'h65; 4'd11:time_lbl_char=7'h64;  // ed
                4'd12:time_lbl_char=7'h3A;                             // :
                default: time_lbl_char=7'h20;
            endcase
        end
    endfunction

    // "Last Prime:" (11 chars)
    function [6:0] last_lbl_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: last_lbl_char=7'h4C; 4'd1: last_lbl_char=7'h61;  // La
                4'd2: last_lbl_char=7'h73; 4'd3: last_lbl_char=7'h74;  // st
                4'd4: last_lbl_char=7'h20; 4'd5: last_lbl_char=7'h50;  // ' P'
                4'd6: last_lbl_char=7'h72; 4'd7: last_lbl_char=7'h69;  // ri
                4'd8: last_lbl_char=7'h6D; 4'd9: last_lbl_char=7'h65;  // me
                4'd10:last_lbl_char=7'h3A;                             // :
                default: last_lbl_char=7'h20;
            endcase
        end
    endfunction

    // "Last 20 Primes Found:" (21 chars)
    function [6:0] grid_lbl_char;
        input [4:0] col;
        begin
            case(col)
                5'd0: grid_lbl_char=7'h4C; 5'd1: grid_lbl_char=7'h61;  // La
                5'd2: grid_lbl_char=7'h73; 5'd3: grid_lbl_char=7'h74;  // st
                5'd4: grid_lbl_char=7'h20; 5'd5: grid_lbl_char=7'h32;  // ' 2'
                5'd6: grid_lbl_char=7'h30; 5'd7: grid_lbl_char=7'h20;  // '0 '
                5'd8: grid_lbl_char=7'h50; 5'd9: grid_lbl_char=7'h72;  // Pr
                5'd10:grid_lbl_char=7'h69; 5'd11:grid_lbl_char=7'h6D;  // im
                5'd12:grid_lbl_char=7'h65; 5'd13:grid_lbl_char=7'h73;  // es
                5'd14:grid_lbl_char=7'h20; 5'd15:grid_lbl_char=7'h46;  // ' F'
                5'd16:grid_lbl_char=7'h6F; 5'd17:grid_lbl_char=7'h75;  // ou
                5'd18:grid_lbl_char=7'h6E; 5'd19:grid_lbl_char=7'h64;  // nd
                5'd20:grid_lbl_char=7'h3A;                             // :
                default: grid_lbl_char=7'h20;
            endcase
        end
    endfunction

    // "Status:" (7 chars)
    function [6:0] status_lbl_char;
        input [2:0] col;
        begin
            case(col)
                3'd0: status_lbl_char = 7'h53; 3'd1: status_lbl_char = 7'h74;  // St
                3'd2: status_lbl_char = 7'h61; 3'd3: status_lbl_char = 7'h74;  // at
                3'd4: status_lbl_char = 7'h75; 3'd5: status_lbl_char = 7'h73;  // us
                3'd6: status_lbl_char = 7'h3A;                                  // :
                default: status_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Generating" (10 chars)
    function [6:0] gen_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: gen_char = 7'h47; 4'd1: gen_char = 7'h65;  // Ge
                4'd2: gen_char = 7'h6E; 4'd3: gen_char = 7'h65;  // ne
                4'd4: gen_char = 7'h72; 4'd5: gen_char = 7'h61;  // ra
                4'd6: gen_char = 7'h74; 4'd7: gen_char = 7'h69;  // ti
                4'd8: gen_char = 7'h6E; 4'd9: gen_char = 7'h67;  // ng
                default: gen_char = 7'h20;
            endcase
        end
    endfunction

    // "Complete" (8 chars)
    function [6:0] cmp_char;
        input [2:0] col;
        begin
            case(col)
                3'd0: cmp_char = 7'h43; 3'd1: cmp_char = 7'h6F;  // Co
                3'd2: cmp_char = 7'h6D; 3'd3: cmp_char = 7'h70;  // mp
                3'd4: cmp_char = 7'h6C; 3'd5: cmp_char = 7'h65;  // le
                3'd6: cmp_char = 7'h74; default: cmp_char = 7'h65; // te
            endcase
        end
    endfunction

    // "Back to Menu" (12 chars)
    function [6:0] back_char;
        input [3:0] col;
        begin
            case(col)
                4'd0: back_char = 7'h42; 4'd1: back_char = 7'h61;  // Ba
                4'd2: back_char = 7'h63; 4'd3: back_char = 7'h6B;  // ck
                4'd4: back_char = 7'h20; 4'd5: back_char = 7'h74;  // ' t'
                4'd6: back_char = 7'h6F; 4'd7: back_char = 7'h20;  // 'o '
                4'd8: back_char = 7'h4D; 4'd9: back_char = 7'h65;  // Me
                4'd10:back_char = 7'h6E; 4'd11:back_char = 7'h75;  // nu
                default: back_char = 7'h20;
            endcase
        end
    endfunction

    // ---- Pre-computed BCD digit characters (double-dabble, no division) ----
    reg [6:0] cnt_bcd_ff   [0:7];
    reg [6:0] time_bcd_ff  [0:7];
    reg [6:0] prime_bcd_ff [0:255];

    // --- Division-free time conversion (elapsed_sec -> HH:MM:SS ASCII) ---
    wire [1:0]  t_hrs_w = (elapsed_sec >= 13'd7200) ? 2'd2 :
                          (elapsed_sec >= 13'd3600) ? 2'd1 : 2'd0;
    wire [12:0] t_rem_h_w    = elapsed_sec - t_hrs_w * 13'd3600;
    wire [26:0] t_mprod_w    = t_rem_h_w * 15'd17477;     // reciprocal of 60
    wire [5:0]  t_mins_w     = t_mprod_w[25:20];
    wire [12:0] t_sec_full_w = t_rem_h_w - t_mins_w * 7'd60;
    wire [5:0]  t_secs_w     = t_sec_full_w[5:0];
    wire [13:0] mt_prod_w    = t_mins_w * 8'd205;         // reciprocal of 10
    wire [3:0]  m_tens_w     = mt_prod_w[13:11];
    wire [3:0]  m_ones_w     = t_mins_w - m_tens_w * 4'd10;
    wire [13:0] st_prod_w    = t_secs_w * 8'd205;
    wire [3:0]  s_tens_w     = st_prod_w[13:11];
    wire [3:0]  s_ones_w     = t_secs_w - s_tens_w * 4'd10;

    always @(posedge clk_vga) begin
        time_bcd_ff[0] <= 7'h30;
        time_bcd_ff[1] <= 7'h30 + {5'd0, t_hrs_w};
        time_bcd_ff[2] <= 7'h3A;
        time_bcd_ff[3] <= 7'h30 + {3'd0, m_tens_w};
        time_bcd_ff[4] <= 7'h30 + {3'd0, m_ones_w};
        time_bcd_ff[5] <= 7'h3A;
        time_bcd_ff[6] <= 7'h30 + {3'd0, s_tens_w};
        time_bcd_ff[7] <= 7'h30 + {3'd0, s_ones_w};
    end

    // --- BCD converter for count and 20 primes (current_n display removed) ---
    localparam [4:0] SEQ_CNT  = 5'd0;
    localparam [4:0] SEQ_PR0  = 5'd1;
    localparam [4:0] SEQ_LAST = 5'd20;

    reg [4:0]  seq_idx_ff;
    reg        seq_go_ff;
    wire [4:0] pr_slot_w = seq_idx_ff - SEQ_PR0;
    wire [26:0] dd_bin_w = (seq_idx_ff == SEQ_CNT) ? {3'd0, prime_count} :
                           get_prime(last_primes, pr_slot_w);
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
            seq_idx_ff <= 5'd0;
            seq_go_ff  <= 1'b0;
        end else begin
            seq_go_ff <= 1'b0;
            if (dd_done_w) begin
                if (seq_idx_ff == SEQ_CNT) begin
                    cnt_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[28 +: 4]};
                    cnt_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[24 +: 4]};
                    cnt_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[20 +: 4]};
                    cnt_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[16 +: 4]};
                    cnt_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[12 +: 4]};
                    cnt_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[ 8 +: 4]};
                    cnt_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[ 4 +: 4]};
                    cnt_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[ 0 +: 4]};
                end
                else begin
                    prime_bcd_ff[{pr_slot_w, 3'd0}] <= 7'h30 + {3'd0, dd_bcd_w[28 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd1}] <= 7'h30 + {3'd0, dd_bcd_w[24 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd2}] <= 7'h30 + {3'd0, dd_bcd_w[20 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd3}] <= 7'h30 + {3'd0, dd_bcd_w[16 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd4}] <= 7'h30 + {3'd0, dd_bcd_w[12 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd5}] <= 7'h30 + {3'd0, dd_bcd_w[ 8 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd6}] <= 7'h30 + {3'd0, dd_bcd_w[ 4 +: 4]};
                    prime_bcd_ff[{pr_slot_w, 3'd7}] <= 7'h30 + {3'd0, dd_bcd_w[ 0 +: 4]};
                end
                seq_idx_ff <= (seq_idx_ff == SEQ_LAST) ? 5'd0 : seq_idx_ff + 5'd1;
                seq_go_ff  <= 1'b1;
            end else if (dd_ready_w && !seq_go_ff) begin
                seq_go_ff <= 1'b1;
            end
        end
    end

    // ---- Layout constants (grid-aligned) ----
    localparam LBL_X       = 10'd16;
    localparam VAL_X       = 10'd128;   // inline value column (after 13-char label + 1-char gap)
    localparam CNT_Y       = 10'd64;    // Row  4 — "Primes Found: <val>"
    localparam TIME_Y      = 10'd96;    // Row  6 — "Time Elapsed: <val>"
    localparam LAST_Y      = 10'd128;   // Row  8 — "Last Prime:   <val>"
    localparam STATUS_Y    = 10'd160;   // Row 10 — "Status: generating/complete"
    localparam GRID_LBL_X  = 10'd232;   // 21 chars x 8 = 168 px, centered ~((640-168)/2=236) -> 232 for 8-align
    localparam GRID_LBL_Y  = 10'd288;   // Row 18 — "Last 20 Primes Found:"
    localparam GRID_Y      = 10'd320;   // Row 20 — grid top
    localparam DIV2_Y      = 10'd400;   // Row 25 — divider below grid
    localparam GRID_X0     = 10'd16;
    localparam GRID_CW     = 10'd160;
    localparam GRID_RH     = 10'd16;
    localparam BACK_LBL_X  = 10'd272;   // "Back to Menu" 12*8=96px, centered in button (224..416)

    // ---- Element types ----
    localparam ELEM_BG          = 4'd0;
    localparam ELEM_CNT_LBL     = 4'd1;
    localparam ELEM_CNT_VAL     = 4'd2;
    localparam ELEM_TIME_LBL    = 4'd3;
    localparam ELEM_TIME_VAL    = 4'd4;
    localparam ELEM_LAST_LBL    = 4'd5;
    localparam ELEM_LAST_VAL    = 4'd6;
    localparam ELEM_DIV         = 4'd7;
    localparam ELEM_GRID_LBL    = 4'd8;
    localparam ELEM_PRIME       = 4'd9;
    localparam ELEM_BACK        = 4'd10;
    localparam ELEM_STATUS_LBL  = 4'd11;
    localparam ELEM_STATUS_VAL  = 4'd12;

    // ---- Pre-computed offsets ----
    wire [9:0] cnt_lbl_dx_w,    cnt_val_dx_w,    cnt_dy_w;
    wire [9:0] time_lbl_dx_w,   time_val_dx_w,   time_dy_w;
    wire [9:0] last_lbl_dx_w,   last_val_dx_w,   last_dy_w;
    wire [9:0] status_lbl_dx_w, status_val_dx_w, status_dy_w;
    wire [9:0] grid_lbl_dx_w,   grid_lbl_dy_w;
    wire [9:0] grid_dy_w,       grid_dx_w;
    wire [9:0] back_lbl_dx_w,   back_dy_w;

    assign cnt_lbl_dx_w    = pixel_x - LBL_X;
    assign cnt_val_dx_w    = pixel_x - VAL_X;
    assign cnt_dy_w        = pixel_y - CNT_Y;
    assign time_lbl_dx_w   = pixel_x - LBL_X;
    assign time_val_dx_w   = pixel_x - VAL_X;
    assign time_dy_w       = pixel_y - TIME_Y;
    assign last_lbl_dx_w   = pixel_x - LBL_X;
    assign last_val_dx_w   = pixel_x - VAL_X;
    assign last_dy_w       = pixel_y - LAST_Y;
    assign status_lbl_dx_w = pixel_x - LBL_X;
    assign status_val_dx_w = pixel_x - VAL_X;
    assign status_dy_w     = pixel_y - STATUS_Y;
    assign grid_lbl_dx_w   = pixel_x - GRID_LBL_X;
    assign grid_lbl_dy_w   = pixel_y - GRID_LBL_Y;
    assign grid_dy_w       = pixel_y - GRID_Y;
    assign grid_dx_w       = pixel_x - GRID_X0;
    assign back_lbl_dx_w   = pixel_x - BACK_LBL_X;
    assign back_dy_w       = pixel_y - BACK_Y_LO;

    // Grid cell indices
    wire [9:0] grid_row_w, grid_col_w;
    wire [9:0] cell_x_off_w, cell_y_off_w;
    wire [4:0] prime_slot_w;

    assign grid_row_w   = grid_dy_w >> 4;
    assign grid_col_w   = (grid_dx_w >= 10'd480) ? 10'd3 :
                           (grid_dx_w >= 10'd320) ? 10'd2 :
                           (grid_dx_w >= 10'd160) ? 10'd1 : 10'd0;
    assign cell_x_off_w = (grid_col_w[1:0] == 2'd3) ? (grid_dx_w - 10'd480) :
                           (grid_col_w[1:0] == 2'd2) ? (grid_dx_w - 10'd320) :
                           (grid_col_w[1:0] == 2'd1) ? (grid_dx_w - 10'd160) : grid_dx_w;
    assign cell_y_off_w = {6'd0, grid_dy_w[3:0]};
    assign prime_slot_w = (grid_col_w[1:0] * 3'd5) + grid_row_w[2:0];

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

            // Top divider y=16..17
            if ((pixel_y == 10'd16) || (pixel_y == 10'd17)) begin
                cur_elem = ELEM_DIV;
            end

            // "Primes Found: <val>"  y=64..79
            else if ((pixel_y >= CNT_Y) && (pixel_y < CNT_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd104)) begin
                    cur_elem = ELEM_CNT_LBL;
                    cur_fg   = COL_GRAY;
                    cur_char = cnt_lbl_char(cnt_lbl_dx_w[6:3]);
                    cur_row  = cnt_dy_w[3:0];
                end
                else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd64)) begin
                    cur_elem = ELEM_CNT_VAL;
                    cur_fg   = COL_WHITE;
                    cur_char = cnt_bcd_ff[cnt_val_dx_w[5:3]];
                    cur_row  = cnt_dy_w[3:0];
                end
            end

            // "Time Elapsed: <val>"  y=96..111
            else if ((pixel_y >= TIME_Y) && (pixel_y < TIME_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd104)) begin
                    cur_elem = ELEM_TIME_LBL;
                    cur_fg   = COL_GRAY;
                    cur_char = time_lbl_char(time_lbl_dx_w[6:3]);
                    cur_row  = time_dy_w[3:0];
                end
                else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd64)) begin
                    cur_elem = ELEM_TIME_VAL;
                    cur_fg   = compute_done ? COL_GREEN : COL_YELLOW;
                    cur_char = time_bcd_ff[time_val_dx_w[5:3]];
                    cur_row  = time_dy_w[3:0];
                end
            end

            // "Last Prime: <val>"  y=128..143
            else if ((pixel_y >= LAST_Y) && (pixel_y < LAST_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd88)) begin
                    cur_elem = ELEM_LAST_LBL;
                    cur_fg   = COL_GRAY;
                    cur_char = last_lbl_char(last_lbl_dx_w[6:3]);
                    cur_row  = last_dy_w[3:0];
                end
                else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd64)) begin
                    cur_elem = ELEM_LAST_VAL;
                    cur_fg   = COL_LGRAY;
                    cur_char = prime_bcd_ff[{5'd0, last_val_dx_w[5:3]}];
                    cur_row  = last_dy_w[3:0];
                end
            end

            // "Status: generating/complete"  y=160..175
            else if ((pixel_y >= STATUS_Y) && (pixel_y < STATUS_Y + 10'd16)) begin
                if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd56)) begin
                    cur_elem = ELEM_STATUS_LBL;
                    cur_fg   = COL_GRAY;
                    cur_char = status_lbl_char(status_lbl_dx_w[5:3]);
                    cur_row  = status_dy_w[3:0];
                end
                else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd80)) begin
                    // "generating" = 10 chars (80px, red). "complete" = 8 chars (64px, green).
                    cur_elem = ELEM_STATUS_VAL;
                    cur_fg   = compute_done ? COL_GREEN : COL_RED;
                    if (compute_done) begin
                        // "complete" occupies cols 0..7; cols 8..9 are spaces
                        cur_char = (status_val_dx_w < 10'd64) ? cmp_char(status_val_dx_w[5:3])
                                                              : 7'h20;
                    end
                    else begin
                        cur_char = gen_char(status_val_dx_w[6:3]);
                    end
                    cur_row  = status_dy_w[3:0];
                end
            end

            // "Last 20 Primes Found:" label  y=288..303 (21 chars x 8 = 168 px)
            else if ((pixel_y >= GRID_LBL_Y) && (pixel_y < GRID_LBL_Y + 10'd16)) begin
                if ((pixel_x >= GRID_LBL_X) && (pixel_x < GRID_LBL_X + 10'd168)) begin
                    cur_elem = ELEM_GRID_LBL;
                    cur_fg   = COL_GRAY;
                    cur_char = grid_lbl_char(grid_lbl_dx_w[7:3]);
                    cur_row  = grid_lbl_dy_w[3:0];
                end
            end

            // Prime grid  y=320..399 (5 rows x 16 px)
            else if ((pixel_y >= GRID_Y) && (pixel_y < GRID_Y + 10'd80)) begin
                if ((pixel_x >= GRID_X0) && (pixel_x < GRID_X0 + 10'd640)) begin
                    if ((cell_x_off_w < 10'd64) && (cell_y_off_w < 10'd16)) begin
                        cur_elem = ELEM_PRIME;
                        cur_fg   = COL_LGRAY;
                        cur_char = prime_bcd_ff[{prime_slot_w, cell_x_off_w[5:3]}];
                        cur_row  = cell_y_off_w[3:0];
                    end
                end
            end

            // Divider 2  y=400..401
            else if ((pixel_y == DIV2_Y) || (pixel_y == DIV2_Y + 10'd1)) begin
                cur_elem = ELEM_DIV;
            end

            // Back to Menu button  y=448..463
            else if ((pixel_y >= BACK_Y_LO) && (pixel_y <= BACK_Y_HI)) begin
                if ((pixel_x >= BACK_X_LO) && (pixel_x <= BACK_X_HI)) begin
                    cur_elem = ELEM_BACK;
                    cur_fg   = back_hover_w ? COL_NAVY : COL_WHITE;
                    if ((pixel_x >= BACK_LBL_X) && (pixel_x < BACK_LBL_X + 10'd96)) begin
                        cur_char = back_char(back_lbl_dx_w[6:3]);
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
                ELEM_BG:  pixel_color_ff <= COL_NAVY;
                ELEM_DIV: pixel_color_ff <= COL_DGRAY;
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
