`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// sd_prime_parser.v
//
// Purpose:
//   Parses a stream of ASCII bytes representing decimal prime numbers stored
//   one-per-line in a text file.
//
//   This parser is used by Test Mode to convert SD-card text data into binary
//   prime values that can be compared against primes stored in DDR2.
//
// Supported input format:
//   - ASCII decimal digits, '0' through '9', build one number.
//   - LF, 8'h0A, ends a number line.
//   - CR, 8'h0D, is ignored for Windows-style CR/LF files.
//   - Capital 'A', 8'h41, ends the entire test stream.
//
// Example input file:
//   2
//   3
//   5
//   7
//   A
//
// Parsing algorithm:
//   1) Clear the accumulator at the start of a parse session.
//   2) For each decimal digit, update:
//
//        accum_next = accum_current * 10 + digit
//
//      The multiply-by-10 operation is implemented using shifts:
//
//        value * 10 = (value << 3) + (value << 1)
//
//   3) When LF arrives, output the accumulated number if at least one digit was
//      seen on that line.
//   4) When capital 'A' or end_of_stream arrives, assert stream_done.
//
// Example:
//   Bytes "1", "7", "\n" are parsed as:
//      accum = 0*10 + 1 = 1
//      accum = 1*10 + 7 = 17
//      LF causes prime_valid to pulse and prime_value to become 17.
//
// Interface behavior:
//   - prime_valid pulses for one clock when a complete number line is parsed.
//   - prime_value holds the most recently parsed number.
//   - stream_done stays high after the stop marker or end_of_stream is seen.
//
// Notes:
//   - This module is not an encoded FSM. The parser state is represented by
//     accum_value_ff, digit_seen_ff, and stream_done.
//   - The stop marker 'A' is required by the updated project specification.
//------------------------------------------------------------------------------

module sd_prime_parser (
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk,           // System clock for parser logic
    input  wire        resetn,        // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Control
    //--------------------------------------------------------------------------
    input  wire        start_parse,   // Clears parser state for a fresh stream

    //--------------------------------------------------------------------------
    // Byte-stream input
    //--------------------------------------------------------------------------
    input  wire        byte_valid,    // One-clock pulse when byte_in is valid
    input  wire [7:0]  byte_in,       // ASCII byte from SD text stream
    input  wire        end_of_stream, // External end-of-stream indicator

    //--------------------------------------------------------------------------
    // Parsed prime output
    //--------------------------------------------------------------------------
    output reg         prime_valid,   // One-clock pulse when prime_value is valid
    output reg  [31:0] prime_value,   // Parsed binary value from completed line
    output reg         stream_done    // High after stop marker or end_of_stream
);

    //--------------------------------------------------------------------------
    // Internal accumulation registers
    //
    // accum_value_ff stores the decimal number currently being parsed.
    // digit_seen_ff records whether the current line contains at least one digit.
    //--------------------------------------------------------------------------
    reg [31:0] accum_value_ff; // Current decimal accumulator
    reg        digit_seen_ff;  // Current line has seen at least one digit

    reg [31:0] accum_value_n;  // Next decimal accumulator
    reg        digit_seen_n;   // Next digit-seen flag

    reg        prime_valid_n;  // Next prime-valid pulse
    reg [31:0] prime_value_n;  // Next parsed prime output value
    reg        stream_done_n;  // Next stream-done flag

    //--------------------------------------------------------------------------
    // ASCII classification and decimal accumulation helpers
    //
    // These wires classify the incoming byte and compute the next accumulated
    // decimal value when a digit is received.
    //--------------------------------------------------------------------------
    wire        is_digit_w;          // byte_in is ASCII '0' through '9'
    wire        is_lf_w;             // byte_in is line feed, '\n'
    wire        is_cr_w;             // byte_in is carriage return, '\r'
    wire        is_stop_w;           // byte_in is capital 'A' stop marker
    wire [3:0]  digit_value_w;       // Numeric value of ASCII digit
    wire [31:0] mult10_w;            // accum_value_ff multiplied by 10
    wire [31:0] next_digit_accum_w;  // Accumulator after adding current digit

    assign is_digit_w         = (byte_in >= 8'h30) && (byte_in <= 8'h39);
    assign is_lf_w            = (byte_in == 8'h0A);
    assign is_cr_w            = (byte_in == 8'h0D);
    assign is_stop_w          = (byte_in == 8'h41); // 'A'

    assign digit_value_w      = byte_in[3:0];
    assign mult10_w           = (accum_value_ff << 3) + (accum_value_ff << 1);
    assign next_digit_accum_w = mult10_w + {28'd0, digit_value_w};

    //--------------------------------------------------------------------------
    // Parser next-state logic
    //
    // This block consumes incoming ASCII bytes and updates the decimal
    // accumulator, parsed output pulse, and stream completion flag.
    //--------------------------------------------------------------------------
    always @(*) begin
        // Hold current parser state by default.
        accum_value_n = accum_value_ff;
        digit_seen_n  = digit_seen_ff;

        // prime_valid is a pulse, while prime_value and stream_done hold state.
        prime_valid_n = 1'b0;
        prime_value_n = prime_value;
        stream_done_n = stream_done;

        //----------------------------------------------------------------------
        // Start a fresh parse session and clear all parser state.
        //----------------------------------------------------------------------
        if (start_parse) begin
            accum_value_n = 32'd0;
            digit_seen_n  = 1'b0;

            prime_valid_n = 1'b0;
            prime_value_n = 32'd0;
            stream_done_n = 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Consume one valid byte only while the stream is still active.
            //------------------------------------------------------------------
            if (byte_valid && !stream_done) begin
                //--------------------------------------------------------------
                // Decimal digit: multiply accumulator by 10 and add new digit.
                //--------------------------------------------------------------
                if (is_digit_w) begin
                    accum_value_n = next_digit_accum_w;
                    digit_seen_n  = 1'b1;
                end

                //--------------------------------------------------------------
                // Carriage return: ignore it so CR/LF text files work normally.
                //--------------------------------------------------------------
                else if (is_cr_w) begin
                    accum_value_n = accum_value_ff;
                    digit_seen_n  = digit_seen_ff;
                end

                //--------------------------------------------------------------
                // Line feed: complete the current number line if digits appeared.
                //--------------------------------------------------------------
                else if (is_lf_w) begin
                    // A non-empty line produces one parsed prime value.
                    if (digit_seen_ff) begin
                        prime_valid_n = 1'b1;
                        prime_value_n = accum_value_ff;
                    end
                    // Empty lines are ignored and do not produce prime_valid.
                    else begin
                        prime_valid_n = 1'b0;
                        prime_value_n = prime_value;
                    end

                    accum_value_n = 32'd0;
                    digit_seen_n  = 1'b0;
                end

                //--------------------------------------------------------------
                // Capital 'A': stop parsing the SD prime stream.
                //--------------------------------------------------------------
                else if (is_stop_w) begin
                    stream_done_n = 1'b1;
                    accum_value_n = 32'd0;
                    digit_seen_n  = 1'b0;
                    prime_valid_n = 1'b0;
                    prime_value_n = prime_value;
                end

                //--------------------------------------------------------------
                // Any other byte is ignored without changing the current number.
                //--------------------------------------------------------------
                else begin
                    accum_value_n = accum_value_ff;
                    digit_seen_n  = digit_seen_ff;
                end
            end

            //------------------------------------------------------------------
            // External end_of_stream also terminates parsing.
            //------------------------------------------------------------------
            if (end_of_stream) begin
                stream_done_n = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // All parser state and registered outputs update on the rising edge of clk.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset parser state and clear outputs.
        if (!resetn) begin
            accum_value_ff <= 32'd0;
            digit_seen_ff  <= 1'b0;

            prime_valid    <= 1'b0;
            prime_value    <= 32'd0;
            stream_done    <= 1'b0;
        end
        // Normal operation loads next-state parser values.
        else begin
            accum_value_ff <= accum_value_n;
            digit_seen_ff  <= digit_seen_n;

            prime_valid    <= prime_valid_n;
            prime_value    <= prime_value_n;
            stream_done    <= stream_done_n;
        end
    end

endmodule