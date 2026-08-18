`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// sd_byte_sync.v
//
// Purpose:
//   Cross a byte-stream event from clk_sd into clk_cpu safely.
//
// Source domain (clk_sd):
//   - sd_byte_valid is a 1-cycle pulse indicating sd_byte is valid
//   - sd_stream_done is a level that goes high when the file stream is done
//
// Destination domain (clk_cpu):
//   - cpu_byte_valid is a 1-cycle pulse for each transferred byte
//   - cpu_byte is the transferred byte value
//   - cpu_stream_done is the synchronized stream-done level
//
// CDC strategy:
//   - In the SD clock domain, latch each byte and toggle an event bit.
//   - In the CPU clock domain, synchronize the toggle and detect changes.
//   - Synchronize the done level separately with a standard 2-flop sync.
//------------------------------------------------------------------------------
module sd_byte_sync (
    //--------------------------------------------------------------------------
    // Source domain clock / reset
    //--------------------------------------------------------------------------
    input  wire       clk_sd,
    input  wire       resetn_sd,

    //--------------------------------------------------------------------------
    // Destination domain clock / reset
    //--------------------------------------------------------------------------
    input  wire       clk_cpu,
    input  wire       resetn_cpu,

    //--------------------------------------------------------------------------
    // Source-domain byte stream
    //--------------------------------------------------------------------------
    input  wire [7:0] sd_byte,
    input  wire       sd_byte_valid,
    input  wire       sd_stream_done,

    //--------------------------------------------------------------------------
    // CPU-domain outputs
    //--------------------------------------------------------------------------
    output reg  [7:0] cpu_byte,
    output reg        cpu_byte_valid,
    output reg        cpu_stream_done
);

    //--------------------------------------------------------------------------
    // Source-domain holding registers
    //--------------------------------------------------------------------------
    reg [7:0] sd_byte_hold_ff;
    reg       sd_toggle_ff;

    always @(posedge clk_sd) begin
        if (!resetn_sd) begin
            sd_byte_hold_ff <= 8'd0;
            sd_toggle_ff    <= 1'b0;
        end
        else begin
            if (sd_byte_valid) begin
                sd_byte_hold_ff <= sd_byte;
                sd_toggle_ff    <= ~sd_toggle_ff;
            end
            else begin
                sd_byte_hold_ff <= sd_byte_hold_ff;
                sd_toggle_ff    <= sd_toggle_ff;
            end
        end
    end

    //--------------------------------------------------------------------------
    // CPU-domain synchronizers
    //--------------------------------------------------------------------------
    reg [1:0] toggle_sync_ff;
    reg       toggle_prev_ff;

    reg [7:0] byte_sync_s1_ff;
    reg [7:0] byte_sync_s2_ff;

    reg [1:0] done_sync_ff;

    always @(posedge clk_cpu) begin
        if (!resetn_cpu) begin
            toggle_sync_ff <= 2'b00;
            toggle_prev_ff <= 1'b0;

            byte_sync_s1_ff <= 8'd0;
            byte_sync_s2_ff <= 8'd0;

            done_sync_ff    <= 2'b00;

            cpu_byte        <= 8'd0;
            cpu_byte_valid  <= 1'b0;
            cpu_stream_done <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Synchronize byte-event toggle
            //------------------------------------------------------------------
            toggle_sync_ff <= {toggle_sync_ff[0], sd_toggle_ff};
            toggle_prev_ff <= toggle_sync_ff[1];

            //------------------------------------------------------------------
            // Retiming stages for held byte bus
            //------------------------------------------------------------------
            byte_sync_s1_ff <= sd_byte_hold_ff;
            byte_sync_s2_ff <= byte_sync_s1_ff;

            //------------------------------------------------------------------
            // Synchronize done level
            //------------------------------------------------------------------
            done_sync_ff    <= {done_sync_ff[0], sd_stream_done};

            //------------------------------------------------------------------
            // Generate CPU-domain outputs
            //------------------------------------------------------------------
            cpu_byte_valid  <= toggle_sync_ff[1] ^ toggle_prev_ff;
            cpu_stream_done <= done_sync_ff[1];

            if (toggle_sync_ff[1] ^ toggle_prev_ff) begin
                cpu_byte <= byte_sync_s2_ff;
            end
            else begin
                cpu_byte <= cpu_byte;
            end
        end
    end

endmodule