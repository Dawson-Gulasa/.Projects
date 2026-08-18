`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// mouse_ps2_ctrl.v
//
// Purpose:
//   High-level PS/2 mouse controller for the Nexys A7 USB-HID mouse input path.
//
//   This module initializes the PS/2 mouse and then forwards received mouse
//   bytes to the packet decoder. It sits above the low-level PS/2 receiver and
//   transmitter modules so the rest of the mouse subsystem does not need to
//   handle startup commands or ACK checking.
//
// Initialization algorithm:
//   1) Wait briefly after reset so the USB-HID/PS/2 bridge and mouse settle.
//   2) Send 8'hF4, the PS/2 "Enable Data Reporting" command.
//   3) Wait for transmit completion.
//   4) Wait for the mouse ACK byte, 8'hFA.
//   5) After ACK, assert init_done and forward incoming mouse bytes.
//
// Example:
//   After reset, the FSM sends 8'hF4. If the mouse responds with 8'hFA, the FSM
//   enters STREAM state. A later received byte such as 8'h08 is copied to
//   mouse_byte and mouse_byte_valid_pulse is asserted for one clock.
//
// Interface summary:
//   - clk / resetn:
//       System clock and synchronized active-low reset.
//   - ps2_clk_raw / ps2_data_raw:
//       Sampled PS/2 line values from top-level open-collector wiring.
//   - ps2_clk_drive_low / ps2_data_drive_low:
//       Drive-low controls passed back to the top level.
//   - init_done:
//       High once stream reporting has been enabled.
//   - mouse_byte / mouse_byte_valid_pulse:
//       Clean received byte stream for the mouse packet decoder.
//   - rx_error_pulse_dbg / tx_error_pulse_dbg:
//       Debug pulses for low-level PS/2 receive/transmit problems.
//
// Notes:
//   - This module does not directly own the inout PS/2 pins.
//   - Top-level logic must implement the open-collector behavior.
//   - The FSM is fully synchronous and uses non-blocking assignments.
//------------------------------------------------------------------------------

module mouse_ps2_ctrl #(
    parameter integer CLK_HZ          = 100_000_000, // System clock frequency in Hz
    parameter integer STARTUP_WAIT_MS = 20           // Startup delay before sending 0xF4
)(
    input  wire       clk,                    // System clock
    input  wire       resetn,                 // Synchronized active-low reset

    input  wire       ps2_clk_raw,            // Sampled PS/2 clock line from top level
    input  wire       ps2_data_raw,           // Sampled PS/2 data line from top level

    output wire       ps2_clk_drive_low,      // Pull PS/2 clock low when 1, release when 0
    output wire       ps2_data_drive_low,     // Pull PS/2 data low when 1, release when 0

    output reg        init_done,              // High after mouse stream mode is enabled
    output reg  [7:0] mouse_byte,             // Latest received mouse byte
    output reg        mouse_byte_valid_pulse, // One-clock valid pulse for mouse_byte

    output wire       rx_error_pulse_dbg,     // Debug pulse for PS/2 receive frame error
    output wire       tx_error_pulse_dbg      // Debug pulse for PS/2 transmit/ACK error
);

    //--------------------------------------------------------------------------
    // Local timing and FSM parameters
    //
    // STARTUP_WAIT_CLKS converts the millisecond startup delay into clk cycles.
    // The FSM then uses this delay before sending the mouse enable command.
    //--------------------------------------------------------------------------
    localparam integer STARTUP_WAIT_CLKS = (CLK_HZ / 1000) * STARTUP_WAIT_MS;

    localparam [2:0] S_BOOT_WAIT   = 3'd0; // Wait for mouse/bridge to settle
    localparam [2:0] S_SEND_F4     = 3'd1; // Start transmit of enable command
    localparam [2:0] S_WAIT_TX     = 3'd2; // Wait for transmit completion
    localparam [2:0] S_WAIT_ACK    = 3'd3; // Wait for 0xFA ACK from mouse
    localparam [2:0] S_STREAM      = 3'd4; // Forward live mouse bytes

    //--------------------------------------------------------------------------
    // Internal receive-side wires
    //
    // ps2_rx converts serial PS/2 frames into bytes and reports frame errors.
    //--------------------------------------------------------------------------
    wire [7:0] rx_data_w;            // Byte received by PS/2 receiver
    wire       rx_valid_pulse_w;     // One-clock pulse when rx_data_w is valid
    wire       rx_error_pulse_w;     // One-clock pulse on receive error

    //--------------------------------------------------------------------------
    // Internal transmit-side wires
    //
    // ps2_tx sends the host command byte and reports completion or error.
    //--------------------------------------------------------------------------
    wire       tx_busy_w;            // Transmitter busy status
    wire       tx_done_pulse_w;      // One-clock pulse when transmit completes
    wire       tx_error_pulse_w;     // One-clock pulse on transmit error

    //--------------------------------------------------------------------------
    // Internal FSM registers
    //--------------------------------------------------------------------------
    reg [2:0]  state_ff;             // Current initialization/streaming FSM state
    reg [31:0] startup_wait_count_ff;// Counts startup delay cycles
    reg        tx_start_pulse_ff;    // One-clock transmit-start pulse
    reg [7:0]  tx_data_ff;           // Byte presented to PS/2 transmitter
    reg        ignore_echo_ff;       // Used to ignore observed outbound 0xF4 echo

    //--------------------------------------------------------------------------
    // Low-level PS/2 receiver
    //
    // Receives device-to-host PS/2 frames from the raw clock/data lines and
    // outputs complete bytes to this controller.
    //--------------------------------------------------------------------------
    ps2_rx u_ps2_rx (
        .clk            (clk),
        .resetn         (resetn),
        .ps2_clk_raw    (ps2_clk_raw),
        .ps2_data_raw   (ps2_data_raw),
        .rx_data        (rx_data_w),
        .rx_valid_pulse (rx_valid_pulse_w),
        .rx_error_pulse (rx_error_pulse_w)
    );

    //--------------------------------------------------------------------------
    // Low-level PS/2 transmitter
    //
    // Sends the host-to-device command byte. The top-level open-collector
    // interface uses ps2_clk_drive_low and ps2_data_drive_low.
    //--------------------------------------------------------------------------
    ps2_tx u_ps2_tx (
        .clk                (clk),
        .resetn             (resetn),
        .ps2_clk_raw        (ps2_clk_raw),
        .ps2_data_raw       (ps2_data_raw),
        .tx_data            (tx_data_ff),
        .tx_start_pulse     (tx_start_pulse_ff),
        .busy               (tx_busy_w),
        .tx_done_pulse      (tx_done_pulse_w),
        .tx_error_pulse     (tx_error_pulse_w),
        .ps2_clk_drive_low  (ps2_clk_drive_low),
        .ps2_data_drive_low (ps2_data_drive_low)
    );

    //--------------------------------------------------------------------------
    // Debug output assignments
    //
    // Expose low-level receiver/transmitter errors so top-level or testbench
    // logic can observe initialization and bus issues.
    //--------------------------------------------------------------------------
    assign rx_error_pulse_dbg = rx_error_pulse_w;
    assign tx_error_pulse_dbg = tx_error_pulse_w;

    //--------------------------------------------------------------------------
    // Main mouse initialization and streaming FSM
    //
    // This FSM performs the required PS/2 startup sequence before any mouse
    // bytes are forwarded:
    //   BOOT_WAIT -> SEND_F4 -> WAIT_TX -> WAIT_ACK -> STREAM
    //
    // Once STREAM is reached, every received PS/2 byte is forwarded as a
    // one-clock mouse_byte_valid_pulse for the packet decoder.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Default one-clock pulses low unless a state explicitly raises them.
        tx_start_pulse_ff      <= 1'b0;
        mouse_byte_valid_pulse <= 1'b0;

        // Return the controller to the startup state during reset.
        if (!resetn) begin
            state_ff                <= S_BOOT_WAIT;
            startup_wait_count_ff   <= 32'd0;
            tx_start_pulse_ff       <= 1'b0;
            tx_data_ff              <= 8'hF4;
            init_done               <= 1'b0;
            mouse_byte              <= 8'd0;
            mouse_byte_valid_pulse  <= 1'b0;
            ignore_echo_ff          <= 1'b0;
        end
        else begin
            case (state_ff)

                //--------------------------------------------------------------
                // BOOT_WAIT
                //
                // Let the board-side USB-HID/PS2 bridge and mouse settle before
                // sending the enable-streaming command.
                //--------------------------------------------------------------
                S_BOOT_WAIT: begin
                    init_done <= 1'b0;

                    // Keep counting until the configured startup delay expires.
                    if (startup_wait_count_ff < (STARTUP_WAIT_CLKS - 1)) begin
                        startup_wait_count_ff <= startup_wait_count_ff + 32'd1;
                    end
                    // Delay complete, so prepare to send the enable command.
                    else begin
                        startup_wait_count_ff <= 32'd0;
                        state_ff              <= S_SEND_F4;
                    end
                end

                //--------------------------------------------------------------
                // SEND_F4
                //
                // Start one PS/2 transmit operation for 8'hF4, which tells the
                // mouse to begin reporting movement packets.
                //--------------------------------------------------------------
                S_SEND_F4: begin
                    tx_data_ff        <= 8'hF4;
                    tx_start_pulse_ff <= 1'b1;
                    ignore_echo_ff    <= 1'b1;
                    state_ff          <= S_WAIT_TX;
                end

                //--------------------------------------------------------------
                // WAIT_TX
                //
                // Wait until the transmitter finishes sending 8'hF4. If the
                // transmit path reports an error, retry the command.
                //--------------------------------------------------------------
                S_WAIT_TX: begin
                    // Transmit completed, so the next expected byte is ACK.
                    if (tx_done_pulse_w) begin
                        state_ff <= S_WAIT_ACK;
                    end
                    // Transmit failed, so retry the enable command.
                    else if (tx_error_pulse_w) begin
                        state_ff <= S_SEND_F4;
                    end
                end

                //--------------------------------------------------------------
                // WAIT_ACK
                //
                // Wait for the mouse to acknowledge the enable command with
                // 8'hFA. Some simulations or bus observations may also see the
                // outbound 8'hF4 command, so one optional echo is ignored.
                //--------------------------------------------------------------
                S_WAIT_ACK: begin
                    // Process a newly received byte while waiting for ACK.
                    if (rx_valid_pulse_w) begin
                        // Ignore one observed 8'hF4 echo from the command phase.
                        if (ignore_echo_ff && (rx_data_w == 8'hF4)) begin
                            ignore_echo_ff <= 1'b0;
                        end
                        // ACK received, so mouse initialization is complete.
                        else if (rx_data_w == 8'hFA) begin
                            init_done      <= 1'b1;
                            ignore_echo_ff <= 1'b0;
                            state_ff       <= S_STREAM;
                        end
                    end

                    // If transmit reports an error while waiting, retry setup.
                    if (tx_error_pulse_w) begin
                        state_ff <= S_SEND_F4;
                    end
                end

                //--------------------------------------------------------------
                // STREAM
                //
                // Normal operating state. Every received byte is forwarded to
                // the packet decoder with a one-cycle valid pulse.
                //--------------------------------------------------------------
                S_STREAM: begin
                    init_done <= 1'b1;

                    // Forward each valid received byte into the mouse packet path.
                    if (rx_valid_pulse_w) begin
                        mouse_byte             <= rx_data_w;
                        mouse_byte_valid_pulse <= 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // Unknown state recovery
                //--------------------------------------------------------------
                default: begin
                    state_ff <= S_BOOT_WAIT;
                end
            endcase
        end
    end

endmodule