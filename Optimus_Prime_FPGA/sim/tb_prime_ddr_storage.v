`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_prime_ddr_storage.v
//
// Module definition / purpose:
//   Self-checking verification for the DDR-backed prime storage path.
//
// DUT scope used in this testbench:
//   - prime_storage_frontend
//   - internal prime_storage_mem behavior through its exported DDR interface
//
// Tests run in this testbench:
//   1) Reset / idle output behavior
//   2) Single prime enqueue -> DDR write -> stored_count update
//   3) Back-to-back queued writes while DDR acknowledges slowly
//   4) Read-after-write correctness
//   5) Held read behavior while queued writes are still draining
//   6) start_new_run bookkeeping reset behavior
//   7) storage_full behavior when an out-of-range prime index is presented
//   8) Randomized write / read traffic against a behavioral DDR memory model
//   9) Forced-fail mode to prove the testbench is not always-pass
//
// Testbench philosophy:
//   - The DUT is verified against a behavioral reference memory model
//   - DDR write/read acknowledgements are returned with randomized latency
//   - Read data is compared against the reference model
//   - Edge cases and queue-sensitive cases are explicitly exercised
//
// Notes:
//   - This testbench verifies the storage path only, not the full prime
//     controller or test-mode compare controller.
//   - The behavioral DDR model stores only the lower 32-bit prime payload,
//     matching the storage interface presented to prime_storage_frontend.
//------------------------------------------------------------------------------
module tb_prime_ddr_storage;

    //--------------------------------------------------------------------------
    // Parameters chosen for a fast, readable simulation
    //--------------------------------------------------------------------------
    localparam integer DATA_WIDTH   = 32;
    localparam integer ADDR_WIDTH   = 8;
    localparam integer DEPTH        = 64;
    localparam integer QUEUE_DEPTH  = 8;
    localparam integer QUEUE_AWIDTH = 3;

    localparam integer CLK_PERIOD_NS      = 10;
    localparam integer MAX_WAIT_CYCLES    = 300;
    localparam integer RANDOM_OP_COUNT    = 60;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt the first checked readback so the
    // testbench demonstrates a FAIL result on demand.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 1;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    //--------------------------------------------------------------------------
    // DUT inputs
    //--------------------------------------------------------------------------
    reg                    start_new_run;
    reg                    prime_found_pulse;
    reg  [DATA_WIDTH-1:0]  prime_found_value;
    reg  [31:0]            prime_found_index;
    reg                    rd_en;
    reg  [ADDR_WIDTH-1:0]  rd_addr;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire [31:0]            stored_count;
    wire                   storage_full;
    wire [DATA_WIDTH-1:0]  rd_data;
    wire                   rd_data_valid;

    wire                   ddr_wr_req;
    wire [ADDR_WIDTH-1:0]  ddr_wr_addr;
    wire [DATA_WIDTH-1:0]  ddr_wr_data;
    reg                    ddr_wr_ack;

    wire                   ddr_rd_req;
    wire [ADDR_WIDTH-1:0]  ddr_rd_addr;
    reg  [DATA_WIDTH-1:0]  ddr_rd_data;
    reg                    ddr_rd_data_valid;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    prime_storage_frontend #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DEPTH        (DEPTH),
        .QUEUE_DEPTH  (QUEUE_DEPTH),
        .QUEUE_AWIDTH (QUEUE_AWIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .start_new_run     (start_new_run),
        .prime_found_pulse (prime_found_pulse),
        .prime_found_value (prime_found_value),
        .prime_found_index (prime_found_index),
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
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer rand_seed;
    integer rand_i;
    integer local_wait;

    integer rand_lat_i;
    integer rand_addr_i;
    integer rand_val_i;
    integer rand_rw_select_i;

    reg     force_fail_used_ff;

    //--------------------------------------------------------------------------
    // Behavioral DDR memory model state
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] ddr_mem_a [0:DEPTH-1];

    reg                  wr_busy_ff;
    reg [ADDR_WIDTH-1:0] wr_addr_hold_ff;
    reg [DATA_WIDTH-1:0] wr_data_hold_ff;
    integer              wr_countdown_ff;

    reg                  rd_busy_ff;
    reg [ADDR_WIDTH-1:0] rd_addr_hold_ff;
    integer              rd_countdown_ff;

    //--------------------------------------------------------------------------
    // Reference valid-entry model for current run
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] ref_valid_mem_a [0:DEPTH-1];
    reg                  ref_valid_bit_a [0:DEPTH-1];

    integer ref_stored_count_i;

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Utility task: initialize DUT-driving inputs
    //--------------------------------------------------------------------------
    task init_inputs;
        begin
            start_new_run     = 1'b0;
            prime_found_pulse = 1'b0;
            prime_found_value = {DATA_WIDTH{1'b0}};
            prime_found_index = 32'd0;
            rd_en             = 1'b0;
            rd_addr           = {ADDR_WIDTH{1'b0}};

            ddr_wr_ack        = 1'b0;
            ddr_rd_data       = {DATA_WIDTH{1'b0}};
            ddr_rd_data_valid = 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: clear reference model
    //--------------------------------------------------------------------------
    task clear_reference_model;
        integer idx_i;
        begin
            for (idx_i = 0; idx_i < DEPTH; idx_i = idx_i + 1) begin
                ref_valid_mem_a[idx_i] = {DATA_WIDTH{1'b0}};
                ref_valid_bit_a[idx_i] = 1'b0;
                ddr_mem_a[idx_i]       = {DATA_WIDTH{1'b0}};
            end

            ref_stored_count_i = 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: synchronized reset
    //--------------------------------------------------------------------------
    task apply_reset;
        begin
            rst_n = 1'b0;
            init_inputs();
            clear_reference_model();

            wr_busy_ff      = 1'b0;
            wr_addr_hold_ff = {ADDR_WIDTH{1'b0}};
            wr_data_hold_ff = {DATA_WIDTH{1'b0}};
            wr_countdown_ff = 0;

            rd_busy_ff      = 1'b0;
            rd_addr_hold_ff = {ADDR_WIDTH{1'b0}};
            rd_countdown_ff = 0;

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
    // Utility task: send one prime-found event
    //--------------------------------------------------------------------------
    task send_prime_found;
        input [DATA_WIDTH-1:0] value_in;
        input integer          index_in;
        begin
            @(posedge clk);
            prime_found_value <= value_in;
            prime_found_index <= index_in[31:0];
            prime_found_pulse <= 1'b1;

            @(posedge clk);
            prime_found_pulse <= 1'b0;

            if (index_in < DEPTH) begin
                ref_valid_mem_a[index_in] = value_in;
                ref_valid_bit_a[index_in] = 1'b1;

                // Mirror prime_storage_frontend exactly:
                // stored_count becomes the most recently accepted index + 1,
                // not the highest index ever written.
                ref_stored_count_i = index_in + 1;
            end

            //------------------------------------------------------------------
            // Give the DUT one additional clock to absorb the accepted
            // prime_found event before any immediate bookkeeping check.
            //------------------------------------------------------------------
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: pulse start_new_run
    //--------------------------------------------------------------------------
    task pulse_start_new_run;
        begin
            @(posedge clk);
            start_new_run <= 1'b1;
            @(posedge clk);
            start_new_run <= 1'b0;

            clear_reference_model();
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: request one storage read
    //--------------------------------------------------------------------------
    task request_read;
        input integer addr_in;
        begin
            @(posedge clk);
            rd_addr <= addr_in[ADDR_WIDTH-1:0];
            rd_en   <= 1'b1;

            @(posedge clk);
            rd_en   <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait until write traffic drains and frontend becomes stable
    //--------------------------------------------------------------------------
    task wait_until_idle;
        input [255:0] case_name;
        integer wait_i;
        begin
            wait_i = 0;
            while ((ddr_wr_req === 1'b1) ||
                   (wr_busy_ff === 1'b1)  ||
                   (rd_busy_ff === 1'b1)  ||
                   (dut.queue_count_ff != 0) ||
                   (dut.rd_pending_ff !== 1'b0) ||
                   (dut.u_prime_storage_mem.state_ff != 2'd0)) begin
                @(posedge clk);
                wait_i = wait_i + 1;
                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for storage path to become idle"});
                    disable wait_until_idle;
                end
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for rd_data_valid and compare against reference model
    //--------------------------------------------------------------------------
    task expect_read_value;
        input integer read_addr_in;
        input [255:0] case_name;
        integer wait_i;
        reg [DATA_WIDTH-1:0] expected_value_r;
        begin
            total_tests = total_tests + 1;

            //------------------------------------------------------------------
            // Phase 1:
            // Make sure any previous read-data-valid pulse has gone low before
            // waiting for the next read response.
            //------------------------------------------------------------------
            wait_i = 0;
            while (rd_data_valid === 1'b1) begin
                @(posedge clk);
                #1;
                wait_i = wait_i + 1;
                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for previous rd_data_valid pulse to clear"});
                    disable expect_read_value;
                end
            end

            //------------------------------------------------------------------
            // Phase 2:
            // Wait for the new read-data-valid pulse.
            //------------------------------------------------------------------
            wait_i = 0;
            while (rd_data_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                wait_i = wait_i + 1;
                if (wait_i > MAX_WAIT_CYCLES) begin
                    report_error({case_name, " : timeout waiting for rd_data_valid"});
                    disable expect_read_value;
                end
            end

            // DUT outputs are now settled for this returned read value.
            #1;

            expected_value_r = ref_valid_mem_a[read_addr_in];

            if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                expected_value_r   = expected_value_r + 32'd1;
                force_fail_used_ff = 1'b1;
            end

            if (rd_data !== expected_value_r) begin
                $display("FAIL : %0s addr=%0d expected=%0d actual=%0d",
                         case_name, read_addr_in, expected_value_r, rd_data);
                total_errors = total_errors + 1;
            end
            else begin
                $display("PASS : %0s addr=%0d value=%0d",
                         case_name, read_addr_in, rd_data);
                total_passes = total_passes + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: compare stored_count to reference
    //--------------------------------------------------------------------------
    task check_stored_count;
        input [255:0] case_name;
        begin
            total_tests = total_tests + 1;
            if (stored_count !== ref_stored_count_i[31:0]) begin
                $display("FAIL : %0s stored_count expected=%0d actual=%0d",
                         case_name, ref_stored_count_i, stored_count);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : stored_count"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: check storage_full
    //--------------------------------------------------------------------------
    task check_storage_full;
        input integer expected_full_in;
        input [255:0] case_name;
        begin
            total_tests = total_tests + 1;
            if (storage_full !== expected_full_in[0]) begin
                $display("FAIL : %0s storage_full expected=%0d actual=%0d",
                         case_name, expected_full_in, storage_full);
                total_errors = total_errors + 1;
            end
            else begin
                report_pass({case_name, " : storage_full"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Behavioral DDR service model
    //
    // This model accepts one outstanding write and one outstanding read request
    // with randomized return latency. It mirrors the one-at-a-time behavior
    // expected by prime_storage_mem. 
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ddr_wr_ack        <= 1'b0;
            ddr_rd_data_valid <= 1'b0;
            ddr_rd_data       <= {DATA_WIDTH{1'b0}};

            wr_busy_ff        <= 1'b0;
            wr_addr_hold_ff   <= {ADDR_WIDTH{1'b0}};
            wr_data_hold_ff   <= {DATA_WIDTH{1'b0}};
            wr_countdown_ff   <= 0;

            rd_busy_ff        <= 1'b0;
            rd_addr_hold_ff   <= {ADDR_WIDTH{1'b0}};
            rd_countdown_ff   <= 0;
        end
        else begin
            ddr_wr_ack        <= 1'b0;
            ddr_rd_data_valid <= 1'b0;

            //------------------------------------------------------------------
            // Capture new write request
            //------------------------------------------------------------------
            if (ddr_wr_req && !wr_busy_ff) begin
                wr_busy_ff      <= 1'b1;
                wr_addr_hold_ff <= ddr_wr_addr;
                wr_data_hold_ff <= ddr_wr_data;

                rand_seed       <= (rand_seed * 32'd1664525) + 32'd1013904223;
                wr_countdown_ff <= ((rand_seed & 32'h7fffffff) % 4) + 1;
            end
            else if (wr_busy_ff) begin
                if (wr_countdown_ff > 1) begin
                    wr_countdown_ff <= wr_countdown_ff - 1;
                end
                else begin
                    ddr_mem_a[wr_addr_hold_ff] <= wr_data_hold_ff;
                    ddr_wr_ack                 <= 1'b1;
                    wr_busy_ff                 <= 1'b0;
                    wr_countdown_ff            <= 0;
                end
            end

            //------------------------------------------------------------------
            // Capture new read request
            //------------------------------------------------------------------
            if (ddr_rd_req && !rd_busy_ff) begin
                rd_busy_ff      <= 1'b1;
                rd_addr_hold_ff <= ddr_rd_addr;

                rand_seed       <= (rand_seed * 32'd1664525) + 32'd1013904223;
                rd_countdown_ff <= ((rand_seed & 32'h7fffffff) % 4) + 1;
            end
            else if (rd_busy_ff) begin
                if (rd_countdown_ff > 1) begin
                    rd_countdown_ff <= rd_countdown_ff - 1;
                end
                else begin
                    ddr_rd_data       <= ddr_mem_a[rd_addr_hold_ff];
                    ddr_rd_data_valid <= 1'b1;
                    rd_busy_ff        <= 1'b0;
                    rd_countdown_ff   <= 0;
                end
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
        $display("tb_prime_ddr_storage");
        $display("Purpose:");
        $display("  Self-checking verification of the DDR-backed prime storage");
        $display("  path using prime_storage_frontend and a behavioral DDR model.");
        $display("Tests:");
        $display("  reset, queued writes, held reads, read-after-write,");
        $display("  start_new_run reset, storage_full edge cases, random traffic,");
        $display("  and forced-fail.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / idle behavior
        //----------------------------------------------------------------------
        apply_reset();
        wait_cycles(2);

        total_tests = total_tests + 1;
        if ((stored_count !== 32'd0) || (storage_full !== 1'b0) ||
            (rd_data_valid !== 1'b0) || (ddr_wr_req !== 1'b0) || (ddr_rd_req !== 1'b0)) begin
            report_error("reset check : outputs not idle after reset");
        end
        else begin
            report_pass("reset check : outputs idle after reset");
        end

        //----------------------------------------------------------------------
        // Directed case 1: single write
        //----------------------------------------------------------------------
        send_prime_found(32'd2, 0);
        wait_until_idle("single write drain");
        check_stored_count("single write");
        check_storage_full(0, "single write");

        request_read(0);
        expect_read_value(0, "single readback value 0");

        //----------------------------------------------------------------------
        // Directed case 2: queued back-to-back writes
        //----------------------------------------------------------------------
        send_prime_found(32'd3, 1);
        send_prime_found(32'd5, 2);
        send_prime_found(32'd7, 3);
        send_prime_found(32'd11, 4);

        wait_until_idle("queued writes drain");
        check_stored_count("queued writes");

        request_read(1);
        expect_read_value(1, "queued readback addr1");

        request_read(2);
        expect_read_value(2, "queued readback addr2");

        request_read(3);
        expect_read_value(3, "queued readback addr3");

        request_read(4);
        expect_read_value(4, "queued readback addr4");

        //----------------------------------------------------------------------
        // Directed case 3: held read while writes are still draining
        //
        // Issue more writes, then request a read before the queue is empty.
        // The frontend should hold the read until writes finish. :contentReference[oaicite:2]{index=2}
        //----------------------------------------------------------------------
        send_prime_found(32'd13, 5);
        send_prime_found(32'd17, 6);
        send_prime_found(32'd19, 7);

        request_read(7);
        expect_read_value(7, "held read after queued writes");

        wait_until_idle("held read final drain");
        check_stored_count("held read stored_count");

        //----------------------------------------------------------------------
        // Directed case 4: start_new_run bookkeeping reset
        //----------------------------------------------------------------------
        pulse_start_new_run();
        wait_cycles(2);

        check_stored_count("start_new_run clear");
        check_storage_full(0, "start_new_run clear");

        //----------------------------------------------------------------------
        // Directed case 5: write new run data from address 0 upward
        //----------------------------------------------------------------------
        send_prime_found(32'd23, 0);
        send_prime_found(32'd29, 1);
        wait_until_idle("new run writes drain");

        check_stored_count("new run writes");
        request_read(0);
        expect_read_value(0, "new run readback addr0");

        request_read(1);
        expect_read_value(1, "new run readback addr1");

        //----------------------------------------------------------------------
        // Directed case 6: out-of-range index should not advance stored_count,
        // but should assert storage_full. :contentReference[oaicite:3]{index=3}
        //----------------------------------------------------------------------
        send_prime_found(32'd999, DEPTH);
        wait_cycles(2);

        check_stored_count("out-of-range write");
        check_storage_full(1, "out-of-range write");

        //----------------------------------------------------------------------
        // Randomized traffic
        //----------------------------------------------------------------------
        for (rand_i = 0; rand_i < RANDOM_OP_COUNT; rand_i = rand_i + 1) begin
            rand_seed         = (rand_seed * 32'd1664525) + 32'd1013904223;
            rand_rw_select_i  = (rand_seed & 32'h7fffffff) % 3;

            if (rand_rw_select_i != 0) begin
                rand_seed  = (rand_seed * 32'd1664525) + 32'd1013904223;
                rand_addr_i = (rand_seed & 32'h7fffffff) % DEPTH;

                rand_seed  = (rand_seed * 32'd1664525) + 32'd1013904223;
                rand_val_i = ((rand_seed & 32'h7fffffff) % 100000) + 2;

                send_prime_found(rand_val_i[31:0], rand_addr_i);
            end
            else begin
                rand_seed  = (rand_seed * 32'd1664525) + 32'd1013904223;
                rand_addr_i = (rand_seed & 32'h7fffffff) % DEPTH;

                request_read(rand_addr_i);
                expect_read_value(rand_addr_i, "randomized readback");
            end
        end

        wait_until_idle("randomized traffic drain");
        check_stored_count("randomized traffic stored_count");

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_prime_ddr_storage complete");
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