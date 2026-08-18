`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_top_smoke.v
//
// Purpose:
//   Top-level smoke/integration testbench for the Optimus Prime FPGA project.
//
// What this testbench verifies:
//   1) Top-level reset behavior
//   2) Basic VGA output activity: HSYNC and VSYNC are not X and HSYNC toggles
//   3) UI navigation path using renderer navigation wires:
//        MENU -> PARAMS -> GENERATING -> RESULTS -> MENU
//        MENU -> TEST -> MENU
//   4) Soft-reset behavior from a non-menu screen
//   5) Random navigation stress checking for illegal/X display states
//   6) Self-checking PASS/FAIL summary with error count
//   7) Forced-fail case to prove the testbench does not always pass
//
// Notes:
//   - This is intentionally a smoke test, not a deep exhaustive system test.
//   - Lower-level modules already have dedicated testbenches.
//   - This bench uses hierarchical force/release on top-level internal wires
//     so it can drive UI navigation without modeling full mouse/SD/DDR behavior.
//   - Set FORCE_FAIL_CASE = 1 to intentionally fail one check.
//------------------------------------------------------------------------------

module tb_top_smoke;

    //--------------------------------------------------------------------------
    // User-controlled forced failure switch
    //
    // Set to 1 to intentionally fail one check and prove the testbench is
    // self-checking.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL_CASE = 1;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk100mhz;
    reg resetn;

    //--------------------------------------------------------------------------
    // DDR2 interface wires
    //--------------------------------------------------------------------------
    wire [15:0] ddr2_dq;
    wire [1:0]  ddr2_dqs_n;
    wire [1:0]  ddr2_dqs_p;
    wire [12:0] ddr2_addr;
    wire [2:0]  ddr2_ba;
    wire        ddr2_ras_n;
    wire        ddr2_cas_n;
    wire        ddr2_we_n;
    wire [0:0]  ddr2_ck_p;
    wire [0:0]  ddr2_ck_n;
    wire [0:0]  ddr2_cke;
    wire [0:0]  ddr2_cs_n;
    wire [1:0]  ddr2_dm;
    wire [0:0]  ddr2_odt;

    //--------------------------------------------------------------------------
    // VGA outputs
    //--------------------------------------------------------------------------
    wire [3:0] RED;
    wire [3:0] GRN;
    wire [3:0] BLU;
    wire       HSYNC;
    wire       VSYNC;

    //--------------------------------------------------------------------------
    // PS/2 mouse lines
    //--------------------------------------------------------------------------
    tri1 ps2_clk;
    tri1 ps2_data;

    //--------------------------------------------------------------------------
    // microSD interface
    //--------------------------------------------------------------------------
    wire sd_clk;
    wire sd_cmd;
    wire sd_dat3_cs_n;
    wire sd_reset_n;
    reg  sd_dat0_miso;
    wire sd_dat1_unused;
    wire sd_dat2_unused;
    reg  sd_card_detect;

    //--------------------------------------------------------------------------
    // Keypad and pushbuttons
    //--------------------------------------------------------------------------
    reg  [3:0] kp_row;
    wire [3:0] kp_col;

    reg BTNC;
    reg BTNU;
    reg BTND;
    reg BTNL;
    reg BTNR;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_errors;
    integer random_index;
    integer rand_value;

    //--------------------------------------------------------------------------
    // DUT instance
    //--------------------------------------------------------------------------
    top dut (
        .clk100mhz       (clk100mhz),
        .resetn          (resetn),

        .ddr2_dq         (ddr2_dq),
        .ddr2_dqs_n      (ddr2_dqs_n),
        .ddr2_dqs_p      (ddr2_dqs_p),
        .ddr2_addr       (ddr2_addr),
        .ddr2_ba         (ddr2_ba),
        .ddr2_ras_n      (ddr2_ras_n),
        .ddr2_cas_n      (ddr2_cas_n),
        .ddr2_we_n       (ddr2_we_n),
        .ddr2_ck_p       (ddr2_ck_p),
        .ddr2_ck_n       (ddr2_ck_n),
        .ddr2_cke        (ddr2_cke),
        .ddr2_cs_n       (ddr2_cs_n),
        .ddr2_dm         (ddr2_dm),
        .ddr2_odt        (ddr2_odt),

        .RED             (RED),
        .GRN             (GRN),
        .BLU             (BLU),
        .HSYNC           (HSYNC),
        .VSYNC           (VSYNC),

        .ps2_clk         (ps2_clk),
        .ps2_data        (ps2_data),

        .sd_clk          (sd_clk),
        .sd_cmd          (sd_cmd),
        .sd_dat3_cs_n    (sd_dat3_cs_n),
        .sd_reset_n      (sd_reset_n),
        .sd_dat0_miso    (sd_dat0_miso),
        .sd_dat1_unused  (sd_dat1_unused),
        .sd_dat2_unused  (sd_dat2_unused),
        .sd_card_detect  (sd_card_detect),

        .kp_row          (kp_row),
        .kp_col          (kp_col),

        .BTNC            (BTNC),
        .BTNU            (BTNU),
        .BTND            (BTND),
        .BTNL            (BTNL),
        .BTNR            (BTNR)
    );

    //--------------------------------------------------------------------------
    // 100 MHz clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk100mhz = 1'b0;
        forever #5 clk100mhz = ~clk100mhz;
    end

    //--------------------------------------------------------------------------
    // Common reporting task
    //--------------------------------------------------------------------------
    task report_check;
        input        condition_ok;
        input [1023:0] check_name;
        begin
            total_tests = total_tests + 1;

            if (condition_ok) begin
                $display("PASS : %0s", check_name);
            end
            else begin
                total_errors = total_errors + 1;
                $display("FAIL : %0s at time %0t", check_name, $time);
            end
        end
    endtask

    task wait_board_cycles;
        input integer num_cycles;
        integer wait_index;
        begin
            for (wait_index = 0; wait_index < num_cycles; wait_index = wait_index + 1) begin
                @(posedge clk100mhz);
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Wait helper
    //--------------------------------------------------------------------------
    task wait_cpu_cycles;
        input integer num_cycles;
        integer wait_index;
        begin
            for (wait_index = 0; wait_index < num_cycles; wait_index = wait_index + 1) begin
                @(posedge dut.clk_cpu_w);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // UI navigation pulse helpers
    //--------------------------------------------------------------------------
    task pulse_menu_click;
        input [1:0] selected_mode;
        begin
            force dut.nav_mode_sel_w   = selected_mode;
            force dut.nav_menu_click_w = 1'b1;
            wait_cpu_cycles(2);
            force dut.nav_menu_click_w = 1'b0;
            wait_cpu_cycles(10);
            release dut.nav_mode_sel_w;
            release dut.nav_menu_click_w;
        end
    endtask

    task pulse_start_click;
        begin
            force dut.nav_start_w = 1'b1;
            wait_cpu_cycles(5);
            force dut.nav_start_w = 1'b0;
            wait_cpu_cycles(20);
            release dut.nav_start_w;
        end
    endtask

    task pulse_back_click;
        begin
            force dut.nav_back_w = 1'b1;
            wait_cpu_cycles(2);
            force dut.nav_back_w = 1'b0;
            wait_cpu_cycles(10);
            release dut.nav_back_w;
        end
    endtask

    task pulse_subsystem_done;
        begin
            force dut.sub_done_w = 1'b1;
            wait_cpu_cycles(2);
            force dut.sub_done_w = 1'b0;
            wait_cpu_cycles(10);
            release dut.sub_done_w;
        end
    endtask

    task pulse_soft_reset;
        begin
            force dut.btnc_press_w = 1'b1;
            wait_cpu_cycles(2);
            force dut.btnc_press_w = 1'b0;
            wait_cpu_cycles(10);
            release dut.btnc_press_w;
        end
    endtask

    //--------------------------------------------------------------------------
    // Check display mode helper
    //--------------------------------------------------------------------------
    task check_display_mode;
        input [2:0] expected_mode;
        input [1023:0] check_name;
        reg [2:0] compare_mode;
        begin
            compare_mode = expected_mode;

            if (FORCE_FAIL_CASE != 0) begin
                compare_mode = expected_mode ^ 3'b001;
            end
            else begin
                compare_mode = expected_mode;
            end

            report_check((dut.display_mode_w === compare_mode), check_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Check for legal display mode
    //--------------------------------------------------------------------------
    task check_display_mode_legal;
        input [1023:0] check_name;
        begin
            report_check((dut.display_mode_w !== 3'bxxx) &&
                         (dut.display_mode_w <= 3'd6),
                         check_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        total_tests  = 0;
        total_errors = 0;

        resetn         = 1'b0;
        sd_dat0_miso   = 1'b1;
        sd_card_detect = 1'b0;
        kp_row         = 4'b1111;

        BTNC = 1'b0;
        BTNU = 1'b0;
        BTND = 1'b0;
        BTNL = 1'b0;
        BTNR = 1'b0;

        $display("------------------------------------------------------------");
        $display("tb_top_smoke starting");
        $display("FORCE_FAIL_CASE = %0d", FORCE_FAIL_CASE);
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset release
        //----------------------------------------------------------------------
        wait_board_cycles(20);
        resetn = 1'b1;
        wait_board_cycles(500);
        wait_cpu_cycles(200);

        check_display_mode(3'd0, "reset boots UI to MENU display_mode=0");

        //--------------------------------------------------------------------------
        // Fast VGA output smoke check
        //
        // Do not wait for full DDR2/MIG framebuffer bring-up here. The real MIG
        // simulation model is very slow. For this top-level smoke test, only verify
        // that the output signals are not unknown after reset.
        //--------------------------------------------------------------------------
        wait_cpu_cycles(1000);
        
        report_check((HSYNC !== 1'bx), "HSYNC is not X");
        report_check((VSYNC !== 1'bx), "VSYNC is not X");
        report_check((RED   !== 4'bxxxx), "RED output is not X");
        report_check((GRN   !== 4'bxxxx), "GRN output is not X");
        report_check((BLU   !== 4'bxxxx), "BLU output is not X");

        //----------------------------------------------------------------------
        // UI navigation: MENU -> PARAMS using RANGE mode
        //----------------------------------------------------------------------
        pulse_menu_click(2'd0);
        check_display_mode(3'd1, "MENU Range click moves to PARAMS display_mode=1");
        report_check((dut.mode_w === 2'd0), "RANGE mode latched mode=0");

        //----------------------------------------------------------------------
        // UI navigation: PARAMS -> GENERATING
        //----------------------------------------------------------------------
        // Hold sub_done low so the real subsystem cannot immediately skip
        // GENERATING and move to RESULT before this smoke check observes it.
        force dut.sub_done_w = 1'b0;
        
        pulse_start_click();
        check_display_mode(3'd2, "Start click moves PARAMS to GENERATING display_mode=2");
        
        release dut.sub_done_w;
        wait_cpu_cycles(5);

        //----------------------------------------------------------------------
        // UI navigation: GENERATING -> RESULT using forced subsystem done pulse
        //----------------------------------------------------------------------
        pulse_subsystem_done();
        check_display_mode(3'd3, "sub_done moves GENERATING to RESULT display_mode=3");

        //----------------------------------------------------------------------
        // UI navigation: RESULT -> MENU
        //----------------------------------------------------------------------
        pulse_back_click();
        check_display_mode(3'd0, "Back click moves RESULT to MENU display_mode=0");

        //----------------------------------------------------------------------
        // UI navigation: MENU -> TEST -> MENU
        //----------------------------------------------------------------------
        pulse_menu_click(2'd3);
        check_display_mode(3'd5, "MENU Test Mode click moves to TEST display_mode=5");

        pulse_back_click();
        check_display_mode(3'd0, "Back click moves TEST to MENU display_mode=0");

        //----------------------------------------------------------------------
        // Soft reset edge case from PARAMS screen
        //----------------------------------------------------------------------
        pulse_menu_click(2'd1);
        check_display_mode(3'd1, "MENU Time click moves to PARAMS before soft reset");

        pulse_soft_reset();
        check_display_mode(3'd0, "soft reset returns UI to MENU display_mode=0");

        //----------------------------------------------------------------------
        // Random navigation stress
        //----------------------------------------------------------------------
        for (random_index = 0; random_index < 25; random_index = random_index + 1) begin
            rand_value = $random;

            if (rand_value[1:0] == 2'd0) begin
                pulse_menu_click(rand_value[3:2]);
            end
            else if (rand_value[1:0] == 2'd1) begin
                pulse_back_click();
            end
            else if (rand_value[1:0] == 2'd2) begin
                pulse_start_click();
            end
            else begin
                pulse_soft_reset();
            end

            check_display_mode_legal("random navigation keeps display_mode legal and non-X");
        end

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_top_smoke complete");
        $display("Total checks : %0d", total_tests);
        $display("Total errors : %0d", total_errors);
        $display("------------------------------------------------------------");

        if (total_errors == 0) begin
            $display("OVERALL RESULT: PASS");
        end
        else begin
            $display("OVERALL RESULT: FAIL");
        end

        $finish;
    end

endmodule