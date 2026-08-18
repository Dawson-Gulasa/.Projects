`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// key_decoder.v
//
// Purpose:
//   Combinational decoder for the Digilent Pmod KYPD keypad.
//
//   This module receives the currently selected keypad column from col_scanner
//   and the raw keypad row inputs from the physical keypad. It converts that
//   row/column combination into a 4-bit hexadecimal key candidate.
//
// Keypad decode algorithm:
//   1) col_scanner drives one keypad column active low.
//   2) If a key in that column is pressed, exactly one row input is pulled low.
//   3) key_decoder uses the selected column index and active-low row pattern to
//      determine which hex key is being pressed.
//   4) candidate_valid is asserted only for recognized single-row patterns.
//
// Example:
//   If col_idx = 2'd0 and kp_row = 4'b1110, the selected column and active row
//   match the physical key "1", so candidate_valid = 1 and candidate_code = 4'h1.
//
// Important hardware note:
//   This decode table matches the empirically verified wiring/orientation of
//   the Digilent Pmod KYPD directly plugged into the JA header for this project.
//   The mapping may need to be updated if the keypad is rewired or rotated.
//
// Row electrical behavior:
//   - Rows are pulled high when idle.
//   - A pressed key in the selected active-low column pulls one row low.
//   - Valid single-row active-low patterns are:
//       4'b0111, 4'b1011, 4'b1101, 4'b1110
//
// Notes:
//   - This module is purely combinational.
//   - No FSM or registered state is implemented here.
//   - Debouncing is handled later by keypad_debounce.
//------------------------------------------------------------------------------

module key_decoder (
    input  wire [1:0] col_idx,          // Current selected keypad column index
    input  wire [3:0] kp_row,           // Raw active-low keypad row inputs
    output wire       candidate_valid,  // High when row/column maps to a valid key
    output wire [3:0] candidate_code    // Decoded hexadecimal key candidate
);

    //--------------------------------------------------------------------------
    // Internal combinational decode signals
    //
    // These registers hold the combinational decode result before it is assigned
    // to the module outputs.
    //--------------------------------------------------------------------------
    reg       candidate_valid_n;        // Next/combinational candidate-valid value
    reg [3:0] candidate_code_n;         // Next/combinational decoded key value

    //--------------------------------------------------------------------------
    // Row/column decode logic
    //
    // This is the full keypad lookup table for the verified hardware wiring.
    // Any invalid row pattern, idle row pattern, or unsupported column index
    // produces candidate_valid = 0 and candidate_code = 0.
    //--------------------------------------------------------------------------
    always @(*) begin
        candidate_valid_n = 1'b0;
        candidate_code_n  = 4'h0;

        case (col_idx)

            // Column index 0 selects the physical key column: 1, 4, 7, 0.
            2'd0: begin
                case (kp_row)
                    4'b0111: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h0; end // ROW4 -> key 0
                    4'b1011: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h7; end // ROW3 -> key 7
                    4'b1101: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h4; end // ROW2 -> key 4
                    4'b1110: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h1; end // ROW1 -> key 1
                    default: begin candidate_valid_n = 1'b0; candidate_code_n = 4'h0; end // No valid single-row press
                endcase
            end

            // Column index 1 selects the physical key column: A, B, C, D.
            2'd1: begin
                case (kp_row)
                    4'b0111: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hD; end // ROW4 -> key D
                    4'b1011: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hC; end // ROW3 -> key C
                    4'b1101: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hB; end // ROW2 -> key B
                    4'b1110: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hA; end // ROW1 -> key A
                    default: begin candidate_valid_n = 1'b0; candidate_code_n = 4'h0; end // No valid single-row press
                endcase
            end

            // Column index 2 selects the physical key column: 3, 6, 9, E.
            2'd2: begin
                case (kp_row)
                    4'b0111: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hE; end // ROW4 -> key E
                    4'b1011: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h9; end // ROW3 -> key 9
                    4'b1101: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h6; end // ROW2 -> key 6
                    4'b1110: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h3; end // ROW1 -> key 3
                    default: begin candidate_valid_n = 1'b0; candidate_code_n = 4'h0; end // No valid single-row press
                endcase
            end

            // Column index 3 selects the physical key column: 2, 5, 8, F.
            2'd3: begin
                case (kp_row)
                    4'b0111: begin candidate_valid_n = 1'b1; candidate_code_n = 4'hF; end // ROW4 -> key F
                    4'b1011: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h8; end // ROW3 -> key 8
                    4'b1101: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h5; end // ROW2 -> key 5
                    4'b1110: begin candidate_valid_n = 1'b1; candidate_code_n = 4'h2; end // ROW1 -> key 2
                    default: begin candidate_valid_n = 1'b0; candidate_code_n = 4'h0; end // No valid single-row press
                endcase
            end

            // Unknown column index: reject the candidate for safety.
            default: begin
                candidate_valid_n = 1'b0;
                candidate_code_n  = 4'h0;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // The decoded candidate is purely combinational. The downstream keypad
    // debouncer decides whether this candidate is stable enough to accept.
    //--------------------------------------------------------------------------
    assign candidate_valid = candidate_valid_n;
    assign candidate_code  = candidate_code_n;

endmodule