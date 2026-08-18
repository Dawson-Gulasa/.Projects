`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ddr2_fb_ctrl.v
//
// Purpose:
//   Hierarchical DDR2 framebuffer controller built around the Xilinx MIG user
//   interface.
//
//   This module connects the external DDR2 physical interface, the VGA
//   framebuffer path, renderer write requests, front/back buffer swap control,
//   and the prime-storage DDR access path.
//
// Top-level responsibilities:
//   - Instantiate the MIG DDR2 controller.
//   - Export the MIG ui_clk and ui_rst signals.
//   - Synchronize async frame/render events into ui_clk.
//   - Control tear-free front/back framebuffer swaps.
//   - Latch renderer write requests until the DDR engine can service them.
//   - Hold prime-storage read/write requests until the DDR engine can service
//     them.
//   - Instantiate the main DDR clear/read/write engine.
//
// Prime-storage request holding algorithm:
//   1) prime_ddr_bridge sends one-cycle read/write pulses in ui_clk.
//   2) This module latches each request if that channel is not already pending.
//   3) The pending request is held stable until ddr2_fb_engine services it.
//   4) The engine pulses prime_wr_done_pulse_w or prime_rd_done_pulse_w.
//   5) The corresponding pending bit clears, allowing a new request later.
//
// Why request holding is needed:
//   The DDR engine only checks requests when it reaches the correct service
//   point. Without these holding registers, a one-cycle prime request could be
//   missed while the DDR engine is busy clearing, reading the framebuffer, or
//   processing another command.
//
// Notes:
//   - This wrapper is mostly structural wiring.
//   - Main DDR sequencing is handled inside ddr2_fb_engine.
//   - Buffer-swap sequencing is handled inside ddr2_fb_swap_ctrl.
//   - CDC/pulse generation is handled inside ddr2_fb_cdc.
//   - This module uses the full 5M+ prime-storage address configuration.
//------------------------------------------------------------------------------
module ddr2_fb_ctrl (
    //--------------------------------------------------------------------------
    // DDR2 reference clock / reset into MIG
    //--------------------------------------------------------------------------
    input  wire        clk_mem,           // DDR2/MIG reference clock
    input  wire        sys_rst_n,         // Active-low system reset into MIG

    //--------------------------------------------------------------------------
    // DDR2 physical interface
    //--------------------------------------------------------------------------
    inout  wire [15:0] ddr2_dq,           // DDR2 bidirectional data bus
    inout  wire [1:0]  ddr2_dqs_n,        // DDR2 negative data strobe lines
    inout  wire [1:0]  ddr2_dqs_p,        // DDR2 positive data strobe lines
    output wire [12:0] ddr2_addr,         // DDR2 address bus
    output wire [2:0]  ddr2_ba,           // DDR2 bank address bus
    output wire        ddr2_ras_n,        // DDR2 row-address strobe, active low
    output wire        ddr2_cas_n,        // DDR2 column-address strobe, active low
    output wire        ddr2_we_n,         // DDR2 write enable, active low
    output wire [0:0]  ddr2_ck_p,         // DDR2 differential clock positive
    output wire [0:0]  ddr2_ck_n,         // DDR2 differential clock negative
    output wire [0:0]  ddr2_cke,          // DDR2 clock enable
    output wire [0:0]  ddr2_cs_n,         // DDR2 chip select, active low
    output wire [1:0]  ddr2_dm,           // DDR2 data mask bits
    output wire [0:0]  ddr2_odt,          // DDR2 on-die termination control

    //--------------------------------------------------------------------------
    // MIG user clock/reset/status
    //--------------------------------------------------------------------------
    output wire        ui_clk,            // MIG user-interface clock
    output wire        ui_rst,            // MIG user-interface reset
    output wire        ready,             // Framebuffer controller ready flag

    //--------------------------------------------------------------------------
    // Read FIFO write interface in ui_clk domain
    //--------------------------------------------------------------------------
    output wire [63:0] fifo_wr_data,      // Pixel data written into VGA FIFO
    output wire        fifo_wr_en,        // One-clock FIFO write enable
    input  wire        fifo_full,         // FIFO full flag from async FIFO
    output wire        fifo_rst,          // FIFO reset from DDR engine

    //--------------------------------------------------------------------------
    // Video timing input
    //--------------------------------------------------------------------------
    input  wire        vsync_in,          // VGA VSYNC input, synchronized internally

    //--------------------------------------------------------------------------
    // Renderer write request interface
    //--------------------------------------------------------------------------
    input  wire [26:0] wr_addr,           // Renderer framebuffer write address
    input  wire [63:0] wr_data,           // Renderer framebuffer write data
    input  wire        wr_req,            // Renderer write request pulse
    output wire        wr_ack,            // Renderer write acknowledge pulse

    //--------------------------------------------------------------------------
    // Prime-storage DDR2 access path
    //
    // This path stores prime results in a DDR2 region separate from the frame
    // buffers. The current configuration supports the full 5M+ prime-storage
    // address range.
    //--------------------------------------------------------------------------
    input  wire        prime_wr_req,      // One-clock prime-storage write request
    input  wire [22:0] prime_wr_addr,     // Prime-storage write address/index
    input  wire [31:0] prime_wr_data,     // Prime-storage write data
    output wire        prime_wr_ack,      // One-clock prime-storage write acknowledge

    input  wire        prime_rd_req,      // One-clock prime-storage read request
    input  wire [22:0] prime_rd_addr,     // Prime-storage read address/index
    output wire [31:0] prime_rd_data,     // Prime-storage read data
    output wire        prime_rd_data_valid, // One-clock prime read-data-valid pulse

    //--------------------------------------------------------------------------
    // Frame done / buffer swap handshake
    //--------------------------------------------------------------------------
    input  wire        frame_done_req,    // Renderer requests completed back-buffer frame
    output wire        frame_done_ack,    // Buffer swap controller acknowledges frame_done
    output wire [26:0] back_buf_base,     // Base address of the current back buffer

    //--------------------------------------------------------------------------
    // Debug / visibility outputs
    //--------------------------------------------------------------------------
    output wire        debug_drain_active,// DDR engine is draining/clearing activity
    output wire        ready_toggle,      // Toggles once when ready first rises
    output wire        calib_done,        // MIG calibration complete flag
    output wire        debug_rd_active,   // DDR engine framebuffer read active flag
    output wire [4:0]  debug_state,       // DDR engine debug state
    output wire        debug_vsync_seen,  // VSYNC pulse observed after synchronization
    output wire        debug_front_buf,   // Current front-buffer select
    output wire        debug_wr_pending,  // Renderer write latch currently pending
    output wire        debug_app_wdf_rdy, // MIG write-data channel ready
    output wire        debug_app_rdy      // MIG command channel ready
);

    //--------------------------------------------------------------------------
    // MIG user-interface wires
    //
    // These are the application-side command, write-data, and read-data signals
    // connected between the MIG and ddr2_fb_engine.
    //--------------------------------------------------------------------------
    wire        ui_clk_i;                 // Internal MIG ui_clk
    wire        ui_clk_sync_rst;          // Internal MIG ui_clk reset
    wire        init_calib_complete;      // MIG calibration complete

    wire [26:0] app_addr_w;               // MIG app command address
    wire [2:0]  app_cmd_w;                // MIG app command type
    wire        app_en_w;                 // MIG app command enable

    wire [63:0] app_wdf_data_w;           // MIG app write-data bus
    wire        app_wdf_end_w;            // MIG app write-data end flag
    wire [7:0]  app_wdf_mask_w;           // MIG app write-data byte mask
    wire        app_wdf_wren_w;           // MIG app write-data enable

    wire [63:0] app_rd_data_w;            // MIG app read-data bus
    wire        app_rd_data_end_w;        // MIG app read-data end flag
    wire        app_rd_data_valid_w;      // MIG app read-data valid
    wire        app_rdy_w;                // MIG command ready
    wire        app_wdf_rdy_w;            // MIG write-data ready

    //--------------------------------------------------------------------------
    // Synchronized pulse/control wires
    //--------------------------------------------------------------------------
    wire vsync_pulse_w;                   // ui_clk pulse from synchronized VSYNC
    wire fd_pulse_w;                      // ui_clk pulse from frame_done_req
    wire wr_req_pulse_w;                  // ui_clk pulse from renderer wr_req

    //--------------------------------------------------------------------------
    // Buffer swap control wires
    //--------------------------------------------------------------------------
    wire front_buf_w;                     // Current front-buffer select

    //--------------------------------------------------------------------------
    // Renderer write latch wires
    //--------------------------------------------------------------------------
    wire [26:0] wr_addr_lat_w;            // Latched renderer write address
    wire [63:0] wr_data_lat_w;            // Latched renderer write data
    wire        wr_pending_w;             // Renderer write pending flag
    wire        wr_done_pulse_w;          // DDR engine completed renderer write

    //--------------------------------------------------------------------------
    // Prime-storage internal request wires
    //
    // prime_ddr_bridge creates one-cycle pulses in ui_clk. These local registers
    // hold the requests until ddr2_fb_engine actually completes them.
    //--------------------------------------------------------------------------
    wire        prime_wr_done_pulse_w;    // DDR engine completed held prime write
    wire        prime_rd_done_pulse_w;    // DDR engine completed held prime read

    reg         prime_wr_pending_ff;      // Held prime write request is pending
    reg         prime_wr_pending_n;       // Next prime write pending flag
    reg [22:0]  prime_wr_addr_lat_ff;     // Held prime write address
    reg [22:0]  prime_wr_addr_lat_n;      // Next held prime write address
    reg [31:0]  prime_wr_data_lat_ff;     // Held prime write data
    reg [31:0]  prime_wr_data_lat_n;      // Next held prime write data

    reg         prime_rd_pending_ff;      // Held prime read request is pending
    reg         prime_rd_pending_n;       // Next prime read pending flag
    reg [22:0]  prime_rd_addr_lat_ff;     // Held prime read address
    reg [22:0]  prime_rd_addr_lat_n;      // Next held prime read address

    wire        prime_wr_pending_w;       // Prime write pending sent to DDR engine
    wire        prime_rd_pending_w;       // Prime read pending sent to DDR engine

    assign prime_wr_pending_w = prime_wr_pending_ff;
    assign prime_rd_pending_w = prime_rd_pending_ff;

    //--------------------------------------------------------------------------
    // Export MIG clock/reset/debug status
    //--------------------------------------------------------------------------
    assign ui_clk            = ui_clk_i;
    assign ui_rst            = ui_clk_sync_rst;
    assign calib_done        = init_calib_complete;
    assign debug_app_wdf_rdy = app_wdf_rdy_w;
    assign debug_app_rdy     = app_rdy_w;

    //--------------------------------------------------------------------------
    // Prime write acknowledge
    //
    // The write is acknowledged when the DDR engine finishes the held prime
    // write transaction.
    //--------------------------------------------------------------------------
    assign prime_wr_ack = prime_wr_done_pulse_w;

    //--------------------------------------------------------------------------
    // Xilinx MIG DDR2 controller
    //
    // The MIG handles the physical DDR2 interface and exposes the app_* command
    // interface used by the project DDR engine.
    //--------------------------------------------------------------------------
    mig mig_inst (
        .ddr2_dq             (ddr2_dq),
        .ddr2_dqs_n          (ddr2_dqs_n),
        .ddr2_dqs_p          (ddr2_dqs_p),
        .ddr2_addr           (ddr2_addr),
        .ddr2_ba             (ddr2_ba),
        .ddr2_ras_n          (ddr2_ras_n),
        .ddr2_cas_n          (ddr2_cas_n),
        .ddr2_we_n           (ddr2_we_n),
        .ddr2_ck_p           (ddr2_ck_p),
        .ddr2_ck_n           (ddr2_ck_n),
        .ddr2_cke            (ddr2_cke),
        .ddr2_cs_n           (ddr2_cs_n),
        .ddr2_dm             (ddr2_dm),
        .ddr2_odt            (ddr2_odt),
        .sys_clk_i           (clk_mem),
        .sys_rst             (sys_rst_n),

        .app_addr            (app_addr_w),
        .app_cmd             (app_cmd_w),
        .app_en              (app_en_w),
        .app_wdf_data        (app_wdf_data_w),
        .app_wdf_end         (app_wdf_end_w),
        .app_wdf_mask        (app_wdf_mask_w),
        .app_wdf_wren        (app_wdf_wren_w),
        .app_rd_data         (app_rd_data_w),
        .app_rd_data_end     (app_rd_data_end_w),
        .app_rd_data_valid   (app_rd_data_valid_w),
        .app_rdy             (app_rdy_w),
        .app_wdf_rdy         (app_wdf_rdy_w),

        .ui_clk              (ui_clk_i),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .init_calib_complete (init_calib_complete),

        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0)
    );

    //--------------------------------------------------------------------------
    // CDC / pulse generation
    //
    // Converts async or external request-style inputs into clean ui_clk pulses.
    //--------------------------------------------------------------------------
    ddr2_fb_cdc u_ddr2_fb_cdc (
        .ui_clk           (ui_clk_i),
        .ui_rst           (ui_clk_sync_rst),
        .vsync_in         (vsync_in),
        .frame_done_req   (frame_done_req),
        .wr_req           (wr_req),
        .vsync_pulse      (vsync_pulse_w),
        .fd_pulse         (fd_pulse_w),
        .wr_req_pulse     (wr_req_pulse_w),
        .debug_vsync_seen (debug_vsync_seen)
    );

    //--------------------------------------------------------------------------
    // Tear-free front/back buffer swap control
    //
    // Performs buffer swaps only at safe frame boundaries after frame_done_req
    // has crossed into ui_clk.
    //--------------------------------------------------------------------------
    ddr2_fb_swap_ctrl u_ddr2_fb_swap_ctrl (
        .ui_clk         (ui_clk_i),
        .ui_rst         (ui_clk_sync_rst),
        .ready          (ready),
        .vsync_pulse    (vsync_pulse_w),
        .fd_pulse       (fd_pulse_w),
        .front_buf      (front_buf_w),
        .frame_done_ack (frame_done_ack),
        .back_buf_base  (back_buf_base),
        .ready_toggle   (ready_toggle),
        .debug_front_buf(debug_front_buf)
    );

    //--------------------------------------------------------------------------
    // Single-entry renderer write request latch
    //
    // Holds one renderer write request until the DDR engine completes it. This
    // prevents a one-cycle renderer write pulse from being missed.
    //--------------------------------------------------------------------------
    ddr2_fb_write_latch u_ddr2_fb_write_latch (
        .ui_clk           (ui_clk_i),
        .ui_rst           (ui_clk_sync_rst),
        .wr_req_pulse     (wr_req_pulse_w),
        .wr_addr          (wr_addr),
        .wr_data          (wr_data),
        .wr_done_pulse    (wr_done_pulse_w),
        .wr_addr_lat      (wr_addr_lat_w),
        .wr_data_lat      (wr_data_lat_w),
        .wr_pending       (wr_pending_w),
        .wr_ack           (wr_ack),
        .debug_wr_pending (debug_wr_pending)
    );

    //--------------------------------------------------------------------------
    // Prime request holding registers
    //
    // These registers store one pending prime write and one pending prime read.
    // The requests remain stable until ddr2_fb_engine pulses the matching done
    // signal.
    //--------------------------------------------------------------------------
    always @(posedge ui_clk_i) begin
        // Clear held prime requests during MIG ui_clk reset.
        if (ui_clk_sync_rst) begin
            prime_wr_pending_ff  <= 1'b0;
            prime_wr_addr_lat_ff <= 23'd0;
            prime_wr_data_lat_ff <= 32'd0;

            prime_rd_pending_ff  <= 1'b0;
            prime_rd_addr_lat_ff <= 23'd0;
        end
        // Normal operation loads the next held-request state.
        else begin
            prime_wr_pending_ff  <= prime_wr_pending_n;
            prime_wr_addr_lat_ff <= prime_wr_addr_lat_n;
            prime_wr_data_lat_ff <= prime_wr_data_lat_n;

            prime_rd_pending_ff  <= prime_rd_pending_n;
            prime_rd_addr_lat_ff <= prime_rd_addr_lat_n;
        end
    end

    //--------------------------------------------------------------------------
    // Prime request holding next-state logic
    //
    // Write channel:
    //   - Latch a new write request only if no write is already pending.
    //   - Hold the request until the DDR engine pulses prime_wr_done_pulse_w.
    //
    // Read channel:
    //   - Latch a new read request only if no read is already pending.
    //   - Hold the request until the DDR engine pulses prime_rd_done_pulse_w.
    //--------------------------------------------------------------------------
    always @(*) begin
        prime_wr_pending_n  = prime_wr_pending_ff;
        prime_wr_addr_lat_n = prime_wr_addr_lat_ff;
        prime_wr_data_lat_n = prime_wr_data_lat_ff;

        prime_rd_pending_n  = prime_rd_pending_ff;
        prime_rd_addr_lat_n = prime_rd_addr_lat_ff;

        // Clear a held write after the DDR engine completes it.
        if (prime_wr_done_pulse_w) begin
            prime_wr_pending_n  = 1'b0;
            prime_wr_addr_lat_n = prime_wr_addr_lat_ff;
            prime_wr_data_lat_n = prime_wr_data_lat_ff;
        end
        // Latch a new write request if the write channel is free.
        else if (prime_wr_req && !prime_wr_pending_ff) begin
            prime_wr_pending_n  = 1'b1;
            prime_wr_addr_lat_n = prime_wr_addr;
            prime_wr_data_lat_n = prime_wr_data;
        end
        // Otherwise keep the current held write request state.
        else begin
            prime_wr_pending_n  = prime_wr_pending_ff;
            prime_wr_addr_lat_n = prime_wr_addr_lat_ff;
            prime_wr_data_lat_n = prime_wr_data_lat_ff;
        end

        // Clear a held read after the DDR engine completes it.
        if (prime_rd_done_pulse_w) begin
            prime_rd_pending_n  = 1'b0;
            prime_rd_addr_lat_n = prime_rd_addr_lat_ff;
        end
        // Latch a new read request if the read channel is free.
        else if (prime_rd_req && !prime_rd_pending_ff) begin
            prime_rd_pending_n  = 1'b1;
            prime_rd_addr_lat_n = prime_rd_addr;
        end
        // Otherwise keep the current held read request state.
        else begin
            prime_rd_pending_n  = prime_rd_pending_ff;
            prime_rd_addr_lat_n = prime_rd_addr_lat_ff;
        end
    end

    //--------------------------------------------------------------------------
    // Main DDR clear/read/write engine
    //
    // This module performs the actual MIG app_* command sequencing for:
    //   - startup framebuffer clear
    //   - front-buffer read refill into FIFO
    //   - renderer framebuffer writes
    //   - prime-storage writes and reads
    //--------------------------------------------------------------------------
    ddr2_fb_engine u_ddr2_fb_engine (
        .ui_clk              (ui_clk_i),
        .ui_rst              (ui_clk_sync_rst),
        .init_calib_complete (init_calib_complete),
        .vsync_pulse         (vsync_pulse_w),
        .front_buf           (front_buf_w),
        .fifo_full           (fifo_full),

        .app_rd_data         (app_rd_data_w),
        .app_rd_data_end     (app_rd_data_end_w),
        .app_rd_data_valid   (app_rd_data_valid_w),
        .app_rdy             (app_rdy_w),
        .app_wdf_rdy         (app_wdf_rdy_w),

        .wr_pending          (wr_pending_w),
        .wr_addr_lat         (wr_addr_lat_w),
        .wr_data_lat         (wr_data_lat_w),

        .prime_wr_pending    (prime_wr_pending_w),
        .prime_wr_addr_lat   (prime_wr_addr_lat_ff),
        .prime_wr_data_lat   (prime_wr_data_lat_ff),
        .prime_rd_pending    (prime_rd_pending_w),
        .prime_rd_addr_lat   (prime_rd_addr_lat_ff),

        .ready               (ready),
        .fifo_wr_data        (fifo_wr_data),
        .fifo_wr_en          (fifo_wr_en),
        .fifo_rst            (fifo_rst),

        .wr_done_pulse       (wr_done_pulse_w),
        .prime_wr_done_pulse (prime_wr_done_pulse_w),
        .prime_rd_data       (prime_rd_data),
        .prime_rd_data_valid (prime_rd_data_valid),
        .prime_rd_done_pulse (prime_rd_done_pulse_w),

        .debug_drain_active  (debug_drain_active),
        .debug_rd_active     (debug_rd_active),
        .debug_state         (debug_state),

        .app_addr            (app_addr_w),
        .app_cmd             (app_cmd_w),
        .app_en              (app_en_w),
        .app_wdf_data        (app_wdf_data_w),
        .app_wdf_end         (app_wdf_end_w),
        .app_wdf_mask        (app_wdf_mask_w),
        .app_wdf_wren        (app_wdf_wren_w)
    );

endmodule