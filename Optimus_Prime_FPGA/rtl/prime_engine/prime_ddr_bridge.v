`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// prime_ddr_bridge.v
//
// Purpose:
//   Clock-domain crossing bridge between the CPU-domain prime-storage path and
//   the DDR2 ui_clk-domain prime-storage interface.
//
//   The prime subsystem runs in clk_cpu, while the DDR2 controller runs in the
//   MIG ui_clk domain. This module safely transfers prime read/write requests
//   across those two domains using held request levels, synchronized buses, and
//   completion toggles.
//
// CDC write algorithm:
//   1) CPU receives cpu_wr_req and stores cpu_wr_addr/cpu_wr_data in holding
//      registers.
//   2) CPU raises cpu_wr_pending_ff and keeps the address/data stable.
//   3) ui_clk synchronizes the pending level and held buses.
//   4) ui_clk waits briefly for the synchronized buses to settle, then pulses
//      ddr_prime_wr_req once.
//   5) When DDR acknowledges the write, ui_clk toggles ui_wr_done_toggle_ff.
//   6) CPU synchronizes that toggle back, clears pending, and pulses cpu_wr_ack.
//
// CDC read algorithm:
//   1) CPU receives cpu_rd_req and stores cpu_rd_addr in a holding register.
//   2) CPU raises cpu_rd_pending_ff and keeps the address stable.
//   3) ui_clk synchronizes the pending level and address bus.
//   4) ui_clk waits briefly, then pulses ddr_prime_rd_req once.
//   5) When DDR read data returns, ui_clk stores it and toggles done.
//   6) CPU synchronizes the data and toggle back, waits a few cycles for data
//      synchronization, then pulses cpu_rd_data_valid.
//
// Example:
//   If the CPU requests a write of value 32'd17 to address 5, the CPU side holds
//   address 5 and data 17 stable while pending is high. The DDR side later
//   captures that stable request, issues exactly one DDR write, then toggles
//   completion so the CPU can generate cpu_wr_ack.
//
// Notes:
//   - One outstanding write and one outstanding read are supported at a time.
//   - A level handshake is used instead of crossing narrow pulses with changing
//     buses.
//   - This module is intended for control/storage traffic, not high-throughput
//     streaming data.
//------------------------------------------------------------------------------
module prime_ddr_bridge #(
    parameter integer ADDR_WIDTH = 16, // Width of prime-storage address bus
    parameter integer DATA_WIDTH = 32  // Width of prime-storage data bus
)(
    //--------------------------------------------------------------------------
    // CPU clock domain
    //--------------------------------------------------------------------------
    input  wire                    clk_cpu,             // CPU/subsystem clock
    input  wire                    rst_n_cpu,           // Active-low reset synchronized to clk_cpu

    input  wire                    cpu_wr_req,          // CPU-domain write request pulse
    input  wire [ADDR_WIDTH-1:0]   cpu_wr_addr,         // CPU-domain write address
    input  wire [DATA_WIDTH-1:0]   cpu_wr_data,         // CPU-domain write data
    output wire                    cpu_wr_ack,          // CPU-domain write acknowledge pulse

    input  wire                    cpu_rd_req,          // CPU-domain read request pulse
    input  wire [ADDR_WIDTH-1:0]   cpu_rd_addr,         // CPU-domain read address
    output wire [DATA_WIDTH-1:0]   cpu_rd_data,         // CPU-domain returned read data
    output wire                    cpu_rd_data_valid,   // CPU-domain read-data-valid pulse

    //--------------------------------------------------------------------------
    // DDR ui_clk domain
    //--------------------------------------------------------------------------
    input  wire                    ui_clk,              // DDR/MIG user-interface clock
    input  wire                    ui_rst,              // Active-high reset in ui_clk domain

    output wire                    ddr_prime_wr_req,    // DDR-domain write request pulse
    output wire [ADDR_WIDTH-1:0]   ddr_prime_wr_addr,   // DDR-domain write address
    output wire [DATA_WIDTH-1:0]   ddr_prime_wr_data,   // DDR-domain write data
    input  wire                    ddr_prime_wr_ack,    // DDR-domain write acknowledge pulse

    output wire                    ddr_prime_rd_req,    // DDR-domain read request pulse
    output wire [ADDR_WIDTH-1:0]   ddr_prime_rd_addr,   // DDR-domain read address
    input  wire [DATA_WIDTH-1:0]   ddr_prime_rd_data,   // DDR-domain returned read data
    input  wire                    ddr_prime_rd_data_valid // DDR-domain read-data-valid pulse
);

    //==========================================================================
    // CPU-domain held request state
    //
    // The CPU side holds address/data stable while a request is pending. The
    // ui_clk side samples these held values after synchronizing the pending
    // request level.
    //==========================================================================
    reg                  cpu_wr_pending_ff;        // CPU write request currently pending
    reg [ADDR_WIDTH-1:0] cpu_wr_addr_hold_ff;      // Held CPU write address
    reg [DATA_WIDTH-1:0] cpu_wr_data_hold_ff;      // Held CPU write data

    reg                  cpu_rd_pending_ff;        // CPU read request currently pending
    reg [ADDR_WIDTH-1:0] cpu_rd_addr_hold_ff;      // Held CPU read address

    reg                  cpu_wr_done_seen_ff;      // Last synchronized write-completion toggle seen
    reg                  cpu_rd_done_seen_ff;      // Last synchronized read-completion toggle seen

    reg                  cpu_wr_ack_ff;            // Registered CPU write acknowledge pulse
    reg [DATA_WIDTH-1:0] cpu_rd_data_ff;           // Registered CPU read data
    reg                  cpu_rd_data_valid_ff;     // Registered CPU read-data-valid pulse

    reg                  cpu_rd_capture_pending_ff;// Waiting to capture synchronized read data
    reg [1:0]            cpu_rd_capture_wait_ff;   // Small wait for read-data bus synchronization

    assign cpu_wr_ack        = cpu_wr_ack_ff;
    assign cpu_rd_data       = cpu_rd_data_ff;
    assign cpu_rd_data_valid = cpu_rd_data_valid_ff;

    //==========================================================================
    // Synchronize held request buses into ui_clk
    //
    // These sync modules bring the held address/data buses into ui_clk. The
    // request pending level controls when the destination is allowed to use them.
    //==========================================================================
    wire [ADDR_WIDTH-1:0] wr_addr_sync_ui_w; // Write address synchronized to ui_clk
    wire [DATA_WIDTH-1:0] wr_data_sync_ui_w; // Write data synchronized to ui_clk
    wire [ADDR_WIDTH-1:0] rd_addr_sync_ui_w; // Read address synchronized to ui_clk

    sync_ff #(
        .WIDTH     (ADDR_WIDTH),
        .RESET_VAL (0)
    ) u_sync_wr_addr_to_ui (
        .dst_clk (ui_clk),
        .resetn  (~ui_rst),
        .d       (cpu_wr_addr_hold_ff),
        .q       (wr_addr_sync_ui_w)
    );

    sync_ff #(
        .WIDTH     (DATA_WIDTH),
        .RESET_VAL (0)
    ) u_sync_wr_data_to_ui (
        .dst_clk (ui_clk),
        .resetn  (~ui_rst),
        .d       (cpu_wr_data_hold_ff),
        .q       (wr_data_sync_ui_w)
    );

    sync_ff #(
        .WIDTH     (ADDR_WIDTH),
        .RESET_VAL (0)
    ) u_sync_rd_addr_to_ui (
        .dst_clk (ui_clk),
        .resetn  (~ui_rst),
        .d       (cpu_rd_addr_hold_ff),
        .q       (rd_addr_sync_ui_w)
    );

    //==========================================================================
    // Synchronize CPU pending levels into ui_clk
    //
    // Pending levels remain high until completion, so the destination has time
    // to see each request reliably.
    //==========================================================================
    wire cpu_wr_pending_sync_ui_w; // CPU write-pending level synchronized to ui_clk
    wire cpu_rd_pending_sync_ui_w; // CPU read-pending level synchronized to ui_clk

    sync_ff #(
        .WIDTH     (1),
        .RESET_VAL (0)
    ) u_sync_wr_pending_to_ui (
        .dst_clk (ui_clk),
        .resetn  (~ui_rst),
        .d       (cpu_wr_pending_ff),
        .q       (cpu_wr_pending_sync_ui_w)
    );

    sync_ff #(
        .WIDTH     (1),
        .RESET_VAL (0)
    ) u_sync_rd_pending_to_ui (
        .dst_clk (ui_clk),
        .resetn  (~ui_rst),
        .d       (cpu_rd_pending_ff),
        .q       (cpu_rd_pending_sync_ui_w)
    );

    //==========================================================================
    // ui_clk-domain service state
    //
    // The DDR side detects pending requests, waits briefly for synchronized
    // buses to settle, then issues exactly one DDR request pulse.
    //==========================================================================
    reg                  ui_wr_seen_ff;          // Current write pending level has been serviced
    reg                  ui_rd_seen_ff;          // Current read pending level has been serviced

    reg                  ui_wr_arm_ff;           // Write request armed while buses settle
    reg [1:0]            ui_wr_wait_ff;          // Write bus-settle countdown
    reg                  ui_rd_arm_ff;           // Read request armed while bus settles
    reg [1:0]            ui_rd_wait_ff;          // Read bus-settle countdown

    reg                  ui_wr_req_ff;           // Registered DDR write request pulse
    reg [ADDR_WIDTH-1:0] ui_wr_addr_ff;          // Registered DDR write address
    reg [DATA_WIDTH-1:0] ui_wr_data_ff;          // Registered DDR write data

    reg                  ui_rd_req_ff;           // Registered DDR read request pulse
    reg [ADDR_WIDTH-1:0] ui_rd_addr_ff;          // Registered DDR read address

    reg [DATA_WIDTH-1:0] ui_rd_data_hold_ff;     // Held DDR read data for CPU synchronization

    reg                  ui_wr_done_toggle_ff;   // Toggles when DDR write completes
    reg                  ui_rd_done_toggle_ff;   // Toggles when DDR read completes

    assign ddr_prime_wr_req  = ui_wr_req_ff;
    assign ddr_prime_wr_addr = ui_wr_addr_ff;
    assign ddr_prime_wr_data = ui_wr_data_ff;

    assign ddr_prime_rd_req  = ui_rd_req_ff;
    assign ddr_prime_rd_addr = ui_rd_addr_ff;

    //==========================================================================
    // Synchronize completion toggles into clk_cpu
    //
    // Completion toggles allow the CPU side to detect each completed transaction
    // even though the completion pulse originated in another clock domain.
    //==========================================================================
    wire ui_wr_done_toggle_sync_cpu_w; // Write-completion toggle synchronized to clk_cpu
    wire ui_rd_done_toggle_sync_cpu_w; // Read-completion toggle synchronized to clk_cpu

    sync_ff #(
        .WIDTH     (1),
        .RESET_VAL (0)
    ) u_sync_wr_done_to_cpu (
        .dst_clk (clk_cpu),
        .resetn  (rst_n_cpu),
        .d       (ui_wr_done_toggle_ff),
        .q       (ui_wr_done_toggle_sync_cpu_w)
    );

    sync_ff #(
        .WIDTH     (1),
        .RESET_VAL (0)
    ) u_sync_rd_done_to_cpu (
        .dst_clk (clk_cpu),
        .resetn  (rst_n_cpu),
        .d       (ui_rd_done_toggle_ff),
        .q       (ui_rd_done_toggle_sync_cpu_w)
    );

    //==========================================================================
    // Synchronize returned read data into clk_cpu
    //
    // The ui_clk side holds read data stable after it returns from DDR. The CPU
    // waits a few cycles after seeing the read-done toggle before using this
    // synchronized bus.
    //==========================================================================
    wire [DATA_WIDTH-1:0] rd_data_sync_cpu_w; // Read data synchronized to clk_cpu

    sync_ff #(
        .WIDTH     (DATA_WIDTH),
        .RESET_VAL (0)
    ) u_sync_rd_data_to_cpu (
        .dst_clk (clk_cpu),
        .resetn  (rst_n_cpu),
        .d       (ui_rd_data_hold_ff),
        .q       (rd_data_sync_cpu_w)
    );

    //==========================================================================
    // CPU-domain control logic
    //
    // This block accepts CPU read/write requests, holds request buses stable,
    // watches for synchronized completion toggles, and generates CPU-domain
    // acknowledge/data-valid pulses.
    //==========================================================================
    always @(posedge clk_cpu) begin
        // Clear all CPU-side request, acknowledge, and readback state.
        if (!rst_n_cpu) begin
            cpu_wr_pending_ff         <= 1'b0;
            cpu_wr_addr_hold_ff       <= {ADDR_WIDTH{1'b0}};
            cpu_wr_data_hold_ff       <= {DATA_WIDTH{1'b0}};

            cpu_rd_pending_ff         <= 1'b0;
            cpu_rd_addr_hold_ff       <= {ADDR_WIDTH{1'b0}};

            cpu_wr_done_seen_ff       <= 1'b0;
            cpu_rd_done_seen_ff       <= 1'b0;

            cpu_wr_ack_ff             <= 1'b0;
            cpu_rd_data_ff            <= {DATA_WIDTH{1'b0}};
            cpu_rd_data_valid_ff      <= 1'b0;

            cpu_rd_capture_pending_ff <= 1'b0;
            cpu_rd_capture_wait_ff    <= 2'd0;
        end
        else begin
            //------------------------------------------------------------------
            // Default CPU-domain output pulses low each cycle.
            //------------------------------------------------------------------
            cpu_wr_ack_ff        <= 1'b0;
            cpu_rd_data_valid_ff <= 1'b0;

            //------------------------------------------------------------------
            // CPU write request handling.
            //------------------------------------------------------------------
            if (cpu_wr_req && !cpu_wr_pending_ff) begin
                cpu_wr_pending_ff   <= 1'b1;
                cpu_wr_addr_hold_ff <= cpu_wr_addr;
                cpu_wr_data_hold_ff <= cpu_wr_data;
            end
            // A changed write-done toggle means the DDR side completed the write.
            else if (ui_wr_done_toggle_sync_cpu_w != cpu_wr_done_seen_ff) begin
                cpu_wr_done_seen_ff <= ui_wr_done_toggle_sync_cpu_w;
                cpu_wr_pending_ff   <= 1'b0;
                cpu_wr_ack_ff       <= 1'b1;
            end
            // No write-side change, so hold the current request state.
            else begin
                cpu_wr_pending_ff   <= cpu_wr_pending_ff;
                cpu_wr_addr_hold_ff <= cpu_wr_addr_hold_ff;
                cpu_wr_data_hold_ff <= cpu_wr_data_hold_ff;
                cpu_wr_done_seen_ff <= cpu_wr_done_seen_ff;
            end

            //------------------------------------------------------------------
            // CPU read request handling.
            //------------------------------------------------------------------
            if (cpu_rd_req && !cpu_rd_pending_ff && !cpu_rd_capture_pending_ff) begin
                cpu_rd_pending_ff   <= 1'b1;
                cpu_rd_addr_hold_ff <= cpu_rd_addr;
            end
            // A changed read-done toggle means DDR data has returned in ui_clk.
            else if (ui_rd_done_toggle_sync_cpu_w != cpu_rd_done_seen_ff) begin
                cpu_rd_done_seen_ff        <= ui_rd_done_toggle_sync_cpu_w;
                cpu_rd_pending_ff          <= 1'b0;
                cpu_rd_capture_pending_ff  <= 1'b1;
                cpu_rd_capture_wait_ff     <= 2'd2;
            end
            // Wait a few CPU cycles so the returned data bus is fully synchronized.
            else if (cpu_rd_capture_pending_ff) begin
                if (cpu_rd_capture_wait_ff != 2'd0) begin
                    cpu_rd_capture_pending_ff <= 1'b1;
                    cpu_rd_capture_wait_ff    <= cpu_rd_capture_wait_ff - 2'd1;
                end
                // Capture synchronized read data and pulse valid once.
                else begin
                    cpu_rd_capture_pending_ff <= 1'b0;
                    cpu_rd_capture_wait_ff    <= 2'd0;
                    cpu_rd_data_ff            <= rd_data_sync_cpu_w;
                    cpu_rd_data_valid_ff      <= 1'b1;
                end
            end
            // No read-side change, so hold the current request/capture state.
            else begin
                cpu_rd_pending_ff         <= cpu_rd_pending_ff;
                cpu_rd_addr_hold_ff       <= cpu_rd_addr_hold_ff;
                cpu_rd_done_seen_ff       <= cpu_rd_done_seen_ff;
                cpu_rd_capture_pending_ff <= cpu_rd_capture_pending_ff;
                cpu_rd_capture_wait_ff    <= cpu_rd_capture_wait_ff;
                cpu_rd_data_ff            <= cpu_rd_data_ff;
            end
        end
    end

    //==========================================================================
    // ui_clk-domain control logic
    //
    // This block services synchronized CPU pending levels. It waits a short
    // number of ui_clk cycles before issuing DDR requests so the synchronized
    // address/data buses are stable.
    //==========================================================================
    always @(posedge ui_clk) begin
        // Clear all DDR-side service state during ui_clk reset.
        if (ui_rst) begin
            ui_wr_seen_ff         <= 1'b0;
            ui_rd_seen_ff         <= 1'b0;

            ui_wr_arm_ff          <= 1'b0;
            ui_wr_wait_ff         <= 2'd0;
            ui_rd_arm_ff          <= 1'b0;
            ui_rd_wait_ff         <= 2'd0;

            ui_wr_req_ff          <= 1'b0;
            ui_wr_addr_ff         <= {ADDR_WIDTH{1'b0}};
            ui_wr_data_ff         <= {DATA_WIDTH{1'b0}};

            ui_rd_req_ff          <= 1'b0;
            ui_rd_addr_ff         <= {ADDR_WIDTH{1'b0}};

            ui_rd_data_hold_ff    <= {DATA_WIDTH{1'b0}};

            ui_wr_done_toggle_ff  <= 1'b0;
            ui_rd_done_toggle_ff  <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Default DDR request pulses low each ui_clk cycle.
            //------------------------------------------------------------------
            ui_wr_req_ff <= 1'b0;
            ui_rd_req_ff <= 1'b0;

            //------------------------------------------------------------------
            // Write request service.
            //------------------------------------------------------------------
            if (!cpu_wr_pending_sync_ui_w) begin
                ui_wr_seen_ff <= 1'b0;
                ui_wr_arm_ff  <= 1'b0;
                ui_wr_wait_ff <= 2'd0;
                ui_wr_addr_ff <= ui_wr_addr_ff;
                ui_wr_data_ff <= ui_wr_data_ff;
            end
            // New synchronized write-pending level detected, so arm the wait.
            else if (cpu_wr_pending_sync_ui_w && !ui_wr_seen_ff && !ui_wr_arm_ff) begin
                ui_wr_arm_ff  <= 1'b1;
                ui_wr_wait_ff <= 2'd2;
                ui_wr_seen_ff <= ui_wr_seen_ff;
                ui_wr_addr_ff <= ui_wr_addr_ff;
                ui_wr_data_ff <= ui_wr_data_ff;
            end
            // Wait for the synchronized write address/data buses to settle.
            else if (ui_wr_arm_ff) begin
                if (ui_wr_wait_ff != 2'd0) begin
                    ui_wr_arm_ff  <= 1'b1;
                    ui_wr_wait_ff <= ui_wr_wait_ff - 2'd1;
                    ui_wr_seen_ff <= ui_wr_seen_ff;
                    ui_wr_addr_ff <= ui_wr_addr_ff;
                    ui_wr_data_ff <= ui_wr_data_ff;
                end
                // Capture synchronized write bus and issue exactly one DDR write pulse.
                else begin
                    ui_wr_arm_ff  <= 1'b0;
                    ui_wr_wait_ff <= 2'd0;
                    ui_wr_addr_ff <= wr_addr_sync_ui_w;
                    ui_wr_data_ff <= wr_data_sync_ui_w;
                    ui_wr_req_ff  <= 1'b1;
                    ui_wr_seen_ff <= 1'b1;
                end
            end
            // Current write request has already been serviced, so hold state.
            else begin
                ui_wr_seen_ff <= ui_wr_seen_ff;
                ui_wr_arm_ff  <= ui_wr_arm_ff;
                ui_wr_wait_ff <= ui_wr_wait_ff;
                ui_wr_addr_ff <= ui_wr_addr_ff;
                ui_wr_data_ff <= ui_wr_data_ff;
            end

            //------------------------------------------------------------------
            // Read request service.
            //------------------------------------------------------------------
            if (!cpu_rd_pending_sync_ui_w) begin
                ui_rd_seen_ff <= 1'b0;
                ui_rd_arm_ff  <= 1'b0;
                ui_rd_wait_ff <= 2'd0;
                ui_rd_addr_ff <= ui_rd_addr_ff;
            end
            // New synchronized read-pending level detected, so arm the wait.
            else if (cpu_rd_pending_sync_ui_w && !ui_rd_seen_ff && !ui_rd_arm_ff) begin
                ui_rd_arm_ff  <= 1'b1;
                ui_rd_wait_ff <= 2'd2;
                ui_rd_seen_ff <= ui_rd_seen_ff;
                ui_rd_addr_ff <= ui_rd_addr_ff;
            end
            // Wait for the synchronized read-address bus to settle.
            else if (ui_rd_arm_ff) begin
                if (ui_rd_wait_ff != 2'd0) begin
                    ui_rd_arm_ff  <= 1'b1;
                    ui_rd_wait_ff <= ui_rd_wait_ff - 2'd1;
                    ui_rd_seen_ff <= ui_rd_seen_ff;
                    ui_rd_addr_ff <= ui_rd_addr_ff;
                end
                // Capture synchronized read address and issue exactly one DDR read pulse.
                else begin
                    ui_rd_arm_ff  <= 1'b0;
                    ui_rd_wait_ff <= 2'd0;
                    ui_rd_addr_ff <= rd_addr_sync_ui_w;
                    ui_rd_req_ff  <= 1'b1;
                    ui_rd_seen_ff <= 1'b1;
                end
            end
            // Current read request has already been serviced, so hold state.
            else begin
                ui_rd_seen_ff <= ui_rd_seen_ff;
                ui_rd_arm_ff  <= ui_rd_arm_ff;
                ui_rd_wait_ff <= ui_rd_wait_ff;
                ui_rd_addr_ff <= ui_rd_addr_ff;
            end

            //------------------------------------------------------------------
            // Write completion toggle.
            //------------------------------------------------------------------
            if (ddr_prime_wr_ack) begin
                ui_wr_done_toggle_ff <= ~ui_wr_done_toggle_ff;
            end
            // No write completion this cycle, so hold the toggle.
            else begin
                ui_wr_done_toggle_ff <= ui_wr_done_toggle_ff;
            end

            //------------------------------------------------------------------
            // Read completion toggle and read-data capture.
            //------------------------------------------------------------------
            if (ddr_prime_rd_data_valid) begin
                ui_rd_data_hold_ff   <= ddr_prime_rd_data;
                ui_rd_done_toggle_ff <= ~ui_rd_done_toggle_ff;
            end
            // No read completion this cycle, so hold data and toggle state.
            else begin
                ui_rd_data_hold_ff   <= ui_rd_data_hold_ff;
                ui_rd_done_toggle_ff <= ui_rd_done_toggle_ff;
            end
        end
    end

endmodule