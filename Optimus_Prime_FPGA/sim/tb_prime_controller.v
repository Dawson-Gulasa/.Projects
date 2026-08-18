 `timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_prime_controller.v
//
// Purpose:
//   Self-checking testbench for prime_controller.v.
//
// What this testbench verifies:
//   1) Reset / idle behavior
//   2) SINGLE mode correctness for prime and non-prime values
//   3) RANGE mode correctness, including prime_count, largest_prime,
//      last_prime_found, and prime_found event stream
//   4) RANGE mode edge cases:
//        - range_start > range_limit
//        - range_limit < 2
//        - even/odd starts around 2
//   5) TIME mode behavior with 1 Hz tick stimulus
//   6) Abort behavior while active
//   7) Recent-prime packed history correctness
//   8) Randomized RANGE-mode regression
//   9) Forced-fail mode to prove the testbench is not always-pass
//
// Test strategy:
//   - Uses the real prime_controller and its real internal prime_check_core.
//   - Maintains a software reference model for expected primes in each case.
//   - Tracks prime_found_pulse / value / index events during the run.
//   - Compares completion-state outputs against the reference model.
//   - Includes one-shot forced-fail corruption when FORCE_FAIL = 1.
//
// Notes:
//   - This is a controller-level testbench, not a storage-front-end testbench.
//   - tick_1hz is generated explicitly by the testbench only for TIME-mode cases.
//   - The controller's strict no-overshoot TIME policy is respected.
//------------------------------------------------------------------------------
module tb_prime_controller;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    //--------------------------------------------------------------------------
    // DUT inputs
    //--------------------------------------------------------------------------
    reg         start;
    reg         abort;
    reg  [1:0]  mode;
    reg  [31:0] single_value;
    reg  [31:0] range_start;
    reg  [31:0] range_limit;
    reg  [31:0] time_limit_sec;
    reg         tick_1hz;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire        busy;
    wire        done;
    wire        mode_complete;
    wire [31:0] prime_count;
    wire [31:0] largest_prime;
    wire [31:0] current_candidate;
    wire [31:0] last_prime_found;
    wire        single_is_prime;
    wire [31:0] elapsed_seconds;
    wire        prime_found_pulse;
    wire [31:0] prime_found_value;
    wire [31:0] prime_found_index;
    wire [639:0] recent_primes_flat;
    wire [4:0]   recent_valid_count;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    prime_controller dut (
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
        .prime_found_pulse (prime_found_pulse),
        .prime_found_value (prime_found_value),
        .prime_found_index (prime_found_index),
        .recent_primes_flat(recent_primes_flat),
        .recent_valid_count(recent_valid_count)
    );

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer wait_ctr;

    integer r_start_i;
    integer r_limit_i;
    integer rand_nonneg_a_i;
    integer rand_nonneg_b_i;

    reg     force_fail_used_ff;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt the first checked expected prime_count
    // value so the testbench proves it is not an always-pass testbench.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 0;

    //--------------------------------------------------------------------------
    // Timing constants
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD_NS     = 10;
    localparam integer MAX_WAIT_CYCLES   = 400000;
    localparam integer RANDOM_RANGE_TESTS= 20;
    localparam integer MAX_REF_PRIMES    = 256;

    //--------------------------------------------------------------------------
    // Mode encoding (matches DUT)
    //--------------------------------------------------------------------------
    localparam [1:0] MODE_SINGLE   = 2'b00;
    localparam [1:0] MODE_RANGE    = 2'b01;
    localparam [1:0] MODE_TIME     = 2'b10;
    localparam [1:0] MODE_RESERVED = 2'b11;

    //--------------------------------------------------------------------------
    // Reference-model storage for expected prime lists
    //--------------------------------------------------------------------------
    integer ref_prime_count_i;
    integer ref_largest_prime_i;
    integer ref_last_prime_i;
    integer ref_single_is_prime_i;

    integer ref_prime_mem [0:MAX_REF_PRIMES-1];

    integer obs_prime_count_i;
    integer obs_prime_mem [0:MAX_REF_PRIMES-1];

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Utility task: initialize inputs
    //--------------------------------------------------------------------------
    task init_inputs;
        begin
            start          = 1'b0;
            abort          = 1'b0;
            mode           = MODE_SINGLE;
            single_value   = 32'd0;
            range_start    = 32'd0;
            range_limit    = 32'd0;
            time_limit_sec = 32'd0;
            tick_1hz       = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: synchronized reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            rst_n = 1'b0;
            init_inputs();

            repeat (4) @(posedge clk);

            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: report pass
    //--------------------------------------------------------------------------
    task report_pass;
        input [255:0] msg;
        begin
            total_passes = total_passes + 1;
            $display("PASS : %0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: report error
    //--------------------------------------------------------------------------
    task report_error;
        input [255:0] msg;
        begin
            total_errors = total_errors + 1;
            $display("FAIL : %0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait fixed cycles
    //--------------------------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Reference helper: primality test
    //--------------------------------------------------------------------------
    function is_prime_ref;
        input integer candidate_in;
        integer d_i;
        begin
            if (candidate_in < 2) begin
                is_prime_ref = 0;
            end
            else if (candidate_in == 2) begin
                is_prime_ref = 1;
            end
            else if ((candidate_in % 2) == 0) begin
                is_prime_ref = 0;
            end
            else begin
                is_prime_ref = 1;
                d_i = 3;
                while ((d_i * d_i) <= candidate_in) begin
                    if ((candidate_in % d_i) == 0) begin
                        is_prime_ref = 0;
                        d_i = candidate_in;
                    end
                    else begin
                        d_i = d_i + 2;
                    end
                end
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Reference helper: build expected prime list for SINGLE
    //--------------------------------------------------------------------------
    task build_single_reference;
        input integer single_value_in;
        begin
            ref_prime_count_i   = 0;
            ref_largest_prime_i = 0;
            ref_last_prime_i    = 0;
            ref_single_is_prime_i = is_prime_ref(single_value_in);

            if (ref_single_is_prime_i != 0) begin
                ref_prime_mem[0]   = single_value_in;
                ref_prime_count_i  = 1;
                ref_largest_prime_i= single_value_in;
                ref_last_prime_i   = single_value_in;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Reference helper: build expected prime list for RANGE
    //--------------------------------------------------------------------------
    task build_range_reference;
        input integer start_in;
        input integer limit_in;
        integer cand_i;
        begin
            ref_prime_count_i    = 0;
            ref_largest_prime_i  = 0;
            ref_last_prime_i     = 0;
            ref_single_is_prime_i= 0;

            if ((start_in > limit_in) || (limit_in < 2)) begin
                ref_prime_count_i   = 0;
                ref_largest_prime_i = 0;
                ref_last_prime_i    = 0;
            end
            else begin
                cand_i = start_in;
                while (cand_i <= limit_in) begin
                    if (is_prime_ref(cand_i) != 0) begin
                        if (ref_prime_count_i < MAX_REF_PRIMES) begin
                            ref_prime_mem[ref_prime_count_i] = cand_i;
                        end
                        ref_prime_count_i   = ref_prime_count_i + 1;
                        ref_largest_prime_i = cand_i;
                        ref_last_prime_i    = cand_i;
                    end
                    cand_i = cand_i + 1;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: clear observed prime event log
    //--------------------------------------------------------------------------
    task clear_observed_log;
        begin
            obs_prime_count_i = 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: pulse start
    //--------------------------------------------------------------------------
    task pulse_start;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: pulse abort
    //--------------------------------------------------------------------------
    task pulse_abort;
        begin
            @(posedge clk);
            abort <= 1'b1;
            @(posedge clk);
            abort <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: pulse tick_1hz
    //--------------------------------------------------------------------------
    task pulse_tick_1hz;
        begin
            @(posedge clk);
            tick_1hz <= 1'b1;
            @(posedge clk);
            tick_1hz <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for normal completion
    //--------------------------------------------------------------------------
    task wait_for_done_or_complete;
        input [255:0] case_name;
        integer local_wait;
        begin
            //------------------------------------------------------------------
            // Phase 1:
            // Wait for the controller to leave any previous HOLD_COMPLETE /
            // mode_complete state from the last test case.
            //
            // This prevents the task from immediately returning because the
            // previous run is still holding mode_complete high.
            //------------------------------------------------------------------
            local_wait = 0;
            while ((mode_complete === 1'b1) && (busy !== 1'b1) && (done !== 1'b1)) begin
                @(posedge clk);
                local_wait = local_wait + 1;
                if (local_wait > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for new run to start"});
                    disable wait_for_done_or_complete;
                end
            end

            //------------------------------------------------------------------
            // Phase 2:
            // Wait for the new run to complete normally.
            //------------------------------------------------------------------
            local_wait = 0;
            while ((done !== 1'b1) && (mode_complete !== 1'b1)) begin
                @(posedge clk);
                local_wait = local_wait + 1;
                if (local_wait > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for completion"});
                    disable wait_for_done_or_complete;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: check recent-prime packed history
    //
    // Packing from DUT:
    //   [31:0]   newest
    //   [63:32]  second newest
    //   ...
    //--------------------------------------------------------------------------
    task check_recent_history;
        input [255:0] case_name;
        integer expect_valid_i;
        integer idx_i;
        reg [31:0] recent_word_r;
        integer ref_idx_i;
        begin
            total_tests = total_tests + 1;

            if (ref_prime_count_i < 20) begin
                expect_valid_i = ref_prime_count_i;
            end
            else begin
                expect_valid_i = 20;
            end

            if (recent_valid_count !== expect_valid_i[4:0]) begin
                $display("FAIL : %0s recent_valid_count expected=%0d actual=%0d",
                         case_name, expect_valid_i, recent_valid_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : recent_valid_count"});
            end

            for (idx_i = 0; idx_i < expect_valid_i; idx_i = idx_i + 1) begin
                recent_word_r = recent_primes_flat[(idx_i*32) +: 32];
                ref_idx_i     = ref_prime_count_i - 1 - idx_i;

                total_tests = total_tests + 1;
                if (recent_word_r !== ref_prime_mem[ref_idx_i]) begin
                    $display("FAIL : %0s recent history idx=%0d expected=%0d actual=%0d",
                             case_name, idx_i, ref_prime_mem[ref_idx_i], recent_word_r);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : recent history entry"});
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: compare observed prime_found event stream to reference list
    //--------------------------------------------------------------------------
    task compare_event_stream;
        input [255:0] case_name;
        integer idx_i;
        begin
            total_tests = total_tests + 1;
            if (obs_prime_count_i !== ref_prime_count_i) begin
                $display("FAIL : %0s event count expected=%0d actual=%0d",
                         case_name, ref_prime_count_i, obs_prime_count_i);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : event count"});
            end

            for (idx_i = 0; idx_i < ref_prime_count_i; idx_i = idx_i + 1) begin
                total_tests = total_tests + 1;
                if (obs_prime_mem[idx_i] !== ref_prime_mem[idx_i]) begin
                    $display("FAIL : %0s event value idx=%0d expected=%0d actual=%0d",
                             case_name, idx_i, ref_prime_mem[idx_i], obs_prime_mem[idx_i]);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : event value"});
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: compare completion-state outputs to reference
    //--------------------------------------------------------------------------
    task compare_final_outputs;
        input [255:0] case_name;
        integer expected_prime_count_check;
        begin
            expected_prime_count_check = ref_prime_count_i;

            // Optional forced-fail mode:
            // intentionally corrupt the first checked prime_count result.
            if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                expected_prime_count_check = expected_prime_count_check + 1;
                force_fail_used_ff         = 1'b1;
            end

            total_tests = total_tests + 1;
            if (prime_count !== expected_prime_count_check[31:0]) begin
                $display("FAIL : %0s prime_count expected=%0d actual=%0d",
                         case_name, expected_prime_count_check, prime_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : prime_count"});
            end

            total_tests = total_tests + 1;
            if (largest_prime !== ref_largest_prime_i[31:0]) begin
                $display("FAIL : %0s largest_prime expected=%0d actual=%0d",
                         case_name, ref_largest_prime_i, largest_prime);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : largest_prime"});
            end

            total_tests = total_tests + 1;
            if (last_prime_found !== ref_last_prime_i[31:0]) begin
                $display("FAIL : %0s last_prime_found expected=%0d actual=%0d",
                         case_name, ref_last_prime_i, last_prime_found);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : last_prime_found"});
            end

            total_tests = total_tests + 1;
            if (mode_complete !== 1'b1) begin
                report_error({case_name, " : mode_complete was not high after completion"});
            end
            else begin
                report_pass({case_name, " : mode_complete high"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: run SINGLE-mode case
    //--------------------------------------------------------------------------
    task run_single_case;
        input integer single_value_in;
        input [255:0] case_name;
        begin
            build_single_reference(single_value_in);
            clear_observed_log();

            mode         = MODE_SINGLE;
            single_value = single_value_in[31:0];
            range_start  = 32'd0;
            range_limit  = 32'd0;
            time_limit_sec = 32'd0;

            pulse_start();
            wait_for_done_or_complete(case_name);
            wait_cycles(2);

            compare_final_outputs(case_name);
            compare_event_stream(case_name);
            check_recent_history(case_name);

            total_tests = total_tests + 1;
            if (single_is_prime !== ref_single_is_prime_i[0]) begin
                $display("FAIL : %0s single_is_prime expected=%0d actual=%0d",
                         case_name, ref_single_is_prime_i, single_is_prime);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : single_is_prime"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: run RANGE-mode case
    //--------------------------------------------------------------------------
    task run_range_case;
        input integer start_in;
        input integer limit_in;
        input [255:0] case_name;
        begin
            build_range_reference(start_in, limit_in);
            clear_observed_log();

            mode           = MODE_RANGE;
            single_value   = 32'd0;
            range_start    = start_in[31:0];
            range_limit    = limit_in[31:0];
            time_limit_sec = 32'd0;

            pulse_start();
            wait_for_done_or_complete(case_name);
            wait_cycles(2);

            compare_final_outputs(case_name);
            compare_event_stream(case_name);
            check_recent_history(case_name);

            total_tests = total_tests + 1;
            if (single_is_prime !== 1'b0) begin
                report_error({case_name, " : single_is_prime should remain 0 in RANGE mode"});
            end
            else begin
                report_pass({case_name, " : single_is_prime inactive"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: run TIME-mode case
    //
    // For TIME mode we do not compare exact prime_count because the stop point
    // depends on the controller's internal core latency and strict abort timing.
    // Instead we verify:
    //   - elapsed_seconds reaches the requested limit
    //   - completion happens
    //   - event indices are sequential
    //   - reported prime_count matches number of observed prime_found events
    //   - recent history matches observed event stream tail
    //--------------------------------------------------------------------------
    task run_time_case;
        input integer time_limit_in;
        input [255:0] case_name;
        integer idx_i;
        integer expect_valid_i;
        integer recent_word_expect_i;
        reg [31:0] recent_word_r;
        begin
            clear_observed_log();

            mode           = MODE_TIME;
            single_value   = 32'd0;
            range_start    = 32'd0;
            range_limit    = 32'd0;
            time_limit_sec = time_limit_in[31:0];

            pulse_start();

            for (idx_i = 0; idx_i < time_limit_in; idx_i = idx_i + 1) begin
                wait_cycles(20);
                pulse_tick_1hz();
            end

            wait_for_done_or_complete(case_name);
            wait_cycles(2);

            total_tests = total_tests + 1;
            if (elapsed_seconds !== time_limit_in[31:0]) begin
                $display("FAIL : %0s elapsed_seconds expected=%0d actual=%0d",
                         case_name, time_limit_in, elapsed_seconds);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : elapsed_seconds"});
            end

            total_tests = total_tests + 1;
            if (prime_count !== obs_prime_count_i[31:0]) begin
                $display("FAIL : %0s TIME-mode prime_count expected observed-event-count=%0d actual=%0d",
                         case_name, obs_prime_count_i, prime_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : prime_count matches events"});
            end

            total_tests = total_tests + 1;
            if (mode_complete !== 1'b1) begin
                report_error({case_name, " : mode_complete was not high"});
            end
            else begin
                report_pass({case_name, " : mode_complete high"});
            end

            if (obs_prime_count_i < 20) begin
                expect_valid_i = obs_prime_count_i;
            end
            else begin
                expect_valid_i = 20;
            end

            total_tests = total_tests + 1;
            if (recent_valid_count !== expect_valid_i[4:0]) begin
                $display("FAIL : %0s recent_valid_count expected=%0d actual=%0d",
                         case_name, expect_valid_i, recent_valid_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : recent_valid_count"});
            end

            for (idx_i = 0; idx_i < expect_valid_i; idx_i = idx_i + 1) begin
                recent_word_r = recent_primes_flat[(idx_i*32) +: 32];
                recent_word_expect_i = obs_prime_mem[obs_prime_count_i - 1 - idx_i];

                total_tests = total_tests + 1;
                if (recent_word_r !== recent_word_expect_i[31:0]) begin
                    $display("FAIL : %0s TIME-mode recent history idx=%0d expected=%0d actual=%0d",
                             case_name, idx_i, recent_word_expect_i, recent_word_r);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : TIME-mode recent history"});
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Monitor observed prime_found events
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            obs_prime_count_i <= 0;
        end
        else begin
            if (prime_found_pulse) begin
                if (obs_prime_count_i < MAX_REF_PRIMES) begin
                    obs_prime_mem[obs_prime_count_i] <= prime_found_value;
                end

                if (prime_found_index !== obs_prime_count_i[31:0]) begin
                    $display("FAIL : prime_found_index mismatch expected=%0d actual=%0d",
                             obs_prime_count_i, prime_found_index);
                    total_errors <= total_errors + 1;
                end

                obs_prime_count_i <= obs_prime_count_i + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests        = 0;
        total_passes       = 0;
        total_errors       = 0;
        rand_seed          = 32'h4280_2026;
        force_fail_used_ff = 1'b0;

        $display("------------------------------------------------------------");
        $display("tb_prime_controller");
        $display("Purpose:");
        $display("  Self-checking verification of SINGLE, RANGE, TIME, abort,");
        $display("  recent-prime history, randomized RANGE tests, and forced-fail.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / idle check
        //----------------------------------------------------------------------
        apply_reset();

        total_tests = total_tests + 1;
        if ((busy !== 1'b0) || (done !== 1'b0) || (mode_complete !== 1'b0) ||
            (prime_count !== 32'd0) || (largest_prime !== 32'd0) ||
            (last_prime_found !== 32'd0) || (single_is_prime !== 1'b0) ||
            (elapsed_seconds !== 32'd0) || (recent_valid_count !== 5'd0)) begin
            report_error("reset check : outputs not idle after reset");
        end
        else begin
            report_pass("reset check : outputs idle after reset");
        end

        //----------------------------------------------------------------------
        // SINGLE mode directed tests
        //----------------------------------------------------------------------
        run_single_case(0,  "single case : zero");
        run_single_case(1,  "single case : one");
        run_single_case(2,  "single case : two");
        run_single_case(17, "single case : prime 17");
        run_single_case(21, "single case : composite 21");

        //----------------------------------------------------------------------
        // RANGE mode directed tests
        //----------------------------------------------------------------------
        run_range_case(0, 20, "range case : 0 to 20");
        run_range_case(10, 2, "range case : empty start greater than limit");
        run_range_case(0, 1,  "range case : upper bound below 2");
        run_range_case(4, 4,  "range case : even single-value empty prime range");
        run_range_case(2, 30, "range case : 2 to 30");

        //----------------------------------------------------------------------
        // TIME mode directed test
        //----------------------------------------------------------------------
        run_time_case(2, "time case : two ticks");

        //----------------------------------------------------------------------
        // Abort behavior
        //----------------------------------------------------------------------
        mode           = MODE_RANGE;
        single_value   = 32'd0;
        range_start    = 32'd2;
        range_limit    = 32'd100;
        time_limit_sec = 32'd0;
        clear_observed_log();

        pulse_start();
        wait_cycles(10);
        pulse_abort();
        wait_cycles(3);

        total_tests = total_tests + 1;
        if ((busy !== 1'b0) || (done !== 1'b0) || (mode_complete !== 1'b0) ||
            (prime_count !== 32'd0) || (largest_prime !== 32'd0) ||
            (last_prime_found !== 32'd0) || (elapsed_seconds !== 32'd0) ||
            (recent_valid_count !== 5'd0)) begin
            report_error("abort case : controller did not return to clean idle");
        end
        else begin
            report_pass("abort case : controller returned to clean idle");
        end

        //----------------------------------------------------------------------
        // Randomized RANGE-mode regression
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_RANGE_TESTS; rand_i = rand_i + 1) begin
            //------------------------------------------------------------------
            // Generate randomized nonnegative RANGE-mode bounds.
            //
            // Important:
            //   rand_seed is an integer, so it can become negative during the
            //   LCG sequence. If a negative value is used directly with % 40,
            //   the result can also be negative, which makes the software
            //   reference model and DUT interpret the range differently.
            //
            // To avoid that, force the random values nonnegative first.
            //------------------------------------------------------------------
            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_nonneg_a_i = rand_seed & 32'h7fffffff;
            r_start_i       = rand_nonneg_a_i % 40;

            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_nonneg_b_i = rand_seed & 32'h7fffffff;
            r_limit_i       = r_start_i + (rand_nonneg_b_i % 40);

            run_range_case(r_start_i, r_limit_i, "randomized range case");
        end

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_prime_controller complete");
        $display("Total tests run : %0d", total_tests);
        $display("Total passes    : %0d", total_passes);
        $display("Total errors    : %0d", total_errors);

        if (total_errors == 0) begin
            $display("RESULT          : PASS");
        end
        else begin
            $display("RESULT          : FAIL");
        end
        $display("------------------------------------------------------------");

        $finish;
    end

endmodule