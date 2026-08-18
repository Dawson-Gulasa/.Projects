`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ui_fsm.v
//
// Purpose:
//   Main UI navigation FSM for the project.
//
//   This module controls which screen is currently displayed and generates the
//   one-cycle control pulses needed by the prime subsystem. It also routes live
//   prime-subsystem status outputs into display-friendly widths for the renderer.
//
// Screen navigation:
//   Menu     -- Range/Time/Single click --> Params
//   Menu     -- Test Mode click ---------> Test
//   Menu     -- Controls click ----------> Controls
//   Params   -- Back click --------------> Menu
//   Params   -- Start Finding -----------> Generating + subsystem start
//   Generate -- subsystem done ----------> Result
//   Generate -- Stop click --------------> Menu + subsystem abort
//   Result   -- Back click --------------> Menu
//   Test     -- Back click --------------> Menu
//   Controls -- Back click --------------> Menu
//   Any      -- soft_reset --------------> Menu + subsystem abort
//
// Mode encoding used by the UI:
//   RANGE  = 0
//   TIME   = 1
//   SINGLE = 2
//   TEST   = 3
//
// Notes:
//   - This FSM runs in the clk_cpu domain.
//   - Mouse/button hit detection is handled in ui_frame_renderer/screen logic.
//   - Parameter entry values are handled by param_entry, not this FSM.
//   - Test-mode comparison status is produced by test_mode_ctrl, not here.
//------------------------------------------------------------------------------

module ui_fsm (
    input  wire        clk_cpu,                // CPU/UI clock domain
    input  wire        resetn,                 // Active-low reset synchronized to clk_cpu

    input  wire        left_click_pulse,       // One-clock left mouse click pulse, currently unused here

    //--------------------------------------------------------------------------
    // Navigation inputs from ui_frame_renderer / screen_mux
    //--------------------------------------------------------------------------
    input  wire [1:0]  nav_mode_sel,           // Menu-selected mode button
    input  wire        nav_menu_click,         // One-clock pulse when a menu mode button is clicked
    input  wire        nav_back,               // One-clock pulse when Back is clicked
    input  wire        nav_start,              // One-clock pulse when Start Finding is clicked
    input  wire        nav_stop,               // One-clock pulse when Stop is clicked during generation
    input  wire        nav_controls,           // One-clock pulse when Controls is clicked from menu

    input  wire        soft_reset,             // Return to menu and abort active compute

    //--------------------------------------------------------------------------
    // Prime subsystem status inputs
    //--------------------------------------------------------------------------
    input  wire        sub_busy,               // Prime subsystem busy flag, currently unused here
    input  wire        sub_done,               // One-clock pulse when prime subsystem completes
    input  wire        sub_mode_complete,      // High when the current prime mode is complete
    input  wire [31:0] sub_prime_count,        // Number of primes found by subsystem
    input  wire [31:0] sub_largest_prime,      // Largest prime found by subsystem
    input  wire [31:0] sub_current_candidate,  // Current candidate being checked
    input  wire [31:0] sub_last_prime_found,   // Most recent prime found, currently unused here
    input  wire        sub_single_is_prime,    // SINGLE mode result flag
    input  wire [31:0] sub_elapsed_seconds,    // Elapsed seconds from TIME mode
    input  wire [639:0] sub_recent_primes_flat,// Packed recent primes, 20 entries x 32 bits
    input  wire [4:0]  sub_recent_valid_count, // Number of valid recent primes, currently unused here

    //--------------------------------------------------------------------------
    // Control outputs to prime_subsystem
    //--------------------------------------------------------------------------
    output reg         sub_start,              // One-clock pulse to start prime subsystem
    output reg         sub_abort,              // One-clock pulse to abort prime subsystem
    output reg         sub_start_new_run,      // One-clock pulse to clear storage for new run

    //--------------------------------------------------------------------------
    // Outputs to ui_frame_renderer / screen_mux
    //--------------------------------------------------------------------------
    output reg  [2:0]  display_mode,           // Current screen selected for rendering

    output reg  [1:0]  mode,                   // Current UI compute mode selection

    output wire        entry_done,             // Parameter entry done flag, tied low here
    output wire        input_error,            // Parameter input error flag, tied low here

    output wire [23:0] prime_count,            // Display-width prime count
    output wire [26:0] current_n,              // Display-width current candidate
    output wire [12:0] elapsed_sec,            // Display-width elapsed seconds
    output wire        compute_done,           // Display compute-complete flag
    output wire [539:0] last_primes,           // Packed recent primes, 20 entries x 27 bits
    output wire [26:0] largest_prime,          // Display-width largest prime
    output wire        single_is_prime         // SINGLE mode primality result
);

    //--------------------------------------------------------------------------
    // Display screen constants
    //
    // These values select which screen the renderer draws.
    //--------------------------------------------------------------------------
    localparam SCREEN_MENU     = 3'd0;         // Main menu screen
    localparam SCREEN_PARAMS   = 3'd1;         // Parameter entry screen
    localparam SCREEN_GEN      = 3'd2;         // Generating / running screen
    localparam SCREEN_RESULT   = 3'd3;         // Results screen
    localparam SCREEN_ERROR    = 3'd4;         // Error screen, reserved
    localparam SCREEN_TEST     = 3'd5;         // Test Mode screen
    localparam SCREEN_CONTROLS = 3'd6;         // Controls/help screen

    //--------------------------------------------------------------------------
    // UI compute mode constants
    //
    // These match the menu choices selected by nav_mode_sel.
    //--------------------------------------------------------------------------
    localparam CMODE_RANGE  = 2'd0;            // Generate primes in a range
    localparam CMODE_TIME   = 2'd1;            // Generate primes for a time limit
    localparam CMODE_SINGLE = 2'd2;            // Check one number for primality
    localparam CMODE_TEST   = 2'd3;            // Compare stored primes against SD card

    //--------------------------------------------------------------------------
    // UI navigation FSM
    //
    // This FSM latches the selected mode, changes screens, and generates
    // one-cycle start/abort/storage-reset pulses for the prime subsystem.
    //--------------------------------------------------------------------------
    always @(posedge clk_cpu) begin
        // Return to the menu and clear subsystem pulses during reset.
        if (!resetn) begin
            display_mode      <= SCREEN_MENU;
            mode              <= CMODE_RANGE;
            sub_start         <= 1'b0;
            sub_abort         <= 1'b0;
            sub_start_new_run <= 1'b0;
        end
        else begin
            // Control outputs are pulses, so they default low every cycle.
            sub_start         <= 1'b0;
            sub_abort         <= 1'b0;
            sub_start_new_run <= 1'b0;

            // Soft reset has highest priority and aborts any active compute run.
            if (soft_reset) begin
                display_mode <= SCREEN_MENU;
                mode         <= CMODE_RANGE;
                sub_abort    <= 1'b1;
            end
            // A menu mode click selects the requested mode and leaves the menu.
            else if (nav_menu_click && display_mode == SCREEN_MENU) begin
                mode <= nav_mode_sel;

                // Test Mode does not use the normal parameter-entry screen.
                if (nav_mode_sel == CMODE_TEST) begin
                    display_mode <= SCREEN_TEST;
                end
                // Range, Time, and Single modes use the parameter-entry screen.
                else begin
                    display_mode <= SCREEN_PARAMS;
                end
            end
            // Controls button opens the Controls screen from the main menu.
            else if (nav_controls && display_mode == SCREEN_MENU) begin
                display_mode <= SCREEN_CONTROLS;
            end
            // Start Finding launches the prime subsystem from the Params screen.
            else if (nav_start && display_mode == SCREEN_PARAMS) begin
                display_mode      <= SCREEN_GEN;
                sub_start         <= 1'b1;
                sub_start_new_run <= 1'b1;
            end
            // When the prime subsystem finishes, show the Results screen.
            else if (sub_done && display_mode == SCREEN_GEN) begin
                display_mode <= SCREEN_RESULT;
            end
            // Stop during generation aborts the active run and returns to menu.
            else if (nav_stop && display_mode == SCREEN_GEN) begin
                display_mode <= SCREEN_MENU;
                sub_abort    <= 1'b1;
            end
            // Back returns from secondary screens to the main menu.
            else if (nav_back && (display_mode == SCREEN_PARAMS ||
                                  display_mode == SCREEN_RESULT ||
                                  display_mode == SCREEN_TEST ||
                                  display_mode == SCREEN_CONTROLS)) begin
                display_mode <= SCREEN_MENU;
            end
            // No navigation event occurred, so hold the current screen.
            else begin
                display_mode <= display_mode;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Parameter-entry status outputs
    //
    // Parameter entry is handled by param_entry in the top-level hierarchy, so
    // these legacy status outputs are tied inactive here.
    //--------------------------------------------------------------------------
    assign entry_done  = 1'b0;
    assign input_error = 1'b0;

    //--------------------------------------------------------------------------
    // Subsystem-to-UI width mapping
    //
    // The prime subsystem uses 32-bit values internally. The renderer displays
    // narrower fields, so this section truncates the live data to the display
    // widths used by the screen modules.
    //--------------------------------------------------------------------------
    assign prime_count     = sub_prime_count[23:0];
    assign current_n       = sub_current_candidate[26:0];
    assign elapsed_sec     = sub_elapsed_seconds[12:0];
    assign compute_done    = sub_mode_complete;
    assign single_is_prime = sub_single_is_prime;

    //--------------------------------------------------------------------------
    // Recent-prime packing conversion
    //
    // The subsystem stores 20 recent primes as 32-bit entries:
    //   sub_recent_primes_flat[31:0]   = newest prime
    //   sub_recent_primes_flat[63:32]  = second newest prime
    //
    // The UI uses 27-bit display entries:
    //   last_primes[26:0]   = newest display value
    //   last_primes[53:27]  = second newest display value
    //
    // Example:
    //   If sub_recent_primes_flat[31:0] = 32'd101, then
    //   last_primes[26:0] receives 27'd101.
    //--------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < 20; gi = gi + 1) begin : gen_prime_pack
            assign last_primes[gi*27 +: 27] =
                sub_recent_primes_flat[gi*32 +: 27];
        end
    endgenerate

    assign largest_prime = sub_largest_prime[26:0];

endmodule