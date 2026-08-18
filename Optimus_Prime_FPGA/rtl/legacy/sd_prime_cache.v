`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// sd_prime_cache.v
//
// Purpose:
//   Caches parsed prime values from the SD-card text file and replays them later
//   to test_mode_ctrl using the same request/valid/end-of-file interface used by
//   the live SD feeder.
//
// Why this module is needed:
//   The SD file is parsed during an earlier load phase, but Test Mode may run
//   later after the file parser is no longer actively producing values. This
//   module stores the parsed primes in a local cache so Test Mode can request
//   them one at a time during comparison.
//
// Load behavior:
//   - load_prime_valid pulses when load_prime_value contains a parsed prime.
//   - Each accepted value is written into cache_mem_a at stored_count.
//   - stored_count increments after each accepted prime.
//   - load_done marks that no more SD primes will be loaded.
//
// Replay behavior:
//   - start_read begins a fresh replay from cache index 0.
//   - next_prime requests the next cached prime.
//   - sd_prime_valid pulses for one clock when sd_prime_value is valid.
//   - sd_end_of_file asserts once the replay reaches stored_count and loading
//     has completed.
//
// Cache example:
//   If the SD parser loads 2, 3, and 5:
//      cache_mem_a[0] = 2
//      cache_mem_a[1] = 3
//      cache_mem_a[2] = 5
//      stored_count   = 3
//
//   During replay, three next_prime requests return 2, then 3, then 5. A later
//   request asserts sd_end_of_file after cache_load_done is high.
//
// Notes:
//   - This module keeps test_mode_ctrl unchanged by matching its expected SD
//     request/response interface.
//   - If more than DEPTH primes are parsed, extra values are ignored.
//   - This module does not use an encoded FSM. State is represented by
//     stored_count, cache_load_done, replay_idx_ff, and the replay outputs.
//------------------------------------------------------------------------------

module sd_prime_cache #(
    parameter integer DEPTH      = 256, // Maximum number of SD primes cached
    parameter integer ADDR_WIDTH = 8    // Cache address width; DEPTH should be 2^ADDR_WIDTH
)(
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk,              // System clock
    input  wire        resetn,           // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Load interface from SD parser
    //--------------------------------------------------------------------------
    input  wire        load_prime_valid, // One-clock pulse when load_prime_value is valid
    input  wire [31:0] load_prime_value, // Parsed prime value to store in cache
    input  wire        load_done,        // High/pulse indicating SD loading is complete

    //--------------------------------------------------------------------------
    // Replay interface to test_mode_ctrl
    //--------------------------------------------------------------------------
    input  wire        start_read,       // Starts a fresh replay from cache index 0
    input  wire        next_prime,       // Requests the next cached prime value
    output reg         sd_prime_valid,   // One-clock pulse when sd_prime_value is valid
    output reg  [31:0] sd_prime_value,   // Cached SD prime value returned to Test Mode
    output reg         sd_end_of_file,   // High when replay has reached the loaded end

    //--------------------------------------------------------------------------
    // Status/debug outputs
    //--------------------------------------------------------------------------
    output reg  [15:0] stored_count,     // Number of parsed primes stored in cache
    output reg         cache_load_done   // High after the SD parser reports load_done
);

    //--------------------------------------------------------------------------
    // Local cache memory
    //
    // Each cache entry stores one parsed prime value from the SD text file.
    //--------------------------------------------------------------------------
    reg [31:0] cache_mem_a [0:DEPTH-1];

    //--------------------------------------------------------------------------
    // Replay index registers
    //
    // replay_idx_ff points to the next cached value that will be returned when
    // next_prime is requested.
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] replay_idx_ff;
    reg [ADDR_WIDTH-1:0] replay_idx_n;

    //--------------------------------------------------------------------------
    // Next-state registers for cache status and replay outputs
    //--------------------------------------------------------------------------
    reg [15:0] stored_count_n;
    reg        cache_load_done_n;

    reg        sd_prime_valid_n;
    reg [31:0] sd_prime_value_n;
    reg        sd_end_of_file_n;

    //--------------------------------------------------------------------------
    // Sequential state update and cache write
    //
    // This block updates all registered state and stores newly parsed SD primes
    // into the cache memory.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset all cache bookkeeping and replay outputs.
        if (!resetn) begin
            replay_idx_ff    <= {ADDR_WIDTH{1'b0}};
            stored_count     <= 16'd0;
            cache_load_done  <= 1'b0;

            sd_prime_valid   <= 1'b0;
            sd_prime_value   <= 32'd0;
            sd_end_of_file   <= 1'b0;
        end
        else begin
            // Normal operation loads next-state values.
            replay_idx_ff    <= replay_idx_n;
            stored_count     <= stored_count_n;
            cache_load_done  <= cache_load_done_n;

            sd_prime_valid   <= sd_prime_valid_n;
            sd_prime_value   <= sd_prime_value_n;
            sd_end_of_file   <= sd_end_of_file_n;

            //------------------------------------------------------------------
            // Store one parsed SD prime into the next free cache entry.
            //------------------------------------------------------------------
            if (load_prime_valid && (stored_count < DEPTH)) begin
                cache_mem_a[stored_count[ADDR_WIDTH-1:0]] <= load_prime_value;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Cache load and replay next-state logic
    //
    // This block handles both phases:
    //   1) Loading parsed values into the cache
    //   2) Replaying cached values to Test Mode on request
    //--------------------------------------------------------------------------
    always @(*) begin
        // Hold current values by default.
        replay_idx_n       = replay_idx_ff;
        stored_count_n     = stored_count;
        cache_load_done_n  = cache_load_done;

        // sd_prime_valid is a one-clock pulse by default.
        sd_prime_valid_n   = 1'b0;
        sd_prime_value_n   = sd_prime_value;
        sd_end_of_file_n   = sd_end_of_file;

        //----------------------------------------------------------------------
        // Load path: count accepted parsed primes.
        //----------------------------------------------------------------------
        if (load_prime_valid && (stored_count < DEPTH)) begin
            stored_count_n = stored_count + 16'd1;
        end
        else begin
            stored_count_n = stored_count;
        end

        //----------------------------------------------------------------------
        // Load completion flag.
        //----------------------------------------------------------------------
        if (load_done) begin
            cache_load_done_n = 1'b1;
        end
        else begin
            cache_load_done_n = cache_load_done;
        end

        //----------------------------------------------------------------------
        // Replay path: restart from the beginning of the cached prime list.
        //----------------------------------------------------------------------
        if (start_read) begin
            replay_idx_n     = {ADDR_WIDTH{1'b0}};
            sd_prime_valid_n = 1'b0;
            sd_prime_value_n = 32'd0;
            sd_end_of_file_n = 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Serve one cached value when Test Mode requests the next prime.
            //------------------------------------------------------------------
            if (next_prime) begin
                // A cached entry is available, so return it and advance replay.
                if (replay_idx_ff < stored_count[ADDR_WIDTH-1:0]) begin
                    sd_prime_valid_n = 1'b1;
                    sd_prime_value_n = cache_mem_a[replay_idx_ff];
                    replay_idx_n     = replay_idx_ff + {{(ADDR_WIDTH-1){1'b0}},1'b1};
                    sd_end_of_file_n = 1'b0;
                end
                // No more cached entries remain and loading is complete.
                else if (cache_load_done) begin
                    sd_prime_valid_n = 1'b0;
                    sd_prime_value_n = sd_prime_value;
                    sd_end_of_file_n = 1'b1;
                    replay_idx_n     = replay_idx_ff;
                end
                // Cache is temporarily empty because loading has not finished yet.
                else begin
                    sd_prime_valid_n = 1'b0;
                    sd_prime_value_n = sd_prime_value;
                    sd_end_of_file_n = 1'b0;
                    replay_idx_n     = replay_idx_ff;
                end
            end
            // No replay request this cycle, so hold output value and EOF state.
            else begin
                replay_idx_n     = replay_idx_ff;
                sd_prime_valid_n = 1'b0;
                sd_prime_value_n = sd_prime_value;
                sd_end_of_file_n = sd_end_of_file;
            end
        end
    end

endmodule