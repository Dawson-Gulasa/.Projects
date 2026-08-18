`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_input_ctrl.v
//
// Purpose:
//   Self-checking testbench for input_ctrl.v.
//
// What this testbench verifies:
//   1) Reset / idle behavior
//   2) Debounced onboard pushbutton behavior for all five buttons
//   3) Button bounce rejection
//   4) Button stable-level assertion and one-clock press pulse generation
//   5) Button release behavior
//   6) Full keypad scan / decode / debounce behavior for all 16 hex keys
//   7) Keypad hold behavior (key_valid stays high, key_press does not repeat)
//   8) Keypad release behavior
//   9) Invalid keypad row pattern rejection
//
// Test strategy:
//   - Exhaustive across all five onboard buttons
//   - Exhaustive across all sixteen keypad hex keys
//   - Edge-case timing tests included for bounce and invalid row patterns
//
// Important simulation note:
//   The real design uses millisecond-scale debounce and scan timing.
//   To keep simulation practical while still testing the true logic paths,
//   this testbench overrides the internal tick-generator dwell/sample counts
//   to small values using defparam.
//
// Behavioral keypad model used here:
//   - The DUT drives kp_col active-low, one column at a time.
//   - The testbench watches kp_col and drives kp_row accordingly for the
//     currently "pressed" virtual key.
//   - This models how the real keypad matrix electrically behaves.
//
// Pass/Fail behavior:
//   - Fully self-checking
//   - Reports exact failing test section
//   - Prints total test count, total passes, and total errors
//------------------------------------------------------------------------------
module tb_input_ctrl;

    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    //--------------------------------------------------------------------------
    // Raw onboard button stimulus
    //--------------------------------------------------------------------------
    reg btnc_raw;
    reg btnu_raw;
    reg btnd_raw;
    reg btnl_raw;
    reg btnr_raw;

    //--------------------------------------------------------------------------
    // Keypad row stimulus model
    //--------------------------------------------------------------------------
    reg [3:0] kp_row;
    wire [3:0] kp_col;

    reg       key_active_tb;
    reg [3:0] key_code_tb;

    reg       force_invalid_rows_tb;
    reg [3:0] invalid_rows_tb;

    //--------------------------------------------------------------------------
    // DUT outputs
    //--------------------------------------------------------------------------
    wire btnc_level;
    wire btnu_level;
    wire btnd_level;
    wire btnl_level;
    wire btnr_level;

    wire btnc_press;
    wire btnu_press;
    wire btnd_press;
    wire btnl_press;
    wire btnr_press;

    wire       key_valid;
    wire [3:0] key_code;
    wire       key_press;

    //--------------------------------------------------------------------------
    // Testbench bookkeeping
    //--------------------------------------------------------------------------
    integer total_tests;
    integer total_passes;
    integer total_errors;

    integer idx;
    integer timeout_ctr;

    reg     force_fail_used_ff;

    //--------------------------------------------------------------------------
    // Accelerated simulation timing
    //
    // Real design:
    //   - Button sample tick     = 500_000 cycles
    //   - Keypad dwell tick      = 100_000 cycles
    //
    // Testbench acceleration:
    //   - Button sample tick     = 8 cycles
    //   - Keypad dwell tick      = 8 cycles
    //
    // Resulting effective timings:
    //   - Button debounce        = 4 samples  = ~32 cycles plus sync latency
    //   - Keypad frame           = 4 dwells   = 32 cycles
    //   - Keypad debounce        = 4 frames   = ~128 cycles
    //--------------------------------------------------------------------------
    localparam integer CLK_PERIOD_NS       = 10;
    localparam integer BTN_SAMPLE_TICKS_TB = 8;
    localparam integer KEY_DWELL_TICKS_TB  = 8;

    localparam integer BTN_TIMEOUT_CYCLES  = 200;
    localparam integer KEY_TIMEOUT_CYCLES  = 400;

    //--------------------------------------------------------------------------
    // Forced-fail control
    //
    // Set to 1 to intentionally corrupt one expected keypad code comparison so
    // the testbench proves it is not an always-pass testbench.
    //--------------------------------------------------------------------------
    localparam integer FORCE_FAIL = 0;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    input_ctrl dut (
        .clk        (clk),
        .rst_n      (rst_n),

        .btnc_raw   (btnc_raw),
        .btnu_raw   (btnu_raw),
        .btnd_raw   (btnd_raw),
        .btnl_raw   (btnl_raw),
        .btnr_raw   (btnr_raw),

        .kp_row     (kp_row),
        .kp_col     (kp_col),

        .btnc_level (btnc_level),
        .btnu_level (btnu_level),
        .btnd_level (btnd_level),
        .btnl_level (btnl_level),
        .btnr_level (btnr_level),

        .btnc_press (btnc_press),
        .btnu_press (btnu_press),
        .btnd_press (btnd_press),
        .btnl_press (btnl_press),
        .btnr_press (btnr_press),

        .key_valid  (key_valid),
        .key_code   (key_code),
        .key_press  (key_press)
    );

    //--------------------------------------------------------------------------
    // Accelerate internal timing with parameter overrides
    //--------------------------------------------------------------------------
    defparam dut.u_btn_input_ctrl.u_tick_gen.TICKS_PER_PULSE            = BTN_SAMPLE_TICKS_TB;
    defparam dut.u_keypad_input_ctrl.u_col_scanner.TICKS_PER_DWELL      = KEY_DWELL_TICKS_TB;

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Helper function: convert active kp_col pattern to selected column index
    //
    // kp_col patterns from col_scanner:
    //   4'b0111 -> col_idx 0
    //   4'b1011 -> col_idx 1
    //   4'b1101 -> col_idx 2
    //   4'b1110 -> col_idx 3
    //--------------------------------------------------------------------------
    function [1:0] selected_col_idx;
        input [3:0] kp_col_in;
        begin
            case (kp_col_in)
                4'b0111: selected_col_idx = 2'd0;
                4'b1011: selected_col_idx = 2'd1;
                4'b1101: selected_col_idx = 2'd2;
                4'b1110: selected_col_idx = 2'd3;
                default: selected_col_idx = 2'd0;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Helper function: map key code to expected decoded column index
    //--------------------------------------------------------------------------
    function [1:0] key_col_idx_from_code;
        input [3:0] key_in;
        begin
            case (key_in)
                4'h0, 4'h1, 4'h4, 4'h7: key_col_idx_from_code = 2'd0;
                4'hA, 4'hB, 4'hC, 4'hD: key_col_idx_from_code = 2'd1;
                4'h3, 4'h6, 4'h9, 4'hE: key_col_idx_from_code = 2'd2;
                4'h2, 4'h5, 4'h8, 4'hF: key_col_idx_from_code = 2'd3;
                default:                key_col_idx_from_code = 2'd0;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Helper function: map key code to active-low row pattern
    //
    // Row patterns from key_decoder:
    //   4'b0111
    //   4'b1011
    //   4'b1101
    //   4'b1110
    //--------------------------------------------------------------------------
    function [3:0] key_row_pattern_from_code;
        input [3:0] key_in;
        begin
            case (key_in)
                4'h0, 4'hD, 4'hE, 4'hF: key_row_pattern_from_code = 4'b0111;
                4'h7, 4'hC, 4'h9, 4'h8: key_row_pattern_from_code = 4'b1011;
                4'h4, 4'hB, 4'h6, 4'h5: key_row_pattern_from_code = 4'b1101;
                4'h1, 4'hA, 4'h3, 4'h2: key_row_pattern_from_code = 4'b1110;
                default:                key_row_pattern_from_code = 4'b1111;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Keypad electrical behavior model
    //
    // Idle rows are all high. When a virtual key is "pressed," the row is
    // pulled low only when the DUT selects that key's column.
    //--------------------------------------------------------------------------
    always @(*) begin
        if (force_invalid_rows_tb) begin
            kp_row = invalid_rows_tb;
        end
        else if (!key_active_tb) begin
            kp_row = 4'b1111;
        end
        else begin
            if (selected_col_idx(kp_col) == key_col_idx_from_code(key_code_tb)) begin
                kp_row = key_row_pattern_from_code(key_code_tb);
            end
            else begin
                kp_row = 4'b1111;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Helper function: read debounced button level by index
    //--------------------------------------------------------------------------
    function get_btn_level;
        input integer button_idx;
        begin
            case (button_idx)
                0: get_btn_level = btnc_level;
                1: get_btn_level = btnu_level;
                2: get_btn_level = btnd_level;
                3: get_btn_level = btnl_level;
                4: get_btn_level = btnr_level;
                default: get_btn_level = 1'b0;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Helper function: read button press pulse by index
    //--------------------------------------------------------------------------
    function get_btn_press;
        input integer button_idx;
        begin
            case (button_idx)
                0: get_btn_press = btnc_press;
                1: get_btn_press = btnu_press;
                2: get_btn_press = btnd_press;
                3: get_btn_press = btnl_press;
                4: get_btn_press = btnr_press;
                default: get_btn_press = 1'b0;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Utility task: initialize raw inputs
    //--------------------------------------------------------------------------
    task init_inputs;
        begin
            btnc_raw             = 1'b0;
            btnu_raw             = 1'b0;
            btnd_raw             = 1'b0;
            btnl_raw             = 1'b0;
            btnr_raw             = 1'b0;

            key_active_tb        = 1'b0;
            key_code_tb          = 4'h0;
            force_invalid_rows_tb= 1'b0;
            invalid_rows_tb      = 4'b1111;
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
    // Utility task: drive one raw button by index
    //--------------------------------------------------------------------------
    task set_button_raw;
        input integer button_idx;
        input value_in;
        begin
            case (button_idx)
                0: btnc_raw = value_in;
                1: btnu_raw = value_in;
                2: btnd_raw = value_in;
                3: btnl_raw = value_in;
                4: btnr_raw = value_in;
                default: begin end
            endcase
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: ensure no button press pulse appears in a window
    //--------------------------------------------------------------------------
    task expect_no_button_press_window;
        input integer button_idx;
        input integer ncycles;
        input [255:0] case_name;
        integer i;
        begin
            total_tests = total_tests + 1;

            for (i = 0; i < ncycles; i = i + 1) begin
                @(posedge clk);
                if (get_btn_press(button_idx) !== 1'b0) begin
                    report_error({case_name, " : unexpected button press pulse"});
                    disable expect_no_button_press_window;
                end
            end

            report_pass(case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for debounced button level
    //--------------------------------------------------------------------------
    task wait_for_button_level;
        input integer button_idx;
        input expected_level;
        input integer timeout_cycles;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            wait_ctr = 0;
            while (get_btn_level(button_idx) !== expected_level) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > timeout_cycles) begin
                    report_error({case_name, " : timeout waiting for button level"});
                    disable wait_for_button_level;
                end
            end

            report_pass(case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for button press pulse
    //--------------------------------------------------------------------------
    task wait_for_button_press_pulse;
        input integer button_idx;
        input integer timeout_cycles;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            wait_ctr = 0;
            while (get_btn_press(button_idx) !== 1'b1) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > timeout_cycles) begin
                    report_error({case_name, " : timeout waiting for button press pulse"});
                    disable wait_for_button_press_pulse;
                end
            end

            report_pass(case_name);

            @(posedge clk);
            if (get_btn_press(button_idx) !== 1'b0) begin
                report_error({case_name, " : button press pulse wider than one cycle"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: run one full button test case
    //
    // This tests:
    //   - short bounce rejected
    //   - stable press accepted
    //   - one pulse generated
    //   - hold does not retrigger
    //   - short release bounce rejected
    //   - stable release accepted
    //--------------------------------------------------------------------------
    task run_button_case;
        input integer button_idx;
        input [255:0] case_name;
        begin
            // Ensure low start state.
            set_button_raw(button_idx, 1'b0);
            wait_cycles(10);

            // Short bounce before debounce threshold -> should be ignored.
            set_button_raw(button_idx, 1'b1); wait_cycles(3);
            set_button_raw(button_idx, 1'b0); wait_cycles(2);
            set_button_raw(button_idx, 1'b1); wait_cycles(3);
            set_button_raw(button_idx, 1'b0); wait_cycles(3);

            if (get_btn_level(button_idx) !== 1'b0) begin
                report_error({case_name, " : level changed during short press bounce"});
            end
            expect_no_button_press_window(button_idx, 10, {case_name, " : short press bounce rejected"});

            // Stable press.
            set_button_raw(button_idx, 1'b1);
            wait_for_button_press_pulse(button_idx, BTN_TIMEOUT_CYCLES, {case_name, " : press pulse"});
            wait_for_button_level(button_idx, 1'b1, BTN_TIMEOUT_CYCLES, {case_name, " : level high after stable press"});

            // Hold high should not retrigger.
            expect_no_button_press_window(button_idx, 20, {case_name, " : no repeat pulse while held"});

            // Short bounce on release should not immediately clear level.
            set_button_raw(button_idx, 1'b0); wait_cycles(3);
            set_button_raw(button_idx, 1'b1); wait_cycles(2);
            set_button_raw(button_idx, 1'b0); wait_cycles(3);

            if (get_btn_level(button_idx) !== 1'b1) begin
                report_error({case_name, " : level dropped too early during release bounce"});
            end
            else begin
                report_pass({case_name, " : release bounce rejected"});
            end

            // Stable release.
            set_button_raw(button_idx, 1'b0);
            wait_for_button_level(button_idx, 1'b0, BTN_TIMEOUT_CYCLES, {case_name, " : level low after stable release"});

            // No press pulse on release.
            expect_no_button_press_window(button_idx, 10, {case_name, " : no press pulse on release"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for key_press
    //--------------------------------------------------------------------------
    task wait_for_key_press;
        input integer timeout_cycles;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            wait_ctr = 0;
            while (key_press !== 1'b1) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > timeout_cycles) begin
                    report_error({case_name, " : timeout waiting for key_press"});
                    disable wait_for_key_press;
                end
            end

            report_pass(case_name);

            @(posedge clk);
            if (key_press !== 1'b0) begin
                report_error({case_name, " : key_press wider than one cycle"});
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: wait for key_valid state
    //--------------------------------------------------------------------------
    task wait_for_key_valid_state;
        input expected_valid;
        input integer timeout_cycles;
        input [255:0] case_name;
        integer wait_ctr;
        begin
            total_tests = total_tests + 1;

            wait_ctr = 0;
            while (key_valid !== expected_valid) begin
                @(posedge clk);
                wait_ctr = wait_ctr + 1;
                if (wait_ctr > timeout_cycles) begin
                    report_error({case_name, " : timeout waiting for key_valid state"});
                    disable wait_for_key_valid_state;
                end
            end

            report_pass(case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: ensure no key_press pulse appears in a window
    //--------------------------------------------------------------------------
    task expect_no_key_press_window;
        input integer ncycles;
        input [255:0] case_name;
        integer i;
        begin
            total_tests = total_tests + 1;

            for (i = 0; i < ncycles; i = i + 1) begin
                @(posedge clk);
                if (key_press !== 1'b0) begin
                    report_error({case_name, " : unexpected key_press pulse"});
                    disable expect_no_key_press_window;
                end
            end

            report_pass(case_name);
        end
    endtask

    //--------------------------------------------------------------------------
    // Utility task: run one full keypad key test case
    //
    // This tests:
    //   - stable press recognition
    //   - correct decoded key_code
    //   - key_valid while held
    //   - no repeated key_press while held
    //   - stable release behavior
    //--------------------------------------------------------------------------
    task run_keypad_case;
        input [3:0] key_in;
        input [255:0] case_name;
        begin
            key_code_tb   = key_in;
            key_active_tb = 1'b1;

            wait_for_key_press(KEY_TIMEOUT_CYCLES, {case_name, " : key_press"});
            wait_for_key_valid_state(1'b1, KEY_TIMEOUT_CYCLES, {case_name, " : key_valid high"});

            total_tests = total_tests + 1;

            if ((FORCE_FAIL != 0) && (force_fail_used_ff == 1'b0)) begin
                force_fail_used_ff = 1'b1;

                if (key_code !== (key_in ^ 4'h1)) begin
                    $display("FAIL : %0s : forced-fail key_code mismatch expected=%0h actual=%0h",
                             case_name, (key_in ^ 4'h1), key_code);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : forced-fail unexpectedly matched"});
                end
            end
            else begin
                if (key_code !== key_in) begin
                    $display("FAIL : %0s : key_code mismatch expected=%0h actual=%0h",
                             case_name, key_in, key_code);
                    total_errors = total_errors + 1;
                end
                else begin
                    report_pass({case_name, " : key_code correct"});
                end
            end

            expect_no_key_press_window(40, {case_name, " : no repeat key_press while held"});

            key_active_tb = 1'b0;
            wait_for_key_valid_state(1'b0, KEY_TIMEOUT_CYCLES, {case_name, " : key_valid low after release"});
            expect_no_key_press_window(10, {case_name, " : no key_press on release"});
        end
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        total_tests        = 0;
        total_passes       = 0;
        total_errors       = 0;
        force_fail_used_ff = 1'b0;

        $display("------------------------------------------------------------");
        $display("tb_input_ctrl");
        $display("Purpose:");
        $display("  Self-checking verification of input_ctrl using exhaustive");
        $display("  button and keypad tests plus bounce and invalid-pattern");
        $display("  edge cases.");
        $display("------------------------------------------------------------");

        //----------------------------------------------------------------------
        // Reset / initial state
        //----------------------------------------------------------------------
        apply_reset();

        total_tests = total_tests + 1;
        if ((btnc_level !== 1'b0) || (btnu_level !== 1'b0) ||
            (btnd_level !== 1'b0) || (btnl_level !== 1'b0) ||
            (btnr_level !== 1'b0) || (btnc_press !== 1'b0) ||
            (btnu_press !== 1'b0) || (btnd_press !== 1'b0) ||
            (btnl_press !== 1'b0) || (btnr_press !== 1'b0) ||
            (key_valid  !== 1'b0) || (key_press  !== 1'b0)) begin
            report_error("reset check : outputs not idle after reset");
        end
        else begin
            report_pass("reset check : outputs idle after reset");
        end

        //----------------------------------------------------------------------
        // Exhaustive button testing
        //----------------------------------------------------------------------
        run_button_case(0, "button BTNC");
        run_button_case(1, "button BTNU");
        run_button_case(2, "button BTND");
        run_button_case(3, "button BTNL");
        run_button_case(4, "button BTNR");

        //----------------------------------------------------------------------
        // Invalid keypad row pattern test
        //
        // Force multiple rows low, which should never decode to a valid key.
        //----------------------------------------------------------------------
        force_invalid_rows_tb = 1'b1;
        invalid_rows_tb       = 4'b0011;
        wait_cycles(160);

        total_tests = total_tests + 1;
        if (key_valid !== 1'b0) begin
            report_error("keypad invalid-row check : key_valid asserted on invalid row pattern");
        end
        else begin
            report_pass("keypad invalid-row check : invalid row pattern rejected");
        end

        expect_no_key_press_window(20, "keypad invalid-row check : no key_press on invalid row pattern");

        force_invalid_rows_tb = 1'b0;
        invalid_rows_tb       = 4'b1111;
        wait_cycles(20);

        //----------------------------------------------------------------------
        // Exhaustive keypad testing across all 16 hex codes
        //----------------------------------------------------------------------
        run_keypad_case(4'h0, "keypad key 0");
        run_keypad_case(4'h1, "keypad key 1");
        run_keypad_case(4'h2, "keypad key 2");
        run_keypad_case(4'h3, "keypad key 3");
        run_keypad_case(4'h4, "keypad key 4");
        run_keypad_case(4'h5, "keypad key 5");
        run_keypad_case(4'h6, "keypad key 6");
        run_keypad_case(4'h7, "keypad key 7");
        run_keypad_case(4'h8, "keypad key 8");
        run_keypad_case(4'h9, "keypad key 9");
        run_keypad_case(4'hA, "keypad key A");
        run_keypad_case(4'hB, "keypad key B");
        run_keypad_case(4'hC, "keypad key C");
        run_keypad_case(4'hD, "keypad key D");
        run_keypad_case(4'hE, "keypad key E");
        run_keypad_case(4'hF, "keypad key F");

        //----------------------------------------------------------------------
        // Final summary
        //----------------------------------------------------------------------
        $display("------------------------------------------------------------");
        $display("tb_input_ctrl complete");
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