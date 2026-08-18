`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_sd_prime_parser.v
//
// Purpose:
//   Self-checking testbench for sd_prime_parser.v.
//
// What this testbench verifies:
//   1) Reset behavior
//   2) Fresh parse start behavior
//   3) Single-line decimal parsing
//   4) Multi-line decimal parsing
//   5) Carriage-return handling
//   6) Line-feed completion behavior
//   7) Capital 'A' stop-marker handling
//   8) end_of_stream termination behavior
//   9) Empty-line handling
//  10) Leading-zero handling
//  11) Long multi-digit values
//  12) Randomized valid decimal line streams
//
// Design philosophy:
//   - This is a fully self-checking testbench.
//   - It uses directed edge-case tests plus randomized tests.
//   - It checks exact output values, prime_valid pulses, and stream_done.
//   - It reports detailed failures and keeps pass/error totals.
//   - It is written as a lower-level verification block so the parser can
//     later be treated like a trusted subsystem component.
//
// Important parser behaviors under test:
//   - Decimal digits build a number
//   - LF (0x0A) ends a number and pulses prime_valid
//   - CR (0x0D) is ignored
//   - 'A' ends the stream and asserts stream_done
//   - end_of_stream also asserts stream_done
//
// Notes:
//   - This testbench intentionally does NOT instantiate sd_prime_feeder.
//   - The parser is isolated here as a low-level reusable block.
//   - Random testing uses a fixed deterministic seed.
//------------------------------------------------------------------------------
module tb_sd_prime_parser;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg        clk;
    reg        resetn;

    //--------------------------------------------------------------------------
    // DUT stimulus
    //--------------------------------------------------------------------------
    reg        start_parse;
    reg        byte_valid;
    reg [7:0]  byte_in;
    reg        end_of_stream;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire       prime_valid;
    wire [31:0] prime_value;
    wire       stream_done;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer wait_ctr;
    integer expected_count;
    integer observed_count;

    reg     force_fail_used_ff;

    reg [31:0] expected_values_a [0:255];
    reg [31:0] observed_values_a [0:255];

    //--------------------------------------------------------------------------
    // Configurable constants
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD_NS     = 10;
    localparam integer MAX_WAIT_CYCLES   = 50;
    localparam integer RANDOM_LINE_COUNT = 50;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt the first expected parsed value so the
    // testbench proves it is not an always-pass testbench.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 0;

    //--------------------------------------------------------------------------
    // Instantiate DUT
    //--------------------------------------------------------------------------
    sd_prime_parser dut (
        .clk           (clk),
        .resetn        (resetn),
        .start_parse   (start_parse),
        .byte_valid    (byte_valid),
        .byte_in       (byte_in),
        .end_of_stream (end_of_stream),
        .prime_valid   (prime_valid),
        .prime_value   (prime_value),
        .stream_done   (stream_done)
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
            start_parse   = 1'b0;
            byte_valid    = 1'b0;
            byte_in       = 8'd0;
            end_of_stream = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: synchronized reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            resetn = 1'b0;
            init_inputs();

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
    // Utility task: begin a fresh parse session
    //--------------------------------------------------------------------------
    task start_fresh_parse;
        begin
            @(posedge clk);
            start_parse <= 1'b1;
            byte_valid  <= 1'b0;
            byte_in     <= 8'd0;
            end_of_stream <= 1'b0;

            @(posedge clk);
            start_parse <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send one byte as a one-cycle valid pulse
    //--------------------------------------------------------------------------
    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            byte_valid <= 1'b1;
            byte_in    <= b;

            @(posedge clk);
            byte_valid <= 1'b0;
            byte_in    <= 8'd0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send CRLF
    //--------------------------------------------------------------------------
    task send_crlf;
        begin
            send_byte(8'h0D);
            send_byte(8'h0A);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send LF only
    //--------------------------------------------------------------------------
    task send_lf;
        begin
            send_byte(8'h0A);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send stop marker 'A'
    //--------------------------------------------------------------------------
    task send_stop;
        begin
            send_byte(8'h41);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send end_of_stream pulse
    //--------------------------------------------------------------------------
    task pulse_end_of_stream;
        begin
            @(posedge clk);
            end_of_stream <= 1'b1;
            @(posedge clk);
            end_of_stream <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send one unsigned decimal number as ASCII digits
    //
    // Notes:
    //   - This is testbench-only logic.
    //   - No leading zeros are added here unless the caller wants them.
    //--------------------------------------------------------------------------
    task send_decimal_number;
        input integer value_in;
        integer tmp;
        integer div;
        integer started;
        integer digit;
        begin
            if (value_in == 0) begin
                send_byte(8'h30);
            end
            else begin
                tmp     = value_in;
                div     = 1000000000;
                started = 0;

                while (div > 0) begin
                    digit = tmp / div;

                    if ((digit != 0) || (started != 0)) begin
                        send_byte(8'h30 + digit[7:0]);
                        started = 1;
                    end

                    tmp = tmp % div;
                    div = div / 10;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: send one decimal line followed by LF
    //--------------------------------------------------------------------------
    task send_decimal_line;
        input integer value_in;
        begin
            send_decimal_number(value_in);
            send_lf();
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Utility task: send one decimal line and immediately expect the parsed
    // output value.
    //
    // Why this task is needed:
    //   sd_prime_parser pulses prime_valid at the line-feed that terminates
    //   each number. Therefore the testbench must check each output as the
    //   line is sent, not later after many lines have already been transmitted.
    //--------------------------------------------------------------------------
    task send_decimal_line_and_expect;
        input integer value_in;
        input [255:0] case_name;
        begin
            send_decimal_line(value_in);
            expect_prime_value(value_in[31:0], case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: check reset/idle state
    //--------------------------------------------------------------------------
    task check_idle_after_reset;
        begin
            total_tests = total_tests + 1;

            if (prime_valid !== 1'b0) begin
                report_error("reset check: prime_valid was not 0 after reset");
            end
            else if (prime_value !== 32'd0) begin
                report_error("reset check: prime_value was not 0 after reset");
            end
            else if (stream_done !== 1'b0) begin
                report_error("reset check: stream_done was not 0 after reset");
            end
            else begin
                report_pass("reset check: parser entered idle state correctly");
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: verify no unexpected prime_valid pulse in a short window
    //--------------------------------------------------------------------------
    task expect_no_prime_valid;
        input [255:0] case_name;
        integer i;
        begin
            total_tests = total_tests + 1;

            for (i = 0; i < 3; i = i + 1) begin
                @(posedge clk);
                if (prime_valid !== 1'b0) begin
                    report_error({case_name, " : unexpected prime_valid pulse"});
                    disable expect_no_prime_valid;
                end
            end

            report_pass({case_name, " : no unexpected prime_valid pulse"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for one expected parsed value
    //--------------------------------------------------------------------------
    task expect_prime_value;
        input [31:0] expected_value;
        input [255:0] case_name;
        integer local_wait;
        reg [31:0] expected_value_check_r;
        begin
            total_tests = total_tests + 1;

            local_wait = 0;
            while (prime_valid !== 1'b1) begin
                @(posedge clk);
                local_wait = local_wait + 1;
                if (local_wait > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for prime_valid"});
                    disable expect_prime_value;
                end
            end

            expected_value_check_r = expected_value;

            // Optional forced-fail mode:
            // intentionally corrupt the first expected parsed value.
            if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                expected_value_check_r = expected_value_check_r + 32'd1;
                force_fail_used_ff     = 1'b1;
            end

            if (prime_value !== expected_value_check_r) begin
                $display("FAIL : %0s expected=%0d actual=%0d",
                         case_name, expected_value_check_r, prime_value);
                total_errors = total_errors + 1;
            end
            else begin
                $display("PASS : %0s value=%0d", case_name, prime_value);
                total_passes = total_passes + 1;
            end

            // Verify pulse behavior falls back low next cycle.
            @(posedge clk);
            if (prime_valid !== 1'b0) begin
                report_error({case_name, " : prime_valid did not return low after pulse"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for stream_done assertion
    //--------------------------------------------------------------------------
    task expect_stream_done;
        input [255:0] case_name;
        integer local_wait;
        begin
            total_tests = total_tests + 1;

            local_wait = 0;
            while (stream_done !== 1'b1) begin
                @(posedge clk);
                local_wait = local_wait + 1;
                if (local_wait > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for stream_done"});
                    disable expect_stream_done;
                end
            end

            report_pass({case_name, " : stream_done asserted"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: collect a known number of outputs into observed array
    //--------------------------------------------------------------------------
    task collect_n_outputs;
        input integer n_expected;
        input [255:0] case_name;
        integer idx;
        integer local_wait;
        begin
            observed_count = 0;

            for (idx = 0; idx < n_expected; idx = idx + 1) begin
                local_wait = 0;
                while (prime_valid !== 1'b1) begin
                    @(posedge clk);
                    local_wait = local_wait + 1;
                    if (local_wait > MAX_WAIT_CYCLES) begin
                        report_error({case_name, " : timeout collecting output"});
                        disable collect_n_outputs;
                    end
                end

                observed_values_a[observed_count] = prime_value;
                observed_count = observed_count + 1;

                @(posedge clk);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: compare expected and observed arrays
    //--------------------------------------------------------------------------
    task compare_output_arrays;
        input integer n_expected;
        input [255:0] case_name;
        integer idx;
        begin
            total_tests = total_tests + 1;

            if (observed_count !== n_expected) begin
                $display("FAIL : %0s expected_count=%0d observed_count=%0d",
                         case_name, n_expected, observed_count);
                total_errors = total_errors + 1;
            end
            else begin
                for (idx = 0; idx < n_expected; idx = idx + 1) begin
                    if (observed_values_a[idx] !== expected_values_a[idx]) begin
                        $display("FAIL : %0s index=%0d expected=%0d actual=%0d",
                                 case_name, idx, expected_values_a[idx], observed_values_a[idx]);
                        total_errors = total_errors + 1;
                        disable compare_output_arrays;
                    end
                end

                report_pass(case_name);
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
        $display("tb_sd_prime_parser");
        $display("Purpose:");
        $display("  Self-checking verification of sd_prime_parser using");
        $display("  directed edge-case tests and randomized decimal streams.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / initial state
        //----------------------------------------------------------------------
        apply_reset();
        check_idle_after_reset();

        //----------------------------------------------------------------------
        // Fresh parse start clears state
        //----------------------------------------------------------------------
        start_fresh_parse();
        total_tests = total_tests + 1;
        if (stream_done !== 1'b0) begin
            report_error("start_parse check: stream_done was not cleared");
        end
        else begin
            report_pass("start_parse check: parser state cleared");
        end

        //----------------------------------------------------------------------
        // Single-line basic numbers
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_decimal_line(2);
        expect_prime_value(32'd2, "single line: 2");

        start_fresh_parse();
        send_decimal_line(23);
        expect_prime_value(32'd23, "single line: 23");

        start_fresh_parse();
        send_decimal_line(101);
        expect_prime_value(32'd101, "single line: 101");

        //----------------------------------------------------------------------
        // Leading zeros
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_byte(8'h30);
        send_byte(8'h30);
        send_byte(8'h30);
        send_byte(8'h32);
        send_byte(8'h33);
        send_lf();
        expect_prime_value(32'd23, "leading zeros: 00023");

        //----------------------------------------------------------------------
        // CR should be ignored
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_decimal_number(37);
        send_crlf();
        expect_prime_value(32'd37, "CRLF handling: 37");

        //----------------------------------------------------------------------
        // Empty line should not generate a value
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_lf();
        expect_no_prime_valid("empty line handling");

        //----------------------------------------------------------------------
        // Multiple lines in sequence
        //
        // Check each parsed output immediately after its terminating LF.
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_decimal_line_and_expect(2,  "multi-line sequence: line 0");
        send_decimal_line_and_expect(3,  "multi-line sequence: line 1");
        send_decimal_line_and_expect(5,  "multi-line sequence: line 2");
        send_decimal_line_and_expect(7,  "multi-line sequence: line 3");
        send_decimal_line_and_expect(11, "multi-line sequence: line 4");

        //----------------------------------------------------------------------
        // Large multi-digit value
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_decimal_line(99991);
        expect_prime_value(32'd99991, "large value: 99991");

        //----------------------------------------------------------------------
        // Stop marker 'A'
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_decimal_line(13);
        expect_prime_value(32'd13, "stop marker pre-value");
        send_stop();
        expect_stream_done("stop marker A handling");

        //----------------------------------------------------------------------
        // After stream_done, further bytes should not create outputs
        //----------------------------------------------------------------------
        send_decimal_line(17);
        expect_no_prime_valid("ignore bytes after stream_done");

        //----------------------------------------------------------------------
        // end_of_stream also terminates parsing
        //----------------------------------------------------------------------
        start_fresh_parse();
        pulse_end_of_stream();
        expect_stream_done("end_of_stream handling");

        //----------------------------------------------------------------------
        // Stop marker directly with no prior value
        //----------------------------------------------------------------------
        start_fresh_parse();
        send_stop();
        expect_stream_done("stop marker only");

        //----------------------------------------------------------------------
        // Randomized valid decimal line stream
        //
        // Each random decimal line is checked immediately after transmission.
        //----------------------------------------------------------------------
        start_fresh_parse();
        expected_count = RANDOM_LINE_COUNT;

        for (rand_i = 0; rand_i < RANDOM_LINE_COUNT; rand_i = rand_i + 1) begin
            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            expected_values_a[rand_i] = rand_seed % 32'd100000;
            send_decimal_line_and_expect(expected_values_a[rand_i],
                                         "randomized stream line");
        end

        //----------------------------------------------------------------------
        // Randomized stream followed by stop marker
        //----------------------------------------------------------------------
        send_stop();
        expect_stream_done("randomized stream stop marker");

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_sd_prime_parser complete");
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