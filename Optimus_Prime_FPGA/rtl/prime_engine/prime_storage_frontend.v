`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// prime_storage_frontend.v
//
// Purpose:
//   Storage-facing frontend for the prime subsystem.
//
//   This module receives prime_found events from prime_controller and turns
//   them into ordered storage writes. It also accepts read requests from the UI
//   or Test Mode controller and forwards them to the backend when it is safe.
//
// Why this module is needed:
//   The DDR-backed storage path can only accept one command at a time. A new
//   prime may be found while the backend is busy, and a read request may arrive
//   while queued writes are still draining. This frontend prevents those events
//   from being lost by using:
//     1) A small write queue for prime-found events
//     2) A one-entry held read request register
//
// Storage/write algorithm:
//   1) When prime_found_pulse arrives, accept the event if the queue is not full
//      and the index is inside DEPTH.
//   2) Store {prime_found_index, prime_found_value} into the write queue.
//   3) When the backend is ready, issue queued writes in FIFO order.
//   4) Reads wait until queued writes are drained so readback sees the latest
//      completed run data.
//
// Example:
//   If primes 2, 3, and 5 are found while DDR is busy, they are queued as:
//      address 0 -> 2
//      address 1 -> 3
//      address 2 -> 5
//   Once the backend becomes ready, the frontend writes them out in that order.
//
// New-run behavior:
//   - start_new_run clears stored_count and pending queue/read bookkeeping.
//   - Backend memory contents are not physically cleared.
//   - New prime data overwrites from address 0 upward.
//
// Notes:
//   - No synthesis for-loops are used.
//   - Writes have priority over reads so Test Mode readback does not begin until
//     the current run's queued writes have drained.
//   - This module contains queue/read arbitration logic, but no explicit encoded
//     FSM. State is represented by the queue pointers/count and read-pending bit.
//------------------------------------------------------------------------------

module prime_storage_frontend #(
    parameter integer DATA_WIDTH   = 32,    // Width of each stored prime value
    parameter integer ADDR_WIDTH   = 16,    // Width of storage address/index
    parameter integer DEPTH        = 65536, // Maximum number of valid stored entries
    parameter integer QUEUE_DEPTH  = 1024,  // Number of buffered write events
    parameter integer QUEUE_AWIDTH = 10     // Address width for write queue pointers
)(
    input  wire                    clk,               // System clock
    input  wire                    rst_n,             // Active-low synchronized reset
    input  wire                    start_new_run,     // Clears storage bookkeeping for a new run
    input  wire                    prime_found_pulse, // One-clock pulse from prime_controller
    input  wire [DATA_WIDTH-1:0]   prime_found_value, // Prime value from prime_controller
    input  wire [31:0]             prime_found_index, // Zero-based index for the found prime
    input  wire                    rd_en,             // One-clock read request pulse
    input  wire [ADDR_WIDTH-1:0]   rd_addr,           // Requested storage read address

    output wire [31:0]             stored_count,      // Number of valid stored entries
    output wire                    storage_full,      // High when storage capacity has been reached
    output wire [DATA_WIDTH-1:0]   rd_data,           // Readback data from backend storage
    output wire                    rd_data_valid,     // One-clock pulse when rd_data is valid

    //--------------------------------------------------------------------------
    // DDR2 bridge interface
    //--------------------------------------------------------------------------
    output wire                    ddr_wr_req,        // One-clock DDR write request
    output wire [ADDR_WIDTH-1:0]   ddr_wr_addr,       // DDR write address/index
    output wire [DATA_WIDTH-1:0]   ddr_wr_data,       // DDR write data
    input  wire                    ddr_wr_ack,        // One-clock DDR write acknowledge

    output wire                    ddr_rd_req,        // One-clock DDR read request
    output wire [ADDR_WIDTH-1:0]   ddr_rd_addr,       // DDR read address/index
    input  wire [DATA_WIDTH-1:0]   ddr_rd_data,       // DDR read data returned by bridge
    input  wire                    ddr_rd_data_valid  // One-clock DDR read-data-valid pulse
);

    //--------------------------------------------------------------------------
    // Registered bookkeeping outputs
    //
    // stored_count tracks how many addresses contain valid data for the current
    // run. storage_full reports when no more valid entries can be accepted.
    //--------------------------------------------------------------------------
    reg [31:0] stored_count_ff;       // Current valid stored-entry count
    reg [31:0] stored_count_n;        // Next valid stored-entry count

    reg        storage_full_ff;       // Current storage-full flag
    reg        storage_full_n;        // Next storage-full flag

    assign stored_count = stored_count_ff;
    assign storage_full = storage_full_ff;

    //--------------------------------------------------------------------------
    // Small FIFO-style write queue
    //
    // Each queue entry stores one pending backend write:
    //   queue_addr_a[i] = storage address/index
    //   queue_data_a[i] = prime value to write
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] queue_addr_a [0:QUEUE_DEPTH-1]; // Queued write addresses
    reg [DATA_WIDTH-1:0] queue_data_a [0:QUEUE_DEPTH-1]; // Queued write data values

    reg [QUEUE_AWIDTH-1:0] queue_wr_ptr_ff; // Current queue write pointer
    reg [QUEUE_AWIDTH-1:0] queue_wr_ptr_n;  // Next queue write pointer

    reg [QUEUE_AWIDTH-1:0] queue_rd_ptr_ff; // Current queue read pointer
    reg [QUEUE_AWIDTH-1:0] queue_rd_ptr_n;  // Next queue read pointer

    reg [QUEUE_AWIDTH:0]   queue_count_ff;  // Current number of queued writes
    reg [QUEUE_AWIDTH:0]   queue_count_n;   // Next number of queued writes

    wire queue_empty_w;                     // High when no writes are queued
    wire queue_full_w;                      // High when write queue cannot accept more
    wire prime_accept_w;                    // High when incoming prime event is queued

    assign queue_empty_w  = (queue_count_ff == {(QUEUE_AWIDTH+1){1'b0}});
    assign queue_full_w   = (queue_count_ff == QUEUE_DEPTH);

    //--------------------------------------------------------------------------
    // Prime-found accept condition
    //
    // A prime event is accepted only when it belongs to the current run, the
    // queue has space, and the requested storage index is inside the configured
    // storage depth.
    //--------------------------------------------------------------------------
    assign prime_accept_w =
        prime_found_pulse &&
        !start_new_run &&
        !queue_full_w &&
        (prime_found_index < DEPTH);

    //--------------------------------------------------------------------------
    // Held read-request registers
    //
    // A single read request can be held until the backend is ready and all
    // pending writes have completed.
    //--------------------------------------------------------------------------
    reg                  rd_pending_ff;      // Current held-read pending flag
    reg                  rd_pending_n;       // Next held-read pending flag
    reg [ADDR_WIDTH-1:0] rd_addr_hold_ff;    // Held read address
    reg [ADDR_WIDTH-1:0] rd_addr_hold_n;     // Next held read address

    //--------------------------------------------------------------------------
    // Backend command-ready status
    //
    // prime_storage_mem reports when it can accept one new read/write command.
    //--------------------------------------------------------------------------
    wire backend_cmd_ready_w;                // Backend is ready for one command

    //--------------------------------------------------------------------------
    // Backend command arbitration
    //
    // Writes have priority. Reads issue only when the write queue is empty so
    // readback observes all previously found primes from the current run.
    //--------------------------------------------------------------------------
    wire issue_backend_write_w;              // Issue one queued write to backend
    wire issue_backend_read_w;               // Issue one held read to backend

    wire [ADDR_WIDTH-1:0] mem_wr_addr_w;     // Address for next backend write
    wire [DATA_WIDTH-1:0] mem_wr_data_w;     // Data for next backend write

    assign issue_backend_write_w = (!queue_empty_w) && backend_cmd_ready_w;
    assign issue_backend_read_w  = rd_pending_ff && queue_empty_w && backend_cmd_ready_w;

    assign mem_wr_addr_w = queue_addr_a[queue_rd_ptr_ff];
    assign mem_wr_data_w = queue_data_a[queue_rd_ptr_ff];

    //--------------------------------------------------------------------------
    // Backend storage adapter
    //
    // prime_storage_mem converts simple write/read enables into the DDR bridge
    // request/acknowledge interface.
    //--------------------------------------------------------------------------
    prime_storage_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DEPTH      (DEPTH)
    ) u_prime_storage_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .wr_en             (issue_backend_write_w),
        .wr_addr           (mem_wr_addr_w),
        .wr_data           (mem_wr_data_w),
        .rd_en             (issue_backend_read_w),
        .rd_addr           (rd_addr_hold_ff),
        .rd_data           (rd_data),
        .rd_data_valid     (rd_data_valid),
        .cmd_ready         (backend_cmd_ready_w),
        .ddr_wr_req        (ddr_wr_req),
        .ddr_wr_addr       (ddr_wr_addr),
        .ddr_wr_data       (ddr_wr_data),
        .ddr_wr_ack        (ddr_wr_ack),
        .ddr_rd_req        (ddr_rd_req),
        .ddr_rd_addr       (ddr_rd_addr),
        .ddr_rd_data       (ddr_rd_data),
        .ddr_rd_data_valid (ddr_rd_data_valid)
    );

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // Updates bookkeeping registers, queue pointers/count, held read state, and
    // writes accepted prime events into the queue RAM.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Clear all frontend state during reset.
        if (!rst_n) begin
            stored_count_ff <= 32'd0;
            storage_full_ff <= 1'b0;

            queue_wr_ptr_ff <= {QUEUE_AWIDTH{1'b0}};
            queue_rd_ptr_ff <= {QUEUE_AWIDTH{1'b0}};
            queue_count_ff  <= {(QUEUE_AWIDTH+1){1'b0}};

            rd_pending_ff   <= 1'b0;
            rd_addr_hold_ff <= {ADDR_WIDTH{1'b0}};
        end
        else begin
            // Normal operation loads next-state bookkeeping values.
            stored_count_ff <= stored_count_n;
            storage_full_ff <= storage_full_n;

            queue_wr_ptr_ff <= queue_wr_ptr_n;
            queue_rd_ptr_ff <= queue_rd_ptr_n;
            queue_count_ff  <= queue_count_n;

            rd_pending_ff   <= rd_pending_n;
            rd_addr_hold_ff <= rd_addr_hold_n;

            //------------------------------------------------------------------
            // Enqueue one accepted prime-found event.
            //------------------------------------------------------------------
            if (prime_accept_w) begin
                queue_addr_a[queue_wr_ptr_ff] <= prime_found_index[ADDR_WIDTH-1:0];
                queue_data_a[queue_wr_ptr_ff] <= prime_found_value;
            end
            // No accepted prime this cycle, so leave the selected queue entry unchanged.
            else begin
                queue_addr_a[queue_wr_ptr_ff] <= queue_addr_a[queue_wr_ptr_ff];
                queue_data_a[queue_wr_ptr_ff] <= queue_data_a[queue_wr_ptr_ff];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Combinational bookkeeping and queue/read-hold logic
    //
    // This block computes the next values for stored-count bookkeeping, held
    // reads, and queue pointer/count updates.
    //--------------------------------------------------------------------------
    always @(*) begin
        stored_count_n = stored_count_ff;
        storage_full_n = storage_full_ff;

        queue_wr_ptr_n = queue_wr_ptr_ff;
        queue_rd_ptr_n = queue_rd_ptr_ff;
        queue_count_n  = queue_count_ff;

        rd_pending_n   = rd_pending_ff;
        rd_addr_hold_n = rd_addr_hold_ff;

        //----------------------------------------------------------------------
        // New run clears all frontend bookkeeping and pending command state.
        //----------------------------------------------------------------------
        if (start_new_run) begin
            stored_count_n = 32'd0;
            storage_full_n = 1'b0;

            queue_wr_ptr_n = {QUEUE_AWIDTH{1'b0}};
            queue_rd_ptr_n = {QUEUE_AWIDTH{1'b0}};
            queue_count_n  = {(QUEUE_AWIDTH+1){1'b0}};

            rd_pending_n   = 1'b0;
            rd_addr_hold_n = {ADDR_WIDTH{1'b0}};
        end
        else begin
            //------------------------------------------------------------------
            // Stored-count and full-flag bookkeeping.
            //------------------------------------------------------------------
            if (prime_accept_w) begin
                stored_count_n = prime_found_index + 32'd1;

                // Mark storage full when the accepted index reaches capacity.
                if ((prime_found_index + 32'd1) >= DEPTH) begin
                    storage_full_n = 1'b1;
                end
                // Accepted event is still inside available capacity.
                else begin
                    storage_full_n = 1'b0;
                end
            end
            // A prime arrived beyond DEPTH, so count holds and full flag asserts.
            else if (prime_found_pulse && (prime_found_index >= DEPTH)) begin
                stored_count_n = stored_count_ff;
                storage_full_n = 1'b1;
            end
            // No accepted storage event this cycle, so hold current bookkeeping.
            else begin
                stored_count_n = stored_count_ff;
                storage_full_n = storage_full_ff;
            end

            //------------------------------------------------------------------
            // Held read request logic.
            //------------------------------------------------------------------
            if (rd_en && !rd_pending_ff) begin
                rd_pending_n   = 1'b1;
                rd_addr_hold_n = rd_addr;
            end
            // The held read has been issued to the backend, so clear pending.
            else if (issue_backend_read_w) begin
                rd_pending_n   = 1'b0;
                rd_addr_hold_n = rd_addr_hold_ff;
            end
            // No change to held read state.
            else begin
                rd_pending_n   = rd_pending_ff;
                rd_addr_hold_n = rd_addr_hold_ff;
            end

            //------------------------------------------------------------------
            // Queue pointer/count update logic.
            //
            // Four cases are handled:
            //   1) enqueue and dequeue in the same cycle
            //   2) enqueue only
            //   3) dequeue only
            //   4) no queue movement
            //------------------------------------------------------------------
            if (prime_accept_w && issue_backend_write_w) begin
                queue_wr_ptr_n = queue_wr_ptr_ff + {{(QUEUE_AWIDTH-1){1'b0}},1'b1};
                queue_rd_ptr_n = queue_rd_ptr_ff + {{(QUEUE_AWIDTH-1){1'b0}},1'b1};
                queue_count_n  = queue_count_ff;
            end
            // A new write enters the queue, but no backend write leaves yet.
            else if (prime_accept_w) begin
                queue_wr_ptr_n = queue_wr_ptr_ff + {{(QUEUE_AWIDTH-1){1'b0}},1'b1};
                queue_rd_ptr_n = queue_rd_ptr_ff;
                queue_count_n  = queue_count_ff + {{QUEUE_AWIDTH{1'b0}},1'b1};
            end
            // One queued write is issued to the backend.
            else if (issue_backend_write_w) begin
                queue_wr_ptr_n = queue_wr_ptr_ff;
                queue_rd_ptr_n = queue_rd_ptr_ff + {{(QUEUE_AWIDTH-1){1'b0}},1'b1};
                queue_count_n  = queue_count_ff - {{QUEUE_AWIDTH{1'b0}},1'b1};
            end
            // Queue is unchanged this cycle.
            else begin
                queue_wr_ptr_n = queue_wr_ptr_ff;
                queue_rd_ptr_n = queue_rd_ptr_ff;
                queue_count_n  = queue_count_ff;
            end
        end
    end

endmodule