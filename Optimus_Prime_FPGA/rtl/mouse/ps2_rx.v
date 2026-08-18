`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// ps2_rx.v
//
// Purpose:
//   Receive PS/2 frames from the Nexys A7 USB-HID-to-PS/2 interface and convert
//   them into validated bytes in the clk domain.
//
// Behavior:
//   - Synchronizes ps2_clk_raw and ps2_data_raw into clk
//   - Detects falling edges of the synchronized PS/2 clock
//   - Shifts in one PS/2 frame: start, 8 data bits, parity, stop
//   - Checks start/stop/parity and produces rx_valid_pulse on good bytes
//   - Produces rx_error_pulse on malformed frames
//
// Notes:
//   - PS/2 data is sampled on falling edges of the PS/2 clock
//   - Data bits are received LSB first
//   - Odd parity is expected
//   - Reset is synchronous per class style expectations
//------------------------------------------------------------------------------

module ps2_rx (
    input  wire       clk,             // System clock
    input  wire       resetn,          // Synchronized active-low reset
    input  wire       ps2_clk_raw,     // Raw PS/2 clock from top-level pin
    input  wire       ps2_data_raw,    // Raw PS/2 data from top-level pin

    output reg  [7:0] rx_data,         // Received byte
    output reg        rx_valid_pulse,  // One-clk pulse when rx_data is valid
    output reg        rx_error_pulse   // One-clk pulse when a frame is invalid
);

    //--------------------------------------------------------------------------
    // Synchronizers for asynchronous PS/2 inputs
    //--------------------------------------------------------------------------
    reg ps2_clk_meta_ff;
    reg ps2_clk_sync_ff;
    reg ps2_clk_prev_ff;

    reg ps2_data_meta_ff;
    reg ps2_data_sync_ff;

    //--------------------------------------------------------------------------
    // Receive shift/register state
    //--------------------------------------------------------------------------
    reg [3:0] bit_count_ff;
    reg [7:0] data_shift_ff;
    reg       parity_bit_ff;
    reg       frame_active_ff;

    //--------------------------------------------------------------------------
    // Combinational helpers
    //--------------------------------------------------------------------------
    wire ps2_clk_fall_w;
    wire parity_ok_w;
    wire start_ok_w;
    wire stop_ok_w;

    assign ps2_clk_fall_w = (ps2_clk_prev_ff == 1'b1) && (ps2_clk_sync_ff == 1'b0);

    // Odd parity:
    //   parity bit should make {parity, data[7:0]} contain an odd number of ones.
    assign parity_ok_w = (^({parity_bit_ff, data_shift_ff})) == 1'b1;
    assign start_ok_w  = 1'b1; // Start bit is checked when frame begins
    assign stop_ok_w   = (ps2_data_sync_ff == 1'b1);

    //--------------------------------------------------------------------------
    // Sequential logic
    //--------------------------------------------------------------------------
    // This always block holds:
    //   - synchronizers
    //   - PS/2 falling-edge detection history
    //   - frame shifting and validation
    //   - output pulse generation
    //
    // Only non-blocking assignments are used here.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Default output pulses each cycle
        rx_valid_pulse <= 1'b0;
        rx_error_pulse <= 1'b0;

        // Input synchronizers
        ps2_clk_meta_ff  <= ps2_clk_raw;
        ps2_clk_sync_ff  <= ps2_clk_meta_ff;
        ps2_clk_prev_ff  <= ps2_clk_sync_ff;

        ps2_data_meta_ff <= ps2_data_raw;
        ps2_data_sync_ff <= ps2_data_meta_ff;

        // Synchronous reset
        if (!resetn) begin
            rx_data         <= 8'd0;
            rx_valid_pulse  <= 1'b0;
            rx_error_pulse  <= 1'b0;

            ps2_clk_meta_ff <= 1'b1;
            ps2_clk_sync_ff <= 1'b1;
            ps2_clk_prev_ff <= 1'b1;

            ps2_data_meta_ff <= 1'b1;
            ps2_data_sync_ff <= 1'b1;

            bit_count_ff    <= 4'd0;
            data_shift_ff   <= 8'd0;
            parity_bit_ff   <= 1'b0;
            frame_active_ff <= 1'b0;
        end
        else begin
            //--------------------------------------------------------------------------
            // Frame receive process
            //
            // A PS/2 frame is:
            //   start(0), d0, d1, d2, d3, d4, d5, d6, d7, parity, stop(1)
            //--------------------------------------------------------------------------
            if (ps2_clk_fall_w) begin
                //----------------------------------------------------------------------
                // Start a new frame only when the line indicates a valid start bit
                //----------------------------------------------------------------------
                if (!frame_active_ff) begin
                    if (ps2_data_sync_ff == 1'b0) begin
                        frame_active_ff <= 1'b1;
                        bit_count_ff    <= 4'd0;
                        data_shift_ff   <= 8'd0;
                        parity_bit_ff   <= 1'b0;
                    end
                end
                else begin
                    //------------------------------------------------------------------
                    // Shift data bits d0..d7
                    //------------------------------------------------------------------
                    if (bit_count_ff <= 4'd7) begin
                        data_shift_ff[bit_count_ff] <= ps2_data_sync_ff;
                        bit_count_ff                <= bit_count_ff + 4'd1;
                    end

                    //------------------------------------------------------------------
                    // Capture parity bit
                    //------------------------------------------------------------------
                    else if (bit_count_ff == 4'd8) begin
                        parity_bit_ff <= ps2_data_sync_ff;
                        bit_count_ff   <= bit_count_ff + 4'd1;
                    end

                    //------------------------------------------------------------------
                    // Stop bit and full-frame validation
                    //------------------------------------------------------------------
                    else if (bit_count_ff == 4'd9) begin
                        frame_active_ff <= 1'b0;
                        bit_count_ff    <= 4'd0;

                        if (stop_ok_w && parity_ok_w && start_ok_w) begin
                            rx_data        <= data_shift_ff;
                            rx_valid_pulse <= 1'b1;
                        end
                        else begin
                            rx_error_pulse <= 1'b1;
                        end
                    end

                    //------------------------------------------------------------------
                    // Safety default
                    //------------------------------------------------------------------
                    else begin
                        frame_active_ff <= 1'b0;
                        bit_count_ff    <= 4'd0;
                        rx_error_pulse  <= 1'b1;
                    end
                end
            end
        end
    end

endmodule