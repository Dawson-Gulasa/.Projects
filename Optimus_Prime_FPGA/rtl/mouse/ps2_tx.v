`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// ps2_tx.v
//
// Purpose:
//   Send one PS/2 command byte from the FPGA host to the mouse device through
//   the Nexys A7 PS/2-emulated USB HID interface.
//
// Behavior:
//   - Implements host request-to-send sequence
//   - Drives open-collector style low enables for ps2_clk and ps2_data
//   - Sends start, 8 data bits (LSB first), parity, and stop
//   - Waits for device ACK bit
//   - Produces tx_done_pulse or tx_error_pulse
//
// Interface style:
//   This module does NOT directly own the inout pins.
//   Instead it outputs:
//     ps2_clk_drive_low
//     ps2_data_drive_low
//   which the top-level will connect to tri-state/open-collector wiring.
//
// Notes:
//   - Reset is synchronous
//   - Device is expected to generate the serial clock after request-to-send
//   - Odd parity is used
//------------------------------------------------------------------------------

module ps2_tx #(
    parameter integer CLK_HZ            = 100_000_000,
    parameter integer INHIBIT_US        = 120,
    parameter integer TX_TIMEOUT_CLKS   = 5_000_000
)(
    input  wire       clk,                 // System clock
    input  wire       resetn,              // Synchronized active-low reset
    input  wire       ps2_clk_raw,         // Raw PS/2 clock line
    input  wire       ps2_data_raw,        // Raw PS/2 data line

    input  wire [7:0] tx_data,             // Byte to transmit
    input  wire       tx_start_pulse,      // One-clk request to send tx_data

    output reg        busy,                // High while a transaction is active
    output reg        tx_done_pulse,       // One-clk pulse on successful completion
    output reg        tx_error_pulse,      // One-clk pulse on timeout / no-ack

    output reg        ps2_clk_drive_low,   // 1 = drive PS/2 clock low, 0 = release
    output reg        ps2_data_drive_low   // 1 = drive PS/2 data low, 0 = release
);

    //--------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------
    localparam integer INHIBIT_CLKS = (CLK_HZ / 1_000_000) * INHIBIT_US;

    localparam [2:0] S_IDLE        = 3'd0;
    localparam [2:0] S_INHIBIT     = 3'd1;
    localparam [2:0] S_START       = 3'd2;
    localparam [2:0] S_SHIFT       = 3'd3;
    localparam [2:0] S_ACK_WAIT    = 3'd4;
    localparam [2:0] S_DONE_PULSE  = 3'd5;
    localparam [2:0] S_ERROR_PULSE = 3'd6;

    //--------------------------------------------------------------------------
    // State / timing / synchronization
    //--------------------------------------------------------------------------
    reg [2:0] state_ff;

    reg ps2_clk_meta_ff;
    reg ps2_clk_sync_ff;
    reg ps2_clk_prev_ff;

    reg ps2_data_meta_ff;
    reg ps2_data_sync_ff;

    reg [31:0] inhibit_count_ff;
    reg [31:0] timeout_count_ff;

    reg [3:0] bit_index_ff;
    reg [7:0] tx_data_ff;
    reg       parity_ff;

    //--------------------------------------------------------------------------
    // Combinational helpers
    //--------------------------------------------------------------------------
    wire ps2_clk_fall_w;

    assign ps2_clk_fall_w = (ps2_clk_prev_ff == 1'b1) && (ps2_clk_sync_ff == 1'b0);

    //--------------------------------------------------------------------------
    // Sequential logic
    //--------------------------------------------------------------------------
    // This single sequential block holds:
    //   - synchronized input sampling
    //   - state machine register
    //   - PS/2 open-collector drive outputs
    //   - timing counters
    //
    // Only non-blocking assignments are used.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Default one-cycle pulses
        tx_done_pulse  <= 1'b0;
        tx_error_pulse <= 1'b0;

        // Synchronizers
        ps2_clk_meta_ff  <= ps2_clk_raw;
        ps2_clk_sync_ff  <= ps2_clk_meta_ff;
        ps2_clk_prev_ff  <= ps2_clk_sync_ff;

        ps2_data_meta_ff <= ps2_data_raw;
        ps2_data_sync_ff <= ps2_data_meta_ff;

        // Default timeout counter handling while busy
        if (busy) begin
            timeout_count_ff <= timeout_count_ff + 32'd1;
        end
        else begin
            timeout_count_ff <= 32'd0;
        end

        // Synchronous reset
        if (!resetn) begin
            state_ff           <= S_IDLE;
            busy               <= 1'b0;
            tx_done_pulse      <= 1'b0;
            tx_error_pulse     <= 1'b0;

            ps2_clk_drive_low  <= 1'b0;
            ps2_data_drive_low <= 1'b0;

            inhibit_count_ff   <= 32'd0;
            timeout_count_ff   <= 32'd0;
            bit_index_ff       <= 4'd0;
            tx_data_ff         <= 8'd0;
            parity_ff          <= 1'b1;

            ps2_clk_meta_ff    <= 1'b1;
            ps2_clk_sync_ff    <= 1'b1;
            ps2_clk_prev_ff    <= 1'b1;

            ps2_data_meta_ff   <= 1'b1;
            ps2_data_sync_ff   <= 1'b1;
        end
        else begin
            //------------------------------------------------------------------
            // Global timeout protection
            //------------------------------------------------------------------
            if (busy && (timeout_count_ff >= TX_TIMEOUT_CLKS)) begin
                state_ff           <= S_ERROR_PULSE;
                busy               <= 1'b0;
                ps2_clk_drive_low  <= 1'b0;
                ps2_data_drive_low <= 1'b0;
            end
            else begin
                //------------------------------------------------------------------
                // Main transmit state machine
                //------------------------------------------------------------------
                case (state_ff)

                    //--------------------------------------------------------------
                    // IDLE
                    // Wait for a one-cycle transmit request.
                    //--------------------------------------------------------------
                    S_IDLE: begin
                        busy               <= 1'b0;
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b0;
                        inhibit_count_ff   <= 32'd0;
                        bit_index_ff       <= 4'd0;

                        if (tx_start_pulse) begin
                            tx_data_ff       <= tx_data;
                            parity_ff        <= ~(^tx_data); // odd parity bit
                            busy             <= 1'b1;
                            state_ff         <= S_INHIBIT;
                            ps2_clk_drive_low <= 1'b1;       // inhibit clock first
                            ps2_data_drive_low <= 1'b0;      // keep data released during inhibit
                        end
                    end

                    //--------------------------------------------------------------
                    // INHIBIT
                    // Host pulls clock low long enough to request bus ownership.
                    //--------------------------------------------------------------
                    S_INHIBIT: begin
                        ps2_clk_drive_low  <= 1'b1;
                        ps2_data_drive_low <= 1'b0;

                        if (inhibit_count_ff < (INHIBIT_CLKS - 1)) begin
                            inhibit_count_ff <= inhibit_count_ff + 32'd1;
                        end
                        else begin
                            inhibit_count_ff   <= 32'd0;
                            ps2_clk_drive_low  <= 1'b0;  // release clock
                            ps2_data_drive_low <= 1'b1;  // drive start bit low
                            state_ff           <= S_START;
                        end
                    end

                    //--------------------------------------------------------------
                    // START
                    // Wait for the first device-generated falling edge.
                    //--------------------------------------------------------------
                    S_START: begin
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b1; // start bit = 0

                        if (ps2_clk_fall_w) begin
                            bit_index_ff <= 4'd0;

                            // Drive first data bit immediately after start edge
                            if (tx_data_ff[0] == 1'b0) begin
                                ps2_data_drive_low <= 1'b1;
                            end
                            else begin
                                ps2_data_drive_low <= 1'b0;
                            end

                            state_ff <= S_SHIFT;
                        end
                    end

                    //--------------------------------------------------------------
                    // SHIFT
                    // Shift out 8 data bits, then parity, then stop.
                    //--------------------------------------------------------------
                    S_SHIFT: begin
                        ps2_clk_drive_low <= 1'b0;

                        if (ps2_clk_fall_w) begin
                            // Data bits d0..d7
                            if (bit_index_ff <= 4'd6) begin
                                bit_index_ff <= bit_index_ff + 4'd1;

                                if (tx_data_ff[bit_index_ff + 4'd1] == 1'b0) begin
                                    ps2_data_drive_low <= 1'b1;
                                end
                                else begin
                                    ps2_data_drive_low <= 1'b0;
                                end
                            end

                            // Parity bit
                            else if (bit_index_ff == 4'd7) begin
                                bit_index_ff <= bit_index_ff + 4'd1;

                                if (parity_ff == 1'b0) begin
                                    ps2_data_drive_low <= 1'b1;
                                end
                                else begin
                                    ps2_data_drive_low <= 1'b0;
                                end
                            end

                            // Stop bit = release data high
                            else if (bit_index_ff == 4'd8) begin
                                bit_index_ff       <= bit_index_ff + 4'd1;
                                ps2_data_drive_low <= 1'b0;
                            end

                            // Move to ACK wait after stop bit edge
                            else begin
                                bit_index_ff       <= 4'd0;
                                ps2_data_drive_low <= 1'b0;
                                state_ff           <= S_ACK_WAIT;
                            end
                        end
                    end

                    //--------------------------------------------------------------
                    // ACK_WAIT
                    // Device should pull data low for ACK on the next bit time.
                    //--------------------------------------------------------------
                    S_ACK_WAIT: begin
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b0;

                        if (ps2_clk_fall_w) begin
                            busy <= 1'b0;

                            if (ps2_data_sync_ff == 1'b0) begin
                                state_ff <= S_DONE_PULSE;
                            end
                            else begin
                                state_ff <= S_ERROR_PULSE;
                            end
                        end
                    end

                    //--------------------------------------------------------------
                    // DONE_PULSE
                    // One-cycle success pulse.
                    //--------------------------------------------------------------
                    S_DONE_PULSE: begin
                        tx_done_pulse <= 1'b1;
                        state_ff      <= S_IDLE;
                    end

                    //--------------------------------------------------------------
                    // ERROR_PULSE
                    // One-cycle error pulse.
                    //--------------------------------------------------------------
                    S_ERROR_PULSE: begin
                        tx_error_pulse <= 1'b1;
                        state_ff       <= S_IDLE;
                    end

                    //--------------------------------------------------------------
                    // Default
                    //--------------------------------------------------------------
                    default: begin
                        state_ff           <= S_IDLE;
                        busy               <= 1'b0;
                        ps2_clk_drive_low  <= 1'b0;
                        ps2_data_drive_low <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule