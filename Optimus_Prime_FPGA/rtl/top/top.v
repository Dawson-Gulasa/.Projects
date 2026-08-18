`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// top.v
//
// Purpose:
//   Top-level integration module for the Optimus Prime FPGA project on the
//   Nexys A7-100T board.
//
//   This module connects the major project subsystems:
//     1) Clock generation and reset gating
//     2) Pushbutton/keypad input conditioning
//     3) PS/2 mouse input and cursor crossing
//     4) SD-card byte streaming and prime parsing
//     5) UI state control and parameter entry
//     6) Prime computation and DDR-backed prime storage
//     7) DDR2 framebuffer controller
//     8) VGA output with cursor overlay
//
// Design style:
//   - This file is intentionally wiring-oriented.
//   - Major behavior is pushed into lower-level modules.
//   - Clock-domain crossings are handled with explicit synchronizer modules.
//   - DDR2 is shared between the framebuffer path and the prime-storage path.
//------------------------------------------------------------------------------
module top (
    //--------------------------------------------------------------------------
    // Board clock / reset
    //--------------------------------------------------------------------------
    input  wire        clk100mhz,        // 100 MHz oscillator from Nexys A7 board
    input  wire        resetn,           // Active-low board reset input

    //--------------------------------------------------------------------------
    // DDR2 physical interface
    //--------------------------------------------------------------------------
    inout  wire [15:0] ddr2_dq,          // DDR2 bidirectional data bus
    inout  wire [1:0]  ddr2_dqs_n,       // DDR2 negative data strobe
    inout  wire [1:0]  ddr2_dqs_p,       // DDR2 positive data strobe
    output wire [12:0] ddr2_addr,        // DDR2 row/column address bus
    output wire [2:0]  ddr2_ba,          // DDR2 bank address bus
    output wire        ddr2_ras_n,       // DDR2 row-address strobe, active low
    output wire        ddr2_cas_n,       // DDR2 column-address strobe, active low
    output wire        ddr2_we_n,        // DDR2 write enable, active low
    output wire [0:0]  ddr2_ck_p,        // DDR2 differential clock positive
    output wire [0:0]  ddr2_ck_n,        // DDR2 differential clock negative
    output wire [0:0]  ddr2_cke,         // DDR2 clock enable
    output wire [0:0]  ddr2_cs_n,        // DDR2 chip select, active low
    output wire [1:0]  ddr2_dm,          // DDR2 data mask bits
    output wire [0:0]  ddr2_odt,         // DDR2 on-die termination control

    //--------------------------------------------------------------------------
    // VGA output interface
    //--------------------------------------------------------------------------
    output wire [3:0]  RED,              // VGA red channel
    output wire [3:0]  GRN,              // VGA green channel
    output wire [3:0]  BLU,              // VGA blue channel
    output wire        HSYNC,            // VGA horizontal sync
    output wire        VSYNC,            // VGA vertical sync

    //--------------------------------------------------------------------------
    // PS/2 mouse interface through the Nexys A7 USB-HID bridge
    //--------------------------------------------------------------------------
    inout  wire        ps2_clk,          // Open-collector PS/2 clock line
    inout  wire        ps2_data,         // Open-collector PS/2 data line

    //--------------------------------------------------------------------------
    // On-board microSD slot
    //--------------------------------------------------------------------------
    output wire        sd_clk,           // SD-card clock output
    inout  wire        sd_cmd,           // SD-card command line
    output wire        sd_dat3_cs_n,     // SD DAT3 / chip-select line
    output wire        sd_reset_n,       // SD-card active-low reset / enable
    input  wire        sd_dat0_miso,     // SD DAT0 card-to-FPGA data line
    output wire        sd_dat1_unused,   // SD DAT1 unused line held by SD source
    output wire        sd_dat2_unused,   // SD DAT2 unused line held by SD source
    input  wire        sd_card_detect,   // SD-card detect input from socket

    //--------------------------------------------------------------------------
    // Pmod KYPD keypad interface
    //--------------------------------------------------------------------------
    input  wire [3:0]  kp_row,           // Keypad row inputs sampled by FPGA
    output wire [3:0]  kp_col,           // Keypad column drive outputs

    //--------------------------------------------------------------------------
    // Onboard pushbutton inputs
    //--------------------------------------------------------------------------
    input  wire        BTNC,             // Center button, used as soft reset
    input  wire        BTNU,             // Up button, available/debug input
    input  wire        BTND,             // Down button, available/debug input
    input  wire        BTNL,             // Left button, available/debug input
    input  wire        BTNR              // Right button, available/debug input
);

    //==========================================================================
    // Clock generation
    //
    // The PLL generates all project clocks from the 100 MHz board oscillator.
    // The locked signal is used to hold the rest of the design in reset until
    // the derived clocks are stable.
    //==========================================================================
    wire clk_mem_w;      // 200 MHz memory reference clock for DDR2 MIG
    wire clk_vga_w;      // 25 MHz VGA pixel clock
    wire clk_cpu_w;      // 100 MHz main system / UI / compute clock
    wire clk_sd_w;       // 50 MHz SD-card controller clock
    wire pll_locked_w;   // PLL lock indicator

    pll u_pll (
        .resetn  (resetn),
        .locked  (pll_locked_w),
        .clk_in  (clk100mhz),
        .clk_mem (clk_mem_w),
        .clk_vga (clk_vga_w),
        .clk_cpu (clk_cpu_w),
        .clk_sd  (clk_sd_w)
    );

    //--------------------------------------------------------------------------
    // Global reset
    //
    // Downstream logic is released only after the external reset is deasserted
    // and the PLL has locked.
    //--------------------------------------------------------------------------
    wire sys_resetn_w;
    assign sys_resetn_w = resetn & pll_locked_w;

    //==========================================================================
    // Build-profile configuration
    //
    // DEBUG_BUILD selects smaller simulation/debug capacities or full final
    // project capacities from one central location.
    //==========================================================================
    localparam integer DEBUG_BUILD = 0;

    localparam integer PRIME_ADDR_WIDTH_CFG =
        (DEBUG_BUILD != 0) ? 12 : 23;

    localparam integer PRIME_DEPTH_CFG =
        (DEBUG_BUILD != 0) ? 4096 : 5761455;

    localparam integer PRIME_QUEUE_DEPTH_CFG =
        (DEBUG_BUILD != 0) ? 64 : 4096;

    localparam integer PRIME_QUEUE_AWIDTH_CFG =
        (DEBUG_BUILD != 0) ? 6 : 12;

    localparam integer SD_FEEDER_DEPTH_CFG =
        (DEBUG_BUILD != 0) ? 16 : 64;

    localparam integer SD_FEEDER_PTR_WIDTH_CFG =
        (DEBUG_BUILD != 0) ? 4 : 6;

    //==========================================================================
    // Input controller
    //
    // input_ctrl debounces the five onboard pushbuttons and scans the Pmod
    // keypad. It outputs clean stable levels and one-cycle press pulses.
    //==========================================================================
    wire [3:0] kp_col_unused_w;                // Legacy unused keypad column wire
    wire       btnc_level_w, btnu_level_w;     // Debounced button stable levels
    wire       btnd_level_w, btnl_level_w;
    wire       btnr_level_w;
    wire       btnc_press_w, btnu_press_w;     // One-cycle button press pulses
    wire       btnd_press_w, btnl_press_w;
    wire       btnr_press_w;
    wire       key_valid_w;                    // Keypad stable key valid flag
    wire [3:0] key_code_w;                     // Decoded keypad hex code
    wire       key_press_w;                    // One-cycle keypad press pulse

    input_ctrl u_input_ctrl (
        .clk        (clk_cpu_w),
        .rst_n      (sys_resetn_w),
        .btnc_raw   (BTNC),
        .btnu_raw   (BTNU),
        .btnd_raw   (BTND),
        .btnl_raw   (BTNL),
        .btnr_raw   (BTNR),
        .kp_row     (kp_row),
        .kp_col     (kp_col),
        .btnc_level (btnc_level_w),
        .btnu_level (btnu_level_w),
        .btnd_level (btnd_level_w),
        .btnl_level (btnl_level_w),
        .btnr_level (btnr_level_w),
        .btnc_press (btnc_press_w),
        .btnu_press (btnu_press_w),
        .btnd_press (btnd_press_w),
        .btnl_press (btnl_press_w),
        .btnr_press (btnr_press_w),
        .key_valid  (key_valid_w),
        .key_code   (key_code_w),
        .key_press  (key_press_w)
    );

    //==========================================================================
    // PS/2 mouse subsystem
    //
    // The mouse path reads PS/2 packets from the board's USB-HID bridge,
    // updates a bounded cursor position, and transfers cursor state into the
    // VGA clock domain for drawing.
    //==========================================================================
    wire ps2_clk_drive_low_w;       // Mouse subsystem drive-low control for PS/2 clock
    wire ps2_data_drive_low_w;      // Mouse subsystem drive-low control for PS/2 data
    wire ps2_clk_in_w;              // Sampled PS/2 clock line
    wire ps2_data_in_w;             // Sampled PS/2 data line

    wire [9:0] cursor_x_vga_w;      // Cursor X coordinate in VGA clock domain
    wire [9:0] cursor_y_vga_w;      // Cursor Y coordinate in VGA clock domain
    wire       left_btn_vga_w;      // Left mouse button state in VGA domain
    wire       right_btn_vga_w;     // Right mouse button state in VGA domain
    wire       mouse_init_done_w;   // Mouse initialization complete flag
    wire       mouse_rx_err_w;      // Mouse receive error pulse
    wire       mouse_tx_err_w;      // Mouse transmit error pulse

    // Open-collector PS/2 behavior: drive low for 0, otherwise release line.
    assign ps2_clk       = ps2_clk_drive_low_w  ? 1'b0 : 1'bz;
    assign ps2_data      = ps2_data_drive_low_w ? 1'b0 : 1'bz;
    assign ps2_clk_in_w  = ps2_clk;
    assign ps2_data_in_w = ps2_data;

    mouse_subsystem #(
        .CLK_SYS_HZ   (100_000_000),
        .CLK_VGA_HZ   (25_000_000),
        .SCREEN_W     (640),
        .SCREEN_H     (480),
        .CURSOR_X_MIN (16),
        .CURSOR_X_MAX (623),
        .CURSOR_Y_MIN (16),
        .CURSOR_Y_MAX (463)
    ) u_mouse_subsystem (
        .clk_sys             (clk_cpu_w),
        .resetn_sys          (sys_resetn_w),
        .clk_vga             (clk_vga_w),
        .resetn_vga          (sys_resetn_w),
        .ps2_clk_raw         (ps2_clk_in_w),
        .ps2_data_raw        (ps2_data_in_w),
        .ps2_clk_drive_low   (ps2_clk_drive_low_w),
        .ps2_data_drive_low  (ps2_data_drive_low_w),
        .cursor_x_vga        (cursor_x_vga_w),
        .cursor_y_vga        (cursor_y_vga_w),
        .left_btn_vga        (left_btn_vga_w),
        .right_btn_vga       (right_btn_vga_w),
        .mouse_init_done     (mouse_init_done_w),
        .mouse_rx_error_pulse(mouse_rx_err_w),
        .mouse_tx_error_pulse(mouse_tx_err_w)
    );

    //==========================================================================
    // Cursor/button CDC: clk_vga -> clk_cpu
    //
    // The cursor is generated in the VGA domain but the UI renderer and screen
    // hit-detection logic run in the CPU domain. These synchronizers bring the
    // slow-changing cursor/button state into clk_cpu.
    //==========================================================================
    wire [9:0] cursor_x_cpu_w;      // Cursor X synchronized into CPU domain
    wire [9:0] cursor_y_cpu_w;      // Cursor Y synchronized into CPU domain
    wire       left_btn_cpu_w;      // Left button synchronized into CPU domain

    sync_ff #(.WIDTH(10), .RESET_VAL(0)) u_sync_cur_x (
        .dst_clk (clk_cpu_w),
        .resetn  (sys_resetn_w),
        .d       (cursor_x_vga_w),
        .q       (cursor_x_cpu_w)
    );

    sync_ff #(.WIDTH(10), .RESET_VAL(0)) u_sync_cur_y (
        .dst_clk (clk_cpu_w),
        .resetn  (sys_resetn_w),
        .d       (cursor_y_vga_w),
        .q       (cursor_y_cpu_w)
    );

    sync_ff #(.WIDTH(1), .RESET_VAL(0)) u_sync_lbtn (
        .dst_clk (clk_cpu_w),
        .resetn  (sys_resetn_w),
        .d       (left_btn_vga_w),
        .q       (left_btn_cpu_w)
    );

    //--------------------------------------------------------------------------
    // Left-click pulse generation
    //
    // The UI uses a one-cycle pulse when the left mouse button is released.
    // This produces one clean click event after a press/release action.
    //--------------------------------------------------------------------------
    reg  left_btn_cpu_prev_ff;      // Previous synchronized left-button state
    wire left_click_pulse_w;        // One-cycle CPU-domain click pulse

    always @(posedge clk_cpu_w) begin
        // Clear previous button state during reset.
        if (!sys_resetn_w) begin
            left_btn_cpu_prev_ff <= 1'b0;
        end
        // Track the current synchronized button state for edge detection.
        else begin
            left_btn_cpu_prev_ff <= left_btn_cpu_w;
        end
    end

    assign left_click_pulse_w = left_btn_cpu_prev_ff & ~left_btn_cpu_w;

    //==========================================================================
    // Test-mode SD stream control
    //
    // Each Test Mode run restarts the SD stream from the beginning of CSEE4280Primes.txt.
    // test_mode_ctrl generates test_sd_start_w in clk_cpu, which is synchronized
    // into clk_sd and stretched into short local reset pulses. This resets only
    // the SD stream pipeline instead of resetting the full project.
    //==========================================================================
    wire        test_sd_start_w;          // CPU-domain request to restart SD stream
    wire        test_sd_next_w;           // Test-mode request for next SD prime
    wire        test_sd_prime_valid_w;    // Feeder output valid pulse
    wire [31:0] test_sd_prime_value_w;    // Feeder output prime value
    wire        test_sd_end_of_file_w;    // Feeder end-of-file indication

    wire        test_sd_start_sd_w;       // SD-domain synchronized stream-start pulse

    reg [4:0]   sd_stream_rst_cnt_cpu_ff; // CPU-domain local reset stretch counter
    reg [4:0]   sd_stream_rst_cnt_sd_ff;  // SD-domain local reset stretch counter

    wire        sd_stream_resetn_cpu_w;   // CPU-domain reset for SD parser/feeder path
    wire        sd_stream_resetn_sd_w;    // SD-domain reset for SD byte source

    pulse_sync u_test_sd_start_to_sd (
        .src_clk   (clk_cpu_w),
        .src_rst   (~sys_resetn_w),
        .src_pulse (test_sd_start_w),
        .dst_clk   (clk_sd_w),
        .dst_rst   (~sys_resetn_w),
        .dst_pulse (test_sd_start_sd_w)
    );

    //--------------------------------------------------------------------------
    // CPU-domain SD-stream local reset stretcher
    //
    // When Test Mode starts, hold the CPU-side parser/feeder path in reset for
    // a short fixed number of cycles so it begins from a clean state.
    //--------------------------------------------------------------------------
    always @(posedge clk_cpu_w) begin
        // Clear reset counter during global reset.
        if (!sys_resetn_w) begin
            sd_stream_rst_cnt_cpu_ff <= 5'd0;
        end
        // Load the reset stretch counter on a new test-mode SD start.
        else if (test_sd_start_w) begin
            sd_stream_rst_cnt_cpu_ff <= 5'd16;
        end
        // Count down while the local SD reset is active.
        else if (sd_stream_rst_cnt_cpu_ff != 5'd0) begin
            sd_stream_rst_cnt_cpu_ff <= sd_stream_rst_cnt_cpu_ff - 5'd1;
        end
        // Hold at zero once the local reset window has finished.
        else begin
            sd_stream_rst_cnt_cpu_ff <= sd_stream_rst_cnt_cpu_ff;
        end
    end

    //--------------------------------------------------------------------------
    // SD-domain SD-stream local reset stretcher
    //
    // This performs the same reset stretching as the CPU-domain counter, but in
    // clk_sd for the SD-card byte source.
    //--------------------------------------------------------------------------
    always @(posedge clk_sd_w) begin
        // Clear reset counter during global reset.
        if (!sys_resetn_w) begin
            sd_stream_rst_cnt_sd_ff <= 5'd0;
        end
        // Load the reset stretch counter after the start pulse crosses to clk_sd.
        else if (test_sd_start_sd_w) begin
            sd_stream_rst_cnt_sd_ff <= 5'd16;
        end
        // Count down while the SD byte source is being locally reset.
        else if (sd_stream_rst_cnt_sd_ff != 5'd0) begin
            sd_stream_rst_cnt_sd_ff <= sd_stream_rst_cnt_sd_ff - 5'd1;
        end
        // Hold at zero after the local reset window completes.
        else begin
            sd_stream_rst_cnt_sd_ff <= sd_stream_rst_cnt_sd_ff;
        end
    end

    assign sd_stream_resetn_cpu_w = sys_resetn_w && (sd_stream_rst_cnt_cpu_ff == 5'd0);
    assign sd_stream_resetn_sd_w  = sys_resetn_w && (sd_stream_rst_cnt_sd_ff  == 5'd0);

    //==========================================================================
    // microSD SD-protocol byte source
    //
    // The SD source reads CSEE4280Primes.txt from the card and emits a byte stream in the
    // SD clock domain. The byte stream later crosses into clk_cpu for parsing.
    //==========================================================================
    wire        sd_file_byte_valid_sd_w;  // SD-domain byte-valid pulse
    wire [7:0]  sd_file_byte_sd_w;        // SD-domain byte from CSEE4280Primes.txt
    wire        sd_file_done_sd_w;        // SD-domain stream-done pulse
    wire        sd_file_found_w;          // File-found status from SD reader
    wire [2:0]  sd_filesystem_state_w;    // SD filesystem/debug state
    wire [3:0]  sd_card_stat_w;           // SD card/debug status
    wire        sd_card_inserted_w;       // SD card inserted status

    wire        sd_file_byte_valid_cpu_w; // CPU-domain byte-valid pulse
    wire [7:0]  sd_file_byte_cpu_w;       // CPU-domain byte from CSEE4280Primes.txt
    wire        sd_file_done_cpu_w;       // CPU-domain stream-done pulse

    sd_file_byte_source #(
        .FILE_NAME("CSEE4280Primes.txt")
    ) u_sd_file_byte_source (
        .clk_sd          (clk_sd_w),
        .resetn          (sd_stream_resetn_sd_w),
        .sd_clk          (sd_clk),
        .sd_cmd          (sd_cmd),
        .sd_dat0         (sd_dat0_miso),
        .sd_dat1         (sd_dat1_unused),
        .sd_dat2         (sd_dat2_unused),
        .sd_dat3         (sd_dat3_cs_n),
        .sd_reset_n      (sd_reset_n),
        .sd_card_detect  (sd_card_detect),
        .byte_valid      (sd_file_byte_valid_sd_w),
        .byte_out        (sd_file_byte_sd_w),
        .stream_done     (sd_file_done_sd_w),
        .file_found      (sd_file_found_w),
        .filesystem_state(sd_filesystem_state_w),
        .card_stat       (sd_card_stat_w),
        .card_inserted   (sd_card_inserted_w)
    );

    sd_byte_sync u_sd_byte_sync (
        .clk_sd          (clk_sd_w),
        .resetn_sd       (sd_stream_resetn_sd_w),
        .clk_cpu         (clk_cpu_w),
        .resetn_cpu      (sd_stream_resetn_cpu_w),
        .sd_byte         (sd_file_byte_sd_w),
        .sd_byte_valid   (sd_file_byte_valid_sd_w),
        .sd_stream_done  (sd_file_done_sd_w),
        .cpu_byte        (sd_file_byte_cpu_w),
        .cpu_byte_valid  (sd_file_byte_valid_cpu_w),
        .cpu_stream_done (sd_file_done_cpu_w)
    );

    //==========================================================================
    // UI FSM: screen navigation and compute/test control
    //
    // ui_fsm owns the active screen selection and generates start/abort pulses
    // for the prime subsystem. It also forwards live compute results into the
    // renderer-friendly signal widths.
    //==========================================================================
    wire [2:0]  display_mode_w;       // Active screen/mode shown by renderer
    wire [1:0]  mode_w;               // UI-selected mode: range/time/single/test
    wire [26:0] field0_val_w;         // First numeric entry field value
    wire [26:0] field1_val_w;         // Second numeric entry field value
    wire        active_field_w;       // Selected parameter-entry field
    wire        entry_done_w;         // Parameter entry completion flag
    wire        input_error_w;        // Parameter entry error flag
    wire [23:0] prime_count_w;        // UI-width prime count
    wire [26:0] current_n_w;          // UI-width current candidate
    wire [12:0] elapsed_sec_w;        // UI-width elapsed seconds
    wire        compute_done_w;       // Compute complete flag for display
    wire [539:0] last_primes_w;       // Packed list of recent primes for display
    wire [26:0] largest_prime_w;      // UI-width largest prime found
    wire        single_is_prime_w;    // Single-mode result flag

    //--------------------------------------------------------------------------
    // Test-mode status displayed by the UI.
    //--------------------------------------------------------------------------
    wire        test_running_w;       // Test Mode currently comparing values
    wire        test_passed_w;        // Test Mode completed with pass
    wire        test_failed_w;        // Test Mode completed with failure
    wire        no_data_stored_w;     // Test Mode detected no stored prime data
    wire [23:0] primes_checked_w;     // Number of prime comparisons completed
    wire [26:0] fail_ddr_val_w;       // Mismatched DDR/stored value
    wire [26:0] fail_sd_val_w;        // Mismatched SD reference value

    wire        fsm_sub_start_w;      // Start pulse from UI FSM to prime subsystem
    wire        fsm_sub_abort_w;      // Abort pulse from UI FSM to prime subsystem
    wire        fsm_sub_start_new_run_w; // Storage reset pulse for a new compute run

    wire        sub_busy_w;           // Prime subsystem busy flag
    wire        sub_done_w;           // Prime subsystem done pulse
    wire        sub_mode_complete_w;  // Prime subsystem mode complete flag
    wire [31:0] sub_prime_count_w;    // Full prime count from subsystem
    wire [31:0] sub_largest_prime_w;  // Full largest-prime output
    wire [31:0] sub_current_candidate_w; // Full current candidate output
    wire [31:0] sub_last_prime_found_w;  // Most recent prime found
    wire        sub_single_is_prime_w;   // Single-mode result from subsystem
    wire [31:0] sub_elapsed_seconds_w;   // Full elapsed seconds from subsystem
    wire [639:0] sub_recent_primes_flat_w; // Packed recent-prime list, 20x32
    wire [4:0]  sub_recent_valid_count_w;  // Number of valid recent primes
    wire        sub_prime_found_pulse_w;   // Pulse when a prime is found
    wire [31:0] sub_prime_found_value_w;   // Prime value associated with pulse
    wire [31:0] sub_prime_found_index_w;   // Storage index associated with pulse
    wire [31:0] sub_stored_count_w;        // Number of primes stored
    wire        sub_storage_full_w;        // Prime storage full flag

    //--------------------------------------------------------------------------
    // Prime storage readback interface for Test Mode.
    //--------------------------------------------------------------------------
    wire        sub_rd_en_w;                         // Stored-prime read request
    wire [PRIME_ADDR_WIDTH_CFG-1:0] sub_rd_addr_w;   // Stored-prime read address
    wire [31:0] sub_rd_data_w;                       // Stored-prime read data
    wire        sub_rd_data_valid_w;                 // Stored-prime read data valid

    //--------------------------------------------------------------------------
    // Prime-subsystem DDR storage interface.
    //--------------------------------------------------------------------------
    wire        sub_ddr_wr_req_w;                    // CPU-domain prime write request
    wire [PRIME_ADDR_WIDTH_CFG-1:0] sub_ddr_wr_addr_w; // CPU-domain prime write address
    wire [31:0] sub_ddr_wr_data_w;                   // CPU-domain prime write data
    wire        sub_ddr_wr_ack_w;                    // CPU-domain prime write acknowledge

    wire        sub_ddr_rd_req_w;                    // CPU-domain prime read request
    wire [PRIME_ADDR_WIDTH_CFG-1:0] sub_ddr_rd_addr_w; // CPU-domain prime read address
    wire [31:0] sub_ddr_rd_data_in_w;                // CPU-domain prime read data
    wire        sub_ddr_rd_data_valid_in_w;          // CPU-domain prime read data valid

    ui_fsm u_ui_fsm (
        .clk_cpu        (clk_cpu_w),
        .resetn         (sys_resetn_w),
        .left_click_pulse(left_click_pulse_w),
        .nav_mode_sel   (nav_mode_sel_w),
        .nav_menu_click (nav_menu_click_w),
        .nav_back       (nav_back_w),
        .nav_start      (nav_start_w),
        .nav_stop       (nav_stop_w),
        .nav_controls   (nav_controls_w),
        .soft_reset     (btnc_press_w),

        .sub_busy              (sub_busy_w),
        .sub_done              (sub_done_w),
        .sub_mode_complete     (sub_mode_complete_w),
        .sub_prime_count       (sub_prime_count_w),
        .sub_largest_prime     (sub_largest_prime_w),
        .sub_current_candidate (sub_current_candidate_w),
        .sub_last_prime_found  (sub_last_prime_found_w),
        .sub_single_is_prime   (sub_single_is_prime_w),
        .sub_elapsed_seconds   (sub_elapsed_seconds_w),
        .sub_recent_primes_flat(sub_recent_primes_flat_w),
        .sub_recent_valid_count(sub_recent_valid_count_w),

        .sub_start         (fsm_sub_start_w),
        .sub_abort         (fsm_sub_abort_w),
        .sub_start_new_run (fsm_sub_start_new_run_w),

        .display_mode   (display_mode_w),
        .mode           (mode_w),
        .entry_done     (entry_done_w),
        .input_error    (input_error_w),
        .prime_count    (prime_count_w),
        .current_n      (current_n_w),
        .elapsed_sec    (elapsed_sec_w),
        .compute_done   (compute_done_w),
        .last_primes    (last_primes_w),
        .largest_prime  (largest_prime_w),
        .single_is_prime(single_is_prime_w)
    );

    //==========================================================================
    // 1 Hz tick generator
    //
    // TIME mode counts elapsed seconds using a one-cycle pulse generated from
    // the 100 MHz CPU clock. Example: 100,000,000 CPU cycles produces one pulse.
    //==========================================================================
    reg [26:0] tick_1hz_cnt_ff;       // Counts CPU cycles between one-second ticks
    reg        tick_1hz_ff;           // One-cycle elapsed-second tick pulse

    always @(posedge clk_cpu_w) begin
        // Reset the divider and clear the tick pulse.
        if (!sys_resetn_w) begin
            tick_1hz_cnt_ff <= 27'd0;
            tick_1hz_ff     <= 1'b0;
        end
        // Generate one tick after 100,000,000 CPU-clock cycles.
        else if (tick_1hz_cnt_ff >= 27'd99_999_999) begin
            tick_1hz_cnt_ff <= 27'd0;
            tick_1hz_ff     <= 1'b1;
        end
        // Keep counting and hold the tick low on all other cycles.
        else begin
            tick_1hz_cnt_ff <= tick_1hz_cnt_ff + 27'd1;
            tick_1hz_ff     <= 1'b0;
        end
    end

    //==========================================================================
    // Mode encoding translation: UI -> prime subsystem
    //
    // UI encoding:
    //   0 = RANGE, 1 = TIME, 2 = SINGLE, 3 = TEST
    //
    // Prime subsystem encoding:
    //   00 = SINGLE, 01 = RANGE, 10 = TIME, 11 = RESERVED
    //==========================================================================
    reg [1:0] sub_mode_translated_w;  // Mode value translated for prime subsystem

    always @(*) begin
        case (mode_w)
            2'd0:    sub_mode_translated_w = 2'b01;  // RANGE mode
            2'd1:    sub_mode_translated_w = 2'b10;  // TIME mode
            2'd2:    sub_mode_translated_w = 2'b00;  // SINGLE mode
            default: sub_mode_translated_w = 2'b11;  // TEST/reserved mode
        endcase
    end

    //==========================================================================
    // Prime subsystem
    //
    // This block contains the prime controller, prime checker, recent-prime
    // tracking, and prime-storage frontend. Found primes are sent to DDR through
    // the prime DDR bridge below.
    //==========================================================================
    prime_subsystem #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (PRIME_ADDR_WIDTH_CFG),
        .DEPTH        (PRIME_DEPTH_CFG),
        .QUEUE_DEPTH  (PRIME_QUEUE_DEPTH_CFG),
        .QUEUE_AWIDTH (PRIME_QUEUE_AWIDTH_CFG)
    ) u_prime_subsystem (
        .clk               (clk_cpu_w),
        .rst_n             (sys_resetn_w),

        .start             (fsm_sub_start_w),
        .abort             (fsm_sub_abort_w),
        .mode              (sub_mode_translated_w),
        .single_value      ({5'd0, field0_val_w}),
        .range_start       ({5'd0, field0_val_w}),
        .range_limit       ({5'd0, field1_val_w}),
        .time_limit_sec    ({5'd0, field0_val_w}),
        .tick_1hz          (tick_1hz_ff),

        .start_new_run     (fsm_sub_start_new_run_w),
        .rd_en             (sub_rd_en_w),
        .rd_addr           (sub_rd_addr_w),

        .busy              (sub_busy_w),
        .done              (sub_done_w),
        .mode_complete     (sub_mode_complete_w),
        .prime_count       (sub_prime_count_w),
        .largest_prime     (sub_largest_prime_w),
        .current_candidate (sub_current_candidate_w),
        .last_prime_found  (sub_last_prime_found_w),
        .single_is_prime   (sub_single_is_prime_w),
        .elapsed_seconds   (sub_elapsed_seconds_w),

        .recent_primes_flat(sub_recent_primes_flat_w),
        .recent_valid_count(sub_recent_valid_count_w),

        .prime_found_pulse (sub_prime_found_pulse_w),
        .prime_found_value (sub_prime_found_value_w),
        .prime_found_index (sub_prime_found_index_w),

        .stored_count      (sub_stored_count_w),
        .storage_full      (sub_storage_full_w),
        .rd_data           (sub_rd_data_w),
        .rd_data_valid     (sub_rd_data_valid_w),
        .ddr_wr_req        (sub_ddr_wr_req_w),
        .ddr_wr_addr       (sub_ddr_wr_addr_w),
        .ddr_wr_data       (sub_ddr_wr_data_w),
        .ddr_wr_ack        (sub_ddr_wr_ack_w),
        .ddr_rd_req        (sub_ddr_rd_req_w),
        .ddr_rd_addr       (sub_ddr_rd_addr_w),
        .ddr_rd_data       (sub_ddr_rd_data_in_w),
        .ddr_rd_data_valid (sub_ddr_rd_data_valid_in_w)
    );

    //==========================================================================
    // Prime DDR bridge
    //
    // Moves prime-storage read/write traffic safely between clk_cpu and the
    // MIG ui_clk domain used by the DDR2 controller.
    //==========================================================================
    prime_ddr_bridge #(
        .ADDR_WIDTH (PRIME_ADDR_WIDTH_CFG),
        .DATA_WIDTH (32)
    ) u_prime_ddr_bridge (
        .clk_cpu               (clk_cpu_w),
        .rst_n_cpu             (sys_resetn_w),
        .cpu_wr_req            (sub_ddr_wr_req_w),
        .cpu_wr_addr           (sub_ddr_wr_addr_w),
        .cpu_wr_data           (sub_ddr_wr_data_w),
        .cpu_wr_ack            (sub_ddr_wr_ack_w),
        .cpu_rd_req            (sub_ddr_rd_req_w),
        .cpu_rd_addr           (sub_ddr_rd_addr_w),
        .cpu_rd_data           (sub_ddr_rd_data_in_w),
        .cpu_rd_data_valid     (sub_ddr_rd_data_valid_in_w),
        .ui_clk                (ui_clk_w),
        .ui_rst                (ui_rst_w),
        .ddr_prime_wr_req      (ddr_prime_wr_req_w),
        .ddr_prime_wr_addr     (ddr_prime_wr_addr_w),
        .ddr_prime_wr_data     (ddr_prime_wr_data_w),
        .ddr_prime_wr_ack      (ddr_prime_wr_ack_w),
        .ddr_prime_rd_req      (ddr_prime_rd_req_w),
        .ddr_prime_rd_addr     (ddr_prime_rd_addr_w),
        .ddr_prime_rd_data     (ddr_prime_rd_data_w),
        .ddr_prime_rd_data_valid(ddr_prime_rd_data_valid_w)
    );

    //==========================================================================
    // SD test-mode parser/feeder pipeline
    //
    // Algorithm:
    //   1) SD byte source emits ASCII bytes from CSEE4280Primes.txt.
    //   2) sd_prime_parser converts lines such as "31\n" into binary 31.
    //   3) sd_prime_feeder stores parsed values in a small FIFO.
    //   4) test_mode_ctrl requests one SD prime at a time for comparison.
    //
    // Example:
    //   SD text bytes:  "2\n3\n5\nA"
    //   Parser output:  2, 3, 5, then stream_done on 'A'
    //   Test controller compares those values against DDR-stored primes.
    //==========================================================================
    wire [31:0] parser_prime_value_w;     // Parsed binary prime value
    wire        parser_prime_valid_w;     // One-cycle parsed-prime valid pulse
    wire        parser_done_w;            // Parser stream-done flag

    wire        stub_byte_valid_w;        // Byte-valid into parser
    wire [7:0]  stub_byte_w;              // Byte value into parser
    wire        stub_end_w;               // End-of-stream into parser

    assign stub_byte_valid_w = sd_file_byte_valid_cpu_w;
    assign stub_byte_w       = sd_file_byte_cpu_w;
    assign stub_end_w        = sd_file_done_cpu_w;

    sd_prime_parser u_sd_prime_parser (
        .clk           (clk_cpu_w),
        .resetn        (sd_stream_resetn_cpu_w),
        .start_parse   (1'b0),
        .byte_valid    (stub_byte_valid_w),
        .byte_in       (stub_byte_w),
        .end_of_stream (stub_end_w),
        .prime_valid   (parser_prime_valid_w),
        .prime_value   (parser_prime_value_w),
        .stream_done   (parser_done_w)
    );

    sd_prime_feeder #(
        .FIFO_DEPTH (SD_FEEDER_DEPTH_CFG),
        .PTR_WIDTH  (SD_FEEDER_PTR_WIDTH_CFG)
    ) u_sd_prime_feeder (
        .clk                (clk_cpu_w),
        .resetn             (sd_stream_resetn_cpu_w),
        .start_read         (test_sd_start_w),
        .next_prime         (test_sd_next_w),
        .cpu_data           (parser_prime_value_w),
        .cpu_lineflag_pulse (parser_prime_valid_w),
        .stream_done        (parser_done_w),
        .sd_prime_valid     (test_sd_prime_valid_w),
        .sd_prime_value     (test_sd_prime_value_w),
        .sd_end_of_file     (test_sd_end_of_file_w)
    );

    //==========================================================================
    // Test Mode controller
    //
    // Compares primes stored in DDR2 against primes streamed from the SD-card
    // text file. On mismatch, the first failing stored value and SD value are
    // latched for display.
    //==========================================================================
    test_mode_ctrl #(
        .ADDR_WIDTH(PRIME_ADDR_WIDTH_CFG)
    ) u_test_mode_ctrl (
        .clk            (clk_cpu_w),
        .resetn         (sys_resetn_w),
        .start_test     (nav_test_start_w),
        .abort_test     (btnc_press_w | nav_back_w),

        .stored_count   (sub_stored_count_w),
        .rd_en          (sub_rd_en_w),
        .rd_addr        (sub_rd_addr_w),
        .rd_data        (sub_rd_data_w),
        .rd_data_valid  (sub_rd_data_valid_w),

        .sd_start       (test_sd_start_w),
        .sd_next        (test_sd_next_w),
        .sd_prime_valid (test_sd_prime_valid_w),
        .sd_prime_value (test_sd_prime_value_w),
        .sd_end_of_file (test_sd_end_of_file_w),

        .test_running   (test_running_w),
        .test_passed    (test_passed_w),
        .test_failed    (test_failed_w),
        .no_data_stored (no_data_stored_w),
        .primes_checked (primes_checked_w),
        .fail_stored_val(fail_ddr_val_w),
        .fail_sd_val    (fail_sd_val_w)
    );

    //==========================================================================
    // Parameter entry
    //
    // param_entry combines keypad digit input and mouse click selection to build
    // the numeric values used by Range, Time, and Single modes.
    //==========================================================================
    wire        entry_active_w;       // Parameter entry active flag
    wire        cursor_blink_w;       // Blinking cursor indicator for active field
    wire [26:0] practice_val_w;       // Controls/practice screen keypad value
    wire        practice_active_w;    // Controls/practice field active flag

    param_entry u_param_entry (
        .clk              (clk_cpu_w),
        .resetn           (sys_resetn_w),
        .mode             (mode_w),
        .display_mode     (display_mode_w),
        .key_press        (key_press_w),
        .key_code         (key_code_w),
        .cursor_x         (cursor_x_cpu_w),
        .cursor_y         (cursor_y_cpu_w),
        .left_click_pulse (left_click_pulse_w),
        .field0_val       (field0_val_w),
        .field1_val       (field1_val_w),
        .active_field     (active_field_w),
        .entry_active     (entry_active_w),
        .cursor_blink     (cursor_blink_w),
        .practice_val     (practice_val_w),
        .practice_active  (practice_active_w)
    );

    //==========================================================================
    // VGA vsync pulse CDC: clk_vga -> clk_cpu
    //
    // The sprite controller updates motion once per VGA frame, but it runs in
    // clk_cpu. This synchronizes the VGA-domain vsync pulse into clk_cpu.
    //==========================================================================
    wire vsync_pulse_vga_w;       // One-cycle vsync pulse in VGA domain
    wire vsync_pulse_cpu_w;       // One-cycle vsync pulse in CPU domain

    pulse_sync u_vsync_pulse_sync (
        .src_clk   (clk_vga_w),
        .src_rst   (~sys_resetn_w),
        .src_pulse (vsync_pulse_vga_w),
        .dst_clk   (clk_cpu_w),
        .dst_rst   (~sys_resetn_w),
        .dst_pulse (vsync_pulse_cpu_w)
    );

    //==========================================================================
    // Sprite controller
    //
    // Provides moving sprite coordinates for the renderer. Motion is enabled
    // only when sprite_enable_w is asserted by the UI renderer.
    //==========================================================================
    wire        sprite_enable_w;     // Renderer-controlled sprite motion enable
    wire        sp_hb_w;             // Sprite heartbeat/debug output
    wire [1:0]  sp_mode_dbg_w;       // Sprite mode debug output
    wire [10:0] sp_x0_w, sp_x1_w;    // Sprite X positions
    wire [10:0] sp_x2_w, sp_x3_w;
    wire [9:0]  sp_y0_w, sp_y1_w;    // Sprite Y positions
    wire [9:0]  sp_y2_w, sp_y3_w;

    wire [1:0] sprite_mode_w;        // 01 = ping-pong, 00 = static
    assign sprite_mode_w = sprite_enable_w ? 2'b01 : 2'b00;

    sprite_ctrl #(
        .CLK_HZ             (100_000_000),
        .HB_HZ              (2),
        .MOVE_EVERY_N_VSYNC (1),
        .STEP_PIX           (2)
    ) u_sprite_ctrl (
        .clk            (clk_cpu_w),
        .resetn         (sys_resetn_w),
        .sprite_mode_in (sprite_mode_w),
        .double_size    (1'b0),
        .vsync_pulse    (vsync_pulse_cpu_w),
        .hb             (sp_hb_w),
        .mode_dbg       (sp_mode_dbg_w),
        .x0             (sp_x0_w),
        .y0             (sp_y0_w),
        .x1             (sp_x1_w),
        .y1             (sp_y1_w),
        .x2             (sp_x2_w),
        .y2             (sp_y2_w),
        .x3             (sp_x3_w),
        .y3             (sp_y3_w)
    );

    //==========================================================================
    // DDR2 framebuffer controller wiring
    //
    // The DDR2 controller owns the MIG interface, framebuffer reads/writes, and
    // the prime-storage DDR read/write port.
    //==========================================================================
    wire        ui_clk_w;              // MIG user-interface clock
    wire        ui_rst_w;              // MIG user-interface reset
    wire        fb_ready_w;            // Framebuffer path ready flag
    wire        calib_done_w;          // DDR2 calibration complete flag

    wire [63:0] fifo_wr_data_w;        // DDR-to-VGA FIFO write data
    wire        fifo_wr_en_w;          // DDR-to-VGA FIFO write enable
    wire        fifo_full_w;           // DDR-to-VGA FIFO full flag
    wire        fifo_rst_w;            // DDR-to-VGA FIFO reset

    wire        debug_drain_active_w;  // Debug: DDR drain active
    wire        debug_rd_active_w;     // Debug: DDR read active
    wire [4:0]  debug_state_w;         // Debug: DDR controller state
    wire        debug_vsync_seen_w;    // Debug: vsync observed
    wire        debug_front_buf_w;     // Debug: selected front buffer
    wire        debug_wr_pending_w;    // Debug: write pending flag
    wire        debug_app_wdf_rdy_w;   // Debug: MIG write-data ready
    wire        debug_app_rdy_w;       // Debug: MIG command ready

    wire [26:0] wr_addr_w;             // Renderer framebuffer write address
    wire [63:0] wr_data_w;             // Renderer framebuffer write data
    wire        wr_req_w;              // Renderer framebuffer write request
    wire        wr_ack_w;              // Renderer framebuffer write acknowledge

    wire        frame_done_req_w;      // Renderer requests frame swap
    wire        frame_done_ack_w;      // DDR controller acknowledges frame swap
    wire [26:0] back_buf_base_w;       // Current back-buffer base address
    wire        ready_toggle_w;        // Frame-ready toggle to renderer
    wire        rendering_w;           // Renderer currently drawing frame
    wire        dbg_frame_start_w;     // Debug: renderer frame start
    wire        dbg_wr_ack_pulse_w;    // Debug: write acknowledge pulse

    wire        ddr_prime_wr_req_w;    // DDR-domain prime write request
    wire [PRIME_ADDR_WIDTH_CFG-1:0] ddr_prime_wr_addr_w; // DDR prime write address
    wire [31:0] ddr_prime_wr_data_w;  // DDR prime write data
    wire        ddr_prime_wr_ack_w;   // DDR prime write acknowledge

    wire        ddr_prime_rd_req_w;   // DDR-domain prime read request
    wire [PRIME_ADDR_WIDTH_CFG-1:0] ddr_prime_rd_addr_w; // DDR prime read address
    wire [31:0] ddr_prime_rd_data_w; // DDR prime read data
    wire        ddr_prime_rd_data_valid_w; // DDR prime read data valid

    ddr2_fb_ctrl u_ddr2_fb_ctrl (
        .clk_mem            (clk_mem_w),
        .sys_rst_n          (sys_resetn_w),
        .ddr2_dq            (ddr2_dq),
        .ddr2_dqs_n         (ddr2_dqs_n),
        .ddr2_dqs_p         (ddr2_dqs_p),
        .ddr2_addr          (ddr2_addr),
        .ddr2_ba            (ddr2_ba),
        .ddr2_ras_n         (ddr2_ras_n),
        .ddr2_cas_n         (ddr2_cas_n),
        .ddr2_we_n          (ddr2_we_n),
        .ddr2_ck_p          (ddr2_ck_p),
        .ddr2_ck_n          (ddr2_ck_n),
        .ddr2_cke           (ddr2_cke),
        .ddr2_cs_n          (ddr2_cs_n),
        .ddr2_dm            (ddr2_dm),
        .ddr2_odt           (ddr2_odt),
        .ui_clk             (ui_clk_w),
        .ui_rst             (ui_rst_w),
        .ready              (fb_ready_w),
        .fifo_wr_data       (fifo_wr_data_w),
        .fifo_wr_en         (fifo_wr_en_w),
        .fifo_full          (fifo_full_w),
        .fifo_rst           (fifo_rst_w),
        .vsync_in           (VSYNC),
        .wr_addr            (wr_addr_w),
        .wr_data            (wr_data_w),
        .wr_req             (wr_req_w),
        .wr_ack             (wr_ack_w),
        .prime_wr_req       (ddr_prime_wr_req_w),
        .prime_wr_addr      (ddr_prime_wr_addr_w),
        .prime_wr_data      (ddr_prime_wr_data_w),
        .prime_wr_ack       (ddr_prime_wr_ack_w),
        .prime_rd_req       (ddr_prime_rd_req_w),
        .prime_rd_addr      (ddr_prime_rd_addr_w),
        .prime_rd_data      (ddr_prime_rd_data_w),
        .prime_rd_data_valid(ddr_prime_rd_data_valid_w),
        .frame_done_req     (frame_done_req_w),
        .frame_done_ack     (frame_done_ack_w),
        .back_buf_base      (back_buf_base_w),
        .ready_toggle       (ready_toggle_w),
        .debug_drain_active (debug_drain_active_w),
        .calib_done         (calib_done_w),
        .debug_rd_active    (debug_rd_active_w),
        .debug_state        (debug_state_w),
        .debug_vsync_seen   (debug_vsync_seen_w),
        .debug_front_buf    (debug_front_buf_w),
        .debug_wr_pending   (debug_wr_pending_w),
        .debug_app_wdf_rdy  (debug_app_wdf_rdy_w),
        .debug_app_rdy      (debug_app_rdy_w)
    );

    //==========================================================================
    // Async FIFO: DDR2 ui_clk -> VGA clk_vga
    //
    // The DDR2 controller fills this FIFO in ui_clk, and the VGA output drains
    // it in clk_vga as pixels are needed.
    //==========================================================================
    wire [63:0] fifo_rd_data_w;        // FIFO read data into VGA output
    wire        fifo_rd_en_w;          // FIFO read enable from VGA output
    wire        fifo_empty_w;          // FIFO empty flag into VGA output

    async_fifo #(
        .DATA_WIDTH (64),
        .ADDR_WIDTH (4)
    ) u_async_fifo (
        .wr_clk  (ui_clk_w),
        .wr_rst  (fifo_rst_w | ui_rst_w),
        .wr_data (fifo_wr_data_w),
        .wr_en   (fifo_wr_en_w),
        .wr_full (fifo_full_w),
        .rd_clk  (clk_vga_w),
        .rd_rst  ((~sys_resetn_w) | fifo_rst_w),
        .rd_data (fifo_rd_data_w),
        .rd_en   (fifo_rd_en_w),
        .rd_empty(fifo_empty_w)
    );

    //==========================================================================
    // UI frame renderer
    //
    // Converts the selected screen state into framebuffer write transactions.
    // It also performs mouse hit detection and generates navigation pulses for
    // ui_fsm and test_mode_ctrl.
    //==========================================================================
    wire [1:0] nav_mode_sel_w;         // Menu-selected mode
    wire       nav_menu_click_w;       // Menu tile click pulse
    wire       nav_back_w;             // Back button click pulse
    wire       nav_start_w;            // Start compute click pulse
    wire       nav_test_start_w;       // Start Test Mode click pulse
    wire       nav_stop_w;             // Stop compute click pulse
    wire       nav_error_dismiss_w;    // Error/result dismiss pulse
    wire       nav_controls_w;         // Controls-screen click pulse

    ui_frame_renderer u_ui_frame_renderer (
        .clk_cpu          (clk_cpu_w),
        .resetn           (sys_resetn_w),

        .ready_toggle     (ready_toggle_w),
        .frame_done_req   (frame_done_req_w),
        .frame_done_ack   (frame_done_ack_w),
        .back_buf_base    (back_buf_base_w),

        .wr_addr          (wr_addr_w),
        .wr_data          (wr_data_w),
        .wr_req           (wr_req_w),
        .wr_ack           (wr_ack_w),

        .display_mode     (display_mode_w),
        .cursor_x         (cursor_x_cpu_w),
        .cursor_y         (cursor_y_cpu_w),
        .left_btn         (left_btn_cpu_w),

        .mode             (mode_w),
        .field0_val       (field0_val_w),
        .field1_val       (field1_val_w),
        .active_field     (active_field_w),
        .entry_done       (entry_done_w),
        .input_error      (input_error_w),
        .entry_active     (entry_active_w),
        .cursor_blink     (cursor_blink_w),

        .prime_count      (prime_count_w),
        .current_n        (current_n_w),
        .elapsed_sec      (elapsed_sec_w),
        .compute_done     (compute_done_w),
        .last_primes      (last_primes_w),
        .largest_prime    (largest_prime_w),
        .single_is_prime  (single_is_prime_w),

        .test_running     (test_running_w),
        .test_passed      (test_passed_w),
        .test_failed      (test_failed_w),
        .no_data_stored   (no_data_stored_w),
        .primes_checked   (primes_checked_w),
        .fail_ddr_val     (fail_ddr_val_w),
        .fail_sd_val      (fail_sd_val_w),

        .nav_mode_sel     (nav_mode_sel_w),
        .nav_menu_click   (nav_menu_click_w),
        .nav_back         (nav_back_w),
        .nav_start        (nav_start_w),
        .nav_test_start   (nav_test_start_w),
        .nav_stop         (nav_stop_w),
        .nav_error_dismiss(nav_error_dismiss_w),
        .nav_controls     (nav_controls_w),

        .practice_val     (practice_val_w),
        .practice_active  (practice_active_w),
        .cursor_blink_ctrl(cursor_blink_w),

        .sprite_enable    (sprite_enable_w),
        .rendering        (rendering_w),
        .dbg_frame_start  (dbg_frame_start_w),
        .dbg_wr_ack_pulse (dbg_wr_ack_pulse_w)
    );

    //==========================================================================
    // VGA output with cursor overlay
    //
    // Reads packed pixels from the DDR-to-VGA FIFO, generates VGA timing, and
    // overlays the cursor sprite as the final display stage.
    //==========================================================================
    wire visible_unused_w;             // Visible-region flag not used at top level

    vga_output_with_cursor #(
        .DEBUG_OVERLAY_ONLY (1'b0)
    ) u_vga_output_with_cursor (
        .clk_vga     (clk_vga_w),
        .resetn      (sys_resetn_w),
        .fifo_data   (fifo_rd_data_w),
        .fifo_empty  (fifo_empty_w),
        .fifo_rd_en  (fifo_rd_en_w),
        .cursor_x    (cursor_x_vga_w),
        .cursor_y    (cursor_y_vga_w),
        .RED         (RED),
        .GRN         (GRN),
        .BLU         (BLU),
        .HSYNC       (HSYNC),
        .VSYNC       (VSYNC),
        .visible     (visible_unused_w),
        .vsync_pulse (vsync_pulse_vga_w)
    );

endmodule