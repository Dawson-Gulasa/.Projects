`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// sd_prime_feeder.v
//
// Purpose:
//   Buffers parsed SD-card prime values and presents them to test_mode_ctrl with
//   a simple request/response handshake.
//
//   sd_prime_parser produces binary prime values from the SD text stream. This
//   module stores those parsed values in a small FIFO so Test Mode can request
//   one prime at a time without losing data if parsing and comparison happen at
//   different rates.
//
// Feeder algorithm:
//   1) start_read clears the FIFO and begins a fresh Test Mode read session.
//   2) Each cpu_lineflag_pulse enqueues one parsed prime value from cpu_data.
//   3) test_mode_ctrl pulses next_prime when it needs the next SD reference.
//   4) If the FIFO has data, one value is dequeued and sd_prime_valid pulses.
//   5) If a request arrives while the FIFO is empty, the request is held until
//      data becomes available.
//   6) When stream_done is high and the FIFO is empty, sd_end_of_file asserts.
//
// Example:
//   If the parser outputs 2, 3, and 5, the FIFO stores those values in order.
//   Each next_prime request returns one value:
//      request 1 -> sd_prime_value = 2
//      request 2 -> sd_prime_value = 3
//      request 3 -> sd_prime_value = 5
//
// Notes:
//   - The FIFO is intentionally small because this block only bridges the parser
//     stream and Test Mode comparison logic.
//   - This module fixes the earlier one-value overwrite issue by buffering
//     multiple parsed primes.
//   - Sequential logic uses non-blocking assignments only.
//   - No explicit encoded FSM is used; state is represented by FIFO pointers,
//     fifo_count_ff, request_pending_ff, and sd_end_of_file.
//------------------------------------------------------------------------------

module sd_prime_feeder #(
    parameter integer FIFO_DEPTH = 16, // Number of parsed primes that can be buffered
    parameter integer PTR_WIDTH  = 4   // Pointer width for the FIFO depth
)(
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk,                // System clock
    input  wire        resetn,             // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Control from test_mode_ctrl
    //--------------------------------------------------------------------------
    input  wire        start_read,         // One-clock pulse to begin a fresh SD read session
    input  wire        next_prime,         // One-clock pulse requesting the next SD prime

    //--------------------------------------------------------------------------
    // Upstream parsed-prime stream from sd_prime_parser
    //--------------------------------------------------------------------------
    input  wire [31:0] cpu_data,           // Parsed prime value from SD text stream
    input  wire        cpu_lineflag_pulse, // One-clock pulse when cpu_data is valid
    input  wire        stream_done,        // Parser indicates SD stream has ended

    //--------------------------------------------------------------------------
    // Outputs to test_mode_ctrl
    //--------------------------------------------------------------------------
    output reg         sd_prime_valid,     // One-clock pulse when sd_prime_value is valid
    output reg  [31:0] sd_prime_value,     // Next buffered SD prime value
    output reg         sd_end_of_file      // High once parser is done and FIFO is empty
);

    //--------------------------------------------------------------------------
    // Small FIFO storage for parsed SD primes
    //
    // Parsed values are written at wr_ptr_ff and read at rd_ptr_ff. fifo_count_ff
    // tracks how many values are currently stored.
    //--------------------------------------------------------------------------
    reg [31:0] fifo_mem_a [0:FIFO_DEPTH-1]; // FIFO memory for parsed prime values

    reg [PTR_WIDTH-1:0] wr_ptr_ff;          // FIFO write pointer
    reg [PTR_WIDTH-1:0] rd_ptr_ff;          // FIFO read pointer
    reg [PTR_WIDTH:0]   fifo_count_ff;      // Number of entries currently in FIFO
    reg                 request_pending_ff; // Held request when next_prime arrives before data

    //--------------------------------------------------------------------------
    // Combinational helper signals
    //
    // These wires decide whether the current cycle enqueues data, dequeues data,
    // or both. fifo_count_next_w is used for accurate EOF detection after this
    // cycle's FIFO movement.
    //--------------------------------------------------------------------------
    wire fifo_empty_w;                      // High when FIFO has no parsed primes
    wire fifo_full_w;                       // High when FIFO cannot accept another value
    wire request_active_w;                  // Current or previously held next-prime request
    wire do_enqueue_w;                      // Enqueue one parsed prime this cycle
    wire do_dequeue_w;                      // Dequeue one parsed prime this cycle
    wire [PTR_WIDTH:0] fifo_count_next_w;   // FIFO count after enqueue/dequeue activity

    assign fifo_empty_w      = (fifo_count_ff == {PTR_WIDTH+1{1'b0}});
    assign fifo_full_w       = (fifo_count_ff == FIFO_DEPTH[PTR_WIDTH:0]);
    assign request_active_w  = request_pending_ff | next_prime;
    assign do_enqueue_w      = cpu_lineflag_pulse && !fifo_full_w;
    assign do_dequeue_w      = request_active_w && !fifo_empty_w;
    assign fifo_count_next_w = fifo_count_ff +
                               (do_enqueue_w ? {{PTR_WIDTH{1'b0}},1'b1} : {PTR_WIDTH+1{1'b0}}) -
                               (do_dequeue_w ? {{PTR_WIDTH{1'b0}},1'b1} : {PTR_WIDTH+1{1'b0}});

    //--------------------------------------------------------------------------
    // FIFO/request sequential logic
    //
    // This block manages the FIFO, held request bit, output valid pulse, and EOF
    // indication for one Test Mode SD reference stream.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset all FIFO pointers, request state, and outputs.
        if (!resetn) begin
            wr_ptr_ff          <= {PTR_WIDTH{1'b0}};
            rd_ptr_ff          <= {PTR_WIDTH{1'b0}};
            fifo_count_ff      <= {PTR_WIDTH+1{1'b0}};
            request_pending_ff <= 1'b0;

            sd_prime_valid     <= 1'b0;
            sd_prime_value     <= 32'd0;
            sd_end_of_file     <= 1'b0;
        end
        else begin
            // sd_prime_valid is a one-clock pulse unless a dequeue happens below.
            sd_prime_valid <= 1'b0;

            //------------------------------------------------------------------
            // Fresh Test Mode read session.
            //------------------------------------------------------------------
            if (start_read) begin
                wr_ptr_ff          <= {PTR_WIDTH{1'b0}};
                rd_ptr_ff          <= {PTR_WIDTH{1'b0}};
                fifo_count_ff      <= {PTR_WIDTH+1{1'b0}};
                request_pending_ff <= 1'b0;

                sd_prime_valid     <= 1'b0;
                sd_prime_value     <= 32'd0;
                sd_end_of_file     <= 1'b0;
            end
            else begin
                //----------------------------------------------------------------
                // Request tracking.
                //
                // If Test Mode asks for a value while the FIFO is empty, hold that
                // request so the next parsed value can be returned immediately.
                //----------------------------------------------------------------
                if (request_active_w && fifo_empty_w) begin
                    request_pending_ff <= 1'b1;
                end
                // Once a value is dequeued, the outstanding request is satisfied.
                else if (do_dequeue_w) begin
                    request_pending_ff <= 1'b0;
                end
                // No change to request state.
                else begin
                    request_pending_ff <= request_pending_ff;
                end

                //----------------------------------------------------------------
                // Enqueue newly parsed SD prime.
                //----------------------------------------------------------------
                if (do_enqueue_w) begin
                    fifo_mem_a[wr_ptr_ff] <= cpu_data;
                    wr_ptr_ff             <= wr_ptr_ff + {{(PTR_WIDTH-1){1'b0}},1'b1};
                end
                // No enqueue this cycle, so hold the write pointer.
                else begin
                    wr_ptr_ff             <= wr_ptr_ff;
                end

                //----------------------------------------------------------------
                // Dequeue next prime to the Test Mode controller.
                //----------------------------------------------------------------
                if (do_dequeue_w) begin
                    sd_prime_valid <= 1'b1;
                    sd_prime_value <= fifo_mem_a[rd_ptr_ff];
                    rd_ptr_ff      <= rd_ptr_ff + {{(PTR_WIDTH-1){1'b0}},1'b1};
                end
                // No dequeue this cycle, so hold output value and read pointer.
                else begin
                    sd_prime_valid <= 1'b0;
                    sd_prime_value <= sd_prime_value;
                    rd_ptr_ff      <= rd_ptr_ff;
                end

                //----------------------------------------------------------------
                // Update FIFO occupancy after enqueue/dequeue decisions.
                //----------------------------------------------------------------
                fifo_count_ff <= fifo_count_next_w;

                //----------------------------------------------------------------
                // End-of-file detection.
                //
                // EOF becomes true only after the parser is done and all buffered
                // values have been returned to Test Mode.
                //----------------------------------------------------------------
                if (stream_done && (fifo_count_next_w == {PTR_WIDTH+1{1'b0}})) begin
                    sd_end_of_file <= 1'b1;
                end
                // Once asserted, EOF remains high until reset or start_read.
                else begin
                    sd_end_of_file <= sd_end_of_file;
                end
            end
        end
    end

endmodule