`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// screen_results_error_test.v
//
// Purpose:
//   Contains the three UI screen modules:
//     1) screen_results
//     2) screen_error
//     3) screen_test
//
// Notes:
//   - All rendering is 1x text using the shared 8x16 font ROM.
//   - All screen geometry is grid-aligned.
//   - This file is written in ANSI style and keeps combinational and sequential
//     logic separate.
//   - The SINGLE-mode result layout is handled inside screen_results while
//     RANGE/TIME result behavior is preserved.
//------------------------------------------------------------------------------


//==============================================================================
// screen_results
//
// Purpose:
//   Post-computation results screen.
//
// Supported result layouts:
//   1) RANGE / TIME (matches screen_generating.v layout):
//        - Top divider
//        - "Primes Found:" + count
//        - "Time Elapsed:" + HH:MM:SS
//        - "Last Prime:" + largest prime value
//        - "Last 20 Primes Found:" label
//        - 4x5 last-20-primes grid
//        - Lower divider
//        - Back to Menu button
//
//   2) SINGLE:
//        - "RESULT" title
//        - PASS in green or FAILED in red
//        - "<number> is prime!" or "<number> is not prime!"
//        - elapsed time
//        - back button
//
// Notes:
//   - SINGLE mode uses single_value and removes leading zeros from display.
//   - RANGE/TIME result screen mirrors the generating screen layout so users
//     see the same row positions before and after computation completes.
//==============================================================================
module screen_results (
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk_vga,
    input  wire        resetn,

    //--------------------------------------------------------------------------
    // Mode info
    //--------------------------------------------------------------------------
    input  wire [1:0]  mode,
    input  wire        single_is_prime,
    input  wire [26:0] single_value,

    //--------------------------------------------------------------------------
    // Frozen results
    //--------------------------------------------------------------------------
    input  wire [23:0] prime_count,
    input  wire [12:0] elapsed_sec,
    input  wire [26:0] largest_prime,
    input  wire [539:0] last_primes,

    //--------------------------------------------------------------------------
    // Mouse state
    //--------------------------------------------------------------------------
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,

    //--------------------------------------------------------------------------
    // Pixel scan position
    //--------------------------------------------------------------------------
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,

    //--------------------------------------------------------------------------
    // Font ROM interface
    //--------------------------------------------------------------------------
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,

    //--------------------------------------------------------------------------
    // Navigation
    //--------------------------------------------------------------------------
    output reg         back_click_ff,

    //--------------------------------------------------------------------------
    // Pixel color
    //--------------------------------------------------------------------------
    output reg  [3:0]  pixel_color_ff
);

    //--------------------------------------------------------------------------
    // Palette aliases
    //--------------------------------------------------------------------------
    localparam COL_NAVY  = 4'h5;
    localparam COL_WHITE = 4'h1;
    localparam COL_GRAY  = 4'h6;
    localparam COL_GREEN = 4'h9;
    localparam COL_RED   = 4'h2;
    localparam COL_CYAN  = 4'hA;
    localparam COL_DGRAY = 4'hF;
    localparam COL_LGRAY = 4'h9;

    //--------------------------------------------------------------------------
    // Mode decode
    //--------------------------------------------------------------------------
    wire is_single_mode_w;
    assign is_single_mode_w = (mode == 2'd2);

    //--------------------------------------------------------------------------
    // Back button hit region
    //--------------------------------------------------------------------------
    localparam BACK_X_LO  = 10'd224;
    localparam BACK_X_HI  = 10'd416;
    localparam BACK_Y_LO  = 10'd448;
    localparam BACK_Y_HI  = 10'd463;

    wire back_hover_w;
    assign back_hover_w = (cursor_x >= BACK_X_LO) && (cursor_x <= BACK_X_HI) &&
                          (cursor_y >= BACK_Y_LO) && (cursor_y <= BACK_Y_HI);

    reg left_btn_prev_ff;

    //--------------------------------------------------------------------------
    // Back-button click pulse on mouse release while hovering
    //--------------------------------------------------------------------------
    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            back_click_ff    <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;

            if (left_btn_prev_ff && !left_btn && back_hover_w) begin
                back_click_ff <= 1'b1;
            end
            else begin
                back_click_ff <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Extract one 27-bit prime from the packed last_primes bus
    //--------------------------------------------------------------------------
    function [26:0] get_prime;
        input [539:0] bus;
        input [4:0]   idx;
        begin
            get_prime = bus[idx*27 +: 27];
        end
    endfunction

    //--------------------------------------------------------------------------
    // Character lookup functions
    //--------------------------------------------------------------------------

    // "Primes Found:" (13 chars) - RANGE/TIME label row 1
    function [6:0] cnt_lbl_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  cnt_lbl_char = 7'h50; 4'd1:  cnt_lbl_char = 7'h72;  // Pr
                4'd2:  cnt_lbl_char = 7'h69; 4'd3:  cnt_lbl_char = 7'h6D;  // im
                4'd4:  cnt_lbl_char = 7'h65; 4'd5:  cnt_lbl_char = 7'h73;  // es
                4'd6:  cnt_lbl_char = 7'h20; 4'd7:  cnt_lbl_char = 7'h46;  // ' F'
                4'd8:  cnt_lbl_char = 7'h6F; 4'd9:  cnt_lbl_char = 7'h75;  // ou
                4'd10: cnt_lbl_char = 7'h6E; 4'd11: cnt_lbl_char = 7'h64;  // nd
                4'd12: cnt_lbl_char = 7'h3A;                                // :
                default: cnt_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Time Elapsed:" (13 chars) - RANGE/TIME label row 2
    function [6:0] time_lbl_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  time_lbl_char = 7'h54; 4'd1:  time_lbl_char = 7'h69;  // Ti
                4'd2:  time_lbl_char = 7'h6D; 4'd3:  time_lbl_char = 7'h65;  // me
                4'd4:  time_lbl_char = 7'h20; 4'd5:  time_lbl_char = 7'h45;  // ' E'
                4'd6:  time_lbl_char = 7'h6C; 4'd7:  time_lbl_char = 7'h61;  // la
                4'd8:  time_lbl_char = 7'h70; 4'd9:  time_lbl_char = 7'h73;  // ps
                4'd10: time_lbl_char = 7'h65; 4'd11: time_lbl_char = 7'h64;  // ed
                4'd12: time_lbl_char = 7'h3A;                                 // :
                default: time_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Last Prime:" (11 chars) - RANGE/TIME label row 3 (shows largest_prime)
    function [6:0] last_lbl_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  last_lbl_char = 7'h4C; 4'd1:  last_lbl_char = 7'h61;  // La
                4'd2:  last_lbl_char = 7'h73; 4'd3:  last_lbl_char = 7'h74;  // st
                4'd4:  last_lbl_char = 7'h20; 4'd5:  last_lbl_char = 7'h50;  // ' P'
                4'd6:  last_lbl_char = 7'h72; 4'd7:  last_lbl_char = 7'h69;  // ri
                4'd8:  last_lbl_char = 7'h6D; 4'd9:  last_lbl_char = 7'h65;  // me
                4'd10: last_lbl_char = 7'h3A;                                 // :
                default: last_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Last 20 Primes Found:" (21 chars) - RANGE/TIME table label
    function [6:0] grid_lbl_char;
        input [4:0] col;
        begin
            case (col)
                5'd0:  grid_lbl_char = 7'h4C; 5'd1:  grid_lbl_char = 7'h61;  // La
                5'd2:  grid_lbl_char = 7'h73; 5'd3:  grid_lbl_char = 7'h74;  // st
                5'd4:  grid_lbl_char = 7'h20; 5'd5:  grid_lbl_char = 7'h32;  // ' 2'
                5'd6:  grid_lbl_char = 7'h30; 5'd7:  grid_lbl_char = 7'h20;  // '0 '
                5'd8:  grid_lbl_char = 7'h50; 5'd9:  grid_lbl_char = 7'h72;  // Pr
                5'd10: grid_lbl_char = 7'h69; 5'd11: grid_lbl_char = 7'h6D;  // im
                5'd12: grid_lbl_char = 7'h65; 5'd13: grid_lbl_char = 7'h73;  // es
                5'd14: grid_lbl_char = 7'h20; 5'd15: grid_lbl_char = 7'h46;  // ' F'
                5'd16: grid_lbl_char = 7'h6F; 5'd17: grid_lbl_char = 7'h75;  // ou
                5'd18: grid_lbl_char = 7'h6E; 5'd19: grid_lbl_char = 7'h64;  // nd
                5'd20: grid_lbl_char = 7'h3A;                                 // :
                default: grid_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Status:" (7 chars) - RANGE/TIME status row label
    function [6:0] status_lbl_char;
        input [2:0] col;
        begin
            case (col)
                3'd0: status_lbl_char = 7'h53; 3'd1: status_lbl_char = 7'h74;  // St
                3'd2: status_lbl_char = 7'h61; 3'd3: status_lbl_char = 7'h74;  // at
                3'd4: status_lbl_char = 7'h75; 3'd5: status_lbl_char = 7'h73;  // us
                3'd6: status_lbl_char = 7'h3A;                                  // :
                default: status_lbl_char = 7'h20;
            endcase
        end
    endfunction

    // "Complete" (8 chars) - RANGE/TIME status value (always complete on results)
    function [6:0] cmp_char;
        input [2:0] col;
        begin
            case (col)
                3'd0: cmp_char = 7'h43; 3'd1: cmp_char = 7'h6F;  // Co
                3'd2: cmp_char = 7'h6D; 3'd3: cmp_char = 7'h70;  // mp
                3'd4: cmp_char = 7'h6C; 3'd5: cmp_char = 7'h65;  // le
                3'd6: cmp_char = 7'h74; default: cmp_char = 7'h65;  // te
            endcase
        end
    endfunction

    function [6:0] result_title_char;
        input [2:0] col;
        begin
            case (col)
                3'd0: result_title_char = 7'h52; // R
                3'd1: result_title_char = 7'h45; // E
                3'd2: result_title_char = 7'h53; // S
                3'd3: result_title_char = 7'h55; // U
                3'd4: result_title_char = 7'h4C; // L
                default: result_title_char = 7'h54; // T
            endcase
        end
    endfunction

    function [6:0] pass_char;
        input [1:0] col;
        begin
            case (col)
                2'd0: pass_char = 7'h50; // P
                2'd1: pass_char = 7'h41; // A
                2'd2: pass_char = 7'h53; // S
                default: pass_char = 7'h53; // S
            endcase
        end
    endfunction

    function [6:0] failed_char;
        input [2:0] col;
        begin
            case (col)
                3'd0: failed_char = 7'h46; // F
                3'd1: failed_char = 7'h41; // A
                3'd2: failed_char = 7'h49; // I
                3'd3: failed_char = 7'h4C; // L
                3'd4: failed_char = 7'h45; // E
                default: failed_char = 7'h44; // D
            endcase
        end
    endfunction

    function [6:0] elapsed_char;
        input [2:0] col;
        begin
            case (col)
                3'd0: elapsed_char = 7'h45; // E
                3'd1: elapsed_char = 7'h4C; // L
                3'd2: elapsed_char = 7'h41; // A
                3'd3: elapsed_char = 7'h50; // P
                3'd4: elapsed_char = 7'h53; // S
                3'd5: elapsed_char = 7'h45; // E
                default: elapsed_char = 7'h44; // D
            endcase
        end
    endfunction

    function [6:0] is_prime_suffix_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  is_prime_suffix_char = 7'h20; // _
                4'd1:  is_prime_suffix_char = 7'h69; // i
                4'd2:  is_prime_suffix_char = 7'h73; // s
                4'd3:  is_prime_suffix_char = 7'h20; // _
                4'd4:  is_prime_suffix_char = 7'h70; // p
                4'd5:  is_prime_suffix_char = 7'h72; // r
                4'd6:  is_prime_suffix_char = 7'h69; // i
                4'd7:  is_prime_suffix_char = 7'h6D; // m
                4'd8:  is_prime_suffix_char = 7'h65; // e
                default: is_prime_suffix_char = 7'h21; // !
            endcase
        end
    endfunction

    function [6:0] is_not_prime_suffix_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  is_not_prime_suffix_char = 7'h20; // _
                4'd1:  is_not_prime_suffix_char = 7'h69; // i
                4'd2:  is_not_prime_suffix_char = 7'h73; // s
                4'd3:  is_not_prime_suffix_char = 7'h20; // _
                4'd4:  is_not_prime_suffix_char = 7'h6E; // n
                4'd5:  is_not_prime_suffix_char = 7'h6F; // o
                4'd6:  is_not_prime_suffix_char = 7'h74; // t
                4'd7:  is_not_prime_suffix_char = 7'h20; // _
                4'd8:  is_not_prime_suffix_char = 7'h70; // p
                4'd9:  is_not_prime_suffix_char = 7'h72; // r
                4'd10: is_not_prime_suffix_char = 7'h69; // i
                4'd11: is_not_prime_suffix_char = 7'h6D; // m
                4'd12: is_not_prime_suffix_char = 7'h65; // e
                default: is_not_prime_suffix_char = 7'h21; // !
            endcase
        end
    endfunction

    function [6:0] back_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  back_char = 7'h42; // B
                4'd1:  back_char = 7'h61; // a
                4'd2:  back_char = 7'h63; // c
                4'd3:  back_char = 7'h6B; // k
                4'd4:  back_char = 7'h20; // _
                4'd5:  back_char = 7'h74; // t
                4'd6:  back_char = 7'h6F; // o
                4'd7:  back_char = 7'h20; // _
                4'd8:  back_char = 7'h4D; // M
                4'd9:  back_char = 7'h65; // e
                4'd10: back_char = 7'h6E; // n
                default: back_char = 7'h75; // u
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // BCD digit character storage
    //--------------------------------------------------------------------------
    reg [6:0] cnt_bcd_ff    [0:7];
    reg [6:0] time_bcd_ff   [0:7];
    reg [6:0] lrg_bcd_ff    [0:7];
    reg [6:0] single_bcd_ff [0:7];
    reg [6:0] prime_bcd_ff  [0:255];

    //--------------------------------------------------------------------------
    // Division-free HH:MM:SS conversion for elapsed_sec
    //--------------------------------------------------------------------------
    wire [1:0]  t_hrs_w;
    wire [12:0] t_rem_h_w;
    wire [26:0] t_mprod_w;
    wire [5:0]  t_mins_w;
    wire [12:0] t_sec_full_w;
    wire [5:0]  t_secs_w;
    wire [13:0] mt_prod_w;
    wire [3:0]  m_tens_w;
    wire [3:0]  m_ones_w;
    wire [13:0] st_prod_w;
    wire [3:0]  s_tens_w;
    wire [3:0]  s_ones_w;

    assign t_hrs_w     = (elapsed_sec >= 13'd7200) ? 2'd2 :
                         (elapsed_sec >= 13'd3600) ? 2'd1 : 2'd0;
    assign t_rem_h_w   = elapsed_sec - (t_hrs_w * 13'd3600);
    assign t_mprod_w   = t_rem_h_w * 15'd17477;
    assign t_mins_w    = t_mprod_w[25:20];
    assign t_sec_full_w= t_rem_h_w - (t_mins_w * 7'd60);
    assign t_secs_w    = t_sec_full_w[5:0];
    assign mt_prod_w   = t_mins_w * 8'd205;
    assign m_tens_w    = mt_prod_w[13:11];
    assign m_ones_w    = t_mins_w - (m_tens_w * 4'd10);
    assign st_prod_w   = t_secs_w * 8'd205;
    assign s_tens_w    = st_prod_w[13:11];
    assign s_ones_w    = t_secs_w - (s_tens_w * 4'd10);

    //--------------------------------------------------------------------------
    // Elapsed-time digit refresh
    //--------------------------------------------------------------------------
    always @(posedge clk_vga) begin
        if (!resetn) begin
            time_bcd_ff[0] <= 7'h30;
            time_bcd_ff[1] <= 7'h30;
            time_bcd_ff[2] <= 7'h3A;
            time_bcd_ff[3] <= 7'h30;
            time_bcd_ff[4] <= 7'h30;
            time_bcd_ff[5] <= 7'h3A;
            time_bcd_ff[6] <= 7'h30;
            time_bcd_ff[7] <= 7'h30;
        end
        else begin
            time_bcd_ff[0] <= 7'h30;
            time_bcd_ff[1] <= 7'h30 + {5'd0, t_hrs_w};
            time_bcd_ff[2] <= 7'h3A;
            time_bcd_ff[3] <= 7'h30 + {3'd0, m_tens_w};
            time_bcd_ff[4] <= 7'h30 + {3'd0, m_ones_w};
            time_bcd_ff[5] <= 7'h3A;
            time_bcd_ff[6] <= 7'h30 + {3'd0, s_tens_w};
            time_bcd_ff[7] <= 7'h30 + {3'd0, s_ones_w};
        end
    end

    //--------------------------------------------------------------------------
    // Shared sequential BCD converter schedule:
    //   count -> largest -> single_value -> 20 recent primes
    //--------------------------------------------------------------------------
    localparam [4:0] SEQ_CNT  = 5'd0;
    localparam [4:0] SEQ_LRG  = 5'd1;
    localparam [4:0] SEQ_SNG  = 5'd2;
    localparam [4:0] SEQ_PR0  = 5'd3;
    localparam [4:0] SEQ_LAST = 5'd22;

    reg  [4:0]  seq_idx_ff;
    reg         seq_go_ff;
    wire [4:0]  pr_slot_w;
    wire [26:0] dd_bin_w;
    wire [31:0] dd_bcd_w;
    wire        dd_done_w;
    wire        dd_ready_w;

    assign pr_slot_w = seq_idx_ff - SEQ_PR0;
    assign dd_bin_w  = (seq_idx_ff == SEQ_CNT) ? {3'd0, prime_count} :
                       (seq_idx_ff == SEQ_LRG) ? largest_prime :
                       (seq_idx_ff == SEQ_SNG) ? single_value :
                                                 get_prime(last_primes, pr_slot_w);

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
    // Save BCD results for count / largest / single / prime grid
    //--------------------------------------------------------------------------
    always @(posedge clk_vga) begin
        if (!resetn) begin
            seq_idx_ff <= 5'd0;
            seq_go_ff  <= 1'b0;

            cnt_bcd_ff[0]    <= 7'h30; cnt_bcd_ff[1]    <= 7'h30;
            cnt_bcd_ff[2]    <= 7'h30; cnt_bcd_ff[3]    <= 7'h30;
            cnt_bcd_ff[4]    <= 7'h30; cnt_bcd_ff[5]    <= 7'h30;
            cnt_bcd_ff[6]    <= 7'h30; cnt_bcd_ff[7]    <= 7'h30;

            lrg_bcd_ff[0]    <= 7'h30; lrg_bcd_ff[1]    <= 7'h30;
            lrg_bcd_ff[2]    <= 7'h30; lrg_bcd_ff[3]    <= 7'h30;
            lrg_bcd_ff[4]    <= 7'h30; lrg_bcd_ff[5]    <= 7'h30;
            lrg_bcd_ff[6]    <= 7'h30; lrg_bcd_ff[7]    <= 7'h30;

            single_bcd_ff[0] <= 7'h30; single_bcd_ff[1] <= 7'h30;
            single_bcd_ff[2] <= 7'h30; single_bcd_ff[3] <= 7'h30;
            single_bcd_ff[4] <= 7'h30; single_bcd_ff[5] <= 7'h30;
            single_bcd_ff[6] <= 7'h30; single_bcd_ff[7] <= 7'h30;
        end
        else begin
            seq_go_ff <= 1'b0;

            if (dd_done_w) begin
                if (seq_idx_ff == SEQ_CNT) begin
                    cnt_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    cnt_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    cnt_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    cnt_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    cnt_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    cnt_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    cnt_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    cnt_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end
                else if (seq_idx_ff == SEQ_LRG) begin
                    lrg_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    lrg_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    lrg_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    lrg_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    lrg_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    lrg_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    lrg_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    lrg_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end
                else if (seq_idx_ff == SEQ_SNG) begin
                    single_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    single_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    single_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    single_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    single_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    single_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    single_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    single_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end
                else begin
                    prime_bcd_ff[{pr_slot_w, 3'd0}] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    prime_bcd_ff[{pr_slot_w, 3'd1}] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    prime_bcd_ff[{pr_slot_w, 3'd2}] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    prime_bcd_ff[{pr_slot_w, 3'd3}] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    prime_bcd_ff[{pr_slot_w, 3'd4}] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    prime_bcd_ff[{pr_slot_w, 3'd5}] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    prime_bcd_ff[{pr_slot_w, 3'd6}] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    prime_bcd_ff[{pr_slot_w, 3'd7}] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end

                if (seq_idx_ff == SEQ_LAST) begin
                    seq_idx_ff <= 5'd0;
                end
                else begin
                    seq_idx_ff <= seq_idx_ff + 5'd1;
                end

                seq_go_ff <= 1'b1;
            end
            else if (dd_ready_w && !seq_go_ff) begin
                seq_go_ff <= 1'b1;
            end
            else begin
                seq_go_ff <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Layout constants (RANGE / TIME) - matches screen_generating.v
    //   Row  1 (Y= 16): Top divider
    //   Row  4 (Y= 64): "Primes Found:"  + 8-digit count
    //   Row  6 (Y= 96): "Time Elapsed:"  + HH:MM:SS
    //   Row  8 (Y=128): "Last Prime:"    + 8-digit largest_prime
    //   Row 10 (Y=160): "Status:"        + "complete" (green)
    //   Row 18 (Y=288): "Last 20 Primes Found:" label
    //   Row 20..24 (Y=320..399): 4x5 prime grid
    //   Row 25 (Y=400): Divider 2
    //   Row 28 (Y=448): Back to Menu button
    //--------------------------------------------------------------------------
    localparam [9:0] TOP_DIV_Y       = 10'd16;
    localparam [9:0] LBL_X           = 10'd16;
    localparam [9:0] VAL_X           = 10'd128;   // 13-char label + 1-char gap
    localparam [9:0] CNT_Y           = 10'd64;
    localparam [9:0] TIME_Y          = 10'd96;
    localparam [9:0] LAST_Y          = 10'd128;
    localparam [9:0] STATUS_Y        = 10'd160;   // Row 10 - "Status: complete"
    localparam [9:0] GRID_LBL_X      = 10'd232;   // 21 chars x 8 = 168 px (centered, 8-aligned)
    localparam [9:0] GRID_LBL_Y      = 10'd288;
    localparam [9:0] GRID_Y          = 10'd320;
    localparam [9:0] GRID_X0         = 10'd16;
    localparam [9:0] DIV2_Y          = 10'd400;
    localparam [9:0] BACK_LBL_X      = 10'd272;

    localparam [9:0] SINGLE_TITLE_X  = 10'd296;
    localparam [9:0] SINGLE_TITLE_Y  = 10'd16;
    localparam [9:0] SINGLE_PASS_X   = 10'd304;
    localparam [9:0] SINGLE_FAIL_X   = 10'd296;
    localparam [9:0] SINGLE_RESULT_Y = 10'd176;
    localparam [9:0] SINGLE_ELBL_X   = 10'd256;
    localparam [9:0] SINGLE_ELBL_Y   = 10'd272;
    localparam [9:0] SINGLE_TIME_X   = 10'd320;
    localparam [9:0] SINGLE_TIME_Y   = 10'd272;

    //--------------------------------------------------------------------------
    // Element encoding
    //--------------------------------------------------------------------------
    localparam ELEM_BG            = 5'd0;
    localparam ELEM_CNT_LBL       = 5'd1;
    localparam ELEM_CNT_VAL       = 5'd2;
    localparam ELEM_DIV           = 5'd3;
    localparam ELEM_PRIME         = 5'd4;
    localparam ELEM_BACK          = 5'd5;
    localparam ELEM_SINGLE_TITLE  = 5'd6;
    localparam ELEM_SINGLE_PASS   = 5'd7;
    localparam ELEM_SINGLE_FAIL   = 5'd8;
    localparam ELEM_SINGLE_NUM    = 5'd9;
    localparam ELEM_SINGLE_SUFFIX = 5'd10;
    localparam ELEM_SINGLE_ELBL   = 5'd11;
    localparam ELEM_SINGLE_TIME   = 5'd12;
    localparam ELEM_TIME_LBL      = 5'd13;
    localparam ELEM_TIME_VAL      = 5'd14;
    localparam ELEM_LAST_LBL      = 5'd15;
    localparam ELEM_LAST_VAL      = 5'd16;
    localparam ELEM_GRID_LBL      = 5'd17;
    localparam ELEM_STATUS_LBL    = 5'd18;
    localparam ELEM_STATUS_VAL    = 5'd19;

    //--------------------------------------------------------------------------
    // Offset wires
    //--------------------------------------------------------------------------
    wire [9:0] cnt_lbl_dx_w,    cnt_val_dx_w,    cnt_dy_w;
    wire [9:0] time_lbl_dx_w,   time_val_dx_w,   time_dy_w;
    wire [9:0] last_lbl_dx_w,   last_val_dx_w,   last_dy_w;
    wire [9:0] status_lbl_dx_w, status_val_dx_w, status_dy_w;
    wire [9:0] grid_lbl_dx_w, grid_lbl_dy_w;
    wire [9:0] grid_dy_w;
    wire [9:0] grid_dx_w;
    wire [9:0] back_dy_w;
    wire [9:0] back_lbl_dx_w;

    wire [9:0] single_title_dx_w;
    wire [9:0] single_title_dy_w;
    wire [9:0] single_pass_dx_w;
    wire [9:0] single_fail_dx_w;
    wire [9:0] single_result_dy_w;
    wire [9:0] single_elapsed_dx_w;
    wire [9:0] single_elapsed_dy_w;
    wire [9:0] single_time_dx_w;
    wire [9:0] single_time_dy_w;

    assign cnt_lbl_dx_w       = pixel_x - LBL_X;
    assign cnt_val_dx_w       = pixel_x - VAL_X;
    assign cnt_dy_w           = pixel_y - CNT_Y;
    assign time_lbl_dx_w      = pixel_x - LBL_X;
    assign time_val_dx_w      = pixel_x - VAL_X;
    assign time_dy_w          = pixel_y - TIME_Y;
    assign last_lbl_dx_w      = pixel_x - LBL_X;
    assign last_val_dx_w      = pixel_x - VAL_X;
    assign last_dy_w          = pixel_y - LAST_Y;
    assign status_lbl_dx_w    = pixel_x - LBL_X;
    assign status_val_dx_w    = pixel_x - VAL_X;
    assign status_dy_w        = pixel_y - STATUS_Y;
    assign grid_lbl_dx_w      = pixel_x - GRID_LBL_X;
    assign grid_lbl_dy_w      = pixel_y - GRID_LBL_Y;
    assign grid_dy_w          = pixel_y - GRID_Y;
    assign grid_dx_w          = pixel_x - GRID_X0;
    assign back_dy_w          = pixel_y - BACK_Y_LO;
    assign back_lbl_dx_w      = pixel_x - BACK_LBL_X;

    assign single_title_dx_w  = pixel_x - SINGLE_TITLE_X;
    assign single_title_dy_w  = pixel_y - SINGLE_TITLE_Y;
    assign single_pass_dx_w   = pixel_x - SINGLE_PASS_X;
    assign single_fail_dx_w   = pixel_x - SINGLE_FAIL_X;
    assign single_result_dy_w = pixel_y - SINGLE_RESULT_Y;
    assign single_elapsed_dx_w= pixel_x - SINGLE_ELBL_X;
    assign single_elapsed_dy_w= pixel_y - SINGLE_ELBL_Y;
    assign single_time_dx_w   = pixel_x - SINGLE_TIME_X;
    assign single_time_dy_w   = pixel_y - SINGLE_TIME_Y;

    //--------------------------------------------------------------------------
    // Prime-grid cell breakdown
    //--------------------------------------------------------------------------
    wire [9:0] grid_row_w;
    wire [9:0] grid_col_w;
    wire [9:0] cell_x_off_w;
    wire [9:0] cell_y_off_w;
    wire [4:0] prime_slot_w;

    assign grid_row_w   = grid_dy_w >> 4;
    assign grid_col_w   = (grid_dx_w >= 10'd480) ? 10'd3 :
                          (grid_dx_w >= 10'd320) ? 10'd2 :
                          (grid_dx_w >= 10'd160) ? 10'd1 : 10'd0;
    assign cell_x_off_w = (grid_col_w[1:0] == 2'd3) ? (grid_dx_w - 10'd480) :
                          (grid_col_w[1:0] == 2'd2) ? (grid_dx_w - 10'd320) :
                          (grid_col_w[1:0] == 2'd1) ? (grid_dx_w - 10'd160) :
                                                      grid_dx_w;
    assign cell_y_off_w = {6'd0, grid_dy_w[3:0]};
    assign prime_slot_w = (grid_col_w[1:0] * 3'd5) + grid_row_w[2:0];

    //--------------------------------------------------------------------------
    // SINGLE-mode trimmed-number helpers
    //--------------------------------------------------------------------------
    reg  [2:0] single_first_digit_idx_r;
    reg  [3:0] single_digit_count_r;
    wire [3:0] single_suffix_len_w;
    wire [9:0] single_sentence_width_w;
    wire [9:0] single_sentence_x_w;
    wire [9:0] single_num_x_w;
    wire [9:0] single_suffix_x_w;
    wire [9:0] single_sentence_y_w;
    wire [2:0] single_num_col_w;

    assign single_suffix_len_w     = single_is_prime ? 4'd10 : 4'd14;
    assign single_sentence_width_w = {6'd0, single_digit_count_r, 3'b000} +
                                     {6'd0, single_suffix_len_w, 3'b000};
    //--------------------------------------------------------------------------
    // Center the sentence, then force the X origin onto an 8-pixel boundary so
    // the 8x16 font stays aligned for both odd- and even-length strings.
    //--------------------------------------------------------------------------
    assign single_sentence_x_w     = (((10'd640 - single_sentence_width_w) >> 1) >> 3) << 3;
    assign single_num_x_w          = single_sentence_x_w;
    assign single_suffix_x_w       = single_sentence_x_w + {6'd0, single_digit_count_r, 3'b000};
    assign single_sentence_y_w     = 10'd224;
    assign single_num_col_w        = (pixel_x - single_num_x_w) >> 3;

    //--------------------------------------------------------------------------
    // Find first non-zero digit so the SINGLE result does not show leading zeroes
    //--------------------------------------------------------------------------
    always @(*) begin
        if (single_bcd_ff[0] != 7'h30) begin
            single_first_digit_idx_r = 3'd0;
            single_digit_count_r     = 4'd8;
        end
        else if (single_bcd_ff[1] != 7'h30) begin
            single_first_digit_idx_r = 3'd1;
            single_digit_count_r     = 4'd7;
        end
        else if (single_bcd_ff[2] != 7'h30) begin
            single_first_digit_idx_r = 3'd2;
            single_digit_count_r     = 4'd6;
        end
        else if (single_bcd_ff[3] != 7'h30) begin
            single_first_digit_idx_r = 3'd3;
            single_digit_count_r     = 4'd5;
        end
        else if (single_bcd_ff[4] != 7'h30) begin
            single_first_digit_idx_r = 3'd4;
            single_digit_count_r     = 4'd4;
        end
        else if (single_bcd_ff[5] != 7'h30) begin
            single_first_digit_idx_r = 3'd5;
            single_digit_count_r     = 4'd3;
        end
        else if (single_bcd_ff[6] != 7'h30) begin
            single_first_digit_idx_r = 3'd6;
            single_digit_count_r     = 4'd2;
        end
        else begin
            single_first_digit_idx_r = 3'd7;
            single_digit_count_r     = 4'd1;
        end
    end

    //--------------------------------------------------------------------------
    // Stage 0: combinational element decode
    //--------------------------------------------------------------------------
    reg [4:0] cur_elem;
    reg [3:0] cur_fg;
    reg [6:0] cur_char;
    reg [3:0] cur_row;

    always @(*) begin
        cur_elem = ELEM_BG;
        cur_fg   = COL_WHITE;
        cur_char = 7'h20;
        cur_row  = 4'd0;

        if (pixel_active) begin
            //==================================================================
            // SINGLE mode layout
            //==================================================================
            if (is_single_mode_w) begin
                if ((pixel_y >= SINGLE_TITLE_Y) && (pixel_y < SINGLE_TITLE_Y + 10'd16) &&
                    (pixel_x >= SINGLE_TITLE_X) && (pixel_x < SINGLE_TITLE_X + 10'd48)) begin
                    cur_elem = ELEM_SINGLE_TITLE;
                    cur_fg   = COL_WHITE;
                    cur_char = result_title_char(single_title_dx_w[5:3]);
                    cur_row  = single_title_dy_w[3:0];
                end
                else if (single_is_prime &&
                         (pixel_y >= SINGLE_RESULT_Y) && (pixel_y < SINGLE_RESULT_Y + 10'd16) &&
                         (pixel_x >= SINGLE_PASS_X) && (pixel_x < SINGLE_PASS_X + 10'd32)) begin
                    cur_elem = ELEM_SINGLE_PASS;
                    cur_fg   = COL_GREEN;
                    cur_char = pass_char(single_pass_dx_w[4:3]);
                    cur_row  = single_result_dy_w[3:0];
                end
                else if (!single_is_prime &&
                         (pixel_y >= SINGLE_RESULT_Y) && (pixel_y < SINGLE_RESULT_Y + 10'd16) &&
                         (pixel_x >= SINGLE_FAIL_X) && (pixel_x < SINGLE_FAIL_X + 10'd48)) begin
                    cur_elem = ELEM_SINGLE_FAIL;
                    cur_fg   = COL_WHITE;
                    cur_char = failed_char(single_fail_dx_w[5:3]);
                    cur_row  = single_result_dy_w[3:0];
                end
                else if ((pixel_y >= single_sentence_y_w) && (pixel_y < single_sentence_y_w + 10'd16) &&
                         (pixel_x >= single_num_x_w) &&
                         (pixel_x < single_num_x_w + {6'd0, single_digit_count_r, 3'b000})) begin
                    cur_elem = ELEM_SINGLE_NUM;
                    cur_fg   = COL_GRAY;
                    cur_char = single_bcd_ff[single_first_digit_idx_r + single_num_col_w];
                    cur_row  = pixel_y - single_sentence_y_w;
                end
                else if ((pixel_y >= single_sentence_y_w) && (pixel_y < single_sentence_y_w + 10'd16) &&
                         (pixel_x >= single_suffix_x_w) &&
                         (pixel_x < single_suffix_x_w + {6'd0, single_suffix_len_w, 3'b000})) begin
                    cur_elem = ELEM_SINGLE_SUFFIX;
                    cur_fg   = COL_GRAY;

                    if (single_is_prime) begin
                        cur_char = is_prime_suffix_char((pixel_x - single_suffix_x_w) >> 3);
                    end
                    else begin
                        cur_char = is_not_prime_suffix_char((pixel_x - single_suffix_x_w) >> 3);
                    end

                    cur_row  = pixel_y - single_sentence_y_w;
                end
                else if ((pixel_y >= SINGLE_ELBL_Y) && (pixel_y < SINGLE_ELBL_Y + 10'd16) &&
                         (pixel_x >= SINGLE_ELBL_X) && (pixel_x < SINGLE_ELBL_X + 10'd56)) begin
                    cur_elem = ELEM_SINGLE_ELBL;
                    cur_fg   = COL_GRAY;
                    cur_char = elapsed_char(single_elapsed_dx_w[5:3]);
                    cur_row  = single_elapsed_dy_w[3:0];
                end
                else if ((pixel_y >= SINGLE_TIME_Y) && (pixel_y < SINGLE_TIME_Y + 10'd16) &&
                         (pixel_x >= SINGLE_TIME_X) && (pixel_x < SINGLE_TIME_X + 10'd64)) begin
                    cur_elem = ELEM_SINGLE_TIME;
                    cur_fg   = COL_GREEN;
                    cur_char = time_bcd_ff[single_time_dx_w[5:3]];
                    cur_row  = single_time_dy_w[3:0];
                end
                else if ((pixel_y >= BACK_Y_LO) && (pixel_y <= BACK_Y_HI) &&
                         (pixel_x >= BACK_X_LO) && (pixel_x <= BACK_X_HI)) begin
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

            //==================================================================
            // RANGE / TIME result layout (matches screen_generating.v)
            //==================================================================
            else begin
                // Top divider y=16..17
                if ((pixel_y == TOP_DIV_Y) || (pixel_y == TOP_DIV_Y + 10'd1)) begin
                    cur_elem = ELEM_DIV;
                end
                // "Primes Found: <count>"  y=64..79
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
                // "Time Elapsed: <HH:MM:SS>"  y=96..111
                else if ((pixel_y >= TIME_Y) && (pixel_y < TIME_Y + 10'd16)) begin
                    if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd104)) begin
                        cur_elem = ELEM_TIME_LBL;
                        cur_fg   = COL_GRAY;
                        cur_char = time_lbl_char(time_lbl_dx_w[6:3]);
                        cur_row  = time_dy_w[3:0];
                    end
                    else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd64)) begin
                        cur_elem = ELEM_TIME_VAL;
                        cur_fg   = COL_GREEN;
                        cur_char = time_bcd_ff[time_val_dx_w[5:3]];
                        cur_row  = time_dy_w[3:0];
                    end
                end
                // "Last Prime: <value>"  y=128..143  (shows largest_prime)
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
                        cur_char = lrg_bcd_ff[last_val_dx_w[5:3]];
                        cur_row  = last_dy_w[3:0];
                    end
                end
                // "Status: complete"  y=160..175 (always complete on results)
                else if ((pixel_y >= STATUS_Y) && (pixel_y < STATUS_Y + 10'd16)) begin
                    if ((pixel_x >= LBL_X) && (pixel_x < LBL_X + 10'd56)) begin
                        cur_elem = ELEM_STATUS_LBL;
                        cur_fg   = COL_GRAY;
                        cur_char = status_lbl_char(status_lbl_dx_w[5:3]);
                        cur_row  = status_dy_w[3:0];
                    end
                    else if ((pixel_x >= VAL_X) && (pixel_x < VAL_X + 10'd64)) begin
                        cur_elem = ELEM_STATUS_VAL;
                        cur_fg   = COL_GREEN;
                        cur_char = cmp_char(status_val_dx_w[5:3]);
                        cur_row  = status_dy_w[3:0];
                    end
                end
                // "Last 20 Primes Found:" label  y=288..303
                else if ((pixel_y >= GRID_LBL_Y) && (pixel_y < GRID_LBL_Y + 10'd16)) begin
                    if ((pixel_x >= GRID_LBL_X) && (pixel_x < GRID_LBL_X + 10'd168)) begin
                        cur_elem = ELEM_GRID_LBL;
                        cur_fg   = COL_GRAY;
                        cur_char = grid_lbl_char(grid_lbl_dx_w[7:3]);
                        cur_row  = grid_lbl_dy_w[3:0];
                    end
                end
                // Prime grid  y=320..399 (5 rows x 16 px)
                else if ((pixel_y >= GRID_Y) && (pixel_y < GRID_Y + 10'd80) &&
                         (pixel_x >= GRID_X0) && (pixel_x < GRID_X0 + 10'd640)) begin
                    if ((cell_x_off_w < 10'd64) && (cell_y_off_w < 10'd16)) begin
                        cur_elem = ELEM_PRIME;
                        cur_fg   = COL_LGRAY;
                        cur_char = prime_bcd_ff[{prime_slot_w, cell_x_off_w[5:3]}];
                        cur_row  = cell_y_off_w[3:0];
                    end
                end
                // Divider 2  y=400..401
                else if ((pixel_y == DIV2_Y) || (pixel_y == DIV2_Y + 10'd1)) begin
                    cur_elem = ELEM_DIV;
                end
                else if ((pixel_y >= BACK_Y_LO) && (pixel_y <= BACK_Y_HI) &&
                         (pixel_x >= BACK_X_LO) && (pixel_x <= BACK_X_HI)) begin
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

    //--------------------------------------------------------------------------
    // Drive shared font ROM inputs
    //--------------------------------------------------------------------------
    always @(*) begin
        font_char_ff = cur_char;
        font_row_ff  = cur_row;
    end

    //--------------------------------------------------------------------------
    // Stage 1 pipeline
    //--------------------------------------------------------------------------
    reg [4:0] elem_d1_ff;
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

    //--------------------------------------------------------------------------
    // Stage 2 color output
    //--------------------------------------------------------------------------
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
                ELEM_BG: begin
                    pixel_color_ff <= COL_NAVY;
                end

                ELEM_DIV: begin
                    pixel_color_ff <= COL_DGRAY;
                end

                ELEM_BACK: begin
                    if (back_hover_w) begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_NAVY : COL_CYAN;
                    end
                    else begin
                        pixel_color_ff <= font_pixel_row[bit_sel_w] ? COL_WHITE : COL_NAVY;
                    end
                end

                default: begin
                    pixel_color_ff <= font_pixel_row[bit_sel_w] ? fg_d1_ff : COL_NAVY;
                end
            endcase
        end
    end

endmodule


//==============================================================================
// screen_error
//
// Purpose:
//   Invalid-input error screen.
//
// Behavior:
//   - Shows "INVALID INPUT"
//   - Shows "Click anywhere to try again"
//   - Dismisses on any mouse-release click
//==============================================================================
module screen_error (
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk_vga,
    input  wire        resetn,

    //--------------------------------------------------------------------------
    // Mode input (kept for interface consistency)
    //--------------------------------------------------------------------------
    input  wire [1:0]  mode,

    //--------------------------------------------------------------------------
    // Mouse state
    //--------------------------------------------------------------------------
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,

    //--------------------------------------------------------------------------
    // Pixel scan position
    //--------------------------------------------------------------------------
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,

    //--------------------------------------------------------------------------
    // Font ROM interface
    //--------------------------------------------------------------------------
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,

    //--------------------------------------------------------------------------
    // Navigation output
    //--------------------------------------------------------------------------
    output reg         dismiss_click_ff,

    //--------------------------------------------------------------------------
    // Pixel color
    //--------------------------------------------------------------------------
    output reg  [3:0]  pixel_color_ff
);

    //--------------------------------------------------------------------------
    // Palette aliases
    //--------------------------------------------------------------------------
    localparam COL_NAVY  = 4'h5;
    localparam COL_RED   = 4'h2;
    localparam COL_GRAY  = 4'h6;
    localparam COL_WHITE = 4'h1;

    //--------------------------------------------------------------------------
    // Dismiss on any left-button release
    //--------------------------------------------------------------------------
    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            dismiss_click_ff <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;

            if (left_btn_prev_ff && !left_btn) begin
                dismiss_click_ff <= 1'b1;
            end
            else begin
                dismiss_click_ff <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Character lookup functions
    //--------------------------------------------------------------------------
    function [6:0] err_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  err_char = 7'h49; // I
                4'd1:  err_char = 7'h4E; // N
                4'd2:  err_char = 7'h56; // V
                4'd3:  err_char = 7'h41; // A
                4'd4:  err_char = 7'h4C; // L
                4'd5:  err_char = 7'h49; // I
                4'd6:  err_char = 7'h44; // D
                4'd7:  err_char = 7'h20; // _
                4'd8:  err_char = 7'h49; // I
                4'd9:  err_char = 7'h4E; // N
                4'd10: err_char = 7'h50; // P
                4'd11: err_char = 7'h55; // U
                default: err_char = 7'h54; // T
            endcase
        end
    endfunction

    function [6:0] hint_char;
        input [4:0] col;
        begin
            case (col)
                5'd0:  hint_char = 7'h43; // C
                5'd1:  hint_char = 7'h6C; // l
                5'd2:  hint_char = 7'h69; // i
                5'd3:  hint_char = 7'h63; // c
                5'd4:  hint_char = 7'h6B; // k
                5'd5:  hint_char = 7'h20; // _
                5'd6:  hint_char = 7'h61; // a
                5'd7:  hint_char = 7'h6E; // n
                5'd8:  hint_char = 7'h79; // y
                5'd9:  hint_char = 7'h77; // w
                5'd10: hint_char = 7'h68; // h
                5'd11: hint_char = 7'h65; // e
                5'd12: hint_char = 7'h72; // r
                5'd13: hint_char = 7'h65; // e
                5'd14: hint_char = 7'h20; // _
                5'd15: hint_char = 7'h74; // t
                5'd16: hint_char = 7'h6F; // o
                5'd17: hint_char = 7'h20; // _
                5'd18: hint_char = 7'h74; // t
                5'd19: hint_char = 7'h72; // r
                5'd20: hint_char = 7'h79; // y
                5'd21: hint_char = 7'h20; // _
                5'd22: hint_char = 7'h61; // a
                5'd23: hint_char = 7'h67; // g
                5'd24: hint_char = 7'h61; // a
                5'd25: hint_char = 7'h69; // i
                default: hint_char = 7'h6E; // n
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Layout constants
    //--------------------------------------------------------------------------
    localparam [9:0] ERR_X  = 10'd272;
    localparam [9:0] ERR_Y  = 10'd192;
    localparam [9:0] HINT_X = 10'd208;
    localparam [9:0] HINT_Y = 10'd272;

    localparam ELEM_BG   = 3'd0;
    localparam ELEM_ERR  = 3'd1;
    localparam ELEM_HINT = 3'd2;

    wire [9:0] err_dx_w;
    wire [9:0] err_dy_w;
    wire [9:0] hint_dx_w;
    wire [9:0] hint_dy_w;

    assign err_dx_w  = pixel_x - ERR_X;
    assign err_dy_w  = pixel_y - ERR_Y;
    assign hint_dx_w = pixel_x - HINT_X;
    assign hint_dy_w = pixel_y - HINT_Y;

    //--------------------------------------------------------------------------
    // Stage 0 decode
    //--------------------------------------------------------------------------
    reg [2:0] cur_elem;
    reg [3:0] cur_fg;
    reg [6:0] cur_char;
    reg [3:0] cur_row;

    always @(*) begin
        cur_elem = ELEM_BG;
        cur_fg   = COL_WHITE;
        cur_char = 7'h20;
        cur_row  = 4'd0;

        if (pixel_active) begin
            if ((pixel_y >= ERR_Y) && (pixel_y < ERR_Y + 10'd16) &&
                (pixel_x >= ERR_X) && (pixel_x < ERR_X + 10'd104)) begin
                cur_elem = ELEM_ERR;
                cur_fg   = COL_RED;
                cur_char = err_char(err_dx_w[6:3]);
                cur_row  = err_dy_w[3:0];
            end
            else if ((pixel_y >= HINT_Y) && (pixel_y < HINT_Y + 10'd16) &&
                     (pixel_x >= HINT_X) && (pixel_x < HINT_X + 10'd216)) begin
                cur_elem = ELEM_HINT;
                cur_fg   = COL_GRAY;
                cur_char = hint_char(hint_dx_w[7:3]);
                cur_row  = hint_dy_w[3:0];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Drive shared font ROM inputs
    //--------------------------------------------------------------------------
    always @(*) begin
        font_char_ff = cur_char;
        font_row_ff  = cur_row;
    end

    //--------------------------------------------------------------------------
    // Stage 1 pipeline
    //--------------------------------------------------------------------------
    reg [2:0] elem_d1_ff;
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

    //--------------------------------------------------------------------------
    // Stage 2 color output
    //--------------------------------------------------------------------------
    wire [2:0] err_bit_sel_w;
    assign err_bit_sel_w = 3'd7 - px_d1_ff[2:0];

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

                ELEM_ERR,
                ELEM_HINT: begin
                    pixel_color_ff <= font_pixel_row[err_bit_sel_w] ? fg_d1_ff : COL_NAVY;
                end

                default: begin
                    pixel_color_ff <= COL_NAVY;
                end
            endcase
        end
    end

endmodule


//==============================================================================
// screen_test
//
// Purpose:
//   Test-mode screen.
//
// Supported phases:
//   1) Idle:
//        - "Test Mode"
//        - Start Test button
//        - Back button
//
//   2) Running:
//        - "Testing..."
//        - Checks count
//
//   3) Result:
//        - PASSED + checks count
//        - FAILED + DDR2 / SD mismatch values
//        - NO DATA STORED YET!
//==============================================================================
module screen_test (
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk_vga,
    input  wire        resetn,

    //--------------------------------------------------------------------------
    // Test state inputs
    //--------------------------------------------------------------------------
    input  wire        test_running,
    input  wire        test_passed,
    input  wire        test_failed,
    input  wire        no_data_stored,
    input  wire [23:0] primes_checked,
    input  wire [26:0] fail_ddr_val,
    input  wire [26:0] fail_sd_val,

    //--------------------------------------------------------------------------
    // Mouse state
    //--------------------------------------------------------------------------
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,

    //--------------------------------------------------------------------------
    // Pixel scan position
    //--------------------------------------------------------------------------
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        pixel_active,

    //--------------------------------------------------------------------------
    // Font ROM interface
    //--------------------------------------------------------------------------
    output reg  [6:0]  font_char_ff,
    output reg  [3:0]  font_row_ff,
    input  wire [7:0]  font_pixel_row,

    //--------------------------------------------------------------------------
    // Navigation outputs
    //--------------------------------------------------------------------------
    output reg         start_click_ff,
    output reg         back_click_ff,

    //--------------------------------------------------------------------------
    // Pixel color
    //--------------------------------------------------------------------------
    output reg  [3:0]  pixel_color_ff
);

    //--------------------------------------------------------------------------
    // Palette aliases
    //--------------------------------------------------------------------------
    localparam COL_NAVY   = 4'h5;
    localparam COL_WHITE  = 4'h1;
    localparam COL_GRAY   = 4'h6;
    localparam COL_YELLOW = 4'h7;
    localparam COL_CYAN   = 4'hA;
    localparam COL_RED    = 4'h2;
    localparam COL_GREEN  = 4'h9;

    //--------------------------------------------------------------------------
    // Button geometry
    //--------------------------------------------------------------------------
    localparam START_X_LO = 10'd224;
    localparam START_X_HI = 10'd416;
    localparam START_Y_LO = 10'd384;
    localparam START_Y_HI = 10'd399;

    localparam BACK_X_LO  = 10'd224;
    localparam BACK_X_HI  = 10'd416;
    localparam BACK_Y_LO  = 10'd432;
    localparam BACK_Y_HI  = 10'd447;

    wire start_hover_w;
    wire back_hover_w;

    assign start_hover_w = (cursor_x >= START_X_LO) && (cursor_x <= START_X_HI) &&
                           (cursor_y >= START_Y_LO) && (cursor_y <= START_Y_HI);

    assign back_hover_w  = (cursor_x >= BACK_X_LO) && (cursor_x <= BACK_X_HI) &&
                           (cursor_y >= BACK_Y_LO) && (cursor_y <= BACK_Y_HI);

    //--------------------------------------------------------------------------
    // Click pulse generation
    //--------------------------------------------------------------------------
    reg left_btn_prev_ff;

    always @(posedge clk_vga) begin
        if (!resetn) begin
            left_btn_prev_ff <= 1'b0;
            start_click_ff   <= 1'b0;
            back_click_ff    <= 1'b0;
        end
        else begin
            left_btn_prev_ff <= left_btn;

            if (left_btn_prev_ff && !left_btn && start_hover_w && !test_running) begin
                start_click_ff <= 1'b1;
            end
            else begin
                start_click_ff <= 1'b0;
            end

            if (left_btn_prev_ff && !left_btn && back_hover_w) begin
                back_click_ff <= 1'b1;
            end
            else begin
                back_click_ff <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Character lookup functions
    //--------------------------------------------------------------------------
    function [6:0] test_mode_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  test_mode_char = 7'h54; // T
                4'd1:  test_mode_char = 7'h65; // e
                4'd2:  test_mode_char = 7'h73; // s
                4'd3:  test_mode_char = 7'h74; // t
                4'd4:  test_mode_char = 7'h20; // _
                4'd5:  test_mode_char = 7'h4D; // M
                4'd6:  test_mode_char = 7'h6F; // o
                4'd7:  test_mode_char = 7'h64; // d
                default: test_mode_char = 7'h65; // e
            endcase
        end
    endfunction

    function [6:0] start_test_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  start_test_char = 7'h53; // S
                4'd1:  start_test_char = 7'h74; // t
                4'd2:  start_test_char = 7'h61; // a
                4'd3:  start_test_char = 7'h72; // r
                4'd4:  start_test_char = 7'h74; // t
                4'd5:  start_test_char = 7'h20; // _
                4'd6:  start_test_char = 7'h54; // T
                4'd7:  start_test_char = 7'h65; // e
                4'd8:  start_test_char = 7'h73; // s
                4'd9:  start_test_char = 7'h74; // t
                default: start_test_char = 7'h21; // !
            endcase
        end
    endfunction

    function [6:0] back_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  back_char = 7'h42; // B
                4'd1:  back_char = 7'h61; // a
                4'd2:  back_char = 7'h63; // c
                4'd3:  back_char = 7'h6B; // k
                4'd4:  back_char = 7'h20; // _
                4'd5:  back_char = 7'h74; // t
                4'd6:  back_char = 7'h6F; // o
                4'd7:  back_char = 7'h20; // _
                4'd8:  back_char = 7'h4D; // M
                4'd9:  back_char = 7'h65; // e
                4'd10: back_char = 7'h6E; // n
                default: back_char = 7'h75; // u
            endcase
        end
    endfunction

    function [6:0] testing_char;
        input [3:0] col;
        begin
            case (col)
                4'd0:  testing_char = 7'h54; // T
                4'd1:  testing_char = 7'h65; // e
                4'd2:  testing_char = 7'h73; // s
                4'd3:  testing_char = 7'h74; // t
                4'd4:  testing_char = 7'h69; // i
                4'd5:  testing_char = 7'h6E; // n
                4'd6:  testing_char = 7'h67; // g
                4'd7:  testing_char = 7'h2E; // .
                4'd8:  testing_char = 7'h2E; // .
                default: testing_char = 7'h2E; // .
            endcase
        end
    endfunction

    function [6:0] checks_char;
        input [2:0] col;
        begin
            case (col)
                3'd0:  checks_char = 7'h43; // C
                3'd1:  checks_char = 7'h68; // h
                3'd2:  checks_char = 7'h65; // e
                3'd3:  checks_char = 7'h63; // c
                3'd4:  checks_char = 7'h6B; // k
                3'd5:  checks_char = 7'h73; // s
                default: checks_char = 7'h3A; // :
            endcase
        end
    endfunction

    function [6:0] passed_char;
        input [2:0] col;
        begin
            case (col)
                3'd0:  passed_char = 7'h50; // P
                3'd1:  passed_char = 7'h41; // A
                3'd2:  passed_char = 7'h53; // S
                3'd3:  passed_char = 7'h53; // S
                3'd4:  passed_char = 7'h45; // E
                default: passed_char = 7'h44; // D
            endcase
        end
    endfunction

    function [6:0] failed_char;
        input [2:0] col;
        begin
            case (col)
                3'd0:  failed_char = 7'h46; // F
                3'd1:  failed_char = 7'h41; // A
                3'd2:  failed_char = 7'h49; // I
                3'd3:  failed_char = 7'h4C; // L
                3'd4:  failed_char = 7'h45; // E
                default: failed_char = 7'h44; // D
            endcase
        end
    endfunction

    function [6:0] ddr_lbl_char;
        input [2:0] col;
        begin
            case (col)
                3'd0:  ddr_lbl_char = 7'h44; // D
                3'd1:  ddr_lbl_char = 7'h44; // D
                3'd2:  ddr_lbl_char = 7'h52; // R
                3'd3:  ddr_lbl_char = 7'h32; // 2
                default: ddr_lbl_char = 7'h3A; // :
            endcase
        end
    endfunction

    function [6:0] sd_lbl_char;
        input [1:0] col;
        begin
            case (col)
                2'd0:  sd_lbl_char = 7'h53; // S
                2'd1:  sd_lbl_char = 7'h44; // D
                default: sd_lbl_char = 7'h3A; // :
            endcase
        end
    endfunction

    function [6:0] no_data_char;
        input [4:0] col;
        begin
            case (col)
                5'd0:  no_data_char = 7'h4E; // N
                5'd1:  no_data_char = 7'h4F; // O
                5'd2:  no_data_char = 7'h20; // _
                5'd3:  no_data_char = 7'h44; // D
                5'd4:  no_data_char = 7'h41; // A
                5'd5:  no_data_char = 7'h54; // T
                5'd6:  no_data_char = 7'h41; // A
                5'd7:  no_data_char = 7'h20; // _
                5'd8:  no_data_char = 7'h53; // S
                5'd9:  no_data_char = 7'h54; // T
                5'd10: no_data_char = 7'h4F; // O
                5'd11: no_data_char = 7'h52; // R
                5'd12: no_data_char = 7'h45; // E
                5'd13: no_data_char = 7'h44; // D
                5'd14: no_data_char = 7'h20; // _
                5'd15: no_data_char = 7'h59; // Y
                5'd16: no_data_char = 7'h45; // E
                5'd17: no_data_char = 7'h54; // T
                default: no_data_char = 7'h21; // !
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Pre-computed BCD arrays
    //--------------------------------------------------------------------------
    reg [6:0] chk_bcd_ff [0:7];
    reg [6:0] ddr_bcd_ff [0:7];
    reg [6:0] sd_bcd_ff  [0:7];

    localparam [1:0] SEQ_CHK = 2'd0;
    localparam [1:0] SEQ_DDR = 2'd1;
    localparam [1:0] SEQ_SD  = 2'd2;

    reg  [1:0]  seq_idx_ff;
    reg         seq_go_ff;
    wire [26:0] dd_bin_w;
    wire [31:0] dd_bcd_w;
    wire        dd_done_w;
    wire        dd_ready_w;

    assign dd_bin_w = (seq_idx_ff == SEQ_CHK) ? {3'd0, primes_checked} :
                      (seq_idx_ff == SEQ_DDR) ? fail_ddr_val :
                                                fail_sd_val;

    bin2bcd_seq u_bcd (
        .clk   (clk_vga),
        .rst_n (resetn),
        .bin   (dd_bin_w),
        .start (seq_go_ff),
        .bcd   (dd_bcd_w),
        .done  (dd_done_w),
        .ready (dd_ready_w)
    );

    always @(posedge clk_vga) begin
        if (!resetn) begin
            seq_idx_ff <= 2'd0;
            seq_go_ff  <= 1'b0;

            chk_bcd_ff[0] <= 7'h30; chk_bcd_ff[1] <= 7'h30;
            chk_bcd_ff[2] <= 7'h30; chk_bcd_ff[3] <= 7'h30;
            chk_bcd_ff[4] <= 7'h30; chk_bcd_ff[5] <= 7'h30;
            chk_bcd_ff[6] <= 7'h30; chk_bcd_ff[7] <= 7'h30;

            ddr_bcd_ff[0] <= 7'h30; ddr_bcd_ff[1] <= 7'h30;
            ddr_bcd_ff[2] <= 7'h30; ddr_bcd_ff[3] <= 7'h30;
            ddr_bcd_ff[4] <= 7'h30; ddr_bcd_ff[5] <= 7'h30;
            ddr_bcd_ff[6] <= 7'h30; ddr_bcd_ff[7] <= 7'h30;

            sd_bcd_ff[0]  <= 7'h30; sd_bcd_ff[1]  <= 7'h30;
            sd_bcd_ff[2]  <= 7'h30; sd_bcd_ff[3]  <= 7'h30;
            sd_bcd_ff[4]  <= 7'h30; sd_bcd_ff[5]  <= 7'h30;
            sd_bcd_ff[6]  <= 7'h30; sd_bcd_ff[7]  <= 7'h30;
        end
        else begin
            seq_go_ff <= 1'b0;

            if (dd_done_w) begin
                if (seq_idx_ff == SEQ_CHK) begin
                    chk_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    chk_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    chk_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    chk_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    chk_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    chk_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    chk_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    chk_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end
                else if (seq_idx_ff == SEQ_DDR) begin
                    ddr_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    ddr_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    ddr_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    ddr_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    ddr_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    ddr_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    ddr_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    ddr_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end
                else begin
                    sd_bcd_ff[0] <= 7'h30 + {3'd0, dd_bcd_w[31:28]};
                    sd_bcd_ff[1] <= 7'h30 + {3'd0, dd_bcd_w[27:24]};
                    sd_bcd_ff[2] <= 7'h30 + {3'd0, dd_bcd_w[23:20]};
                    sd_bcd_ff[3] <= 7'h30 + {3'd0, dd_bcd_w[19:16]};
                    sd_bcd_ff[4] <= 7'h30 + {3'd0, dd_bcd_w[15:12]};
                    sd_bcd_ff[5] <= 7'h30 + {3'd0, dd_bcd_w[11:8]};
                    sd_bcd_ff[6] <= 7'h30 + {3'd0, dd_bcd_w[7:4]};
                    sd_bcd_ff[7] <= 7'h30 + {3'd0, dd_bcd_w[3:0]};
                end

                if (seq_idx_ff == SEQ_SD) begin
                    seq_idx_ff <= 2'd0;
                end
                else begin
                    seq_idx_ff <= seq_idx_ff + 2'd1;
                end

                seq_go_ff <= 1'b1;
            end
            else if (dd_ready_w && !seq_go_ff) begin
                seq_go_ff <= 1'b1;
            end
            else begin
                seq_go_ff <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Layout constants
    //--------------------------------------------------------------------------
    localparam TITLE_X      = 10'd288;
    localparam TITLE_Y      = 10'd16;
    localparam STATUS_X     = 10'd280;
    localparam STATUS_Y     = 10'd144;
    localparam CHECKS_LBL_X = 10'd248;
    localparam CHECKS_VAL_X = 10'd320;
    localparam CHECKS_Y     = 10'd96;
    localparam RESULT_X     = 10'd296;
    localparam RESULT_Y     = 10'd192;
    localparam NODATA_X     = 10'd240;
    localparam NODATA_Y     = 10'd192;
    localparam DDR_LBL_X    = 10'd184;
    localparam DDR_LBL_Y    = 10'd256;
    localparam DDR_VAL_X    = 10'd296;
    localparam DDR_VAL_Y    = 10'd256;
    localparam SD_LBL_X     = 10'd184;
    localparam SD_LBL_Y     = 10'd304;
    localparam SD_VAL_X     = 10'd296;
    localparam SD_VAL_Y     = 10'd304;
    localparam START_LBL_X  = 10'd272;
    localparam BACK_LBL_X   = 10'd272;

    //--------------------------------------------------------------------------
    // Element encoding
    //--------------------------------------------------------------------------
    localparam ELEM_BG        = 4'd0;
    localparam ELEM_TITLE     = 4'd1;
    localparam ELEM_STATUS    = 4'd2;
    localparam ELEM_CHECKSLBL = 4'd3;
    localparam ELEM_CHECKSVAL = 4'd4;
    localparam ELEM_PASS      = 4'd5;
    localparam ELEM_FAIL      = 4'd6;
    localparam ELEM_NODATA    = 4'd7;
    localparam ELEM_DDRLBL    = 4'd8;
    localparam ELEM_DDRVAL    = 4'd9;
    localparam ELEM_SDLBL     = 4'd10;
    localparam ELEM_SDVAL     = 4'd11;
    localparam ELEM_START     = 4'd12;
    localparam ELEM_BACK      = 4'd13;

    //--------------------------------------------------------------------------
    // Offsets
    //--------------------------------------------------------------------------
    wire [9:0] title_dx_w;
    wire [9:0] title_dy_w;
    wire [9:0] status_dx_w;
    wire [9:0] status_dy_w;
    wire [9:0] checks_lbl_dx_w;
    wire [9:0] checks_val_dx_w;
    wire [9:0] checks_dy_w;
    wire [9:0] result_dx_w;
    wire [9:0] result_dy_w;
    wire [9:0] nodata_dx_w;
    wire [9:0] nodata_dy_w;
    wire [9:0] ddr_lbl_dx_w;
    wire [9:0] ddr_lbl_dy_w;
    wire [9:0] ddr_val_dx_w;
    wire [9:0] ddr_val_dy_w;
    wire [9:0] sd_lbl_dx_w;
    wire [9:0] sd_lbl_dy_w;
    wire [9:0] sd_val_dx_w;
    wire [9:0] sd_val_dy_w;
    wire [9:0] start_lbl_dx_w;
    wire [9:0] start_lbl_dy_w;
    wire [9:0] back_lbl_dx_w;
    wire [9:0] back_lbl_dy_w;

    assign title_dx_w      = pixel_x - TITLE_X;
    assign title_dy_w      = pixel_y - TITLE_Y;
    assign status_dx_w     = pixel_x - STATUS_X;
    assign status_dy_w     = pixel_y - STATUS_Y;
    assign checks_lbl_dx_w = pixel_x - CHECKS_LBL_X;
    assign checks_val_dx_w = pixel_x - CHECKS_VAL_X;
    assign checks_dy_w     = pixel_y - CHECKS_Y;
    assign result_dx_w     = pixel_x - RESULT_X;
    assign result_dy_w     = pixel_y - RESULT_Y;
    assign nodata_dx_w     = pixel_x - NODATA_X;
    assign nodata_dy_w     = pixel_y - NODATA_Y;
    assign ddr_lbl_dx_w    = pixel_x - DDR_LBL_X;
    assign ddr_lbl_dy_w    = pixel_y - DDR_LBL_Y;
    assign ddr_val_dx_w    = pixel_x - DDR_VAL_X;
    assign ddr_val_dy_w    = pixel_y - DDR_VAL_Y;
    assign sd_lbl_dx_w     = pixel_x - SD_LBL_X;
    assign sd_lbl_dy_w     = pixel_y - SD_LBL_Y;
    assign sd_val_dx_w     = pixel_x - SD_VAL_X;
    assign sd_val_dy_w     = pixel_y - SD_VAL_Y;
    assign start_lbl_dx_w  = pixel_x - START_LBL_X;
    assign start_lbl_dy_w  = pixel_y - START_Y_LO;
    assign back_lbl_dx_w   = pixel_x - BACK_LBL_X;
    assign back_lbl_dy_w   = pixel_y - BACK_Y_LO;

    //--------------------------------------------------------------------------
    // Stage 0 decode
    //--------------------------------------------------------------------------
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
            if ((pixel_y >= TITLE_Y) && (pixel_y < TITLE_Y + 10'd16) &&
                (pixel_x >= TITLE_X) && (pixel_x < TITLE_X + 10'd72)) begin
                cur_elem = ELEM_TITLE;
                cur_fg   = COL_WHITE;
                cur_char = test_mode_char(title_dx_w[6:3]);
                cur_row  = title_dy_w[3:0];
            end
            else if ((test_running || test_passed) &&
                     (pixel_y >= CHECKS_Y) && (pixel_y < CHECKS_Y + 10'd16) &&
                     (pixel_x >= CHECKS_LBL_X) && (pixel_x < CHECKS_LBL_X + 10'd56)) begin
                cur_elem = ELEM_CHECKSLBL;
                cur_fg   = COL_GRAY;
                cur_char = checks_char(checks_lbl_dx_w[5:3]);
                cur_row  = checks_dy_w[3:0];
            end
            else if ((test_running || test_passed) &&
                     (pixel_y >= CHECKS_Y) && (pixel_y < CHECKS_Y + 10'd16) &&
                     (pixel_x >= CHECKS_VAL_X) && (pixel_x < CHECKS_VAL_X + 10'd64)) begin
                cur_elem = ELEM_CHECKSVAL;
                cur_fg   = COL_WHITE;
                cur_char = chk_bcd_ff[checks_val_dx_w[5:3]];
                cur_row  = checks_dy_w[3:0];
            end
            else if (test_running &&
                     (pixel_y >= STATUS_Y) && (pixel_y < STATUS_Y + 10'd16) &&
                     (pixel_x >= STATUS_X) && (pixel_x < STATUS_X + 10'd80)) begin
                cur_elem = ELEM_STATUS;
                cur_fg   = COL_GRAY;
                cur_char = testing_char(status_dx_w[6:3]);
                cur_row  = status_dy_w[3:0];
            end
            else if (test_passed &&
                     (pixel_y >= RESULT_Y) && (pixel_y < RESULT_Y + 10'd16) &&
                     (pixel_x >= RESULT_X) && (pixel_x < RESULT_X + 10'd48)) begin
                cur_elem = ELEM_PASS;
                cur_fg   = COL_GREEN;
                cur_char = passed_char(result_dx_w[5:3]);
                cur_row  = result_dy_w[3:0];
            end
            else if (test_failed && !no_data_stored &&
                     (pixel_y >= RESULT_Y) && (pixel_y < RESULT_Y + 10'd16) &&
                     (pixel_x >= RESULT_X) && (pixel_x < RESULT_X + 10'd48)) begin
                cur_elem = ELEM_FAIL;
                cur_fg   = COL_WHITE;
                cur_char = failed_char(result_dx_w[5:3]);
                cur_row  = result_dy_w[3:0];
            end
            else if (no_data_stored &&
                     (pixel_y >= NODATA_Y) && (pixel_y < NODATA_Y + 10'd16) &&
                     (pixel_x >= NODATA_X) && (pixel_x < NODATA_X + 10'd152)) begin
                cur_elem = ELEM_NODATA;
                cur_fg   = COL_WHITE;
                cur_char = no_data_char(nodata_dx_w[7:3]);
                cur_row  = nodata_dy_w[3:0];
            end
            else if (test_failed && !no_data_stored &&
                     (pixel_y >= DDR_LBL_Y) && (pixel_y < DDR_LBL_Y + 10'd16) &&
                     (pixel_x >= DDR_LBL_X) && (pixel_x < DDR_LBL_X + 10'd40)) begin
                cur_elem = ELEM_DDRLBL;
                cur_fg   = COL_GRAY;
                cur_char = ddr_lbl_char(ddr_lbl_dx_w[5:3]);
                cur_row  = ddr_lbl_dy_w[3:0];
            end
            else if (test_failed && !no_data_stored &&
                     (pixel_y >= DDR_VAL_Y) && (pixel_y < DDR_VAL_Y + 10'd16) &&
                     (pixel_x >= DDR_VAL_X) && (pixel_x < DDR_VAL_X + 10'd64)) begin
                cur_elem = ELEM_DDRVAL;
                cur_fg   = COL_WHITE;
                cur_char = ddr_bcd_ff[ddr_val_dx_w[5:3]];
                cur_row  = ddr_val_dy_w[3:0];
            end
            else if (test_failed && !no_data_stored &&
                     (pixel_y >= SD_LBL_Y) && (pixel_y < SD_LBL_Y + 10'd16) &&
                     (pixel_x >= SD_LBL_X) && (pixel_x < SD_LBL_X + 10'd24)) begin
                cur_elem = ELEM_SDLBL;
                cur_fg   = COL_GRAY;
                cur_char = sd_lbl_char(sd_lbl_dx_w[4:3]);
                cur_row  = sd_lbl_dy_w[3:0];
            end
            else if (test_failed && !no_data_stored &&
                     (pixel_y >= SD_VAL_Y) && (pixel_y < SD_VAL_Y + 10'd16) &&
                     (pixel_x >= SD_VAL_X) && (pixel_x < SD_VAL_X + 10'd64)) begin
                cur_elem = ELEM_SDVAL;
                cur_fg   = COL_YELLOW;
                cur_char = sd_bcd_ff[sd_val_dx_w[5:3]];
                cur_row  = sd_val_dy_w[3:0];
            end
            else if (!test_running && !test_passed && !test_failed &&
                     (pixel_y >= START_Y_LO) && (pixel_y <= START_Y_HI) &&
                     (pixel_x >= START_X_LO) && (pixel_x <= START_X_HI)) begin
                cur_elem = ELEM_START;
                cur_fg   = start_hover_w ? COL_NAVY : COL_GREEN;

                if ((pixel_x >= START_LBL_X) && (pixel_x < START_LBL_X + 10'd88)) begin
                    cur_char = start_test_char(start_lbl_dx_w[6:3]);
                    cur_row  = start_lbl_dy_w[3:0];
                end
                else begin
                    cur_char = 7'h20;
                    cur_row  = start_lbl_dy_w[3:0];
                end
            end
            else if ((pixel_y >= BACK_Y_LO) && (pixel_y <= BACK_Y_HI) &&
                     (pixel_x >= BACK_X_LO) && (pixel_x <= BACK_X_HI)) begin
                cur_elem = ELEM_BACK;
                cur_fg   = back_hover_w ? COL_NAVY : COL_WHITE;

                if ((pixel_x >= BACK_LBL_X) && (pixel_x < BACK_LBL_X + 10'd96)) begin
                    cur_char = back_char(back_lbl_dx_w[6:3]);
                    cur_row  = back_lbl_dy_w[3:0];
                end
                else begin
                    cur_char = 7'h20;
                    cur_row  = back_lbl_dy_w[3:0];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Drive shared font ROM inputs
    //--------------------------------------------------------------------------
    always @(*) begin
        font_char_ff = cur_char;
        font_row_ff  = cur_row;
    end

    //--------------------------------------------------------------------------
    // Stage 1 pipeline
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // Stage 2 color output
    //--------------------------------------------------------------------------
    wire [2:0] test_bit_sel_w;
    assign test_bit_sel_w = 3'd7 - px_d1_ff[2:0];

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

                ELEM_START: begin
                    if (start_hover_w) begin
                        pixel_color_ff <= font_pixel_row[test_bit_sel_w] ? COL_NAVY : COL_GREEN;
                    end
                    else begin
                        pixel_color_ff <= font_pixel_row[test_bit_sel_w] ? COL_GREEN : COL_NAVY;
                    end
                end

                ELEM_BACK: begin
                    if (back_hover_w) begin
                        pixel_color_ff <= font_pixel_row[test_bit_sel_w] ? COL_NAVY : COL_CYAN;
                    end
                    else begin
                        pixel_color_ff <= font_pixel_row[test_bit_sel_w] ? COL_WHITE : COL_NAVY;
                    end
                end

                default: begin
                    pixel_color_ff <= font_pixel_row[test_bit_sel_w] ? fg_d1_ff : COL_NAVY;
                end
            endcase
        end
    end

endmodule