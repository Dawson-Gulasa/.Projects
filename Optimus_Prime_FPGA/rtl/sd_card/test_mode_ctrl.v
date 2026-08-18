`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// test_mode_ctrl.v
//
// Purpose:
//   Controls Test Mode by comparing primes stored in DDR-backed storage against
//   prime values parsed from the SD-card text stream.
//
//   This module is the main comparison engine for the project requirement that
//   stored computed primes must be checked against an SD-card reference file.
//
// Test Mode comparison algorithm:
//   1) Wait in IDLE until start_test pulses.
//   2) Restart the SD feeder/parser path with sd_start.
//   3) If stored_count is zero, report no_data_stored and fail.
//   4) Request one stored prime from storage.
//   5) After the stored prime returns, request one SD prime.
//   6) Compare the two values.
//        - If equal, increment primes_checked and move to the next index.
//        - If different, latch both values and report failure.
//   7) If the SD stream ends before a mismatch, report pass.
//   8) If stored data ends but the SD stream still has another value, report
//      failure because the SD file contains extra expected primes.
//
// Example:
//   Stored primes: 2, 3, 5
//   SD primes:     2, 3, 7
//
//   The first two comparisons pass. On the third comparison, stored_value = 5
//   and sd_prime_value = 7, so test_failed asserts and the mismatch values are
//   latched for display.
//
// Notes:
//   - Sequential logic uses non-blocking assignments only.
//   - Combinational logic uses blocking assignments only.
//   - sd_next is generated only when the FSM is ready to wait for sd_prime_valid.
//   - This module contains the main Test Mode FSM.
//------------------------------------------------------------------------------
module test_mode_ctrl #(
    parameter integer ADDR_WIDTH = 16 // Width of stored-prime read address
)(
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire                    clk,             // System clock
    input  wire                    resetn,          // Active-low synchronized reset

    //--------------------------------------------------------------------------
    // Control inputs
    //--------------------------------------------------------------------------
    input  wire                    start_test,      // One-clock pulse to begin Test Mode
    input  wire                    abort_test,      // Abort Test Mode and return to idle

    //--------------------------------------------------------------------------
    // Stored-prime interface
    //--------------------------------------------------------------------------
    input  wire [31:0]             stored_count,    // Number of valid primes stored in memory
    output reg                     rd_en,           // One-clock stored-prime read request
    output reg  [ADDR_WIDTH-1:0]   rd_addr,         // Stored-prime read address/index
    input  wire [31:0]             rd_data,         // Stored-prime read data
    input  wire                    rd_data_valid,   // One-clock pulse when rd_data is valid

    //--------------------------------------------------------------------------
    // SD-prime interface
    //--------------------------------------------------------------------------
    output reg                     sd_start,        // One-clock pulse to restart SD prime feeder
    output reg                     sd_next,         // One-clock pulse requesting next SD prime
    input  wire                    sd_prime_valid,  // One-clock pulse when sd_prime_value is valid
    input  wire [31:0]             sd_prime_value,  // Prime value parsed from SD stream
    input  wire                    sd_end_of_file,  // High when SD feeder/parser has reached end

    //--------------------------------------------------------------------------
    // Status outputs to UI
    //--------------------------------------------------------------------------
    output reg                     test_running,    // High while comparison is active
    output reg                     test_passed,     // High when comparison completes with pass
    output reg                     test_failed,     // High when comparison fails
    output reg                     no_data_stored,  // High when Test Mode started with no stored data
    output reg  [23:0]             primes_checked,  // Number of successful comparisons completed
    output reg  [26:0]             fail_stored_val, // Stored value involved in first mismatch
    output reg  [26:0]             fail_sd_val      // SD value involved in first mismatch
);

    //--------------------------------------------------------------------------
    // Test Mode FSM encoding
    //
    // The FSM alternates between requesting stored data and SD data, then
    // compares the returned values.
    //--------------------------------------------------------------------------
    localparam [2:0] S_IDLE          = 3'd0; // Waiting for start_test
    localparam [2:0] S_CHECK_DATA    = 3'd1; // Check whether any stored data exists
    localparam [2:0] S_REQ_STORED    = 3'd2; // Request stored prime at compare_index
    localparam [2:0] S_WAIT_STORED   = 3'd3; // Wait for stored-prime read data
    localparam [2:0] S_REQ_SD        = 3'd4; // Request next SD prime
    localparam [2:0] S_WAIT_SD       = 3'd5; // Wait for SD prime and compare
    localparam [2:0] S_WAIT_SD_ONLY  = 3'd6; // Stored data ended; check for extra SD data
    localparam [2:0] S_DONE          = 3'd7; // Hold final pass/fail/no-data status

    //--------------------------------------------------------------------------
    // State and datapath registers
    //
    // Each *_ff signal stores current FSM/data state. Each *_n signal is the
    // combinational next value loaded on the next rising clock edge.
    //--------------------------------------------------------------------------
    reg [2:0]              state_ff;          // Current Test Mode FSM state
    reg [2:0]              state_n;           // Next Test Mode FSM state

    reg [ADDR_WIDTH-1:0]   compare_index_ff;  // Current stored-prime index being compared
    reg [ADDR_WIDTH-1:0]   compare_index_n;   // Next stored-prime compare index

    reg [31:0]             stored_value_ff;   // Stored prime value latched for comparison
    reg [31:0]             stored_value_n;    // Next stored prime value

    reg                    rd_en_n;           // Next stored-prime read-enable pulse
    reg [ADDR_WIDTH-1:0]   rd_addr_n;         // Next stored-prime read address

    reg                    sd_start_n;        // Next SD-start pulse
    reg                    sd_next_n;         // Next SD-next request pulse

    reg                    test_running_n;    // Next running status
    reg                    test_passed_n;     // Next pass status
    reg                    test_failed_n;     // Next fail status
    reg                    no_data_stored_n;  // Next no-data status

    reg [23:0]             primes_checked_n;  // Next successful-comparison count
    reg [26:0]             fail_stored_val_n; // Next stored mismatch value
    reg [26:0]             fail_sd_val_n;     // Next SD mismatch value

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // Updates the FSM state, read/SD request pulses, and UI status outputs.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset Test Mode to idle with all status outputs cleared.
        if (!resetn) begin
            state_ff         <= S_IDLE;
            compare_index_ff <= {ADDR_WIDTH{1'b0}};
            stored_value_ff  <= 32'd0;

            rd_en            <= 1'b0;
            rd_addr          <= {ADDR_WIDTH{1'b0}};

            sd_start         <= 1'b0;
            sd_next          <= 1'b0;

            test_running     <= 1'b0;
            test_passed      <= 1'b0;
            test_failed      <= 1'b0;
            no_data_stored   <= 1'b0;

            primes_checked   <= 24'd0;
            fail_stored_val  <= 27'd0;
            fail_sd_val      <= 27'd0;
        end
        // Normal operation loads the combinational next-state values.
        else begin
            state_ff         <= state_n;
            compare_index_ff <= compare_index_n;
            stored_value_ff  <= stored_value_n;

            rd_en            <= rd_en_n;
            rd_addr          <= rd_addr_n;

            sd_start         <= sd_start_n;
            sd_next          <= sd_next_n;

            test_running     <= test_running_n;
            test_passed      <= test_passed_n;
            test_failed      <= test_failed_n;
            no_data_stored   <= no_data_stored_n;

            primes_checked   <= primes_checked_n;
            fail_stored_val  <= fail_stored_val_n;
            fail_sd_val      <= fail_sd_val_n;
        end
    end

    //--------------------------------------------------------------------------
    // Test Mode FSM next-state logic
    //
    // This block controls the stored-prime read sequence, SD-prime request
    // sequence, comparison result, and final UI status flags.
    //--------------------------------------------------------------------------
    always @(*) begin
        // Hold current state/data by default.
        state_n           = state_ff;
        compare_index_n   = compare_index_ff;
        stored_value_n    = stored_value_ff;

        // rd_en, sd_start, and sd_next are one-clock pulses by default.
        rd_en_n           = 1'b0;
        rd_addr_n         = rd_addr;

        sd_start_n        = 1'b0;
        sd_next_n         = 1'b0;

        // Status flags hold until the FSM updates or abort clears them.
        test_running_n    = test_running;
        test_passed_n     = test_passed;
        test_failed_n     = test_failed;
        no_data_stored_n  = no_data_stored;

        primes_checked_n  = primes_checked;
        fail_stored_val_n = fail_stored_val;
        fail_sd_val_n     = fail_sd_val;

        // Abort immediately clears Test Mode and returns to idle.
        if (abort_test) begin
            state_n           = S_IDLE;
            compare_index_n   = {ADDR_WIDTH{1'b0}};
            stored_value_n    = 32'd0;

            rd_addr_n         = {ADDR_WIDTH{1'b0}};

            test_running_n    = 1'b0;
            test_passed_n     = 1'b0;
            test_failed_n     = 1'b0;
            no_data_stored_n  = 1'b0;

            primes_checked_n  = 24'd0;
            fail_stored_val_n = 27'd0;
            fail_sd_val_n     = 27'd0;
        end
        else begin
            case (state_ff)

                //------------------------------------------------------------------
                // IDLE
                //
                // Wait for the UI to start Test Mode. A new start clears old
                // status and restarts the SD feeder/parser stream.
                //------------------------------------------------------------------
                S_IDLE: begin
                    test_running_n    = 1'b0;
                    test_passed_n     = 1'b0;
                    test_failed_n     = 1'b0;
                    no_data_stored_n  = 1'b0;

                    primes_checked_n  = 24'd0;
                    compare_index_n   = {ADDR_WIDTH{1'b0}};
                    fail_stored_val_n = 27'd0;
                    fail_sd_val_n     = 27'd0;

                    // Begin a fresh comparison run when start_test is pulsed.
                    if (start_test) begin
                        test_running_n = 1'b1;
                        sd_start_n     = 1'b1;
                        state_n        = S_CHECK_DATA;
                    end
                    // Otherwise remain idle.
                    else begin
                        state_n = S_IDLE;
                    end
                end

                //------------------------------------------------------------------
                // CHECK_DATA
                //
                // Verify that the compute/storage path has produced at least one
                // stored prime before attempting SD comparison.
                //------------------------------------------------------------------
                S_CHECK_DATA: begin
                    // No stored data means Test Mode cannot compare anything.
                    if (stored_count == 32'd0) begin
                        test_running_n   = 1'b0;
                        test_failed_n    = 1'b1;
                        no_data_stored_n = 1'b1;
                        state_n          = S_DONE;
                    end
                    // Stored data exists, so request the first stored prime.
                    else begin
                        state_n = S_REQ_STORED;
                    end
                end

                //------------------------------------------------------------------
                // REQ_STORED
                //
                // Request the stored prime at compare_index. If all stored values
                // have already been compared, switch to checking whether the SD
                // stream has extra values.
                //------------------------------------------------------------------
                S_REQ_STORED: begin
                    // Read the next stored prime if the index is still valid.
                    if (compare_index_ff < stored_count[ADDR_WIDTH-1:0]) begin
                        rd_en_n   = 1'b1;
                        rd_addr_n = compare_index_ff;
                        state_n   = S_WAIT_STORED;
                    end
                    // Stored data ended; make sure SD also ends before passing.
                    else begin
                        state_n = S_WAIT_SD_ONLY;
                    end
                end

                //------------------------------------------------------------------
                // WAIT_STORED
                //
                // Wait for the DDR/storage path to return the requested stored
                // prime value.
                //------------------------------------------------------------------
                S_WAIT_STORED: begin
                    // Latch stored read data once it becomes valid.
                    if (rd_data_valid) begin
                        stored_value_n = rd_data;
                        state_n        = S_REQ_SD;
                    end
                    // Keep waiting for stored-prime readback.
                    else begin
                        state_n = S_WAIT_STORED;
                    end
                end

                //------------------------------------------------------------------
                // REQ_SD
                //
                // Request the next parsed prime from the SD feeder.
                //------------------------------------------------------------------
                S_REQ_SD: begin
                    sd_next_n = 1'b1;
                    state_n   = S_WAIT_SD;
                end

                //------------------------------------------------------------------
                // WAIT_SD
                //
                // Wait for the SD feeder to return one prime, then compare it
                // against the latched stored value.
                //------------------------------------------------------------------
                S_WAIT_SD: begin
                    // If SD ends here, all compared values matched, so pass.
                    if (sd_end_of_file) begin
                        test_running_n = 1'b0;
                        test_passed_n  = 1'b1;
                        state_n        = S_DONE;
                    end
                    // Compare the returned SD prime against the stored prime.
                    else if (sd_prime_valid) begin
                        // Match: count it and move to the next stored index.
                        if (stored_value_ff == sd_prime_value) begin
                            primes_checked_n = primes_checked + 24'd1;
                            compare_index_n  = compare_index_ff + {{(ADDR_WIDTH-1){1'b0}},1'b1};
                            state_n          = S_REQ_STORED;
                        end
                        // Mismatch: latch both values and report the first error.
                        else begin
                            test_running_n    = 1'b0;
                            test_failed_n     = 1'b1;
                            fail_stored_val_n = stored_value_ff[26:0];
                            fail_sd_val_n     = sd_prime_value[26:0];
                            state_n           = S_DONE;
                        end
                    end
                    // No SD value yet, so keep waiting.
                    else begin
                        state_n = S_WAIT_SD;
                    end
                end

                //------------------------------------------------------------------
                // WAIT_SD_ONLY
                //
                // All stored primes have been consumed. Request one more SD value
                // to determine whether the SD file also ended or contains extra
                // expected primes.
                //------------------------------------------------------------------
                S_WAIT_SD_ONLY: begin
                    sd_next_n = 1'b1;

                    // SD also ended, so all stored primes matched the reference.
                    if (sd_end_of_file) begin
                        test_running_n = 1'b0;
                        test_passed_n  = 1'b1;
                        state_n        = S_DONE;
                    end
                    // SD still has another prime, so stored data ended too early.
                    else if (sd_prime_valid) begin
                        test_running_n    = 1'b0;
                        test_failed_n     = 1'b1;
                        fail_stored_val_n = 27'd0;
                        fail_sd_val_n     = sd_prime_value[26:0];
                        state_n           = S_DONE;
                    end
                    // Wait until SD either returns a value or reports EOF.
                    else begin
                        state_n = S_WAIT_SD_ONLY;
                    end
                end

                //------------------------------------------------------------------
                // DONE
                //
                // Hold final pass/fail/no-data status until reset or abort.
                //------------------------------------------------------------------
                S_DONE: begin
                    state_n = S_DONE;
                end

                //------------------------------------------------------------------
                // Unknown state recovery
                //------------------------------------------------------------------
                default: begin
                    state_n = S_IDLE;
                end
            endcase
        end
    end

endmodule