`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// param_entry.v
//
// Purpose:
//   Handles numeric parameter entry for the Params screen and the practice
//   entry field on the Controls screen.
//
//   This module combines mouse selection and keypad input. The user clicks a
//   value box to activate editing, then enters decimal digits using the keypad.
//   The packed BCD digit buffers are continuously converted into binary values
//   for the rest of the system.
//
// User input behavior:
//   - Click field 0 or field 1 on the Params screen to edit that field.
//   - Click the practice field on the Controls screen to edit the practice value.
//   - Keypad 0-9 appends digits calculator-style.
//   - Key B performs backspace.
//   - Key C clears the active field.
//   - Clicking outside the editable region deactivates entry.
//
// Packed digit-buffer algorithm:
//   Each editable value is stored as 8 packed BCD digits in a 32-bit vector:
//
//      [31:28] = leftmost digit / most significant digit
//      [ 3: 0] = rightmost digit / least significant digit
//
//   Insert digit example:
//      old buffer = 00000012
//      press 3
//      new buffer = 00000123
//
//   Packed operation:
//      dig_v <= {dig_v[27:0], key_code}
//
//   Backspace example:
//      old buffer = 00000123
//      press B
//      new buffer = 00000012
//
//   Packed operation:
//      dig_v <= {4'd0, dig_v[31:4]}
//
// BCD-to-binary conversion:
//   The converter continuously cycles through field0, field1, and practice.
//   Horner's method is used:
//
//      result = (((d0 * 10 + d1) * 10 + d2) ...)
//
//   Multiply-by-10 is implemented using shifts:
//
//      value * 10 = (value << 3) + (value << 1)
//
// Notes:
//   - Clock domain: clk, normally clk_cpu at 100 MHz.
//   - No runtime for-loops are used in the clocked digit-editing logic.
//   - This module contains a small conversion FSM for the BCD-to-binary refresh.
//------------------------------------------------------------------------------

module param_entry (
    input  wire        clk,              // CPU/system clock
    input  wire        resetn,           // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Current UI state from ui_fsm
    //--------------------------------------------------------------------------
    input  wire [1:0]  mode,             // Current mode selection; field1 active only in Range mode
    input  wire [2:0]  display_mode,     // Current screen selected by UI FSM

    //--------------------------------------------------------------------------
    // Keypad input from input controller
    //--------------------------------------------------------------------------
    input  wire        key_press,        // One-clock pulse when a new keypad key is accepted
    input  wire [3:0]  key_code,         // Decoded keypad value, 0 through F

    //--------------------------------------------------------------------------
    // Mouse input in clk domain
    //--------------------------------------------------------------------------
    input  wire [9:0]  cursor_x,         // Current mouse cursor X coordinate
    input  wire [9:0]  cursor_y,         // Current mouse cursor Y coordinate
    input  wire        left_click_pulse, // One-clock pulse when left mouse click is accepted

    //--------------------------------------------------------------------------
    // Binary field value outputs
    //--------------------------------------------------------------------------
    output reg  [26:0] field0_val,       // Binary value for Params field 0
    output reg  [26:0] field1_val,       // Binary value for Params field 1
    output reg         active_field,     // Active Params field: 0 = field0, 1 = field1
    output reg         entry_active,     // High while a Params field is being edited
    output wire        cursor_blink,     // Slow blink signal used by renderer for text cursor

    //--------------------------------------------------------------------------
    // Practice field outputs for Controls screen
    //--------------------------------------------------------------------------
    output reg  [26:0] practice_val,     // Binary value for Controls practice field
    output reg         practice_active   // High while Controls practice field is being edited
);

    // -------------------------------------------------------------------------
    // Screen constants
    //
    // These values match the display_mode encoding from ui_fsm.
    // -------------------------------------------------------------------------
    localparam SCREEN_PARAMS   = 3'd1;   // Parameter-entry screen
    localparam SCREEN_CONTROLS = 3'd6;   // Controls/practice screen

    // -------------------------------------------------------------------------
    // Params screen click hit regions
    //
    // These coordinates must match the value-box locations drawn in the Params
    // screen renderer.
    // -------------------------------------------------------------------------
    localparam FIELD_X_LO = 10'd160;     // Left edge of Params value boxes
    localparam FIELD_X_HI = 10'd223;     // Right edge of Params value boxes
    localparam F0_Y_LO    = 10'd128;     // Top edge of field 0 box
    localparam F0_Y_HI    = 10'd143;     // Bottom edge of field 0 box
    localparam F1_Y_LO    = 10'd192;     // Top edge of field 1 box
    localparam F1_Y_HI    = 10'd207;     // Bottom edge of field 1 box

    // -------------------------------------------------------------------------
    // Packed BCD digit buffers
    //
    // Each buffer stores up to eight decimal digits. The count registers track
    // how many digits are currently valid in each buffer.
    // -------------------------------------------------------------------------
    reg [31:0] f0_dig_v;                 // Packed BCD digits for Params field 0
    reg [31:0] f1_dig_v;                 // Packed BCD digits for Params field 1
    reg [31:0] pr_dig_v;                 // Packed BCD digits for practice field
    reg [3:0]  f0_cnt;                   // Number of digits entered in field 0
    reg [3:0]  f1_cnt;                   // Number of digits entered in field 1
    reg [3:0]  pr_cnt;                   // Number of digits entered in practice field

    // -------------------------------------------------------------------------
    // Params screen click-region detection
    //
    // Field 1 is only selectable in Range mode because other modes use only one
    // numeric parameter.
    // -------------------------------------------------------------------------
    wire in_f0_w = (cursor_x >= FIELD_X_LO) && (cursor_x <= FIELD_X_HI) &&
                   (cursor_y >= F0_Y_LO)    && (cursor_y <= F0_Y_HI);

    wire in_f1_w = (cursor_x >= FIELD_X_LO) && (cursor_x <= FIELD_X_HI) &&
                   (cursor_y >= F1_Y_LO)    && (cursor_y <= F1_Y_HI) &&
                   (mode == 2'd0);

    // -------------------------------------------------------------------------
    // Controls screen practice-field hit region
    //
    // The practice field sits on the Controls screen next to the "Try it out!"
    // label.
    // -------------------------------------------------------------------------
    localparam PRAC_X_LO = 10'd368;      // Left edge of practice value box
    localparam PRAC_X_HI = 10'd431;      // Right edge of practice value box
    localparam PRAC_Y_LO = 10'd240;      // Top edge of practice value box
    localparam PRAC_Y_HI = 10'd255;      // Bottom edge of practice value box

    wire in_prac_w = (cursor_x >= PRAC_X_LO) && (cursor_x <= PRAC_X_HI) &&
                     (cursor_y >= PRAC_Y_LO) && (cursor_y <= PRAC_Y_HI);

    // -------------------------------------------------------------------------
    // Screen-transition detection
    //
    // The digit buffers are cleared when the user first enters Params or
    // Controls. prev_dm_ff stores the previous screen so rising entry into each
    // screen can be detected.
    // -------------------------------------------------------------------------
    reg [2:0] prev_dm_ff;                // Previous display mode

    wire entered_params_w   = (display_mode == SCREEN_PARAMS) &&
                              (prev_dm_ff   != SCREEN_PARAMS);

    wire entered_controls_w = (display_mode == SCREEN_CONTROLS) &&
                              (prev_dm_ff   != SCREEN_CONTROLS);

    always @(posedge clk) begin
        // Reset previous-display tracking to Menu/default.
        if (!resetn)
            prev_dm_ff <= 3'd0;
        // Track the current display mode for next-cycle transition detection.
        else
            prev_dm_ff <= display_mode;
    end

    // -------------------------------------------------------------------------
    // Cursor blink generator
    //
    // At 100 MHz, toggling every 25,000,000 cycles gives a 2 Hz blink toggle.
    // -------------------------------------------------------------------------
    reg [24:0] blink_cnt_ff;             // Counter for blink timing
    reg        blink_ff;                 // Registered blink output

    always @(posedge clk) begin
        // Clear blink timing during reset.
        if (!resetn) begin
            blink_cnt_ff <= 25'd0;
            blink_ff     <= 1'b0;
        end
        // Toggle blink state after the programmed half-period.
        else if (blink_cnt_ff == 25'd24_999_999) begin
            blink_cnt_ff <= 25'd0;
            blink_ff     <= ~blink_ff;
        end
        // Normal blink counter increment.
        else begin
            blink_cnt_ff <= blink_cnt_ff + 25'd1;
        end
    end

    assign cursor_blink = blink_ff;

    // -------------------------------------------------------------------------
    // Key classification
    //
    // Only digits, B, and C are used by this module:
    //   0-9 = append decimal digit
    //   B   = backspace
    //   C   = clear active field
    // -------------------------------------------------------------------------
    wire key_is_digit_w = key_press && (key_code <= 4'h9);       // Accepted key is 0-9
    wire key_is_bksp_w  = key_press && (key_code == 4'hB);       // Accepted key is B/backspace
    wire key_is_clear_w = key_press && (key_code == 4'hC);       // Accepted key is C/clear

    wire key_accept_w   = ((display_mode == SCREEN_PARAMS)   && entry_active) ||
                          ((display_mode == SCREEN_CONTROLS) && practice_active);

    // -------------------------------------------------------------------------
    // Digit entry and mouse-click handling
    //
    // This block handles screen-entry clearing, field activation/deactivation,
    // and packed BCD digit edits from keypad input.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset all digit buffers, counts, and entry-active flags.
        if (!resetn) begin
            f0_dig_v        <= 32'd0;
            f1_dig_v        <= 32'd0;
            pr_dig_v        <= 32'd0;
            f0_cnt          <= 4'd0;
            f1_cnt          <= 4'd0;
            pr_cnt          <= 4'd0;
            entry_active    <= 1'b0;
            active_field    <= 1'b0;
            practice_active <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Clear Params fields on the first cycle after entering Params.
            //------------------------------------------------------------------
            if (entered_params_w) begin
                f0_dig_v     <= 32'd0;
                f1_dig_v     <= 32'd0;
                f0_cnt       <= 4'd0;
                f1_cnt       <= 4'd0;
                entry_active <= 1'b0;
                active_field <= 1'b0;
            end

            //------------------------------------------------------------------
            // Clear the practice field on the first cycle after entering Controls.
            //------------------------------------------------------------------
            if (entered_controls_w) begin
                pr_dig_v        <= 32'd0;
                pr_cnt          <= 4'd0;
                practice_active <= 1'b0;
            end

            //------------------------------------------------------------------
            // Params click handling.
            //
            // Clicking a value box activates that field. Clicking outside both
            // boxes deactivates parameter entry.
            //------------------------------------------------------------------
            if (left_click_pulse && display_mode == SCREEN_PARAMS) begin
                // Click selected field 0.
                if (in_f0_w) begin
                    entry_active <= 1'b1;
                    active_field <= 1'b0;
                end
                // Click selected field 1.
                else if (in_f1_w) begin
                    entry_active <= 1'b1;
                    active_field <= 1'b1;
                end
                // Click outside editable boxes.
                else begin
                    entry_active <= 1'b0;
                end
            end

            //------------------------------------------------------------------
            // Controls click handling.
            //
            // Clicking the practice box activates practice entry. Clicking
            // elsewhere deactivates it.
            //------------------------------------------------------------------
            if (left_click_pulse && display_mode == SCREEN_CONTROLS) begin
                // Click selected the practice input field.
                if (in_prac_w)
                    practice_active <= 1'b1;
                // Click outside the practice field.
                else
                    practice_active <= 1'b0;
            end

            //------------------------------------------------------------------
            // Leaving each screen deactivates its entry mode.
            //------------------------------------------------------------------
            if (display_mode != SCREEN_PARAMS)
                entry_active <= 1'b0;

            if (display_mode != SCREEN_CONTROLS)
                practice_active <= 1'b0;

            //------------------------------------------------------------------
            // Keypad handling for the currently active field.
            //------------------------------------------------------------------
            if (key_accept_w) begin
                //--------------------------------------------------------------
                // Controls screen practice field.
                //--------------------------------------------------------------
                if (display_mode == SCREEN_CONTROLS && practice_active) begin
                    // Append one decimal digit if there is room.
                    if (key_is_digit_w && pr_cnt < 4'd8) begin
                        pr_dig_v <= {pr_dig_v[27:0], key_code};
                        pr_cnt   <= pr_cnt + 4'd1;
                    end
                    // Remove the least significant digit.
                    else if (key_is_bksp_w && pr_cnt > 4'd0) begin
                        pr_dig_v <= {4'd0, pr_dig_v[31:4]};
                        pr_cnt   <= pr_cnt - 4'd1;
                    end
                    // Clear the entire practice field.
                    else if (key_is_clear_w) begin
                        pr_dig_v <= 32'd0;
                        pr_cnt   <= 4'd0;
                    end
                end
                //--------------------------------------------------------------
                // Params screen field 0 / field 1.
                //--------------------------------------------------------------
                else begin
                    // Append a digit to the active Params field.
                    if (key_is_digit_w) begin
                        // Field 0 selected and not full.
                        if (!active_field && f0_cnt < 4'd8) begin
                            f0_dig_v <= {f0_dig_v[27:0], key_code};
                            f0_cnt   <= f0_cnt + 4'd1;
                        end
                        // Field 1 selected and not full.
                        else if (active_field && f1_cnt < 4'd8) begin
                            f1_dig_v <= {f1_dig_v[27:0], key_code};
                            f1_cnt   <= f1_cnt + 4'd1;
                        end
                    end
                    // Backspace the active Params field.
                    else if (key_is_bksp_w) begin
                        // Remove one digit from field 0.
                        if (!active_field && f0_cnt > 4'd0) begin
                            f0_dig_v <= {4'd0, f0_dig_v[31:4]};
                            f0_cnt   <= f0_cnt - 4'd1;
                        end
                        // Remove one digit from field 1.
                        else if (active_field && f1_cnt > 4'd0) begin
                            f1_dig_v <= {4'd0, f1_dig_v[31:4]};
                            f1_cnt   <= f1_cnt - 4'd1;
                        end
                    end
                    // Clear the active Params field.
                    else if (key_is_clear_w) begin
                        // Clear field 0.
                        if (!active_field) begin
                            f0_dig_v <= 32'd0;
                            f0_cnt   <= 4'd0;
                        end
                        // Clear field 1.
                        else begin
                            f1_dig_v <= 32'd0;
                            f1_cnt   <= 4'd0;
                        end
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // BCD-to-binary conversion FSM
    //
    // The converter continuously refreshes all three binary outputs:
    //   field0_val -> field1_val -> practice_val -> repeat
    //
    // Each field takes 8 calculation cycles plus one store cycle. The full
    // three-field refresh is much faster than human input timing.
    // -------------------------------------------------------------------------
    localparam CONV_CALC  = 2'd0;        // Accumulate one digit
    localparam CONV_STORE = 2'd1;        // Store completed binary value

    reg  [1:0]  conv_st_ff;             // Current converter state
    reg  [1:0]  conv_field_ff;          // Current field: 0=f0, 1=f1, 2=practice
    reg  [2:0]  conv_step_ff;           // Current digit step, 0 through 7
    reg  [26:0] conv_acc_ff;            // Running binary accumulator

    // Bit position of the digit currently being consumed.
    // step 0 selects [31:28], and step 7 selects [3:0].
    wire [4:0] conv_bit_pos_w = {~conv_step_ff, 2'b00};

    // Select the current BCD digit from the active field buffer.
    wire [3:0] conv_dig_w =
        (conv_field_ff == 2'd0) ? f0_dig_v[conv_bit_pos_w +: 4] :
        (conv_field_ff == 2'd1) ? f1_dig_v[conv_bit_pos_w +: 4] :
                                  pr_dig_v[conv_bit_pos_w +: 4];

    always @(posedge clk) begin
        // Reset converter state and binary outputs.
        if (!resetn) begin
            conv_st_ff    <= CONV_CALC;
            conv_field_ff <= 2'd0;
            conv_step_ff  <= 3'd0;
            conv_acc_ff   <= 27'd0;
            field0_val    <= 27'd0;
            field1_val    <= 27'd0;
            practice_val  <= 27'd0;
        end
        else begin
            case (conv_st_ff)

                //--------------------------------------------------------------
                // CONV_CALC
                //
                // Consume one BCD digit using Horner's method:
                //   acc = acc * 10 + digit
                //--------------------------------------------------------------
                CONV_CALC: begin
                    conv_acc_ff <= (conv_acc_ff << 3) + (conv_acc_ff << 1)
                                 + {23'd0, conv_dig_w};

                    // After the final digit, move to the store state.
                    if (conv_step_ff == 3'd7)
                        conv_st_ff <= CONV_STORE;
                    // Otherwise continue with the next BCD digit.
                    else
                        conv_step_ff <= conv_step_ff + 3'd1;
                end

                //--------------------------------------------------------------
                // CONV_STORE
                //
                // Store the completed binary value into the output for the field
                // that was just converted, then advance to the next field.
                //--------------------------------------------------------------
                CONV_STORE: begin
                    case (conv_field_ff)
                        // Store converted field 0 and move to field 1.
                        2'd0: begin
                            field0_val    <= conv_acc_ff;
                            conv_field_ff <= 2'd1;
                        end
                        // Store converted field 1 and move to practice field.
                        2'd1: begin
                            field1_val    <= conv_acc_ff;
                            conv_field_ff <= 2'd2;
                        end
                        // Store converted practice field and wrap back to field 0.
                        default: begin
                            practice_val  <= conv_acc_ff;
                            conv_field_ff <= 2'd0;
                        end
                    endcase

                    conv_acc_ff  <= 27'd0;
                    conv_step_ff <= 3'd0;
                    conv_st_ff   <= CONV_CALC;
                end

                //--------------------------------------------------------------
                // Unknown converter state recovery.
                //--------------------------------------------------------------
                default: begin
                    conv_st_ff   <= CONV_CALC;
                    conv_acc_ff  <= 27'd0;
                    conv_step_ff <= 3'd0;
                end
            endcase
        end
    end

endmodule