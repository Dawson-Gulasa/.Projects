`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_sd_prime_feeder.v
//
// Purpose:
//   Self-checking testbench for sd_prime_feeder.v.
//
// What this testbench verifies:
//   1) Reset behavior
//   2) Fresh start_read behavior
//   3) Single enqueue / single dequeue
//   4) Multi-value FIFO ordering
//   5) Request-before-data behavior
//   6) Data-before-request behavior
//   7) Multiple pending requests over time
//   8) end-of-file assertion only after upstream stream_done and FIFO empty
//   9) No duplicate outputs for a single next_prime request
//  10) Randomized enqueue/dequeue sequences with scoreboard checking
//
// Design philosophy:
//   - This is a fully self-checking lower-level subsystem testbench.
//   - It treats the feeder as an isolated handshake/FIFO block.
//   - It checks ordering, pulse behavior, request timing, and EOF timing.
//   - It uses directed edge-case testing plus randomized stress testing.
//   - It reports exact failure locations and final pass/error counts.
//
// Important feeder behaviors under test:
//   - cpu_lineflag_pulse pushes cpu_data into the internal FIFO
//   - next_prime requests one output item
//   - sd_prime_valid pulses for one cycle when an item is returned
//   - start_read resets internal state for a fresh compare run
//   - sd_end_of_file asserts only after stream_done and FIFO empty
//
// Notes:
//   - This bench does not instantiate sd_prime_parser.
//   - The testbench uses a software-style scoreboard queue to track expected
//     feeder outputs independently of the DUT.
//------------------------------------------------------------------------------
module tb_sd_prime_feeder;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg         clk;
    reg         resetn;

    //--------------------------------------------------------------------------
    // DUT stimulus
    //--------------------------------------------------------------------------
    reg         start_read;
    reg         next_prime;
    reg [31:0]  cpu_data;
    reg         cpu_lineflag_pulse;
    reg         stream_done;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire        sd_prime_valid;
    wire [31:0] sd_prime_value;
    wire        sd_end_of_file;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer local_wait;

    reg     force_fail_used_ff;

    //--------------------------------------------------------------------------
    // Software scoreboard queue
    //
    // expected_mem_a stores the values that should eventually emerge from the
    // feeder in FIFO order.
    //--------------------------------------------------------------------------
    reg [31:0] expected_mem_a [0:511];
    integer expected_wr_idx;
    integer expected_rd_idx;
    integer expected_count;

    //--------------------------------------------------------------------------
    // Configurable constants
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD_NS      = 10;
    localparam integer MAX_WAIT_CYCLES    = 100;
    localparam integer RANDOM_STEPS       = 200;
    localparam integer DUT_FIFO_DEPTH_TB  = 16;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt the first expected dequeue value so the
    // testbench proves it is not an always-pass testbench.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 1;

    //--------------------------------------------------------------------------
    // Instantiate DUT
    //--------------------------------------------------------------------------
    sd_prime_feeder #(
        .FIFO_DEPTH (16),
        .PTR_WIDTH  (4)
    ) dut (
        .clk                (clk),
        .resetn             (resetn),
        .start_read         (start_read),
        .next_prime         (next_prime),
        .cpu_data           (cpu_data),
        .cpu_lineflag_pulse (cpu_lineflag_pulse),
        .stream_done        (stream_done),
        .sd_prime_valid     (sd_prime_valid),
        .sd_prime_value     (sd_prime_value),
        .sd_end_of_file     (sd_end_of_file)
    );

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
            start_read         = 1'b0;
            next_prime         = 1'b0;
            cpu_data           = 32'd0;
            cpu_lineflag_pulse = 1'b0;
            stream_done        = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: clear software scoreboard
    //--------------------------------------------------------------------------
    task clear_scoreboard;
        begin
            expected_wr_idx = 0;
            expected_rd_idx = 0;
            expected_count  = 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: synchronized reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            resetn = 1'b0;
            init_inputs();
            clear_scoreboard();

            repeat (4) @(posedge clk);

            resetn = 1'b1;
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
    // Scoreboard helper: push one expected value
    //--------------------------------------------------------------------------
    task sb_push;
        input [31:0] value_in;
        begin
            expected_mem_a[expected_wr_idx] = value_in;
            expected_wr_idx = expected_wr_idx + 1;
            expected_count  = expected_count + 1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Scoreboard helper: pop and compare one expected value
    //--------------------------------------------------------------------------
    task sb_expect_pop;
        input [255:0] case_name;
        reg [31:0] expected_value_r;
        begin
            if (expected_count <= 0) begin
                report_error({case_name, " : scoreboard underflow, DUT produced unexpected value"});
            end
            else begin
                expected_value_r = expected_mem_a[expected_rd_idx];

                // Optional forced-fail mode:
                // intentionally corrupt the first expected dequeue value.
                if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                    expected_value_r    = expected_value_r + 32'd1;
                    force_fail_used_ff  = 1'b1;
                end

                if (sd_prime_value !== expected_value_r) begin
                    $display("FAIL : %0s expected=%0d actual=%0d",
                             case_name, expected_value_r, sd_prime_value);
                    total_errors = total_errors + 1;
                end
                else begin
                    $display("PASS : %0s value=%0d", case_name, sd_prime_value);
                    total_passes = total_passes + 1;
                end

                expected_rd_idx = expected_rd_idx + 1;
                expected_count  = expected_count - 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: issue start_read pulse and clear scoreboard
    //
    // This models a fresh test-mode compare session.
    //--------------------------------------------------------------------------
    task issue_start_read;
        begin
            @(posedge clk);
            start_read <= 1'b1;
            next_prime <= 1'b0;
            cpu_lineflag_pulse <= 1'b0;
            stream_done <= 1'b0;

            @(posedge clk);
            start_read <= 1'b0;

            clear_scoreboard();
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: enqueue one parsed prime
    //
    // This mimics one prime arriving from sd_prime_parser.
    //--------------------------------------------------------------------------
    task enqueue_prime;
        input [31:0] value_in;
        begin
            @(posedge clk);
            cpu_data           <= value_in;
            cpu_lineflag_pulse <= 1'b1;

            @(posedge clk);
            cpu_lineflag_pulse <= 1'b0;
            cpu_data           <= 32'd0;

            sb_push(value_in);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: request one next prime and expect one valid response
    //--------------------------------------------------------------------------
    task request_and_expect_one;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            @(posedge clk);
            next_prime <= 1'b1;

            @(posedge clk);
            next_prime <= 1'b0;

            // Allow DUT nonblocking assignments to settle before sampling.
            #1;
            wait_ctr = 0;

            while (sd_prime_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for sd_prime_valid"});
                    disable request_and_expect_one;
                end
            end

            sb_expect_pop(case_name);

            // Verify pulse returns low on the following cycle.
            @(posedge clk);
            #1;
            if (sd_prime_valid !== 1'b0) begin
                report_error({case_name, " : sd_prime_valid did not return low after pulse"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: request one next prime but expect no immediate output
    //
    // This is used when the FIFO is empty and the request should become pending.
    //--------------------------------------------------------------------------
    task request_and_expect_no_immediate_output;
        input [255:0] case_name;
        begin
            total_tests = total_tests + 1;

            @(posedge clk);
            next_prime <= 1'b1;

            @(posedge clk);
            next_prime <= 1'b0;

            // Allow DUT nonblocking assignments to settle before sampling.
            #1;
            if (sd_prime_valid !== 1'b0) begin
                report_error({case_name, " : unexpected sd_prime_valid while FIFO empty"});
            end
            else begin
                report_pass({case_name, " : request correctly waited for future data"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: expect EOF asserted
    //--------------------------------------------------------------------------
    task expect_eof_high;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            wait_ctr = 0;
            while (sd_end_of_file !== 1'b1) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for sd_end_of_file"});
                    disable expect_eof_high;
                end
            end

            report_pass({case_name, " : sd_end_of_file asserted"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: expect EOF low over a short window
    //--------------------------------------------------------------------------
    task expect_eof_low;
        input [255:0] case_name;
        integer i;
        begin
            total_tests = total_tests + 1;

            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk);
                if (sd_end_of_file !== 1'b0) begin
                    report_error({case_name, " : sd_end_of_file asserted too early"});
                    disable expect_eof_low;
                end
            end

            report_pass({case_name, " : sd_end_of_file remained low"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: assert upstream stream_done and hold it high
    //
    // Why this is needed:
    //   The DUT asserts sd_end_of_file only when stream_done is high in the
    //   same cycle that the effective FIFO count becomes zero. Therefore the
    //   testbench must be able to hold stream_done high while the remaining
    //   buffered values are drained.
    //--------------------------------------------------------------------------
    task assert_stream_done;
        begin
            @(posedge clk);
            stream_done <= 1'b1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: clear upstream stream_done
    //--------------------------------------------------------------------------
    task clear_stream_done;
        begin
            @(posedge clk);
            stream_done <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: check reset state
    //--------------------------------------------------------------------------
    task check_idle_after_reset;
        begin
            total_tests = total_tests + 1;

            if (sd_prime_valid !== 1'b0) begin
                report_error("reset check: sd_prime_valid was not 0 after reset");
            end
            else if (sd_prime_value !== 32'd0) begin
                report_error("reset check: sd_prime_value was not 0 after reset");
            end
            else if (sd_end_of_file !== 1'b0) begin
                report_error("reset check: sd_end_of_file was not 0 after reset");
            end
            else begin
                report_pass("reset check: feeder entered idle state correctly");
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
        $display("tb_sd_prime_feeder");
        $display("Purpose:");
        $display("  Self-checking verification of sd_prime_feeder using");
        $display("  directed FIFO/handshake tests and randomized stress tests.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / initial state
        //----------------------------------------------------------------------
        apply_reset();
        check_idle_after_reset();

        //----------------------------------------------------------------------
        // Single enqueue / single dequeue
        //----------------------------------------------------------------------
        issue_start_read();
        enqueue_prime(32'd2);
        request_and_expect_one("single enqueue/dequeue");

        //----------------------------------------------------------------------
        // FIFO ordering with multiple values
        //----------------------------------------------------------------------
        issue_start_read();
        enqueue_prime(32'd2);
        enqueue_prime(32'd3);
        enqueue_prime(32'd5);
        enqueue_prime(32'd7);

        request_and_expect_one("fifo order value 0");
        request_and_expect_one("fifo order value 1");
        request_and_expect_one("fifo order value 2");
        request_and_expect_one("fifo order value 3");

        //----------------------------------------------------------------------
        // Request before data arrives
        //
        // The feeder should remember the pending request and satisfy it when
        // the next parsed prime arrives.
        //----------------------------------------------------------------------
        issue_start_read();
        request_and_expect_no_immediate_output("request before data");
        enqueue_prime(32'd11);

        total_tests = total_tests + 1;
        @(posedge clk);
        #1;
        if (sd_prime_valid !== 1'b1) begin
            report_error("request before data : pending request was not satisfied when data arrived");
        end
        else begin
            sb_expect_pop("request before data response");
        end

        @(posedge clk);
        #1;
        if (sd_prime_valid !== 1'b0) begin
            report_error("request before data : sd_prime_valid did not return low after pulse");
        end

        //----------------------------------------------------------------------
        // Data before request
        //----------------------------------------------------------------------
        issue_start_read();
        enqueue_prime(32'd13);
        expect_eof_low("data before request: eof still low");
        request_and_expect_one("data before request");

        //----------------------------------------------------------------------
        // EOF should wait until FIFO is empty
        //----------------------------------------------------------------------
        issue_start_read();
        enqueue_prime(32'd17);
        enqueue_prime(32'd19);
        assert_stream_done();
        expect_eof_low("eof must wait while fifo not empty");

        request_and_expect_one("eof delayed until dequeue 0");
        expect_eof_low("eof still low with one item remaining");

        request_and_expect_one("eof delayed until dequeue 1");
        expect_eof_high("eof after fifo empty");
        clear_stream_done();

        //----------------------------------------------------------------------
        // start_read should clear feeder state and old pending data
        //----------------------------------------------------------------------
        issue_start_read();
        enqueue_prime(32'd23);
        enqueue_prime(32'd29);
        issue_start_read();

        total_tests = total_tests + 1;
        @(posedge clk);
        if (sd_end_of_file !== 1'b0) begin
            report_error("start_read clear check: sd_end_of_file was not cleared");
        end
        else begin
            report_pass("start_read clear check: eof cleared");
        end

        request_and_expect_no_immediate_output("start_read flushed old fifo contents");

        //----------------------------------------------------------------------
        // Randomized enqueue/dequeue stress
        //
        // Randomly choose between:
        //   0 = enqueue
        //   1 = request if data is available
        //   2 = idle
        //
        // Important note:
        //   Empty-request behavior is already tested explicitly in the directed
        //   section above. It is intentionally not mixed into the randomized
        //   section, because the DUT remembers pending requests internally and
        //   that would require extra scoreboard state tracking.
        //
        // Then finish by draining all expected items and asserting EOF.
        //----------------------------------------------------------------------
        issue_start_read();

        for (rand_i = 0; rand_i < RANDOM_STEPS; rand_i = rand_i + 1) begin
            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;

            case (rand_seed % 3)
                0: begin
                    // Enqueue only if the DUT FIFO should still have space.
                    // This keeps the software scoreboard aligned with the DUT,
                    // because the DUT silently ignores enqueue attempts when its
                    // FIFO is full.
                    if (expected_count < DUT_FIFO_DEPTH_TB) begin
                        enqueue_prime(rand_seed % 32'd100000);
                    end
                    else begin
                        @(posedge clk);
                    end
                end

                1: begin
                    // Request one value only when the scoreboard says data is
                    // currently available.
                    //
                    // Do NOT issue empty requests in the randomized section.
                    // The DUT remembers pending requests, and that would require
                    // separate scoreboard tracking for the pending-request state.
                    if (expected_count > 0) begin
                        request_and_expect_one("randomized dequeue");
                    end
                    else begin
                        @(posedge clk);
                    end
                end

                default: begin
                    @(posedge clk);
                end
            endcase
        end

        // Signal upstream completion and hold it high while the remaining FIFO
        // contents are drained.
        assert_stream_done();

        // Drain anything still expected.
        while (expected_count > 0) begin
            request_and_expect_one("randomized final drain");
        end

        expect_eof_high("randomized final eof");
        clear_stream_done();

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_sd_prime_feeder complete");
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