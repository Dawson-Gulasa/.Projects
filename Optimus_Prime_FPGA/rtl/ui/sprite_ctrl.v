`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// sprite_ctrl.v
//
// Purpose:
//   Controls the center coordinates for four moving sprites in the project UI.
//
//   Motion is updated only on vsync_pulse so sprite movement stays aligned with
//   VGA frame timing. This prevents the sprites from changing position in the
//   middle of a displayed frame and helps keep motion visually smooth.
//
// Supported motion modes through sprite_mode_in:
//   2'b00 : Default/static positions
//   2'b01 : Ping-pong bounce at diagonal angles
//   2'b10 : Vertical wrap motion
//   2'b11 : Treated as default/static positions
//
// Ping-pong motion algorithm:
//   - Each sprite has an X and Y direction.
//   - On each enabled vsync update, STEP_PIX is added to X and Y.
//   - If the next center position crosses a boundary, the coordinate clamps to
//     the boundary and the corresponding direction reverses.
//
// Example:
//   If x0 is moving left and x0_next_w reaches x_min_c_w, sprite 0 is placed at
//   x_min_c_w and dx0 changes from negative to positive.
//
// Vertical wrap algorithm:
//   - Sprites 0 and 2 move downward.
//   - Sprites 1 and 3 move upward.
//   - When a sprite crosses the top or bottom wrap boundary, it reappears on
//     the opposite side while preserving overshoot.
//
// Example:
//   If y0_wrap_next_w is 461 and y_wrap_max_w is 459, the sprite wraps by
//   subtracting the wrap span instead of simply jumping to the minimum value.
//   This keeps motion smooth even when STEP_PIX causes overshoot.
//
// Notes:
//   - Reset is synchronous and active low.
//   - Heartbeat logic runs continuously in the clk domain.
//   - Sprite motion state changes only on vsync_pulse.
//   - This module is mainly datapath/control logic, not a formal encoded FSM.
//------------------------------------------------------------------------------

module sprite_ctrl #(
    parameter integer CLK_HZ             = 100_000_000, // Clock frequency for heartbeat timing
    parameter integer HB_HZ              = 2,           // Heartbeat blink frequency
    parameter integer MOVE_EVERY_N_VSYNC = 1,           // Move once every N vsync pulses
    parameter integer STEP_PIX           = 2            // Sprite movement step in pixels
)(
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk,              // System clock for sprite motion logic
    input  wire        resetn,           // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Control inputs
    //--------------------------------------------------------------------------
    input  wire [1:0]  sprite_mode_in,   // Selected sprite motion mode
    input  wire        double_size,      // Selects normal or double-size sprite bounds
    input  wire        vsync_pulse,      // One-clock pulse used to update motion per frame

    //--------------------------------------------------------------------------
    // Debug outputs
    //--------------------------------------------------------------------------
    output wire        hb,               // Heartbeat debug signal
    output wire [1:0]  mode_dbg,         // Registered copy of sprite_mode_in

    //--------------------------------------------------------------------------
    // Sprite center coordinate outputs
    //--------------------------------------------------------------------------
    output wire [10:0] x0,               // Sprite 0 center X coordinate
    output wire [9:0]  y0,               // Sprite 0 center Y coordinate
    output wire [10:0] x1,               // Sprite 1 center X coordinate
    output wire [9:0]  y1,               // Sprite 1 center Y coordinate
    output wire [10:0] x2,               // Sprite 2 center X coordinate
    output wire [9:0]  y2,               // Sprite 2 center Y coordinate
    output wire [10:0] x3,               // Sprite 3 center X coordinate
    output wire [9:0]  y3                // Sprite 3 center Y coordinate
);

    //--------------------------------------------------------------------------
    // Default center locations
    //
    // These are the static positions used in default mode and after reset.
    //--------------------------------------------------------------------------
    localparam [10:0] X_DEF_C  = 11'd320; // Default shared X center
    localparam [9:0]  Y0_DEF_C = 10'd64;  // Default Y center for sprite 0
    localparam [9:0]  Y1_DEF_C = 10'd181; // Default Y center for sprite 1
    localparam [9:0]  Y2_DEF_C = 10'd298; // Default Y center for sprite 2
    localparam [9:0]  Y3_DEF_C = 10'd415; // Default Y center for sprite 3

    //--------------------------------------------------------------------------
    // Screen limits
    //
    // Full visible VGA area is 640 by 480 pixels.
    //--------------------------------------------------------------------------
    localparam [9:0] X_PIX_MAX = 10'd639; // Maximum visible X pixel
    localparam [9:0] Y_PIX_MAX = 10'd479; // Maximum visible Y pixel

    //--------------------------------------------------------------------------
    // 20-pixel boundary region
    //
    // Sprite motion is kept inside this inset border region instead of using the
    // absolute screen edges.
    //--------------------------------------------------------------------------
    localparam [9:0] BOUND_MIN   = 10'd19;  // Minimum border coordinate
    localparam [9:0] BOUND_MAX_X = 10'd619; // Maximum X border coordinate
    localparam [9:0] BOUND_MAX_Y = 10'd459; // Maximum Y border coordinate

    //--------------------------------------------------------------------------
    // Sprite dimensions
    //
    // These dimensions are used to compute legal center-coordinate limits.
    //--------------------------------------------------------------------------
    localparam [9:0] W_NRM = 10'd64;  // Normal sprite width
    localparam [9:0] H_NRM = 10'd16;  // Normal sprite height
    localparam [9:0] W_DBL = 10'd128; // Double-size sprite width
    localparam [9:0] H_DBL = 10'd32;  // Double-size sprite height

    //--------------------------------------------------------------------------
    // Wrap-mode motion step
    //--------------------------------------------------------------------------
    localparam integer WRAP_STEP = 2; // Vertical wrap movement step in pixels

    //--------------------------------------------------------------------------
    // Heartbeat divider configuration
    //
    // The heartbeat toggles at HB_HZ using a simple clock divider.
    //--------------------------------------------------------------------------
    localparam integer HB_DIV   = (CLK_HZ / (HB_HZ * 2));
    localparam integer HB_CNT_W = (HB_DIV <= 2) ? 2 : $clog2(HB_DIV);

    //--------------------------------------------------------------------------
    // VSYNC divider width
    //
    // This allows sprite motion to occur every N frames instead of every frame.
    //--------------------------------------------------------------------------
    localparam integer VSYNC_CNT_W = (MOVE_EVERY_N_VSYNC <= 1) ? 1
                                                               : $clog2(MOVE_EVERY_N_VSYNC);

    //--------------------------------------------------------------------------
    // Selected sprite size
    //
    // double_size changes the sprite dimensions, which also changes the legal
    // center-coordinate range.
    //--------------------------------------------------------------------------
    wire [9:0] spr_w_w;  // Active sprite width
    wire [9:0] spr_h_w;  // Active sprite height
    wire [9:0] half_w_w; // Half of active sprite width
    wire [9:0] half_h_w; // Half of active sprite height

    assign spr_w_w  = double_size ? W_DBL : W_NRM;
    assign spr_h_w  = double_size ? H_DBL : H_NRM;
    assign half_w_w = spr_w_w >> 1;
    assign half_h_w = spr_h_w >> 1;

    //--------------------------------------------------------------------------
    // Ping-pong center bounds
    //
    // These bounds keep the entire sprite inside the border region by accounting
    // for half of the sprite width and height.
    //--------------------------------------------------------------------------
    wire [10:0] x_min_c_w; // Minimum allowed sprite center X
    wire [10:0] x_max_c_w; // Maximum allowed sprite center X
    wire [9:0]  y_min_c_w; // Minimum allowed sprite center Y
    wire [9:0]  y_max_c_w; // Maximum allowed sprite center Y

    assign x_min_c_w = half_w_w + BOUND_MIN;
    assign x_max_c_w = BOUND_MAX_X - half_w_w;
    assign y_min_c_w = half_h_w + BOUND_MIN;
    assign y_max_c_w = BOUND_MAX_Y - half_h_w;

    //--------------------------------------------------------------------------
    // Wrap bounds
    //
    // Wrap mode uses the full border region and preserves overshoot using the
    // span between the minimum and maximum wrap coordinates.
    //--------------------------------------------------------------------------
    wire [9:0] y_wrap_min_w;  // Minimum Y coordinate for wrap mode
    wire [9:0] y_wrap_max_w;  // Maximum Y coordinate for wrap mode
    wire [9:0] y_wrap_span_w; // Total vertical span used for wrapping

    assign y_wrap_min_w  = BOUND_MIN;
    assign y_wrap_max_w  = BOUND_MAX_Y;
    assign y_wrap_span_w = y_wrap_max_w - y_wrap_min_w + 10'd1;

    //--------------------------------------------------------------------------
    // Internal registered state
    //
    // These registers hold heartbeat/debug state, sprite positions, and sprite
    // directions.
    //--------------------------------------------------------------------------
    reg               hb_ff;            // Registered heartbeat output
    reg [1:0]         mode_dbg_ff;      // Registered mode debug output

    reg [HB_CNT_W-1:0]    hb_cnt_ff;        // Heartbeat divider counter
    reg [VSYNC_CNT_W-1:0] vsync_div_cnt_ff; // Frame divider counter

    reg [10:0] x0_ff, x1_ff, x2_ff, x3_ff; // Registered sprite X centers
    reg [9:0]  y0_ff, y1_ff, y2_ff, y3_ff; // Registered sprite Y centers

    reg signed [3:0] dx0_ff, dy0_ff; // Sprite 0 signed X/Y direction
    reg signed [3:0] dx1_ff, dy1_ff; // Sprite 1 signed X/Y direction
    reg signed [3:0] dx2_ff, dy2_ff; // Sprite 2 signed X/Y direction
    reg signed [3:0] dx3_ff, dy3_ff; // Sprite 3 signed X/Y direction

    //--------------------------------------------------------------------------
    // Next-state signals
    //
    // These are computed combinationally and loaded into the registered state on
    // the next rising clock edge.
    //--------------------------------------------------------------------------
    reg               hb_n;            // Next heartbeat value
    reg [1:0]         mode_dbg_n;      // Next debug mode value

    reg [HB_CNT_W-1:0]    hb_cnt_n;        // Next heartbeat counter
    reg [VSYNC_CNT_W-1:0] vsync_div_cnt_n; // Next vsync divider counter

    reg [10:0] x0_n, x1_n, x2_n, x3_n; // Next sprite X centers
    reg [9:0]  y0_n, y1_n, y2_n, y3_n; // Next sprite Y centers

    reg signed [3:0] dx0_n, dy0_n; // Next sprite 0 direction
    reg signed [3:0] dx1_n, dy1_n; // Next sprite 1 direction
    reg signed [3:0] dx2_n, dy2_n; // Next sprite 2 direction
    reg signed [3:0] dx3_n, dy3_n; // Next sprite 3 direction

    //--------------------------------------------------------------------------
    // VSYNC motion-step enable
    //
    // do_step_w is high on the vsync pulses where motion should actually update.
    //--------------------------------------------------------------------------
    wire do_step_w; // High when this vsync pulse should move the sprites

    assign do_step_w = (MOVE_EVERY_N_VSYNC <= 1) ? 1'b1
                                                 : (vsync_div_cnt_ff == MOVE_EVERY_N_VSYNC - 1);

    //--------------------------------------------------------------------------
    // Ping-pong next-position math
    //
    // These signed candidate positions are checked against the bounds before
    // being accepted into the next sprite position.
    //--------------------------------------------------------------------------
    wire signed [10:0] x0_next_w, x1_next_w, x2_next_w, x3_next_w; // Candidate X positions
    wire signed [10:0] y0_next_w, y1_next_w, y2_next_w, y3_next_w; // Candidate Y positions

    assign x0_next_w = $signed({1'b0, x0_ff}) + $signed(dx0_ff);
    assign y0_next_w = $signed({1'b0, y0_ff}) + $signed(dy0_ff);

    assign x1_next_w = $signed({1'b0, x1_ff}) + $signed(dx1_ff);
    assign y1_next_w = $signed({1'b0, y1_ff}) + $signed(dy1_ff);

    assign x2_next_w = $signed({1'b0, x2_ff}) + $signed(dx2_ff);
    assign y2_next_w = $signed({1'b0, y2_ff}) + $signed(dy2_ff);

    assign x3_next_w = $signed({1'b0, x3_ff}) + $signed(dx3_ff);
    assign y3_next_w = $signed({1'b0, y3_ff}) + $signed(dy3_ff);

    //--------------------------------------------------------------------------
    // Wrap-mode next-position math
    //
    // Sprites 0 and 2 move down. Sprites 1 and 3 move up. The *_down_w and
    // *_up_w signals preserve overshoot when a sprite crosses a wrap boundary.
    //--------------------------------------------------------------------------
    wire signed [10:0] y0_wrap_next_w, y1_wrap_next_w, y2_wrap_next_w, y3_wrap_next_w;
    wire signed [10:0] y0_wrap_down_w, y1_wrap_up_w, y2_wrap_down_w, y3_wrap_up_w;

    assign y0_wrap_next_w = $signed({1'b0, y0_ff}) + WRAP_STEP;
    assign y2_wrap_next_w = $signed({1'b0, y2_ff}) + WRAP_STEP;
    assign y1_wrap_next_w = $signed({1'b0, y1_ff}) - WRAP_STEP;
    assign y3_wrap_next_w = $signed({1'b0, y3_ff}) - WRAP_STEP;

    assign y0_wrap_down_w = y0_wrap_next_w - $signed({1'b0, y_wrap_span_w});
    assign y2_wrap_down_w = y2_wrap_next_w - $signed({1'b0, y_wrap_span_w});
    assign y1_wrap_up_w   = y1_wrap_next_w + $signed({1'b0, y_wrap_span_w});
    assign y3_wrap_up_w   = y3_wrap_next_w + $signed({1'b0, y_wrap_span_w});

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // All sprite coordinate outputs are driven from registered state.
    //--------------------------------------------------------------------------
    assign hb       = hb_ff;
    assign mode_dbg = mode_dbg_ff;

    assign x0 = x0_ff;
    assign y0 = y0_ff;
    assign x1 = x1_ff;
    assign y1 = y1_ff;
    assign x2 = x2_ff;
    assign y2 = y2_ff;
    assign x3 = x3_ff;
    assign y3 = y3_ff;

    //--------------------------------------------------------------------------
    // Sprite motion next-state logic
    //
    // Default behavior:
    //   - Hold all registered values.
    //   - Run the heartbeat continuously.
    //   - Update sprite motion only on vsync_pulse.
    //--------------------------------------------------------------------------
    always @(*) begin
        //----------------------------------------------------------------------
        // Hold current values by default.
        //----------------------------------------------------------------------
        hb_n            = hb_ff;
        mode_dbg_n      = mode_dbg_ff;

        hb_cnt_n        = hb_cnt_ff;
        vsync_div_cnt_n = vsync_div_cnt_ff;

        x0_n = x0_ff; y0_n = y0_ff;
        x1_n = x1_ff; y1_n = y1_ff;
        x2_n = x2_ff; y2_n = y2_ff;
        x3_n = x3_ff; y3_n = y3_ff;

        dx0_n = dx0_ff; dy0_n = dy0_ff;
        dx1_n = dx1_ff; dy1_n = dy1_ff;
        dx2_n = dx2_ff; dy2_n = dy2_ff;
        dx3_n = dx3_ff; dy3_n = dy3_ff;

        //----------------------------------------------------------------------
        // Capture the current motion mode for debug visibility.
        //----------------------------------------------------------------------
        mode_dbg_n = sprite_mode_in;

        //----------------------------------------------------------------------
        // Heartbeat counter.
        //----------------------------------------------------------------------
        if (hb_cnt_ff == HB_DIV - 1) begin
            hb_cnt_n = {HB_CNT_W{1'b0}};
            hb_n     = ~hb_ff;
        end
        else begin
            hb_cnt_n = hb_cnt_ff + 1'b1;
        end

        //----------------------------------------------------------------------
        // VSYNC-gated motion logic.
        //----------------------------------------------------------------------
        if (vsync_pulse) begin
            //------------------------------------------------------------------
            // Update the optional frame divider for slower sprite movement.
            //------------------------------------------------------------------
            if (MOVE_EVERY_N_VSYNC > 1) begin
                // This frame is a movement frame, so reset the divider.
                if (do_step_w) begin
                    vsync_div_cnt_n = {VSYNC_CNT_W{1'b0}};
                end
                // Not enough frames have passed yet, so keep counting.
                else begin
                    vsync_div_cnt_n = vsync_div_cnt_ff + 1'b1;
                end
            end
            else begin
                vsync_div_cnt_n = vsync_div_cnt_ff;
            end

            //------------------------------------------------------------------
            // Select the active motion mode.
            //------------------------------------------------------------------
            case (sprite_mode_in)

                //==============================================================
                // MODE 1: Ping-pong bounce
                //
                // Each sprite moves diagonally and reverses direction when its
                // center reaches the legal boundary.
                //==============================================================
                2'b01: begin
                    if (do_step_w) begin
                        //------------------------------------------------------
                        // Sprite 0 X bounce.
                        //------------------------------------------------------
                        if (x0_next_w <= $signed({1'b0, x_min_c_w})) begin
                            dx0_n =  STEP_PIX;
                            x0_n  =  x_min_c_w;
                        end
                        else if (x0_next_w >= $signed({1'b0, x_max_c_w})) begin
                            dx0_n = -STEP_PIX;
                            x0_n  =  x_max_c_w;
                        end
                        else begin
                            x0_n  = x0_next_w[10:0];
                        end

                        //------------------------------------------------------
                        // Sprite 0 Y bounce.
                        //------------------------------------------------------
                        if (y0_next_w <= $signed({1'b0, y_min_c_w})) begin
                            dy0_n =  STEP_PIX;
                            y0_n  =  y_min_c_w;
                        end
                        else if (y0_next_w >= $signed({1'b0, y_max_c_w})) begin
                            dy0_n = -STEP_PIX;
                            y0_n  =  y_max_c_w;
                        end
                        else begin
                            y0_n  = y0_next_w[9:0];
                        end

                        //------------------------------------------------------
                        // Sprite 1 X bounce.
                        //------------------------------------------------------
                        if (x1_next_w <= $signed({1'b0, x_min_c_w})) begin
                            dx1_n =  STEP_PIX;
                            x1_n  =  x_min_c_w;
                        end
                        else if (x1_next_w >= $signed({1'b0, x_max_c_w})) begin
                            dx1_n = -STEP_PIX;
                            x1_n  =  x_max_c_w;
                        end
                        else begin
                            x1_n  = x1_next_w[10:0];
                        end

                        //------------------------------------------------------
                        // Sprite 1 Y bounce.
                        //------------------------------------------------------
                        if (y1_next_w <= $signed({1'b0, y_min_c_w})) begin
                            dy1_n =  STEP_PIX;
                            y1_n  =  y_min_c_w;
                        end
                        else if (y1_next_w >= $signed({1'b0, y_max_c_w})) begin
                            dy1_n = -STEP_PIX;
                            y1_n  =  y_max_c_w;
                        end
                        else begin
                            y1_n  = y1_next_w[9:0];
                        end

                        //------------------------------------------------------
                        // Sprite 2 X bounce.
                        //------------------------------------------------------
                        if (x2_next_w <= $signed({1'b0, x_min_c_w})) begin
                            dx2_n =  STEP_PIX;
                            x2_n  =  x_min_c_w;
                        end
                        else if (x2_next_w >= $signed({1'b0, x_max_c_w})) begin
                            dx2_n = -STEP_PIX;
                            x2_n  =  x_max_c_w;
                        end
                        else begin
                            x2_n  = x2_next_w[10:0];
                        end

                        //------------------------------------------------------
                        // Sprite 2 Y bounce.
                        //------------------------------------------------------
                        if (y2_next_w <= $signed({1'b0, y_min_c_w})) begin
                            dy2_n =  STEP_PIX;
                            y2_n  =  y_min_c_w;
                        end
                        else if (y2_next_w >= $signed({1'b0, y_max_c_w})) begin
                            dy2_n = -STEP_PIX;
                            y2_n  =  y_max_c_w;
                        end
                        else begin
                            y2_n  = y2_next_w[9:0];
                        end

                        //------------------------------------------------------
                        // Sprite 3 X bounce.
                        //------------------------------------------------------
                        if (x3_next_w <= $signed({1'b0, x_min_c_w})) begin
                            dx3_n =  STEP_PIX;
                            x3_n  =  x_min_c_w;
                        end
                        else if (x3_next_w >= $signed({1'b0, x_max_c_w})) begin
                            dx3_n = -STEP_PIX;
                            x3_n  =  x_max_c_w;
                        end
                        else begin
                            x3_n  = x3_next_w[10:0];
                        end

                        //------------------------------------------------------
                        // Sprite 3 Y bounce.
                        //------------------------------------------------------
                        if (y3_next_w <= $signed({1'b0, y_min_c_w})) begin
                            dy3_n =  STEP_PIX;
                            y3_n  =  y_min_c_w;
                        end
                        else if (y3_next_w >= $signed({1'b0, y_max_c_w})) begin
                            dy3_n = -STEP_PIX;
                            y3_n  =  y_max_c_w;
                        end
                        else begin
                            y3_n  = y3_next_w[9:0];
                        end
                    end
                end

                //==============================================================
                // MODE 2: Vertical wrap
                //
                // Sprites 0 and 2 move downward. Sprites 1 and 3 move upward.
                // Crossing a wrap boundary moves the sprite to the opposite side.
                //==============================================================
                2'b10: begin
                    if (do_step_w) begin
                        //------------------------------------------------------
                        // Sprites 0 and 2 move down and wrap at the bottom.
                        //------------------------------------------------------
                        if (y0_wrap_next_w > $signed({1'b0, y_wrap_max_w})) begin
                            y0_n = y0_wrap_down_w[9:0];
                        end
                        else begin
                            y0_n = y0_wrap_next_w[9:0];
                        end

                        if (y2_wrap_next_w > $signed({1'b0, y_wrap_max_w})) begin
                            y2_n = y2_wrap_down_w[9:0];
                        end
                        else begin
                            y2_n = y2_wrap_next_w[9:0];
                        end

                        //------------------------------------------------------
                        // Sprites 1 and 3 move up and wrap at the top.
                        //------------------------------------------------------
                        if (y1_wrap_next_w < $signed({1'b0, y_wrap_min_w})) begin
                            y1_n = y1_wrap_up_w[9:0];
                        end
                        else begin
                            y1_n = y1_wrap_next_w[9:0];
                        end

                        if (y3_wrap_next_w < $signed({1'b0, y_wrap_min_w})) begin
                            y3_n = y3_wrap_up_w[9:0];
                        end
                        else begin
                            y3_n = y3_wrap_next_w[9:0];
                        end
                    end
                end

                //==============================================================
                // MODE 0 and MODE 3: Default/static placement
                //
                // Reset all sprites to the centered default layout and restore
                // their starting ping-pong directions.
                //==============================================================
                default: begin
                    x0_n = X_DEF_C; y0_n = Y0_DEF_C;
                    x1_n = X_DEF_C; y1_n = Y1_DEF_C;
                    x2_n = X_DEF_C; y2_n = Y2_DEF_C;
                    x3_n = X_DEF_C; y3_n = Y3_DEF_C;

                    dx0_n = -STEP_PIX; dy0_n = -STEP_PIX;
                    dx1_n =  STEP_PIX; dy1_n = -STEP_PIX;
                    dx2_n = -STEP_PIX; dy2_n =  STEP_PIX;
                    dx3_n =  STEP_PIX; dy3_n =  STEP_PIX;

                    vsync_div_cnt_n = {VSYNC_CNT_W{1'b0}};
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // On reset, sprites return to their default centers and initial diagonal
    // directions. During normal operation, all registers load the next-state
    // values computed above.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset heartbeat, debug state, counters, sprite positions, and directions.
        if (!resetn) begin
            hb_ff            <= 1'b0;
            mode_dbg_ff      <= 2'd0;

            hb_cnt_ff        <= {HB_CNT_W{1'b0}};
            vsync_div_cnt_ff <= {VSYNC_CNT_W{1'b0}};

            x0_ff <= X_DEF_C; y0_ff <= Y0_DEF_C;
            x1_ff <= X_DEF_C; y1_ff <= Y1_DEF_C;
            x2_ff <= X_DEF_C; y2_ff <= Y2_DEF_C;
            x3_ff <= X_DEF_C; y3_ff <= Y3_DEF_C;

            dx0_ff <= -STEP_PIX; dy0_ff <= -STEP_PIX;
            dx1_ff <=  STEP_PIX; dy1_ff <= -STEP_PIX;
            dx2_ff <= -STEP_PIX; dy2_ff <=  STEP_PIX;
            dx3_ff <=  STEP_PIX; dy3_ff <=  STEP_PIX;
        end
        // Normal operation updates all registered sprite-control state.
        else begin
            hb_ff            <= hb_n;
            mode_dbg_ff      <= mode_dbg_n;

            hb_cnt_ff        <= hb_cnt_n;
            vsync_div_cnt_ff <= vsync_div_cnt_n;

            x0_ff <= x0_n; y0_ff <= y0_n;
            x1_ff <= x1_n; y1_ff <= y1_n;
            x2_ff <= x2_n; y2_ff <= y2_n;
            x3_ff <= x3_n; y3_ff <= y3_n;

            dx0_ff <= dx0_n; dy0_ff <= dy0_n;
            dx1_ff <= dx1_n; dy1_ff <= dy1_n;
            dx2_ff <= dx2_n; dy2_ff <= dy2_n;
            dx3_ff <= dx3_n; dy3_ff <= dy3_n;
        end
    end

endmodule