`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// mouse_packet_decoder.v
//
// Purpose:
//   Decodes the standard 3-byte PS/2 mouse packet stream into clean button,
//   overflow, and signed movement signals for the cursor controller.
//
// Packet decode algorithm:
//   1) Wait for a valid first packet byte. In a standard PS/2 mouse packet,
//      byte 0 must have bit[3] = 1.
//   2) Store byte 0 as the status byte.
//   3) Store byte 1 as the X movement byte.
//   4) Use byte 2 as the Y movement byte and decode the complete packet.
//   5) Pulse packet_valid_pulse for one clk cycle.
//
// Example:
//   If the incoming bytes are:
//      byte0 = 8'b0000_1001
//      byte1 = 8'd5
//      byte2 = 8'd0
//
//   Then:
//      left_btn = 1
//      x_delta  = +5
//      y_delta  = 0
//      packet_valid_pulse pulses once when byte2 is received.
//
// Standard PS/2 packet format:
//   Byte 0:
//     bit[0] = left button
//     bit[1] = right button
//     bit[2] = middle button
//     bit[3] = always 1 for packet alignment
//     bit[4] = X sign
//     bit[5] = Y sign
//     bit[6] = X overflow
//     bit[7] = Y overflow
//
//   Byte 1:
//     X movement, 8-bit two's complement
//
//   Byte 2:
//     Y movement, 8-bit two's complement
//
// Notes:
//   - This module only decodes packets; it does not update cursor position.
//   - Overflow flags are preserved so higher-level logic can ignore large jumps.
//   - The byte collection logic acts like a small packet-alignment FSM.
//   - Reset is synchronous.
//------------------------------------------------------------------------------

module mouse_packet_decoder (
    input  wire        clk,                    // System clock for packet decode logic
    input  wire        resetn,                 // Synchronized active-low reset

    input  wire [7:0]  mouse_byte,             // Byte stream from mouse_ps2_ctrl
    input  wire        mouse_byte_valid_pulse, // One-clock pulse when mouse_byte is valid

    output reg         packet_valid_pulse,     // One-clock pulse when a full packet is decoded

    output reg         left_btn,               // Decoded left button state
    output reg         right_btn,              // Decoded right button state
    output reg         middle_btn,             // Decoded middle button state

    output reg         x_overflow,             // Decoded X overflow flag
    output reg         y_overflow,             // Decoded Y overflow flag

    output reg  signed [8:0] x_delta,          // Sign-extended 9-bit X movement delta
    output reg  signed [8:0] y_delta           // Sign-extended 9-bit Y movement delta
);

    //--------------------------------------------------------------------------
    // Byte collection state
    //
    // byte_index_ff tracks which byte of the 3-byte packet is expected next:
    //   0 = searching for aligned status byte
    //   1 = capturing X movement byte
    //   2 = capturing Y movement byte and decoding the packet
    //--------------------------------------------------------------------------
    reg [1:0] byte_index_ff;       // Current packet byte index
    reg [7:0] packet_byte0_ff;     // Stored packet status byte
    reg [7:0] packet_byte1_ff;     // Stored X movement byte
    reg [7:0] packet_byte2_ff;     // Stored Y movement byte/debug copy

    //--------------------------------------------------------------------------
    // Packet collection and decode FSM
    //
    // This sequential block aligns to byte 0 using the required bit[3] = 1,
    // stores the next two bytes, and emits a one-cycle valid pulse when a full
    // packet has been decoded.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Default the packet-valid pulse low unless a full packet completes.
        packet_valid_pulse <= 1'b0;

        // Clear packet collection and decoded outputs during reset.
        if (!resetn) begin
            byte_index_ff      <= 2'd0;
            packet_byte0_ff    <= 8'd0;
            packet_byte1_ff    <= 8'd0;
            packet_byte2_ff    <= 8'd0;

            packet_valid_pulse <= 1'b0;

            left_btn           <= 1'b0;
            right_btn          <= 1'b0;
            middle_btn         <= 1'b0;

            x_overflow         <= 1'b0;
            y_overflow         <= 1'b0;

            x_delta            <= 9'sd0;
            y_delta            <= 9'sd0;
        end
        else begin
            //------------------------------------------------------------------
            // Only update the packet FSM when a new mouse byte arrives.
            //------------------------------------------------------------------
            if (mouse_byte_valid_pulse) begin
                //--------------------------------------------------------------
                // Byte 0 search / realignment
                //
                // A valid PS/2 mouse status byte must have bit[3] set. Bytes
                // without this bit are ignored so the decoder can recover from
                // bad alignment or dropped bytes.
                //--------------------------------------------------------------
                if (byte_index_ff == 2'd0) begin
                    // Accept the byte as packet byte 0 only if alignment bit is set.
                    if (mouse_byte[3] == 1'b1) begin
                        packet_byte0_ff <= mouse_byte;
                        byte_index_ff   <= 2'd1;
                    end
                end

                //--------------------------------------------------------------
                // Byte 1 capture
                //
                // The second packet byte is the raw 8-bit X movement value.
                //--------------------------------------------------------------
                else if (byte_index_ff == 2'd1) begin
                    packet_byte1_ff <= mouse_byte;
                    byte_index_ff   <= 2'd2;
                end

                //--------------------------------------------------------------
                // Byte 2 capture and packet decode
                //
                // The third byte completes the packet. Decode button states,
                // overflow bits, and signed movement deltas.
                //--------------------------------------------------------------
                else begin
                    packet_byte2_ff <= mouse_byte;
                    byte_index_ff   <= 2'd0;

                    left_btn        <= packet_byte0_ff[0];
                    right_btn       <= packet_byte0_ff[1];
                    middle_btn      <= packet_byte0_ff[2];

                    x_overflow      <= packet_byte0_ff[6];
                    y_overflow      <= packet_byte0_ff[7];

                    // Sign-extend X using the X sign bit from byte 0.
                    x_delta         <= {packet_byte0_ff[4], packet_byte1_ff};

                    // Sign-extend Y using the Y sign bit from byte 0.
                    y_delta         <= {packet_byte0_ff[5], mouse_byte};

                    packet_valid_pulse <= 1'b1;
                end
            end
        end
    end

endmodule