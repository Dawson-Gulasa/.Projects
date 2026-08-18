`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// ui_frame_renderer.v
//
// Purpose:
//   Frame rendering engine for the Optimus Prime UI.
//   Replaces frame_renderer_gold in the top-level design.
//
// Architecture — Row-Buffer approach:
//   For each scan row (0..479):
//     Phase 1 — SCAN (644 clocks):
//       Issue all 640 pixel X coordinates to screen_mux sequentially.
//       Starting 4 cycles later (pipeline depth), collect the returned
//       4-bit palette colors and pack them into 40 x 64-bit words stored
//       in a register-based line buffer.
//     Phase 2 — WRITE (40 DDR2 handshakes):
//       Write the 40 buffered words to DDR2 sequentially, waiting for
//       wr_ack between each.
//
//   This completely decouples the screen_mux pipeline from DDR2 write
//   latency, eliminating the corruption caused by the previous streaming
//   approach where variable DDR2 ack timing could pollute the pixel
//   pipeline state.
//
// Pipeline timing (from screen_menu.v / screen_mux.v):
//   Posedge N  : cur_pix_x_ff set (NBA)
//   Posedge N+1: font ROM latches, screen Stage 1 latches
//   Posedge N+2: screen Stage 2 fires (pixel_color_ff valid)
//   Posedge N+3: screen_mux output register fires
//   Posedge N+4: renderer reads smux_pixel_color_w (NBA lag)
//   => Pipeline depth = 4 cycles
//
// Pixel packing: bits[3:0] = pixel 0 (leftmost), bits[63:60] = pixel 15
//
// DDR2 write interface: toggle handshake (wr_req toggles, wr_ack_pulse acks).
// Frame control: frame_renderer_cdc handles ready_toggle / frame_done_ack.
//------------------------------------------------------------------------------
module ui_frame_renderer (
    input  wire        clk_cpu,
    input  wire        resetn,

    //--------------------------------------------------------------------------
    // Frame control (identical interface to frame_renderer_gold)
    //--------------------------------------------------------------------------
    input  wire        ready_toggle,
    output reg         frame_done_req,
    input  wire        frame_done_ack,
    input  wire [26:0] back_buf_base,

    //--------------------------------------------------------------------------
    // DDR2 write port
    //--------------------------------------------------------------------------
    output reg  [26:0] wr_addr,
    output reg  [63:0] wr_data,
    output reg         wr_req,
    input  wire        wr_ack,

    //--------------------------------------------------------------------------
    // UI state inputs (clk_cpu domain, pre-synchronized)
    //--------------------------------------------------------------------------
    input  wire [2:0]  display_mode,
    input  wire [9:0]  cursor_x,
    input  wire [9:0]  cursor_y,
    input  wire        left_btn,
    input  wire [1:0]  mode,
    input  wire [26:0] field0_val,
    input  wire [26:0] field1_val,
    input  wire        active_field,
    input  wire        entry_done,
    input  wire        input_error,
    input  wire        entry_active,
    input  wire        cursor_blink,
    input  wire [23:0] prime_count,
    input  wire [26:0] current_n,
    input  wire [12:0] elapsed_sec,
    input  wire        compute_done,
    input  wire [539:0] last_primes,
    input  wire [26:0] largest_prime,
    input  wire        single_is_prime,
    input  wire        test_running,
    input  wire        test_passed,
    input  wire        test_failed,
    input  wire        no_data_stored,
    input  wire [23:0] primes_checked,
    input  wire [26:0] fail_ddr_val,
    input  wire [26:0] fail_sd_val,

    //--------------------------------------------------------------------------
    // Navigation outputs -> ui_fsm (1-cycle pulses from screen_mux)
    //--------------------------------------------------------------------------
    output wire [1:0]  nav_mode_sel,
    output wire        nav_menu_click,
    output wire        nav_back,
    output wire        nav_start,
    output wire        nav_test_start,
    output wire        nav_stop,
    output wire        nav_error_dismiss,
    output wire        nav_controls,

    // Controls screen practice field
    input  wire [26:0] practice_val,
    input  wire        practice_active,
    input  wire        cursor_blink_ctrl,

    //--------------------------------------------------------------------------
    // Sprite enable -> sprite_ctrl
    //--------------------------------------------------------------------------
    output wire        sprite_enable,

    //--------------------------------------------------------------------------
    // Status
    //--------------------------------------------------------------------------
    output reg         rendering,

    //--------------------------------------------------------------------------
    // Debug outputs (pulse-stretched by caller for LED visibility)
    //--------------------------------------------------------------------------
    output wire        dbg_frame_start,
    output wire        dbg_wr_ack_pulse
);

    //--------------------------------------------------------------------------
    // Constants
    //--------------------------------------------------------------------------
    localparam [14:0] TOTAL_WORDS   = 15'd19200;  // 40 cols x 480 rows
    localparam [5:0]  WORDS_PER_ROW = 6'd40;
    localparam [26:0] ADDR_STEP     = 27'd8;       // bytes per 64-bit word
    localparam [3:0]  PIPE_DEPTH    = 4'd4;         // screen_mux pipeline depth
    localparam [9:0]  SCAN_LEN      = 10'd644;     // 640 issue + 4 drain
    localparam [9:0]  PIXELS_PER_ROW= 10'd640;
    localparam [9:0]  LAST_ROW      = 10'd479;

    //--------------------------------------------------------------------------
    // FSM state encoding
    //--------------------------------------------------------------------------
    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_SCAN   = 3'd1;
    localparam [2:0] S_WRITE  = 3'd2;
    localparam [2:0] S_WR_ACK = 3'd3;

    reg [2:0] state_ff;

    //--------------------------------------------------------------------------
    // Scan position
    //--------------------------------------------------------------------------
    reg [9:0]  scan_cnt_ff;      // 0..643 within S_SCAN
    reg [9:0]  pixel_y_ff;       // 0..479 current scan row
    reg [5:0]  write_idx_ff;     // 0..39 during write phase
    reg [26:0] wr_addr_cnt_ff;   // DDR2 write address, increments through frame

    //--------------------------------------------------------------------------
    // Pixel X driven into screen_mux
    //--------------------------------------------------------------------------
    reg [9:0] cur_pix_x_ff;

    //--------------------------------------------------------------------------
    // 64-bit word accumulator (builds one 16-pixel word at a time)
    //--------------------------------------------------------------------------
    reg [63:0] word_build_ff;

    //--------------------------------------------------------------------------
    // Line buffer: 40 x 64-bit words = one full 640-pixel row
    //--------------------------------------------------------------------------
    reg [63:0] line_buf_ff [0:39];

    //--------------------------------------------------------------------------
    // CDC: convert toggle frame control to one-cycle frame_start pulse
    //--------------------------------------------------------------------------
    wire        frame_start_w;
    wire [26:0] back_base_cdc_w;
    wire        wr_ack_pulse_w;

    frame_renderer_cdc u_frame_renderer_cdc (
        .clk_cpu           (clk_cpu),
        .resetn            (resetn),
        .ready_toggle      (ready_toggle),
        .frame_done_ack    (frame_done_ack),
        .back_buf_base     (back_buf_base),
        .wr_ack            (wr_ack),
        .values_ready      (1'b1),
        .frame_start       (frame_start_w),
        .back_base         (back_base_cdc_w),
        .wr_ack_pulse      (wr_ack_pulse_w),
        .debug_fda_pending (),
        .debug_fda_sync2   ()
    );

    //--------------------------------------------------------------------------
    // Debug output assignments
    //--------------------------------------------------------------------------
    assign dbg_frame_start  = frame_start_w;
    assign dbg_wr_ack_pulse = wr_ack_pulse_w;

    //--------------------------------------------------------------------------
    // Font ROM (shared via screen_mux)
    //--------------------------------------------------------------------------
    wire [6:0] font_char_w;
    wire [3:0] font_row_w;
    wire [7:0] font_pixel_row_w;

    font_rom_ascii u_font_rom_ascii (
        .clk       (clk_cpu),
        .char_code (font_char_w),
        .row       (font_row_w),
        .pixel_row (font_pixel_row_w)
    );

    //--------------------------------------------------------------------------
    // Screen mux
    //--------------------------------------------------------------------------
    wire [3:0] smux_pixel_color_w;

    screen_mux u_screen_mux (
        .clk_vga          (clk_cpu),
        .resetn           (resetn),
        .display_mode     (display_mode),
        .cursor_x         (cursor_x),
        .cursor_y         (cursor_y),
        .left_btn         (left_btn),
        .pixel_x          (cur_pix_x_ff),
        .pixel_y          (pixel_y_ff),
        .pixel_active     (1'b1),
        .mode             (mode),
        .field0_val       (field0_val),
        .field1_val       (field1_val),
        .active_field     (active_field),
        .entry_done       (entry_done),
        .input_error      (input_error),
        .entry_active     (entry_active),
        .cursor_blink     (cursor_blink),
        .prime_count      (prime_count),
        .current_n        (current_n),
        .elapsed_sec      (elapsed_sec),
        .compute_done     (compute_done),
        .last_primes      (last_primes),
        .largest_prime    (largest_prime),
        .single_is_prime  (single_is_prime),
        .test_running     (test_running),
        .test_passed      (test_passed),
        .test_failed      (test_failed),
        .no_data_stored   (no_data_stored),
        .primes_checked   (primes_checked),
        .fail_ddr_val     (fail_ddr_val),
        .fail_sd_val      (fail_sd_val),
        .font_char        (font_char_w),
        .font_row         (font_row_w),
        .font_pixel_row   (font_pixel_row_w),
        .nav_mode_sel     (nav_mode_sel),
        .nav_menu_click   (nav_menu_click),
        .nav_back         (nav_back),
        .nav_start        (nav_start),
        .nav_test_start   (nav_test_start),
        .nav_stop         (nav_stop),
        .nav_error_dismiss(nav_error_dismiss),
        .nav_controls     (nav_controls),
        .practice_val     (practice_val),
        .practice_active  (practice_active),
        .cursor_blink_ctrl(cursor_blink_ctrl),
        .sprite_enable    (sprite_enable),
        .pixel_color      (smux_pixel_color_w)
    );

    //--------------------------------------------------------------------------
    // Collection logic
    //
    // collecting_w   : true when a valid color is arriving from the pipeline
    // collect_x_w    : which pixel (0..639) is being collected
    // collect_word_w : which line_buf word (0..39)
    // collect_nib_w  : which nibble within the word (0..15)
    // word_complete_w: true when the last nibble of a word is being collected
    //--------------------------------------------------------------------------
    wire        collecting_w;
    wire [9:0]  collect_x_w;
    wire [5:0]  collect_word_w;
    wire [3:0]  collect_nib_w;
    wire        word_complete_w;

    assign collecting_w   = (state_ff == S_SCAN) && (scan_cnt_ff >= {6'd0, PIPE_DEPTH});
    assign collect_x_w    = scan_cnt_ff - {6'd0, PIPE_DEPTH};
    assign collect_word_w = collect_x_w[9:4];
    assign collect_nib_w  = collect_x_w[3:0];
    assign word_complete_w= collecting_w && (collect_nib_w == 4'd15);

    //--------------------------------------------------------------------------
    // Combinational word builder
    //
    // Starts from word_build_ff and overwrites one nibble slot when
    // collecting_w is active.
    //--------------------------------------------------------------------------
    reg [63:0] word_build_next;

    always @(*) begin
        word_build_next = word_build_ff;

        if (collecting_w) begin
            case (collect_nib_w)
                4'd0:  word_build_next[3:0]   = smux_pixel_color_w;
                4'd1:  word_build_next[7:4]   = smux_pixel_color_w;
                4'd2:  word_build_next[11:8]  = smux_pixel_color_w;
                4'd3:  word_build_next[15:12] = smux_pixel_color_w;
                4'd4:  word_build_next[19:16] = smux_pixel_color_w;
                4'd5:  word_build_next[23:20] = smux_pixel_color_w;
                4'd6:  word_build_next[27:24] = smux_pixel_color_w;
                4'd7:  word_build_next[31:28] = smux_pixel_color_w;
                4'd8:  word_build_next[35:32] = smux_pixel_color_w;
                4'd9:  word_build_next[39:36] = smux_pixel_color_w;
                4'd10: word_build_next[43:40] = smux_pixel_color_w;
                4'd11: word_build_next[47:44] = smux_pixel_color_w;
                4'd12: word_build_next[51:48] = smux_pixel_color_w;
                4'd13: word_build_next[55:52] = smux_pixel_color_w;
                4'd14: word_build_next[59:56] = smux_pixel_color_w;
                4'd15: word_build_next[63:60] = smux_pixel_color_w;
                default: word_build_next = word_build_ff;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Main FSM (sequential)
    //--------------------------------------------------------------------------
    always @(posedge clk_cpu) begin
        if (!resetn) begin
            state_ff       <= S_IDLE;
            rendering      <= 1'b0;
            frame_done_req <= 1'b0;
            scan_cnt_ff    <= 10'd0;
            pixel_y_ff     <= 10'd0;
            write_idx_ff   <= 6'd0;
            wr_addr_cnt_ff <= 27'd0;
            cur_pix_x_ff   <= 10'd0;
            word_build_ff  <= 64'd0;
            wr_addr        <= 27'd0;
            wr_data        <= 64'd0;
            wr_req         <= 1'b0;
        end
        else begin
            case (state_ff)

                //--------------------------------------------------------------
                // S_IDLE: wait for frame_start from CDC
                //--------------------------------------------------------------
                S_IDLE: begin
                    if (frame_start_w) begin
                        pixel_y_ff     <= 10'd0;
                        scan_cnt_ff    <= 10'd0;
                        wr_addr_cnt_ff <= back_base_cdc_w;
                        word_build_ff  <= 64'd0;
                        rendering      <= 1'b1;
                        state_ff       <= S_SCAN;
                    end
                    else begin
                        rendering <= 1'b0;
                    end
                end

                //--------------------------------------------------------------
                // S_SCAN: scan one row of 640 pixels into line_buf
                //
                // scan_cnt 0..639  : issue pixel X = scan_cnt to screen_mux
                // scan_cnt 640..643: hold pixel X (drain pipeline tail)
                // scan_cnt 4..643  : collect pixel (scan_cnt-4) color
                //
                // Every 16 collected pixels, store completed word to line_buf
                // and clear word_build_ff for the next word.
                //--------------------------------------------------------------
                S_SCAN: begin
                    // --- Pixel issue ---
                    // Top of major if-then-else: issue phase or drain phase?
                    if (scan_cnt_ff < PIXELS_PER_ROW) begin
                        cur_pix_x_ff <= scan_cnt_ff;
                    end
                    // else: hold cur_pix_x_ff (drain phase, implicit)

                    // --- Collection and word building ---
                    // Top of major if-then-else: word boundary?
                    if (word_complete_w) begin
                        line_buf_ff[collect_word_w] <= word_build_next;
                        word_build_ff <= 64'd0;
                    end
                    else if (collecting_w) begin
                        word_build_ff <= word_build_next;
                    end

                    // --- Scan advance ---
                    // Top of major if-then-else: row scan complete?
                    if (scan_cnt_ff == SCAN_LEN - 10'd1) begin
                        write_idx_ff <= 6'd0;
                        state_ff     <= S_WRITE;
                    end
                    else begin
                        scan_cnt_ff <= scan_cnt_ff + 10'd1;
                    end
                end

                //--------------------------------------------------------------
                // S_WRITE: issue DDR2 write for one line_buf word
                //--------------------------------------------------------------
                S_WRITE: begin
                    wr_addr  <= wr_addr_cnt_ff;
                    wr_data  <= line_buf_ff[write_idx_ff];
                    wr_req   <= ~wr_req;
                    state_ff <= S_WR_ACK;
                end

                //--------------------------------------------------------------
                // S_WR_ACK: wait for DDR2 write acknowledge, then advance
                //--------------------------------------------------------------
                S_WR_ACK: begin
                    if (wr_ack_pulse_w) begin
                        // Advance write address for next word
                        wr_addr_cnt_ff <= wr_addr_cnt_ff + ADDR_STEP;

                        // Top of major if-then-else: last word of row?
                        if (write_idx_ff == WORDS_PER_ROW - 6'd1) begin
                            // Top of major if-then-else: last row of frame?
                            if (pixel_y_ff == LAST_ROW) begin
                                rendering      <= 1'b0;
                                frame_done_req <= ~frame_done_req;
                                state_ff       <= S_IDLE;
                            end
                            else begin
                                // Start next row
                                pixel_y_ff    <= pixel_y_ff + 10'd1;
                                scan_cnt_ff   <= 10'd0;
                                word_build_ff <= 64'd0;
                                state_ff      <= S_SCAN;
                            end
                        end
                        else begin
                            // Next word in same row
                            write_idx_ff <= write_idx_ff + 6'd1;
                            state_ff     <= S_WRITE;
                        end
                    end
                    // else: stay in S_WR_ACK (implicit)
                end

                //--------------------------------------------------------------
                // Default: safe recovery
                //--------------------------------------------------------------
                default: begin
                    state_ff  <= S_IDLE;
                    rendering <= 1'b0;
                end

            endcase
        end
    end

endmodule
