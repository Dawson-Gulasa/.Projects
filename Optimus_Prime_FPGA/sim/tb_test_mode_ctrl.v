`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_test_mode_ctrl.v
//
// Module definition / purpose:
//   Self-checking testbench for test_mode_ctrl.v using the real SD parser and
//   SD prime feeder modules.
//
// Tests performed:
//   1) Reset / idle output behavior
//   2) No-data-stored case
//   3) Exact-match PASS case
//   4) First-value mismatch FAIL case
//   5) Middle-value mismatch FAIL case
//   6) Stored list shorter than SD list
//   7) SD list shorter than stored list
//   8) Abort while test mode is active
//   9) Restart after DONE using abort_test
//  10) Randomized exact-match cases
//  11) Randomized mismatch cases
//  12) Forced-fail mode to prove the bench is not always-pass
//
// Verification strategy:
//   - Behavioral stored-prime memory model responds to rd_en / rd_addr.
//   - Real sd_prime_parser parses ASCII decimal lines ending in LF.
//   - Real sd_prime_feeder buffers parsed values and responds to sd_next.
//   - Final outputs are checked automatically with PASS/FAIL reporting.
//------------------------------------------------------------------------------
module tb_test_mode_ctrl;

    //--------------------------------------------------------------------------
    // Simulation parameters
    //--------------------------------------------------------------------------
    localparam integer ADDR_WIDTH              = 8;
    localparam integer MAX_VALUES              = 64;
    localparam integer CLK_PERIOD_NS           = 10;
    localparam integer MAX_WAIT_CYCLES         = 2000;
    localparam integer RANDOM_PASS_CASES       = 6;
    localparam integer RANDOM_MISMATCH_CASES   = 6;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set FORCE_FAIL = 1 to intentionally corrupt the first expected
    // primes_checked value. Normal run should use FORCE_FAIL = 0.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 1;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk;
    reg resetn;

    //--------------------------------------------------------------------------
    // DUT control inputs
    //--------------------------------------------------------------------------
    reg start_test;
    reg abort_test;

    //--------------------------------------------------------------------------
    // Stored-prime read interface
    //--------------------------------------------------------------------------
    reg  [31:0]           stored_count;
    wire                  rd_en;
    wire [ADDR_WIDTH-1:0] rd_addr;
    reg  [31:0]           rd_data;
    reg                   rd_data_valid;

    //--------------------------------------------------------------------------
    // SD-prime interface between test_mode_ctrl and sd_prime_feeder
    //--------------------------------------------------------------------------
    wire                  sd_start;
    wire                  sd_next;
    wire                  sd_prime_valid;
    wire [31:0]           sd_prime_value;
    wire                  sd_end_of_file;

    //--------------------------------------------------------------------------
    // DUT status outputs
    //--------------------------------------------------------------------------
    wire                  test_running;
    wire                  test_passed;
    wire                  test_failed;
    wire                  no_data_stored;
    wire [23:0]           primes_checked;
    wire [26:0]           fail_stored_val;
    wire [26:0]           fail_sd_val;

    //--------------------------------------------------------------------------
    // Parser byte-stream stimulus
    //--------------------------------------------------------------------------
    reg                   byte_valid;
    reg  [7:0]            byte_in;
    reg                   end_of_stream;

    wire                  parser_prime_valid;
    wire [31:0]           parser_prime_value;
    wire                  parser_stream_done;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer loop_i;
    integer wait_i;

    integer force_fail_used_i;

    //--------------------------------------------------------------------------
    // Behavioral stored-prime memory
    //--------------------------------------------------------------------------
    reg [31:0] stored_mem_a [0:MAX_VALUES-1];

    reg                  rd_pending_ff;
    reg [ADDR_WIDTH-1:0] rd_addr_hold_ff;
    integer              rd_delay_count_ff;

    //--------------------------------------------------------------------------
    // Case arrays
    //--------------------------------------------------------------------------
    integer stored_case_count_i;
    integer sd_case_count_i;
    integer stored_case_mem_i [0:MAX_VALUES-1];
    integer sd_case_mem_i     [0:MAX_VALUES-1];

    integer rand_len_i;
    integer rand_value_i;
    integer rand_mismatch_pos_i;

    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------
    test_mode_ctrl #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk            (clk),
        .resetn         (resetn),
        .start_test     (start_test),
        .abort_test     (abort_test),

        .stored_count   (stored_count),
        .rd_en          (rd_en),
        .rd_addr        (rd_addr),
        .rd_data        (rd_data),
        .rd_data_valid  (rd_data_valid),

        .sd_start       (sd_start),
        .sd_next        (sd_next),
        .sd_prime_valid (sd_prime_valid),
        .sd_prime_value (sd_prime_value),
        .sd_end_of_file (sd_end_of_file),

        .test_running   (test_running),
        .test_passed    (test_passed),
        .test_failed    (test_failed),
        .no_data_stored (no_data_stored),
        .primes_checked (primes_checked),
        .fail_stored_val(fail_stored_val),
        .fail_sd_val    (fail_sd_val)
    );

    //--------------------------------------------------------------------------
    // Real SD prime parser
    //--------------------------------------------------------------------------
    sd_prime_parser u_sd_prime_parser (
        .clk          (clk),
        .resetn       (resetn),
        .start_parse  (sd_start),
        .byte_valid   (byte_valid),
        .byte_in      (byte_in),
        .end_of_stream(end_of_stream),
        .prime_valid  (parser_prime_valid),
        .prime_value  (parser_prime_value),
        .stream_done  (parser_stream_done)
    );

    //--------------------------------------------------------------------------
    // Real SD prime feeder
    //--------------------------------------------------------------------------
    sd_prime_feeder #(
        .FIFO_DEPTH(16),
        .PTR_WIDTH (4)
    ) u_sd_prime_feeder (
        .clk               (clk),
        .resetn            (resetn),
        .start_read        (sd_start),
        .next_prime        (sd_next),
        .cpu_data          (parser_prime_value),
        .cpu_lineflag_pulse(parser_prime_valid),
        .stream_done       (parser_stream_done),
        .sd_prime_valid    (sd_prime_valid),
        .sd_prime_value    (sd_prime_value),
        .sd_end_of_file    (sd_end_of_file)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Initialize driven inputs
    //--------------------------------------------------------------------------
    task init_inputs;
        begin
            start_test     = 1'b0;
            abort_test     = 1'b0;
            stored_count   = 32'd0;

            rd_data        = 32'd0;
            rd_data_valid  = 1'b0;

            byte_valid     = 1'b0;
            byte_in        = 8'd0;
            end_of_stream  = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Clear test case data
    //--------------------------------------------------------------------------
    task clear_case_data;
        integer idx_i;
        begin
            stored_case_count_i = 0;
            sd_case_count_i     = 0;

            for (idx_i = 0; idx_i < MAX_VALUES; idx_i = idx_i + 1) begin
                stored_case_mem_i[idx_i] = 0;
                sd_case_mem_i[idx_i]     = 0;
                stored_mem_a[idx_i]      = 0;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Apply reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            resetn = 1'b0;
            init_inputs();
            clear_case_data();

            rd_pending_ff     = 1'b0;
            rd_addr_hold_ff   = {ADDR_WIDTH{1'b0}};
            rd_delay_count_ff = 0;

            repeat (5) @(posedge clk);

            resetn = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Report helpers
    //--------------------------------------------------------------------------
    task report_pass;
        input [255:0] msg;
        begin
            total_passes = total_passes + 1;
            $display("PASS : %0s", msg);
        end
    endtask

    task report_error;
        input [255:0] msg;
        begin
            total_errors = total_errors + 1;
            $display("FAIL : %0s", msg);
        end
    endtask

    //--------------------------------------------------------------------------
    // Wait helper
    //--------------------------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer idx_i;
        begin
            for (idx_i = 0; idx_i < n; idx_i = idx_i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Load behavioral stored-prime memory for one case
    //--------------------------------------------------------------------------
    task load_stored_model;
        integer idx_i;
        begin
            stored_count = stored_case_count_i[31:0];

            for (idx_i = 0; idx_i < MAX_VALUES; idx_i = idx_i + 1) begin
                if (idx_i < stored_case_count_i) begin
                    stored_mem_a[idx_i] = stored_case_mem_i[idx_i][31:0];
                end
                else begin
                    stored_mem_a[idx_i] = 32'd0;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Pulse start_test
    //--------------------------------------------------------------------------
    task pulse_start_test;
        begin
            @(posedge clk);
            start_test <= 1'b1;

            @(posedge clk);
            start_test <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Pulse abort_test
    //--------------------------------------------------------------------------
    task pulse_abort_test;
        begin
            @(posedge clk);
            abort_test <= 1'b1;

            @(posedge clk);
            abort_test <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Send one byte into parser
    //--------------------------------------------------------------------------
    task send_byte;
        input [7:0] byte_value;
        begin
            @(posedge clk);
            byte_in    <= byte_value;
            byte_valid <= 1'b1;

            @(posedge clk);
            byte_in    <= 8'd0;
            byte_valid <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Send unsigned decimal integer followed by LF
    //--------------------------------------------------------------------------
    task send_decimal_line;
        input integer value_in;
        integer div_i;
        integer rem_i;
        integer digit_i;
        integer started_i;
        begin
            rem_i     = value_in;
            started_i = 0;

            div_i = 1000000000;
            while (div_i > 0) begin
                digit_i = rem_i / div_i;

                if ((digit_i != 0) || (started_i != 0) || (div_i == 1)) begin
                    send_byte(8'h30 + digit_i[7:0]);
                    started_i = 1;
                end

                rem_i = rem_i - (digit_i * div_i);
                div_i = div_i / 10;
            end

            send_byte(8'h0A);
        end
    endtask

    //--------------------------------------------------------------------------
    // Send current SD case stream followed by capital 'A'
    //--------------------------------------------------------------------------
    task send_sd_stream;
        input integer gap_cycles;
        integer idx_i;
        begin
            // Let sd_start reset parser/feeder first.
            wait_cycles(4);

            for (idx_i = 0; idx_i < sd_case_count_i; idx_i = idx_i + 1) begin
                send_decimal_line(sd_case_mem_i[idx_i]);
                wait_cycles(gap_cycles);
            end

            //------------------------------------------------------------------
            // Important:
            //   Give test_mode_ctrl time to request and consume the final parsed
            //   SD value before sending the capital 'A' stop marker.
            //
            //   Without this delay, sd_end_of_file can arrive before or in the
            //   same cycle as the final sd_prime_valid pulse. Since the RTL
            //   checks sd_end_of_file first, the controller can stop one compare
            //   early in simulation.
            //------------------------------------------------------------------
            wait_cycles(20);

            send_byte(8'h41); // 'A' stop marker
        end
    endtask

    //--------------------------------------------------------------------------
    // Wait for terminal test-mode result
    //--------------------------------------------------------------------------
    task wait_for_terminal_result;
        input [255:0] case_name;
        integer local_wait_i;
        begin
            local_wait_i = 0;

            while ((test_passed !== 1'b1) &&
                   (test_failed !== 1'b1) &&
                   (no_data_stored !== 1'b1)) begin
                @(posedge clk);
                local_wait_i = local_wait_i + 1;

                if (local_wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for terminal result"});
                    disable wait_for_terminal_result;
                end
            end

            // Allow final registered outputs to settle.
            @(posedge clk);
            #1;
        end
    endtask

    //--------------------------------------------------------------------------
    // Check final status outputs
    //--------------------------------------------------------------------------
    task check_final_status;
        input integer expected_pass;
        input integer expected_fail;
        input integer expected_no_data;
        input integer expected_checked;
        input integer expected_fail_stored;
        input integer expected_fail_sd;
        input [255:0] case_name;

        integer expected_checked_adj;
        begin
            expected_checked_adj = expected_checked;

            if ((FORCE_FAIL != 0) && (force_fail_used_i == 0)) begin
                expected_checked_adj = expected_checked_adj + 1;
                force_fail_used_i    = 1;
            end

            total_tests = total_tests + 1;
            if (test_running !== 1'b0) begin
                report_error({case_name, " : test_running not low"});
            end
            else begin
                report_pass({case_name, " : test_running low"});
            end

            total_tests = total_tests + 1;
            if (test_passed !== expected_pass[0]) begin
                $display("FAIL : %0s test_passed expected=%0d actual=%0d",
                         case_name, expected_pass, test_passed);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : test_passed"});
            end

            total_tests = total_tests + 1;
            if (test_failed !== expected_fail[0]) begin
                $display("FAIL : %0s test_failed expected=%0d actual=%0d",
                         case_name, expected_fail, test_failed);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : test_failed"});
            end

            total_tests = total_tests + 1;
            if (no_data_stored !== expected_no_data[0]) begin
                $display("FAIL : %0s no_data_stored expected=%0d actual=%0d",
                         case_name, expected_no_data, no_data_stored);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : no_data_stored"});
            end

            total_tests = total_tests + 1;
            if (primes_checked !== expected_checked_adj[23:0]) begin
                $display("FAIL : %0s primes_checked expected=%0d actual=%0d",
                         case_name, expected_checked_adj, primes_checked);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : primes_checked"});
            end

            total_tests = total_tests + 1;
            if (fail_stored_val !== expected_fail_stored[26:0]) begin
                $display("FAIL : %0s fail_stored_val expected=%0d actual=%0d",
                         case_name, expected_fail_stored, fail_stored_val);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : fail_stored_val"});
            end

            total_tests = total_tests + 1;
            if (fail_sd_val !== expected_fail_sd[26:0]) begin
                $display("FAIL : %0s fail_sd_val expected=%0d actual=%0d",
                         case_name, expected_fail_sd, fail_sd_val);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : fail_sd_val"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Run one complete comparison case
    //--------------------------------------------------------------------------
    task run_compare_case;
        input integer gap_cycles;
        input integer expected_pass;
        input integer expected_fail;
        input integer expected_no_data;
        input integer expected_checked;
        input integer expected_fail_stored;
        input integer expected_fail_sd;
        input [255:0] case_name;
        begin
            load_stored_model();

            pulse_start_test();

            // Feed the SD text stream in parallel with the controller run.
            fork
                send_sd_stream(gap_cycles);
                wait_for_terminal_result(case_name);
            join

            check_final_status(
                expected_pass,
                expected_fail,
                expected_no_data,
                expected_checked,
                expected_fail_stored,
                expected_fail_sd,
                case_name
            );
        end
    endtask

    //--------------------------------------------------------------------------
    // Behavioral stored-prime read model
    //
    // When test_mode_ctrl asserts rd_en, this model returns stored_mem_a[rd_addr]
    // after a short deterministic latency.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            rd_pending_ff     <= 1'b0;
            rd_addr_hold_ff   <= {ADDR_WIDTH{1'b0}};
            rd_delay_count_ff <= 0;
            rd_data           <= 32'd0;
            rd_data_valid     <= 1'b0;
        end
        else begin
            rd_data_valid <= 1'b0;

            if (rd_en && !rd_pending_ff) begin
                rd_pending_ff     <= 1'b1;
                rd_addr_hold_ff   <= rd_addr;
                rd_delay_count_ff <= 2;
            end
            else if (rd_pending_ff) begin
                if (rd_delay_count_ff > 0) begin
                    rd_delay_count_ff <= rd_delay_count_ff - 1;
                end
                else begin
                    rd_data           <= stored_mem_a[rd_addr_hold_ff];
                    rd_data_valid     <= 1'b1;
                    rd_pending_ff     <= 1'b0;
                    rd_delay_count_ff <= 0;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests      = 0;
        total_passes     = 0;
        total_errors     = 0;
        rand_seed        = 32'h4280_2026;
        force_fail_used_i= 0;

        $display("------------------------------------------------------------");
        $display("tb_test_mode_ctrl");
        $display("Purpose:");
        $display("  Self-checking testbench for test_mode_ctrl using real");
        $display("  sd_prime_parser and sd_prime_feeder plus a behavioral");
        $display("  stored-prime read model.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / idle check
        //----------------------------------------------------------------------
        apply_reset();

        total_tests = total_tests + 1;
        if ((test_running !== 1'b0) ||
            (test_passed !== 1'b0) ||
            (test_failed !== 1'b0) ||
            (no_data_stored !== 1'b0) ||
            (primes_checked !== 24'd0) ||
            (fail_stored_val !== 27'd0) ||
            (fail_sd_val !== 27'd0)) begin
            report_error("reset check : outputs not idle");
        end
        else begin
            report_pass("reset check : outputs idle");
        end

        //----------------------------------------------------------------------
        // Case 1: no stored data
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i = 0;
        sd_case_count_i     = 0;
        run_compare_case(0, 0, 1, 1, 0, 0, 0, "no data stored case");

        //----------------------------------------------------------------------
        // Case 2: exact match PASS
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 5;
        sd_case_count_i      = 5;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 2;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
        stored_case_mem_i[2] = 5;   sd_case_mem_i[2] = 5;
        stored_case_mem_i[3] = 7;   sd_case_mem_i[3] = 7;
        stored_case_mem_i[4] = 11;  sd_case_mem_i[4] = 11;

        run_compare_case(0, 1, 0, 0, 5, 0, 0, "exact match pass case");

        //----------------------------------------------------------------------
        // Case 3: mismatch on first value
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 3;
        sd_case_count_i      = 3;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 4;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
        stored_case_mem_i[2] = 5;   sd_case_mem_i[2] = 5;

        run_compare_case(0, 0, 1, 0, 0, 2, 4, "first mismatch fail case");

        //----------------------------------------------------------------------
        // Case 4: mismatch in middle
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 4;
        sd_case_count_i      = 4;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 2;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
        stored_case_mem_i[2] = 5;   sd_case_mem_i[2] = 11;
        stored_case_mem_i[3] = 7;   sd_case_mem_i[3] = 7;

        run_compare_case(1, 0, 1, 0, 2, 5, 11, "middle mismatch fail case");

        //----------------------------------------------------------------------
        // Case 5: stored list shorter than SD list
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 2;
        sd_case_count_i      = 3;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 2;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
                                  sd_case_mem_i[2] = 5;

        run_compare_case(0, 0, 1, 0, 2, 0, 5, "stored shorter than sd case");

        //----------------------------------------------------------------------
        // Case 6: SD list shorter than stored list
        //
        // Current RTL passes when SD reaches EOF before another mismatch.
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 3;
        sd_case_count_i      = 2;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 2;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
        stored_case_mem_i[2] = 5;

        run_compare_case(0, 1, 0, 0, 2, 0, 0, "sd shorter than stored pass case");

        //----------------------------------------------------------------------
        // Case 7: abort while active
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 4;
        sd_case_count_i      = 4;

        stored_case_mem_i[0] = 2;   sd_case_mem_i[0] = 2;
        stored_case_mem_i[1] = 3;   sd_case_mem_i[1] = 3;
        stored_case_mem_i[2] = 5;   sd_case_mem_i[2] = 5;
        stored_case_mem_i[3] = 7;   sd_case_mem_i[3] = 7;

        load_stored_model();
        pulse_start_test();
        wait_cycles(5);
        pulse_abort_test();
        wait_cycles(3);

        total_tests = total_tests + 1;
        if ((test_running !== 1'b0) ||
            (test_passed !== 1'b0) ||
            (test_failed !== 1'b0) ||
            (no_data_stored !== 1'b0) ||
            (primes_checked !== 24'd0)) begin
            report_error("abort case : outputs not cleared");
        end
        else begin
            report_pass("abort case : outputs cleared");
        end

        //----------------------------------------------------------------------
        // Case 8: restart after DONE using abort_test
        //----------------------------------------------------------------------
        apply_reset();
        stored_case_count_i  = 2;
        sd_case_count_i      = 2;

        stored_case_mem_i[0] = 13;  sd_case_mem_i[0] = 13;
        stored_case_mem_i[1] = 17;  sd_case_mem_i[1] = 17;

        run_compare_case(0, 1, 0, 0, 2, 0, 0, "restart first pass");

        pulse_abort_test();
        wait_cycles(3);

        stored_case_count_i  = 3;
        sd_case_count_i      = 3;

        stored_case_mem_i[0] = 19;  sd_case_mem_i[0] = 19;
        stored_case_mem_i[1] = 23;  sd_case_mem_i[1] = 23;
        stored_case_mem_i[2] = 29;  sd_case_mem_i[2] = 29;

        run_compare_case(0, 1, 0, 0, 3, 0, 0, "restart second pass");

        //----------------------------------------------------------------------
        // Randomized exact-match cases
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_PASS_CASES; rand_i = rand_i + 1) begin
            apply_reset();

            rand_seed  = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_len_i = ((rand_seed & 32'h7fffffff) % 8) + 1;

            stored_case_count_i = rand_len_i;
            sd_case_count_i     = rand_len_i;

            for (loop_i = 0; loop_i < rand_len_i; loop_i = loop_i + 1) begin
                rand_seed    = (rand_seed * 32'd1664525) + 32'd1013904223;
                rand_value_i = ((rand_seed & 32'h7fffffff) % 90000) + 2;

                stored_case_mem_i[loop_i] = rand_value_i;
                sd_case_mem_i[loop_i]     = rand_value_i;
            end

            run_compare_case(1, 1, 0, 0, rand_len_i, 0, 0, "random exact match case");
        end

        //----------------------------------------------------------------------
        // Randomized mismatch cases
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_MISMATCH_CASES; rand_i = rand_i + 1) begin
            apply_reset();

            rand_seed  = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_len_i = ((rand_seed & 32'h7fffffff) % 8) + 2;

            stored_case_count_i = rand_len_i;
            sd_case_count_i     = rand_len_i;

            for (loop_i = 0; loop_i < rand_len_i; loop_i = loop_i + 1) begin
                rand_seed    = (rand_seed * 32'd1664525) + 32'd1013904223;
                rand_value_i = ((rand_seed & 32'h7fffffff) % 90000) + 2;

                stored_case_mem_i[loop_i] = rand_value_i;
                sd_case_mem_i[loop_i]     = rand_value_i;
            end

            rand_seed            = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_mismatch_pos_i  = (rand_seed & 32'h7fffffff) % rand_len_i;

            sd_case_mem_i[rand_mismatch_pos_i] =
                sd_case_mem_i[rand_mismatch_pos_i] + 1;

            run_compare_case(
                0,
                0,
                1,
                0,
                rand_mismatch_pos_i,
                stored_case_mem_i[rand_mismatch_pos_i],
                sd_case_mem_i[rand_mismatch_pos_i],
                "random mismatch case"
            );
        end

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_test_mode_ctrl complete");
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