`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_prime_subsystem.v
//
// Module definition / purpose:
//   Self-checking integration testbench for prime_subsystem.v.
//
// Tests performed:
//   1) Reset / idle output behavior
//   2) SINGLE mode edge cases: 0, 1, 2, prime, composite
//   3) RANGE mode edge cases:
//        - range below 2
//        - start > limit
//        - single even composite range
//        - normal small range
//        - non-2 lower bound range
//   4) Storage readback after RANGE mode completion
//   5) Recent-prime history correctness
//   6) Abort behavior during an active run
//   7) start_new_run storage bookkeeping clear
//   8) Randomized RANGE mode regression
//   9) TIME mode basic stop behavior using explicit tick_1hz pulses
//  10) Forced-fail mode to prove the bench is not always-pass
//
// Verification strategy:
//   - The DUT is the real prime_subsystem.
//   - The prime checker, controller, storage frontend, and storage memory are
//     all real RTL.
//   - A behavioral DDR model acknowledges writes and returns read data.
//   - A software reference model computes expected primes.
//   - The testbench checks final status, event stream, storage count,
//     storage readback, recent-prime history, and reset/abort behavior.
//------------------------------------------------------------------------------
module tb_prime_subsystem;

    //--------------------------------------------------------------------------
    // Small simulation-friendly configuration
    //--------------------------------------------------------------------------
    localparam integer DATA_WIDTH   = 32;
    localparam integer ADDR_WIDTH   = 8;
    localparam integer DEPTH        = 128;
    localparam integer QUEUE_DEPTH  = 16;
    localparam integer QUEUE_AWIDTH = 4;

    localparam integer CLK_PERIOD_NS      = 10;
    localparam integer MAX_WAIT_CYCLES    = 500000;
    localparam integer MAX_REF_PRIMES     = 128;
    localparam integer RANDOM_RANGE_TESTS = 12;
 
    integer r_start_i;
    integer r_span_i;
    integer r_limit_i;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set FORCE_FAIL = 1 to intentionally corrupt the first checked expected
    // prime_count value. Normal run should use FORCE_FAIL = 0.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 1;

    //--------------------------------------------------------------------------
    // Mode encodings used by prime_controller / prime_subsystem
    //--------------------------------------------------------------------------
    localparam [1:0] MODE_SINGLE   = 2'b00;
    localparam [1:0] MODE_RANGE    = 2'b01;
    localparam [1:0] MODE_TIME     = 2'b10;
    localparam [1:0] MODE_RESERVED = 2'b11;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    //--------------------------------------------------------------------------
    // DUT inputs
    //--------------------------------------------------------------------------
    reg                  start;
    reg                  abort;
    reg [1:0]            mode;
    reg [31:0]           single_value;
    reg [31:0]           range_start;
    reg [31:0]           range_limit;
    reg [31:0]           time_limit_sec;
    reg                  tick_1hz;

    reg                  start_new_run;
    reg                  rd_en;
    reg [ADDR_WIDTH-1:0] rd_addr;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire                  busy;
    wire                  done;
    wire                  mode_complete;
    wire [31:0]           prime_count;
    wire [31:0]           largest_prime;
    wire [31:0]           current_candidate;
    wire [31:0]           last_prime_found;
    wire                  single_is_prime;
    wire [31:0]           elapsed_seconds;

    wire [639:0]          recent_primes_flat;
    wire [4:0]            recent_valid_count;

    wire                  prime_found_pulse;
    wire [31:0]           prime_found_value;
    wire [31:0]           prime_found_index;

    wire [31:0]           stored_count;
    wire                  storage_full;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  rd_data_valid;

    wire                  ddr_wr_req;
    wire [ADDR_WIDTH-1:0] ddr_wr_addr;
    wire [DATA_WIDTH-1:0] ddr_wr_data;
    reg                   ddr_wr_ack;

    wire                  ddr_rd_req;
    wire [ADDR_WIDTH-1:0] ddr_rd_addr;
    reg  [DATA_WIDTH-1:0] ddr_rd_data;
    reg                   ddr_rd_data_valid;

    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------
    prime_subsystem #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DEPTH        (DEPTH),
        .QUEUE_DEPTH  (QUEUE_DEPTH),
        .QUEUE_AWIDTH (QUEUE_AWIDTH)
    ) dut (
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

        .start_new_run     (start_new_run),
        .rd_en             (rd_en),
        .rd_addr           (rd_addr),

        .busy              (busy),
        .done              (done),
        .mode_complete     (mode_complete),
        .prime_count       (prime_count),
        .largest_prime     (largest_prime),
        .current_candidate (current_candidate),
        .last_prime_found  (last_prime_found),
        .single_is_prime   (single_is_prime),
        .elapsed_seconds   (elapsed_seconds),

        .recent_primes_flat(recent_primes_flat),
        .recent_valid_count(recent_valid_count),

        .prime_found_pulse (prime_found_pulse),
        .prime_found_value (prime_found_value),
        .prime_found_index (prime_found_index),

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
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer loop_i;

    integer force_fail_used_i;

    //--------------------------------------------------------------------------
    // Reference model storage
    //--------------------------------------------------------------------------
    integer ref_prime_count_i;
    integer ref_largest_prime_i;
    integer ref_last_prime_i;
    integer ref_single_is_prime_i;
    integer ref_prime_mem [0:MAX_REF_PRIMES-1];

    integer obs_prime_count_i;
    integer obs_prime_mem [0:MAX_REF_PRIMES-1];

    //--------------------------------------------------------------------------
    // Behavioral DDR model storage
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] ddr_mem_a [0:DEPTH-1];

    reg                  ddr_wr_busy_ff;
    reg [ADDR_WIDTH-1:0] ddr_wr_addr_hold_ff;
    reg [DATA_WIDTH-1:0] ddr_wr_data_hold_ff;
    integer              ddr_wr_delay_ff;

    reg                  ddr_rd_busy_ff;
    reg [ADDR_WIDTH-1:0] ddr_rd_addr_hold_ff;
    integer              ddr_rd_delay_ff;

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Initialize all DUT-driving inputs
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

            start_new_run  = 1'b0;
            rd_en          = 1'b0;
            rd_addr        = {ADDR_WIDTH{1'b0}};

            ddr_wr_ack        = 1'b0;
            ddr_rd_data       = {DATA_WIDTH{1'b0}};
            ddr_rd_data_valid = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Clear behavioral DDR memory and observed event log
    //--------------------------------------------------------------------------
    task clear_models;
        integer idx_i;
        begin
            for (idx_i = 0; idx_i < DEPTH; idx_i = idx_i + 1) begin
                ddr_mem_a[idx_i] = {DATA_WIDTH{1'b0}};
            end

            for (idx_i = 0; idx_i < MAX_REF_PRIMES; idx_i = idx_i + 1) begin
                ref_prime_mem[idx_i] = 0;
                obs_prime_mem[idx_i] = 0;
            end

            ref_prime_count_i     = 0;
            ref_largest_prime_i   = 0;
            ref_last_prime_i      = 0;
            ref_single_is_prime_i = 0;
            obs_prime_count_i     = 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Apply synchronous reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            rst_n = 1'b0;
            init_inputs();
            clear_models();

            ddr_wr_busy_ff       = 1'b0;
            ddr_wr_addr_hold_ff  = {ADDR_WIDTH{1'b0}};
            ddr_wr_data_hold_ff  = {DATA_WIDTH{1'b0}};
            ddr_wr_delay_ff      = 0;

            ddr_rd_busy_ff       = 1'b0;
            ddr_rd_addr_hold_ff  = {ADDR_WIDTH{1'b0}};
            ddr_rd_delay_ff      = 0;

            repeat (5) @(posedge clk);

            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Reporting helpers
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
    // Wait fixed number of clocks
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
    // Pulse start for one clock
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
    // Pulse abort for one clock
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
    // Pulse start_new_run for one clock
    //--------------------------------------------------------------------------
    task pulse_start_new_run;
        begin
            @(posedge clk);
            start_new_run <= 1'b1;
            @(posedge clk);
            start_new_run <= 1'b0;
            wait_cycles(2);
        end
    endtask

    //--------------------------------------------------------------------------
    // Pulse tick_1hz for one clock
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
    // Software reference primality test
    //--------------------------------------------------------------------------
    function is_prime_ref;
        input integer candidate_in;
        integer div_i;
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
                div_i = 3;
                while ((div_i * div_i) <= candidate_in) begin
                    if ((candidate_in % div_i) == 0) begin
                        is_prime_ref = 0;
                        div_i = candidate_in;
                    end
                    else begin
                        div_i = div_i + 2;
                    end
                end
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Build reference model for SINGLE mode
    //--------------------------------------------------------------------------
    task build_single_reference;
        input integer value_in;
        begin
            ref_prime_count_i     = 0;
            ref_largest_prime_i   = 0;
            ref_last_prime_i      = 0;
            ref_single_is_prime_i = is_prime_ref(value_in);

            if (ref_single_is_prime_i != 0) begin
                ref_prime_mem[0]     = value_in;
                ref_prime_count_i    = 1;
                ref_largest_prime_i  = value_in;
                ref_last_prime_i     = value_in;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Build reference model for RANGE mode
    //--------------------------------------------------------------------------
    task build_range_reference;
        input integer start_in;
        input integer limit_in;
        integer cand_i;
        begin
            ref_prime_count_i     = 0;
            ref_largest_prime_i   = 0;
            ref_last_prime_i      = 0;
            ref_single_is_prime_i = 0;

            if ((start_in <= limit_in) && (limit_in >= 2)) begin
                for (cand_i = start_in; cand_i <= limit_in; cand_i = cand_i + 1) begin
                    if (is_prime_ref(cand_i) != 0) begin
                        if (ref_prime_count_i < MAX_REF_PRIMES) begin
                            ref_prime_mem[ref_prime_count_i] = cand_i;
                        end

                        ref_prime_count_i   = ref_prime_count_i + 1;
                        ref_largest_prime_i = cand_i;
                        ref_last_prime_i    = cand_i;
                    end
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Wait for a compute run to complete
    //--------------------------------------------------------------------------
    task wait_for_mode_complete;
        input [255:0] case_name;
        integer wait_i;
        begin
            wait_i = 0;

            // If previous completion is still high, wait until new run is active.
            while ((mode_complete === 1'b1) && (busy !== 1'b1) && (done !== 1'b1)) begin
                @(posedge clk);
                wait_i = wait_i + 1;

                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for new run to start"});
                    disable wait_for_mode_complete;
                end
            end

            wait_i = 0;
            while (mode_complete !== 1'b1) begin
                @(posedge clk);
                wait_i = wait_i + 1;

                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for completion"});
                    disable wait_for_mode_complete;
                end
            end

            wait_cycles(3);
        end
    endtask

    //--------------------------------------------------------------------------
    // Wait for the storage frontend/backend DDR activity to drain
    //--------------------------------------------------------------------------
    task wait_for_storage_idle;
        input [255:0] case_name;
        integer wait_i;
        begin
            wait_i = 0;

            while ((ddr_wr_req === 1'b1) ||
                   (ddr_rd_req === 1'b1) ||
                   (ddr_wr_busy_ff === 1'b1) ||
                   (ddr_rd_busy_ff === 1'b1) ||
                   (dut.u_prime_storage_frontend.queue_count_ff != 0) ||
                   (dut.u_prime_storage_frontend.u_prime_storage_mem.cmd_ready !== 1'b1)) begin
                @(posedge clk);
                wait_i = wait_i + 1;

                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for storage idle"});
                    disable wait_for_storage_idle;
                end
            end

            wait_cycles(2);
        end
    endtask

    //--------------------------------------------------------------------------
    // Compare final compute outputs against reference
    //--------------------------------------------------------------------------
    task check_final_compute_outputs;
        input [255:0] case_name;
        integer expected_count_adj;
        begin
            expected_count_adj = ref_prime_count_i;

            if ((FORCE_FAIL != 0) && (force_fail_used_i == 0)) begin
                expected_count_adj = expected_count_adj + 1;
                force_fail_used_i  = 1;
            end

            total_tests = total_tests + 1;
            if (prime_count !== expected_count_adj[31:0]) begin
                $display("FAIL : %0s prime_count expected=%0d actual=%0d",
                         case_name, expected_count_adj, prime_count);
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
        end
    endtask

    //--------------------------------------------------------------------------
    // Compare observed prime_found event stream against reference
    //--------------------------------------------------------------------------
    task check_event_stream;
        input [255:0] case_name;
        integer idx_i;
        integer compare_count_i;
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

            compare_count_i = ref_prime_count_i;
            if (obs_prime_count_i < compare_count_i) begin
                compare_count_i = obs_prime_count_i;
            end

            for (idx_i = 0; idx_i < compare_count_i; idx_i = idx_i + 1) begin
                total_tests = total_tests + 1;

                if (obs_prime_mem[idx_i] !== ref_prime_mem[idx_i]) begin
                    $display("FAIL : %0s event idx=%0d expected=%0d actual=%0d",
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
    // Check recent-prime history packed bus
    //--------------------------------------------------------------------------
    task check_recent_history;
        input [255:0] case_name;
        integer expected_valid_i;
        integer idx_i;
        integer ref_idx_i;
        reg [31:0] recent_word_r;
        begin
            if (ref_prime_count_i < 20) begin
                expected_valid_i = ref_prime_count_i;
            end
            else begin
                expected_valid_i = 20;
            end

            total_tests = total_tests + 1;
            if (recent_valid_count !== expected_valid_i[4:0]) begin
                $display("FAIL : %0s recent_valid_count expected=%0d actual=%0d",
                         case_name, expected_valid_i, recent_valid_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : recent_valid_count"});
            end

            // NOTE:
            // With the current controller implementation, recent_primes_flat[31:0]
            // contains the newest prime, [63:32] contains the second newest, etc.
            for (idx_i = 0; idx_i < expected_valid_i; idx_i = idx_i + 1) begin
                // recent_primes_flat[31:0] is the newest prime, so compare
                // against the reference list in reverse order.
                ref_idx_i = ref_prime_count_i - 1 - idx_i;
                recent_word_r = recent_primes_flat[(idx_i*32) +: 32];

                total_tests = total_tests + 1;
                if (recent_word_r !== ref_prime_mem[ref_idx_i]) begin
                    $display("FAIL : %0s recent idx=%0d expected=%0d actual=%0d",
                             case_name, idx_i, ref_prime_mem[ref_idx_i], recent_word_r);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : recent value"});
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Request one storage read and check returned value
    //--------------------------------------------------------------------------
    task check_storage_read;
        input integer addr_in;
        input integer expected_value_in;
        input [255:0] case_name;
        integer wait_i;
        begin
            total_tests = total_tests + 1;

            @(posedge clk);
            rd_addr <= addr_in[ADDR_WIDTH-1:0];
            rd_en   <= 1'b1;

            @(posedge clk);
            rd_en   <= 1'b0;

            wait_i = 0;
            while (rd_data_valid !== 1'b1) begin
                @(posedge clk);
                wait_i = wait_i + 1;

                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for rd_data_valid"});
                    disable check_storage_read;
                end
            end

            #1;
            if (rd_data !== expected_value_in[31:0]) begin
                $display("FAIL : %0s storage addr=%0d expected=%0d actual=%0d",
                         case_name, addr_in, expected_value_in, rd_data);
                total_errors = total_errors + 1;
            end
            else begin
                $display("PASS : %0s storage addr=%0d value=%0d",
                         case_name, addr_in, rd_data);
                total_passes = total_passes + 1;
            end

            wait_cycles(1);
        end
    endtask

    //--------------------------------------------------------------------------
    // Check all reference primes in storage
    //--------------------------------------------------------------------------
    task check_storage_contents;
        input [255:0] case_name;
        integer idx_i;
        begin
            wait_for_storage_idle(case_name);

            total_tests = total_tests + 1;
            if (stored_count !== ref_prime_count_i[31:0]) begin
                $display("FAIL : %0s stored_count expected=%0d actual=%0d",
                         case_name, ref_prime_count_i, stored_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : stored_count"});
            end

            for (idx_i = 0; idx_i < ref_prime_count_i; idx_i = idx_i + 1) begin
                check_storage_read(idx_i, ref_prime_mem[idx_i], case_name);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Run and check one SINGLE-mode case
    //--------------------------------------------------------------------------
    task run_single_case;
        input integer value_in;
        input [255:0] case_name;
        begin
            // Each user-level compute run starts with fresh storage bookkeeping.
            pulse_start_new_run();

            build_single_reference(value_in);
            obs_prime_count_i = 0;

            mode           = MODE_SINGLE;
            single_value   = value_in[31:0];
            range_start    = 32'd0;
            range_limit    = 32'd0;
            time_limit_sec = 32'd0;

            pulse_start();
            wait_for_mode_complete(case_name);
            wait_for_storage_idle(case_name);

            check_final_compute_outputs(case_name);
            check_event_stream(case_name);
            check_recent_history(case_name);
            check_storage_contents(case_name);

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
    // Run and check one RANGE-mode case
    //--------------------------------------------------------------------------
    task run_range_case;
        input integer start_in;
        input integer limit_in;
        input [255:0] case_name;
        begin
            // Each user-level compute run starts with fresh storage bookkeeping.
            pulse_start_new_run();

            build_range_reference(start_in, limit_in);
            obs_prime_count_i = 0;
            mode           = MODE_RANGE;
            single_value   = 32'd0;
            range_start    = start_in[31:0];
            range_limit    = limit_in[31:0];
            time_limit_sec = 32'd0;

            pulse_start();
            wait_for_mode_complete(case_name);
            wait_for_storage_idle(case_name);

            check_final_compute_outputs(case_name);
            check_event_stream(case_name);
            check_recent_history(case_name);
            check_storage_contents(case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Run and check basic TIME-mode behavior
    //
    // This does not predict an exact prime_count because strict no-overshoot
    // timing depends on when ticks arrive relative to checker latency. Instead,
    // it checks that elapsed_seconds reaches the requested limit, that event
    // ordering is increasing, and that storage mirrors observed events.
    //--------------------------------------------------------------------------
    task run_time_case;
        input integer seconds_in;
        input [255:0] case_name;
        integer idx_i;
        begin
            obs_prime_count_i = 0;

            mode           = MODE_TIME;
            single_value   = 32'd0;
            range_start    = 32'd0;
            range_limit    = 32'd0;
            time_limit_sec = seconds_in[31:0];

            pulse_start();

            // Let a few checks occur, then tick the time limit.
            for (idx_i = 0; idx_i < seconds_in; idx_i = idx_i + 1) begin
                wait_cycles(80);
                pulse_tick_1hz();
            end

            wait_for_mode_complete(case_name);
            wait_for_storage_idle(case_name);

            total_tests = total_tests + 1;
            if (elapsed_seconds !== seconds_in[31:0]) begin
                $display("FAIL : %0s elapsed_seconds expected=%0d actual=%0d",
                         case_name, seconds_in, elapsed_seconds);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : elapsed_seconds"});
            end

            total_tests = total_tests + 1;
            if (prime_count !== obs_prime_count_i[31:0]) begin
                $display("FAIL : %0s prime_count expected observed=%0d actual=%0d",
                         case_name, obs_prime_count_i, prime_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : prime_count matches events"});
            end

            total_tests = total_tests + 1;
            if (stored_count !== obs_prime_count_i[31:0]) begin
                $display("FAIL : %0s stored_count expected observed=%0d actual=%0d",
                         case_name, obs_prime_count_i, stored_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : stored_count matches events"});
            end

            for (idx_i = 0; idx_i < obs_prime_count_i; idx_i = idx_i + 1) begin
                check_storage_read(idx_i, obs_prime_mem[idx_i], case_name);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Observe prime-found event stream
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
                    $display("FAIL : prime_found_index expected=%0d actual=%0d",
                             obs_prime_count_i, prime_found_index);
                    total_errors <= total_errors + 1;
                end

                obs_prime_count_i <= obs_prime_count_i + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Behavioral DDR response model
    //
    // Writes are acknowledged after a short delay and committed into ddr_mem_a.
    // Reads return ddr_mem_a[addr] after a short delay.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ddr_wr_ack        <= 1'b0;
            ddr_rd_data       <= {DATA_WIDTH{1'b0}};
            ddr_rd_data_valid <= 1'b0;

            ddr_wr_busy_ff      <= 1'b0;
            ddr_wr_addr_hold_ff <= {ADDR_WIDTH{1'b0}};
            ddr_wr_data_hold_ff <= {DATA_WIDTH{1'b0}};
            ddr_wr_delay_ff     <= 0;

            ddr_rd_busy_ff      <= 1'b0;
            ddr_rd_addr_hold_ff <= {ADDR_WIDTH{1'b0}};
            ddr_rd_delay_ff     <= 0;
        end
        else begin
            ddr_wr_ack        <= 1'b0;
            ddr_rd_data_valid <= 1'b0;

            if (ddr_wr_req && !ddr_wr_busy_ff) begin
                ddr_wr_busy_ff      <= 1'b1;
                ddr_wr_addr_hold_ff <= ddr_wr_addr;
                ddr_wr_data_hold_ff <= ddr_wr_data;
                ddr_wr_delay_ff     <= 2;
            end
            else if (ddr_wr_busy_ff) begin
                if (ddr_wr_delay_ff > 0) begin
                    ddr_wr_delay_ff <= ddr_wr_delay_ff - 1;
                end
                else begin
                    ddr_mem_a[ddr_wr_addr_hold_ff] <= ddr_wr_data_hold_ff;
                    ddr_wr_ack                     <= 1'b1;
                    ddr_wr_busy_ff                 <= 1'b0;
                end
            end

            if (ddr_rd_req && !ddr_rd_busy_ff) begin
                ddr_rd_busy_ff      <= 1'b1;
                ddr_rd_addr_hold_ff <= ddr_rd_addr;
                ddr_rd_delay_ff     <= 2;
            end
            else if (ddr_rd_busy_ff) begin
                if (ddr_rd_delay_ff > 0) begin
                    ddr_rd_delay_ff <= ddr_rd_delay_ff - 1;
                end
                else begin
                    ddr_rd_data       <= ddr_mem_a[ddr_rd_addr_hold_ff];
                    ddr_rd_data_valid <= 1'b1;
                    ddr_rd_busy_ff    <= 1'b0;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        total_tests       = 0;
        total_passes      = 0;
        total_errors      = 0;
        rand_seed         = 32'h4280_2026;
        force_fail_used_i = 0;

        $display("------------------------------------------------------------");
        $display("tb_prime_subsystem");
        $display("Purpose:");
        $display("  Self-checking integration test for prime_subsystem.");
        $display("  Tests compute control, prime_found event stream, DDR-backed");
        $display("  storage readback, reset/abort behavior, random ranges,");
        $display("  TIME mode, and forced-fail mode.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / idle check
        //----------------------------------------------------------------------
        apply_reset();

        total_tests = total_tests + 1;
        if ((busy !== 1'b0) ||
            (done !== 1'b0) ||
            (mode_complete !== 1'b0) ||
            (prime_count !== 32'd0) ||
            (largest_prime !== 32'd0) ||
            (last_prime_found !== 32'd0) ||
            (stored_count !== 32'd0) ||
            (storage_full !== 1'b0)) begin
            report_error("reset check : outputs not idle");
        end
        else begin
            report_pass("reset check : outputs idle");
        end

        //----------------------------------------------------------------------
        // SINGLE-mode directed cases
        //----------------------------------------------------------------------
        run_single_case(0,  "single zero");
        run_single_case(1,  "single one");
        run_single_case(2,  "single two");
        run_single_case(17, "single prime 17");
        run_single_case(21, "single composite 21");


        //----------------------------------------------------------------------
        // RANGE-mode directed cases
        //----------------------------------------------------------------------
        run_range_case(0, 1,   "range below two");
        run_range_case(10, 2,  "range start greater than limit");
        run_range_case(4, 4,   "range single even composite");
        run_range_case(0, 20,  "range 0 to 20");
        run_range_case(11, 31, "range 11 to 31");

        //----------------------------------------------------------------------
        // Abort behavior
        //----------------------------------------------------------------------
        obs_prime_count_i = 0;
        mode           = MODE_RANGE;
        single_value   = 32'd0;
        range_start    = 32'd2;
        range_limit    = 32'd100;
        time_limit_sec = 32'd0;

        pulse_start();
        wait_cycles(20);
        pulse_abort();
        wait_cycles(5);

        wait_for_storage_idle("abort case");

        total_tests = total_tests + 1;
        if ((busy !== 1'b0) ||
            (mode_complete !== 1'b0) ||
            (prime_count !== 32'd0) ||
            (largest_prime !== 32'd0)) begin
            report_error("abort case : compute controller did not clear cleanly");
        end
        else begin
            report_pass("abort case : compute controller cleared cleanly");
        end

        // Storage bookkeeping is cleared by start_new_run, not by abort alone.
        pulse_start_new_run();

        total_tests = total_tests + 1;
        if (stored_count !== 32'd0) begin
            $display("FAIL : abort case storage clear expected stored_count=0 actual=%0d",
                     stored_count);
            total_errors = total_errors + 1;
        end
        else begin
            report_pass("abort case : storage cleared after start_new_run");
        end

        //----------------------------------------------------------------------
        // start_new_run should clear storage bookkeeping
        //----------------------------------------------------------------------
        run_range_case(0, 10, "range before start_new_run clear");
        pulse_start_new_run();

        total_tests = total_tests + 1;
        if (stored_count !== 32'd0) begin
            $display("FAIL : start_new_run clear expected stored_count=0 actual=%0d",
                     stored_count);
            total_errors = total_errors + 1;
        end
        else begin
            report_pass("start_new_run clear : stored_count reset");
        end

        //----------------------------------------------------------------------
        // Randomized RANGE-mode regression
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_RANGE_TESTS; rand_i = rand_i + 1) begin


            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            r_start_i = (rand_seed & 32'h7fffffff) % 30;

            rand_seed = (rand_seed * 32'd1664525) + 32'd1013904223;
            r_span_i  = (rand_seed & 32'h7fffffff) % 35;

            r_limit_i = r_start_i + r_span_i;

            run_range_case(r_start_i, r_limit_i, "randomized range");
        end

        //----------------------------------------------------------------------
        // TIME-mode basic behavior
        //----------------------------------------------------------------------
        pulse_start_new_run();
        run_time_case(1, "time mode one second");

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_prime_subsystem complete");
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