`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// col_scanner.v
//
// Purpose:
//   Scans the four columns of the Digilent Pmod KYPD keypad by driving one
//   column active at a time.
//
//   The keypad is a 4x4 matrix. To detect a pressed key, the FPGA selects one
//   column by driving it low, then another module reads the row inputs. The
//   selected column and active row together identify the key.
//
// Scan algorithm:
//   1) Hold one column low for TICKS_PER_DWELL clock cycles.
//   2) Advance to the next column.
//   3) Repeat until all four columns have been scanned.
//   4) Pulse frame_tick when the scanner wraps from the last column back to the
//      first column.
//
// Example:
//   If col_idx = 2'd1, kp_col = 4'b1011. This selects COL3 by driving only
//   kp_col[2] low. If a row input is also low during this dwell, the decoder can
//   determine which key in COL3 is being pressed.
//
// Bus ordering used in this project:
//   kp_col[3] = COL4 = leftmost keypad column  = {1,4,7,0}
//   kp_col[2] = COL3 = next column             = {2,5,8,F}
//   kp_col[1] = COL2 = next column             = {3,6,9,E}
//   kp_col[0] = COL1 = rightmost keypad column = {A,B,C,D}
//
// Electrical behavior:
//   - Columns are active-low.
//   - Only one column is driven low at a time.
//   - Non-selected columns are driven high.
//
// Timing:
//   - TICKS_PER_DWELL controls how long each column remains selected.
//   - With TICKS_PER_DWELL = 100,000 and clk = 100 MHz, each dwell is 1 ms.
//   - One full keypad scan frame takes 4 dwell periods, or about 4 ms.
//
// Notes:
//   - This is a small counter/FSM-style scanner.
//   - frame_tick pulses once per full 4-column scan.
//   - All outputs are registered for clean synchronous behavior.
//------------------------------------------------------------------------------

module col_scanner #(
    parameter integer TICKS_PER_DWELL = 100_000   // Clock cycles per selected column dwell
)(
    input  wire       clk,        // Main system clock for the scanner
    input  wire       rst_n,      // Synchronized active-low reset
    output wire [3:0] kp_col,     // Active-low keypad column drive pattern
    output wire [1:0] col_idx,    // Current selected column index, 0 through 3
    output wire       frame_tick  // One-clock pulse when a full scan frame completes
);

    //--------------------------------------------------------------------------
    // Internal dwell timing
    //
    // dwell_tick pulses once per selected-column dwell period. The scanner only
    // advances to the next column when this pulse occurs.
    //--------------------------------------------------------------------------
    wire dwell_tick;              // One-clock pulse used to advance columns

    //--------------------------------------------------------------------------
    // Scan-state registers
    //
    // col_idx_ff tracks which column is currently selected. frame_tick_ff marks
    // the wrap from column 3 back to column 0. kp_col_ff holds the actual
    // active-low column output pattern.
    //--------------------------------------------------------------------------
    reg [1:0] col_idx_ff;         // Current column index register
    reg [1:0] col_idx_n;          // Next column index

    reg       frame_tick_ff;      // Registered full-frame pulse
    reg       frame_tick_n;       // Next full-frame pulse

    reg [3:0] kp_col_n;           // Next active-low column pattern
    reg [3:0] kp_col_ff;          // Registered active-low column pattern

    //--------------------------------------------------------------------------
    // Dwell tick generator
    //
    // Generates the slower enable pulse that controls how long the scanner
    // remains on each keypad column.
    //--------------------------------------------------------------------------
    tick_gen #(
        .TICKS_PER_PULSE(TICKS_PER_DWELL)
    ) u_tick_gen (
        .clk   (clk),
        .rst_n (rst_n),
        .tick  (dwell_tick)
    );

    //--------------------------------------------------------------------------
    // Column scanner next-state logic
    //
    // This block updates the selected column when dwell_tick occurs and then
    // computes the matching active-low kp_col pattern.
    //--------------------------------------------------------------------------
    always @(*) begin
        col_idx_n    = col_idx_ff;
        frame_tick_n = 1'b0;
        kp_col_n     = kp_col_ff;

        // Reset scanner to a safe idle state with all columns inactive.
        if (!rst_n) begin
            col_idx_n    = 2'd0;
            frame_tick_n = 1'b0;
            kp_col_n     = 4'b1111;
        end
        else begin
            // Advance the selected column only at the dwell rate.
            if (dwell_tick) begin
                // Wrapping from the final column completes one full scan frame.
                if (col_idx_ff == 2'd3) begin
                    col_idx_n    = 2'd0;
                    frame_tick_n = 1'b1;
                end
                // Otherwise move to the next column and keep frame_tick low.
                else begin
                    col_idx_n    = col_idx_ff + 2'd1;
                    frame_tick_n = 1'b0;
                end
            end

            // Drive exactly one active-low column based on the next column index.
            case (col_idx_n)
                2'd0: kp_col_n = 4'b0111; // Select COL4, leftmost column
                2'd1: kp_col_n = 4'b1011; // Select COL3
                2'd2: kp_col_n = 4'b1101; // Select COL2
                2'd3: kp_col_n = 4'b1110; // Select COL1, rightmost column
                default: kp_col_n = 4'b1111; // Safe fallback: no column selected
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // All scanner state and outputs update together on the rising edge of clk.
    // Reset behavior is handled by the next-state logic above.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        col_idx_ff    <= col_idx_n;
        frame_tick_ff <= frame_tick_n;
        kp_col_ff     <= kp_col_n;
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // Registered outputs are used so the keypad decoder receives clean,
    // synchronous column information.
    //--------------------------------------------------------------------------
    assign col_idx    = col_idx_ff;
    assign frame_tick = frame_tick_ff;
    assign kp_col     = kp_col_ff;

endmodule