`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// prime_subsystem.v
//
// Purpose:
//   Top-level wrapper for the prime-compute and prime-storage backend.
//
//   This module connects the prime computation controller to the prime storage
//   frontend and exposes one clean interface to the rest of the project. The UI
//   can start/abort a compute run, observe live compute status, and read stored
//   prime values without manually wiring the controller and storage modules.
//
// System data flow:
//   1) prime_controller runs the selected prime mode.
//   2) Each discovered prime produces a prime_found event.
//   3) prime_storage_frontend receives that event and writes the prime to DDR.
//   4) Stored primes can later be read back by the UI or Test Mode controller.
//
// Supported compute modes:
//   2'b00 = SINGLE   Check whether one entered value is prime.
//   2'b01 = RANGE    Find primes over the selected range.
//   2'b10 = TIME     Find primes until the requested time limit is reached.
//   2'b11 = RESERVED Reserved/unused mode.
//
// Example:
//   In RANGE mode, if the controller finds primes 2, 3, and 5, it emits three
//   prime_found events with indices 0, 1, and 2. The storage frontend writes
//   those values to storage addresses 0, 1, and 2, and stored_count becomes 3.
//
// Notes:
//   - This wrapper is synthesizable.
//   - This wrapper contains no FSM directly; the FSMs live inside
//     prime_controller and prime_storage_frontend.
//   - Top-level logic beyond direct routing is intentionally avoided here.
//   - The storage backend is reached through prime_storage_frontend and the
//     external DDR bridge interface.
//------------------------------------------------------------------------------

module prime_subsystem #(
    parameter integer DATA_WIDTH   = 32,    // Width of each stored prime value
    parameter integer ADDR_WIDTH   = 16,    // Width of storage/DDR address bus
    parameter integer DEPTH        = 65536, // Maximum number of stored entries
    parameter integer QUEUE_DEPTH  = 1024,  // Depth of storage write queue
    parameter integer QUEUE_AWIDTH = 10     // Address width for storage write queue
)(
    input  wire                    clk,                // System clock
    input  wire                    rst_n,              // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Compute-control interface
    //--------------------------------------------------------------------------
    input  wire                    start,              // One-clock pulse to start a compute run
    input  wire                    abort,              // One-clock pulse to abort current compute run
    input  wire [1:0]              mode,               // Compute mode: 00=SINGLE, 01=RANGE, 10=TIME
    input  wire [31:0]             single_value,       // SINGLE-mode value to test
    input  wire [31:0]             range_start,        // RANGE-mode lower bound
    input  wire [31:0]             range_limit,        // RANGE-mode upper bound
    input  wire [31:0]             time_limit_sec,     // TIME-mode run length in seconds
    input  wire                    tick_1hz,           // One-clock 1 Hz timing pulse for TIME mode

    //--------------------------------------------------------------------------
    // Storage-control interface
    //--------------------------------------------------------------------------
    input  wire                    start_new_run,      // Clears storage bookkeeping for a new run
    input  wire                    rd_en,              // One-clock read request for stored prime
    input  wire [ADDR_WIDTH-1:0]   rd_addr,            // Address/index of stored prime to read

    //--------------------------------------------------------------------------
    // Compute-status interface
    //--------------------------------------------------------------------------
    output wire                    busy,               // High while compute run is active
    output wire                    done,               // One-clock pulse when compute run finishes
    output wire                    mode_complete,      // High after normal mode completion
    output wire [31:0]             prime_count,        // Total number of primes found in run
    output wire [31:0]             largest_prime,      // Largest prime found in run
    output wire [31:0]             current_candidate,  // Current candidate being checked
    output wire [31:0]             last_prime_found,   // Most recently found prime value
    output wire                    single_is_prime,    // SINGLE-mode result: 1 if input is prime
    output wire [31:0]             elapsed_seconds,    // Elapsed seconds counted during run

    //--------------------------------------------------------------------------
    // Recent-prime history from the controller
    //--------------------------------------------------------------------------
    output wire [639:0]            recent_primes_flat, // Packed recent-prime history, 20 x 32-bit
    output wire [4:0]              recent_valid_count, // Number of valid entries in recent history

    //--------------------------------------------------------------------------
    // Prime-found event outputs
    //
    // These signals are also routed internally to storage, but they are exposed
    // here so testbenches or higher-level debug logic can observe found primes.
    //--------------------------------------------------------------------------
    output wire                    prime_found_pulse,  // One-clock pulse when a prime is found
    output wire [31:0]             prime_found_value,  // Prime value associated with found event
    output wire [31:0]             prime_found_index,  // Zero-based storage index for found prime

    //--------------------------------------------------------------------------
    // Storage-status and readback interface
    //--------------------------------------------------------------------------
    output wire [31:0]             stored_count,       // Number of valid stored prime entries
    output wire                    storage_full,       // High when storage cannot accept more primes
    output wire [DATA_WIDTH-1:0]   rd_data,            // Readback data from storage
    output wire                    rd_data_valid,      // One-clock pulse when rd_data is valid

    //--------------------------------------------------------------------------
    // DDR2 bridge interface
    //
    // The storage frontend speaks this request/acknowledge style interface.
    // A higher-level DDR bridge moves these requests to the DDR controller.
    //--------------------------------------------------------------------------
    output wire                    ddr_wr_req,         // One-clock DDR write request
    output wire [ADDR_WIDTH-1:0]   ddr_wr_addr,        // DDR write address/index
    output wire [DATA_WIDTH-1:0]   ddr_wr_data,        // DDR write data/prime value
    input  wire                    ddr_wr_ack,         // One-clock DDR write acknowledge

    output wire                    ddr_rd_req,         // One-clock DDR read request
    output wire [ADDR_WIDTH-1:0]   ddr_rd_addr,        // DDR read address/index
    input  wire [DATA_WIDTH-1:0]   ddr_rd_data,        // DDR read data returned by bridge
    input  wire                    ddr_rd_data_valid   // One-clock DDR read-data-valid pulse
);

    //--------------------------------------------------------------------------
    // Internal prime-found event wires
    //
    // The controller generates these events. The storage frontend consumes them,
    // and the wrapper also forwards them to the module outputs.
    //--------------------------------------------------------------------------
    wire                    controller_prime_found_pulse; // Internal found-prime pulse
    wire [31:0]             controller_prime_found_value; // Internal found-prime value
    wire [31:0]             controller_prime_found_index; // Internal found-prime index

    //--------------------------------------------------------------------------
    // Prime controller
    //
    // Responsibilities:
    //   - Run SINGLE, RANGE, and TIME prime-computation modes.
    //   - Generate candidates and feed the primality checker.
    //   - Track count, largest prime, current candidate, and elapsed time.
    //   - Maintain a packed recent-prime history.
    //   - Emit one prime_found event for each discovered prime.
    //--------------------------------------------------------------------------
    prime_controller u_prime_controller (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (start),
        .abort             (abort),
        .mode              (mode),
        .single_value      (single_value),
        .range_start       (range_start),
        .range_limit       (range_limit),
        .time_limit_sec    (time_limit_sec),
        .tick_1hz          (tick_1hz),
        .busy              (busy),
        .done              (done),
        .mode_complete     (mode_complete),
        .prime_count       (prime_count),
        .largest_prime     (largest_prime),
        .current_candidate (current_candidate),
        .last_prime_found  (last_prime_found),
        .single_is_prime   (single_is_prime),
        .elapsed_seconds   (elapsed_seconds),
        .prime_found_pulse (controller_prime_found_pulse),
        .prime_found_value (controller_prime_found_value),
        .prime_found_index (controller_prime_found_index),
        .recent_primes_flat(recent_primes_flat),
        .recent_valid_count(recent_valid_count)
    );

    //--------------------------------------------------------------------------
    // Prime storage frontend
    //
    // Responsibilities:
    //   - Accept prime_found events from the controller.
    //   - Queue/write found primes to the DDR storage path.
    //   - Maintain stored_count and storage_full bookkeeping.
    //   - Provide indexed readback for the UI and Test Mode controller.
    //
    // Storage example:
    //   If prime_found_value = 32'd17 and prime_found_index = 5, the frontend
    //   requests a DDR write so storage entry 5 contains the value 17.
    //--------------------------------------------------------------------------
    prime_storage_frontend #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DEPTH        (DEPTH),
        .QUEUE_DEPTH  (QUEUE_DEPTH),
        .QUEUE_AWIDTH (QUEUE_AWIDTH)
    ) u_prime_storage_frontend (
        .clk               (clk),
        .rst_n             (rst_n),
        .start_new_run     (start_new_run),
        .prime_found_pulse (controller_prime_found_pulse),
        .prime_found_value (controller_prime_found_value),
        .prime_found_index (controller_prime_found_index),
        .rd_en             (rd_en),
        .rd_addr           (rd_addr),
        .stored_count      (stored_count),
        .storage_full      (storage_full),
        .rd_data           (rd_data),
        .rd_data_valid     (rd_data_valid),
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
    // Wrapper event outputs
    //
    // Expose the controller's prime-found event without changing the internal
    // controller-to-storage connection.
    //--------------------------------------------------------------------------
    assign prime_found_pulse = controller_prime_found_pulse;
    assign prime_found_value = controller_prime_found_value;
    assign prime_found_index = controller_prime_found_index;

endmodule