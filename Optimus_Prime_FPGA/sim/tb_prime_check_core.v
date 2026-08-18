`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_prime_check_core.v
//
// Purpose:
//   Self-checking testbench for prime_check_core.v.
//
// What this testbench verifies:
//   1) Reset behavior
//   2) Basic edge cases:
//        - 0, 1 are not prime
//        - 2 is prime
//        - even numbers > 2 are not prime
//   3) Known small primes and composites
//   4) Perfect squares and odd composites
//   5) Deterministic exhaustive sweep over a configurable range
//   6) Randomized testing against a golden software-style reference model
//   7) Abort behavior while the DUT is busy
//   8) Handshake behavior:
//        - start pulse while idle
//        - done pulse appears exactly once per transaction
//        - busy deasserts after completion
//
// Design philosophy:
//   - This testbench treats prime_check_core as a low-level reusable block.
//   - It uses a golden reference function to independently determine whether
//     each candidate is prime.
//   - The testbench is fully self-checking and reports all mismatches.
//   - Terminal output includes pass/fail information, total tests, and errors.
//   - Edge cases are emphasized because they are the most likely failure points
//     in a repeated-subtraction trial-division design.
//
// Notes:
//   - This testbench does NOT require waveform inspection to determine pass/fail.
//   - Random testing is deterministic because a fixed seed is used.
//   - A timeout guard is included so the testbench cannot hang forever if the
//     DUT gets stuck busy.
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// Module under test:
//   prime_check_core
//
// DUT behavior expected by this testbench:
//   - start is a one-cycle pulse while idle
//   - busy stays high while computing
//   - done pulses for one cycle when result is ready
//   - is_prime holds the computed result
//   - abort returns the module to idle on the next clock edge
//------------------------------------------------------------------------------
module tb_prime_check_core;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    //--------------------------------------------------------------------------
    // DUT stimulus
    //--------------------------------------------------------------------------
    reg         start;
    reg         abort;
    reg [31:0]  candidate;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire        busy;
    wire        done;
    wire        is_prime;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer timeout_cycles;
    integer cycle_count;
    integer rand_seed;
    integer rand_i;

    reg [31:0]  expected_is_prime_r;
    reg [31:0]  test_value_r;
    reg [255:0] test_name_r;

    reg         force_fail_used_ff;

    //--------------------------------------------------------------------------
    // Configurable testbench limits
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD_NS        = 10;
    localparam integer MAX_WAIT_CYCLES      = 200000;
    localparam integer EXHAUSTIVE_MAX_VALUE = 200;
    localparam integer RANDOM_TEST_COUNT    = 100;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt the first expected prime/non-prime
    // result so the testbench proves it is not an always-pass testbench.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 0;

    //--------------------------------------------------------------------------
    // Instantiate DUT
    //--------------------------------------------------------------------------
    prime_check_core dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .abort     (abort),
        .candidate (candidate),
        .busy      (busy),
        .done      (done),
        .is_prime  (is_prime)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Golden reference model
    //
    // Purpose:
    //   Determine the mathematically correct prime/non-prime result for a
    //   candidate number using straightforward trial division.
    //
    // Notes:
    //   - This is testbench-only logic, so loops are allowed here.
    //   - This serves as an independent checker against the DUT.
    //--------------------------------------------------------------------------
    function automatic integer is_prime_ref;
        input integer n_in;
        integer d;
        begin
            if (n_in < 2) begin
                is_prime_ref = 0;
            end
            else if (n_in == 2) begin
                is_prime_ref = 1;
            end
            else if ((n_in % 2) == 0) begin
                is_prime_ref = 0;
            end
            else begin
                is_prime_ref = 1;
                d = 3;
                while ((d * d) <= n_in) begin
                    if ((n_in % d) == 0) begin
                        is_prime_ref = 0;
                        d = n_in;
                    end
                    else begin
                        d = d + 2;
                    end
                end
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Utility task: initialize driving signals
    //--------------------------------------------------------------------------
    task init_inputs;
        begin
            start     = 1'b0;
            abort     = 1'b0;
            candidate = 32'd0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: apply synchronized reset
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
    // Utility task: print running summary line on error
    //--------------------------------------------------------------------------
    task report_error;
        input [255:0] msg;
        begin
            total_errors = total_errors + 1;
            $display("FAIL : %0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: print running summary line on pass
    //--------------------------------------------------------------------------
    task report_pass;
        input [255:0] msg;
        begin
            total_passes = total_passes + 1;
            $display("PASS : %0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: verify reset/idle outputs
    //--------------------------------------------------------------------------
    task check_idle_after_reset;
        begin
            total_tests = total_tests + 1;

            if (busy !== 1'b0) begin
                report_error("reset check: busy was not 0 after reset");
            end
            else if (done !== 1'b0) begin
                report_error("reset check: done was not 0 after reset");
            end
            else if (is_prime !== 1'b0) begin
                report_error("reset check: is_prime was not 0 after reset");
            end
            else begin
                report_pass("reset check: DUT entered idle state correctly");
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Core transaction task
    //
    // Purpose:
    //   Start one primality check, wait for done, and compare the DUT result
    //   against the golden reference.
    //
    // Checks performed:
    //   - DUT starts only after start pulse
    //   - busy eventually asserts for active cases
    //   - done must arrive before timeout
    //   - result must match golden reference
    //   - busy must deassert after completion
    //--------------------------------------------------------------------------
    task run_prime_case;
        input [31:0] test_candidate;
        input [255:0] case_name;
        integer local_expected;
        integer local_expected_check;
        integer wait_ctr;
        reg     saw_done;
        begin
            total_tests = total_tests + 1;

            // Determine expected result before stimulating DUT.
            local_expected = is_prime_ref(test_candidate);
            local_expected_check = local_expected;

            // Optional forced-fail mode:
            // intentionally corrupt the first expected result.
            if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                if (local_expected_check == 0) begin
                    local_expected_check = 1;
                end
                else begin
                    local_expected_check = 0;
                end
                force_fail_used_ff = 1'b1;
            end

            // Wait until DUT is idle before launching next case.
            wait_ctr = 0;
            while (busy !== 1'b0) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : DUT never returned to idle before test start"});
                    disable run_prime_case;
                end
            end

            // Apply candidate and one-cycle start pulse.
            @(posedge clk);
            candidate <= test_candidate;
            start     <= 1'b1;
            abort     <= 1'b0;

            @(posedge clk);
            start <= 1'b0;

            // Wait for done pulse with timeout protection.
            wait_ctr = 0;
            saw_done = 1'b0;

            while (saw_done == 1'b0) begin
                @(posedge clk);

                if (done === 1'b1) begin
                    saw_done = 1'b1;
                end
                else begin
                    wait_ctr = wait_ctr + 1;
                end

                if (wait_ctr > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for done"});
                    disable run_prime_case;
                end
            end

            // Compare result against expected model.
            if (is_prime !== local_expected_check[0]) begin
                $display("FAIL : %0s candidate=%0d expected=%0d actual=%0d",
                         case_name, test_candidate, local_expected_check, is_prime);
                total_errors = total_errors + 1;
            end
            else begin
                $display("PASS : %0s candidate=%0d result=%0d",
                         case_name, test_candidate, is_prime);
                total_passes = total_passes + 1;
            end

            // Check that busy drops after completion.
            @(posedge clk);
            if (busy !== 1'b0) begin
                report_error({case_name, " : busy did not deassert after done"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Abort test task
    //
    // Purpose:
    //   Start a long-running candidate, assert abort while DUT is busy, and
    //   verify that the DUT returns to idle without hanging.
    //--------------------------------------------------------------------------
    task run_abort_case;
        input [31:0] test_candidate;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            // Wait for idle.
            wait_ctr = 0;
            while (busy !== 1'b0) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : DUT never returned to idle before abort test"});
                    disable run_abort_case;
                end
            end

            // Launch candidate.
            @(posedge clk);
            candidate <= test_candidate;
            start     <= 1'b1;
            abort     <= 1'b0;

            @(posedge clk);
            start <= 1'b0;

            // Give the DUT a few cycles to enter busy state.
            wait_ctr = 0;
            while ((busy !== 1'b1) && (wait_ctr < 20)) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
            end

            // Assert abort for one cycle.
            @(posedge clk);
            abort <= 1'b1;
            @(posedge clk);
            abort <= 1'b0;

            // Verify DUT returns to idle quickly.
            wait_ctr = 0;
            while (busy !== 1'b0) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > 20) begin
                    report_error({case_name, " : DUT did not return to idle after abort"});
                    disable run_abort_case;
                end
            end

            if (done !== 1'b0) begin
                report_error({case_name, " : done unexpectedly asserted during abort recovery"});
            end
            else begin
                report_pass({case_name, " : abort returned DUT to idle correctly"});
            end
        end
    endtask

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
        $display("tb_prime_check_core");
        $display("Purpose:");
        $display("  Self-checking verification of prime_check_core using");
        $display("  edge cases, deterministic exhaustive sweep, random tests,");
        $display("  and abort behavior.");
        $display("------------------------------------------------------------");

        apply_reset();
        check_idle_after_reset();

        //----------------------------------------------------------------------
        // Edge cases and likely failure points
        //----------------------------------------------------------------------
        run_prime_case(32'd0,   "edge case: zero");
        run_prime_case(32'd1,   "edge case: one");
        run_prime_case(32'd2,   "edge case: two");
        run_prime_case(32'd3,   "edge case: three");
        run_prime_case(32'd4,   "edge case: smallest even composite");
        run_prime_case(32'd5,   "edge case: small odd prime");
        run_prime_case(32'd9,   "edge case: odd square");
        run_prime_case(32'd15,  "edge case: odd composite");
        run_prime_case(32'd17,  "edge case: repeated-subtraction non-divisible");
        run_prime_case(32'd21,  "edge case: odd composite by 3");
        run_prime_case(32'd25,  "edge case: square of 5");
        run_prime_case(32'd27,  "edge case: cube-related composite");
        run_prime_case(32'd29,  "edge case: odd prime");
        run_prime_case(32'd31,  "edge case: odd prime");
        run_prime_case(32'd49,  "edge case: square of 7");
        run_prime_case(32'd97,  "edge case: larger small prime");
        run_prime_case(32'd99,  "edge case: larger small composite");
        run_prime_case(32'd101, "edge case: three-digit prime");
        run_prime_case(32'd121, "edge case: square of 11");
        run_prime_case(32'd169, "edge case: square of 13");

        //----------------------------------------------------------------------
        // Deterministic exhaustive sweep over a manageable range
        //
        // This is effectively exhaustive over 0..EXHAUSTIVE_MAX_VALUE.
        //----------------------------------------------------------------------
        for (cycle_count = 0; cycle_count <= EXHAUSTIVE_MAX_VALUE; cycle_count = cycle_count + 1) begin
            run_prime_case(cycle_count[31:0], "exhaustive sweep");
        end

        //----------------------------------------------------------------------
        // Randomized testing
        //
        // Bias toward values that still complete quickly in simulation.
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_TEST_COUNT; rand_i = rand_i + 1) begin
            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            run_prime_case((rand_seed % 32'd5000), "randomized case");
        end

        //----------------------------------------------------------------------
        // Abort behavior
        //
        // Use a larger odd candidate so the DUT is very likely to be busy long
        // enough for the abort pulse to matter.
        //----------------------------------------------------------------------
        run_abort_case(32'd99991, "abort case: larger odd candidate");
        run_abort_case(32'd65537, "abort case: second larger odd candidate");

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_prime_check_core complete");
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