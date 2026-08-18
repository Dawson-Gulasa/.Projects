`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// ddr2_fb_engine.v
//
// Purpose:
//   Main DDR2 framebuffer and prime-storage engine running in the MIG ui_clk
//   domain.
//
// Responsibilities:
//   1) Clear both framebuffers after MIG calibration completes.
//   2) On each VSYNC, reset/drain the FIFO and begin reading the active front
//      buffer for VGA display.
//   3) Service one pending renderer write into DDR2.
//   4) Service prime-storage read/write requests in a reserved DDR2 region.
//
// Framebuffer behavior:
//   - DDR2 is cleared once at startup.
//   - Front-buffer reads are restarted on VSYNC.
//   - FIFO reset and drain windows are used before accepting returned read data.
//   - Renderer writes are serviced one at a time.
//
// Prime-storage behavior:
//   - Prime values are stored in a DDR2 region separate from framebuffers.
//   - Each prime uses one full 64-bit DDR word.
//   - Lower 32 bits hold the prime value.
//   - Upper 32 bits are unused and written as zero.
//
// Example prime write:
//   If prime_wr_addr_lat = 5 and prime_wr_data_lat = 32'd17, the engine writes
//   one DDR word at:
//
//       PRIME_BASE + 5 * ADDR_STEP
//
//   with write data:
//
//       {32'd0, 32'd17}
//
// Notes:
//   - This module runs entirely in the MIG ui_clk domain.
//   - Main sequencing is controlled by the FSM state_ff.
//   - Framebuffer reads have highest priority in S_IDLE to preserve display
//     behavior.
//   - Prime-storage accesses use available idle DDR cycles.
//------------------------------------------------------------------------------

module ddr2_fb_engine (
    input  wire        ui_clk,               // MIG user-interface clock
    input  wire        ui_rst,               // Synchronous reset in ui_clk domain
    input  wire        init_calib_complete,  // MIG calibration complete flag
    input  wire        vsync_pulse,          // One-clock synchronized VSYNC pulse
    input  wire        front_buf,            // Current front buffer select
    input  wire        fifo_full,            // VGA read FIFO full flag

    input  wire [63:0] app_rd_data,          // MIG read data bus
    input  wire        app_rd_data_end,      // MIG read burst end flag
    input  wire        app_rd_data_valid,    // MIG read data valid flag
    input  wire        app_rdy,              // MIG command channel ready
    input  wire        app_wdf_rdy,          // MIG write-data channel ready

    input  wire        wr_pending,           // Renderer write is pending
    input  wire [26:0] wr_addr_lat,          // Latched renderer write address
    input  wire [63:0] wr_data_lat,          // Latched renderer write data

    //--------------------------------------------------------------------------
    // Prime-storage DDR2 access interface
    //--------------------------------------------------------------------------
    input  wire        prime_wr_pending,     // Prime write request is pending
    input  wire [22:0] prime_wr_addr_lat,    // Latched prime write index
    input  wire [31:0] prime_wr_data_lat,    // Latched prime write data
    input  wire        prime_rd_pending,     // Prime read request is pending
    input  wire [22:0] prime_rd_addr_lat,    // Latched prime read index

    output reg         ready,                // High after clear is complete
    output reg  [63:0] fifo_wr_data,         // Data written into VGA FIFO
    output reg         fifo_wr_en,           // One-clock FIFO write enable
    output reg         fifo_rst,             // FIFO reset signal

    output wire        wr_done_pulse,        // Renderer write completed pulse

    //--------------------------------------------------------------------------
    // Prime-storage completion / readback outputs
    //--------------------------------------------------------------------------
    output wire        prime_wr_done_pulse,  // Prime write completed pulse
    output reg  [31:0] prime_rd_data,        // Prime readback data
    output reg         prime_rd_data_valid,  // One-clock prime read-valid pulse
    output wire        prime_rd_done_pulse,  // Prime read transaction completed pulse

    output wire        debug_drain_active,   // High while read drain window is active
    output wire        debug_rd_active,      // High while framebuffer read engine is active
    output wire [4:0]  debug_state,          // Current FSM state for debug

    output reg  [26:0] app_addr,             // MIG command address
    output reg  [2:0]  app_cmd,              // MIG command type
    output reg         app_en,               // MIG command enable
    output reg  [63:0] app_wdf_data,         // MIG write data
    output reg         app_wdf_end,          // MIG write-data end flag
    output reg  [7:0]  app_wdf_mask,         // MIG write byte mask
    output reg         app_wdf_wren          // MIG write-data enable
);

    //--------------------------------------------------------------------------
    // Frame layout constants
    //--------------------------------------------------------------------------
    localparam [14:0] FRAME_WORDS  = 15'd19200;  // 640x480 framebuffer words
    localparam [26:0] ADDR_STEP    = 27'd8;      // One 64-bit word = 8 bytes
    localparam [26:0] FRAME0_BASE  = 27'd0;      // Framebuffer 0 base address
    localparam [26:0] FRAME1_BASE  = 27'd153600; // Framebuffer 1 base address
    localparam [15:0] TOTAL_CLEAR  = 16'd38400;  // Two framebuffers worth of words

    //--------------------------------------------------------------------------
    // Reserved DDR2 address range for prime storage
    //
    // Frame buffers occupy the lower DDR2 address region. Prime storage starts
    // safely after the framebuffer space.
    //--------------------------------------------------------------------------
    localparam [26:0] PRIME_BASE = 27'd400000;

    //--------------------------------------------------------------------------
    // Read alignment compensation
    //
    // These values preserve the original framebuffer read timing alignment.
    //--------------------------------------------------------------------------
    localparam [26:0] RD_OFFSET    = 27'd64;
    localparam [14:0] RD_CNT_START = 15'd8;

    //--------------------------------------------------------------------------
    // MIG command encodings
    //--------------------------------------------------------------------------
    localparam [2:0] CMD_WRITE = 3'b000;
    localparam [2:0] CMD_READ  = 3'b001;

    //--------------------------------------------------------------------------
    // Main FSM state encoding
    //--------------------------------------------------------------------------
    localparam [4:0] S_INIT           = 5'd0;
    localparam [4:0] S_CLEAR_CMD      = 5'd1;
    localparam [4:0] S_CLEAR_D0       = 5'd2;
    localparam [4:0] S_CLEAR_D1       = 5'd3;
    localparam [4:0] S_CLEAR_NEXT     = 5'd4;
    localparam [4:0] S_IDLE           = 5'd5;
    localparam [4:0] S_RD_CMD         = 5'd6;
    localparam [4:0] S_RD_WAIT        = 5'd7;
    localparam [4:0] S_WR_CMD         = 5'd8;
    localparam [4:0] S_WR_D0          = 5'd9;
    localparam [4:0] S_WR_D1          = 5'd10;
    localparam [4:0] S_WR_NEXT        = 5'd11;
    localparam [4:0] S_PRIME_RD_CMD   = 5'd12;
    localparam [4:0] S_PRIME_RD_WAIT  = 5'd13;
    localparam [4:0] S_PRIME_WR_CMD   = 5'd14;
    localparam [4:0] S_PRIME_WR_D0    = 5'd15;
    localparam [4:0] S_PRIME_WR_NEXT  = 5'd16;

    //--------------------------------------------------------------------------
    // Internal front-buffer base decode
    //--------------------------------------------------------------------------
    wire [26:0] front_base;

    assign front_base = front_buf ? FRAME1_BASE : FRAME0_BASE;

    //--------------------------------------------------------------------------
    // Prime-storage address helpers
    //
    // One logical prime-storage index maps to one 64-bit DDR word.
    //--------------------------------------------------------------------------
    wire [26:0] prime_wr_word_addr_w;
    wire [26:0] prime_rd_word_addr_w;

    assign prime_wr_word_addr_w = PRIME_BASE + ({4'd0, prime_wr_addr_lat} * ADDR_STEP);
    assign prime_rd_word_addr_w = PRIME_BASE + ({4'd0, prime_rd_addr_lat} * ADDR_STEP);

    //--------------------------------------------------------------------------
    // Internal FSM and registered control signals
    //--------------------------------------------------------------------------
    reg [4:0]  state_ff;
    reg [4:0]  state_in;

    reg        ready_in;

    reg [26:0] app_addr_in;
    reg [2:0]  app_cmd_in;
    reg        app_en_in;

    reg [63:0] app_wdf_data_in;
    reg        app_wdf_end_in;
    reg [7:0]  app_wdf_mask_in;
    reg        app_wdf_wren_in;

    reg [63:0] fifo_wr_data_in;
    reg        fifo_wr_en_in;
    reg        fifo_rst_in;

    reg [4:0]  fifo_rst_cnt_ff;
    reg [4:0]  fifo_rst_cnt_in;

    reg [7:0]  drain_cnt_ff;
    reg [7:0]  drain_cnt_in;

    reg [26:0] rd_addr_ff;
    reg [26:0] rd_addr_in;

    reg [14:0] rd_count_ff;
    reg [14:0] rd_count_in;

    reg        rd_active_ff;
    reg        rd_active_in;

    reg        rd_in_flight_ff;
    reg        rd_in_flight_in;

    reg        rd_start_pending_ff;
    reg        rd_start_pending_in;

    reg [26:0] clear_addr_ff;
    reg [26:0] clear_addr_in;

    reg [15:0] clear_count_ff;
    reg [15:0] clear_count_in;

    //--------------------------------------------------------------------------
    // Prime-storage readback holding registers
    //--------------------------------------------------------------------------
    reg [31:0] prime_rd_data_in;
    reg        prime_rd_data_valid_in;

    reg        prime_rd_in_flight_ff;
    reg        prime_rd_in_flight_in;

    //--------------------------------------------------------------------------
    // Debug and completion output assignments
    //--------------------------------------------------------------------------
    assign debug_drain_active = (drain_cnt_ff != 8'd0);
    assign debug_rd_active    = rd_active_ff;
    assign debug_state        = state_ff;

    assign wr_done_pulse       = (state_ff == S_WR_NEXT);
    assign prime_wr_done_pulse = (state_ff == S_PRIME_WR_NEXT);
    assign prime_rd_done_pulse = (state_ff == S_PRIME_RD_WAIT) && app_rd_data_valid;

    //--------------------------------------------------------------------------
    // Main DDR engine next-state logic
    //
    // This block handles returned read data, VSYNC-driven framebuffer read
    // setup, FIFO reset/drain timing, and the main MIG command FSM.
    //--------------------------------------------------------------------------
    always @(*) begin
        // Hold all current values by default.
        state_in            = state_ff;
        ready_in            = ready;

        app_addr_in         = app_addr;
        app_cmd_in          = app_cmd;
        app_en_in           = app_en;

        app_wdf_data_in     = app_wdf_data;
        app_wdf_end_in      = app_wdf_end;
        app_wdf_mask_in     = app_wdf_mask;
        app_wdf_wren_in     = app_wdf_wren;

        fifo_wr_data_in     = fifo_wr_data;
        fifo_wr_en_in       = 1'b0;
        fifo_rst_in         = fifo_rst;

        fifo_rst_cnt_in     = fifo_rst_cnt_ff;
        drain_cnt_in        = drain_cnt_ff;

        rd_addr_in          = rd_addr_ff;
        rd_count_in         = rd_count_ff;
        rd_active_in        = rd_active_ff;
        rd_in_flight_in     = rd_in_flight_ff;
        rd_start_pending_in = rd_start_pending_ff;

        clear_addr_in       = clear_addr_ff;
        clear_count_in      = clear_count_ff;

        prime_rd_data_in       = prime_rd_data;
        prime_rd_data_valid_in = 1'b0;
        prime_rd_in_flight_in  = prime_rd_in_flight_ff;

        // Handle any valid data returned from the MIG read channel.
        if (app_rd_data_valid) begin
            // Framebuffer read data is written into the FIFO only after the
            // reset and drain windows have both completed.
            if (rd_in_flight_ff) begin
                if ((fifo_rst_cnt_ff == 5'd0) && (drain_cnt_ff == 8'd0)) begin
                    fifo_wr_data_in = app_rd_data;
                    fifo_wr_en_in   = 1'b1;
                end
                else begin
                    fifo_wr_data_in = fifo_wr_data;
                    fifo_wr_en_in   = 1'b0;
                end

                // Clear the in-flight flag when the MIG marks the end of read data.
                if (app_rd_data_end) begin
                    rd_in_flight_in = 1'b0;
                end
                else begin
                    rd_in_flight_in = rd_in_flight_in;
                end
            end
            else begin
                fifo_wr_data_in = fifo_wr_data;
                fifo_wr_en_in   = 1'b0;
            end

            // Prime read data is stored in the lower 32 bits of the returned word.
            if (prime_rd_in_flight_ff) begin
                prime_rd_data_in       = app_rd_data[31:0];
                prime_rd_data_valid_in = 1'b1;
                prime_rd_in_flight_in  = 1'b0;
            end
            else begin
                prime_rd_data_in       = prime_rd_data_in;
                prime_rd_data_valid_in = prime_rd_data_valid_in;
                prime_rd_in_flight_in  = prime_rd_in_flight_in;
            end
        end
        else begin
            fifo_wr_data_in        = fifo_wr_data_in;
            fifo_wr_en_in          = fifo_wr_en_in;
            rd_in_flight_in        = rd_in_flight_in;
            prime_rd_data_in       = prime_rd_data_in;
            prime_rd_data_valid_in = 1'b0;
            prime_rd_in_flight_in  = prime_rd_in_flight_in;
        end

        // On every VSYNC after ready, prepare a fresh front-buffer read.
        if (vsync_pulse && ready) begin
            rd_addr_in          = front_base + RD_OFFSET;
            rd_count_in         = RD_CNT_START;

            rd_active_in        = 1'b0;
            rd_start_pending_in = 1'b1;

            fifo_rst_cnt_in     = 5'd20;
            drain_cnt_in        = 8'd80;
        end
        else begin
            rd_addr_in          = rd_addr_in;
            rd_count_in         = rd_count_in;
            rd_active_in        = rd_active_in;
            rd_start_pending_in = rd_start_pending_in;
            fifo_rst_cnt_in     = fifo_rst_cnt_in;
            drain_cnt_in        = drain_cnt_in;
        end

        // Count down the read-data drain window.
        if (drain_cnt_ff != 8'd0) begin
            drain_cnt_in = drain_cnt_ff - 8'd1;
        end
        else begin
            drain_cnt_in = drain_cnt_in;
        end

        // Stretch FIFO reset for a fixed number of ui_clk cycles.
        if (fifo_rst_cnt_ff != 5'd0) begin
            fifo_rst_cnt_in = fifo_rst_cnt_ff - 5'd1;
            fifo_rst_in     = 1'b1;
        end
        else begin
            fifo_rst_cnt_in = fifo_rst_cnt_in;
            fifo_rst_in     = 1'b0;
        end

        // Begin framebuffer reading only after reset and drain timing completes.
        if (rd_start_pending_ff && (fifo_rst_cnt_ff == 5'd0) && (drain_cnt_ff == 8'd0)) begin
            rd_active_in        = 1'b1;
            rd_start_pending_in = 1'b0;
        end
        else begin
            rd_active_in        = rd_active_in;
            rd_start_pending_in = rd_start_pending_in;
        end

        //--------------------------------------------------------------------------
        // Main DDR command FSM
        //--------------------------------------------------------------------------
        case (state_ff)

            //==================================================================
            // S_INIT
            //
            // Wait for MIG calibration, then begin clearing both framebuffers.
            //==================================================================
            S_INIT: begin
                if (init_calib_complete) begin
                    app_addr_in   = 27'd0;
                    clear_addr_in = 27'd0;
                    app_cmd_in    = CMD_WRITE;
                    app_en_in     = 1'b1;
                    state_in      = S_CLEAR_CMD;
                end
                else begin
                    app_addr_in   = app_addr_in;
                    clear_addr_in = clear_addr_in;
                    app_cmd_in    = app_cmd_in;
                    app_en_in     = app_en_in;
                    state_in      = state_in;
                end
            end

            //==================================================================
            // S_CLEAR_CMD
            //
            // Issue one clear-write command and wait for MIG command acceptance.
            //==================================================================
            S_CLEAR_CMD: begin
                if (app_rdy) begin
                    app_en_in = 1'b0;
                    state_in  = S_CLEAR_D0;
                end
                else begin
                    app_en_in = app_en_in;
                    state_in  = state_in;
                end
            end

            //==================================================================
            // S_CLEAR_D0
            //
            // Wait for the MIG write-data path, then begin a zero-data write.
            //==================================================================
            S_CLEAR_D0: begin
                if (app_wdf_rdy) begin
                    app_wdf_data_in = 64'h0000_0000_0000_0000;
                    app_wdf_mask_in = 8'h00;
                    app_wdf_wren_in = 1'b1;
                    app_wdf_end_in  = 1'b0;
                    state_in        = S_CLEAR_D1;
                end
                else begin
                    app_wdf_data_in = app_wdf_data_in;
                    app_wdf_mask_in = app_wdf_mask_in;
                    app_wdf_wren_in = app_wdf_wren_in;
                    app_wdf_end_in  = app_wdf_end_in;
                    state_in        = state_in;
                end
            end

            //==================================================================
            // S_CLEAR_D1
            //
            // Finish one zero-data write and advance the clear address/count.
            //==================================================================
            S_CLEAR_D1: begin
                app_wdf_data_in = 64'h0000_0000_0000_0000;
                app_wdf_mask_in = 8'h00;
                app_wdf_wren_in = 1'b1;
                app_wdf_end_in  = 1'b1;

                clear_count_in  = clear_count_ff + 16'd1;
                clear_addr_in   = clear_addr_ff + ADDR_STEP;

                state_in        = S_CLEAR_NEXT;
            end

            //==================================================================
            // S_CLEAR_NEXT
            //
            // Stop the write-data strobe and either continue clearing or enter
            // normal operation.
            //==================================================================
            S_CLEAR_NEXT: begin
                app_wdf_wren_in = 1'b0;

                if (clear_count_ff == TOTAL_CLEAR) begin
                    ready_in = 1'b1;
                    state_in = S_IDLE;
                end
                else begin
                    app_addr_in = clear_addr_ff;
                    app_cmd_in  = CMD_WRITE;
                    app_en_in   = 1'b1;
                    state_in    = S_CLEAR_CMD;
                end
            end

            //==================================================================
            // S_IDLE
            //
            // Service one available DDR task. Framebuffer reads get priority,
            // followed by renderer writes, prime reads, and prime writes.
            //==================================================================
            S_IDLE: begin
                if (rd_active_ff && !fifo_full && !rd_in_flight_ff) begin
                    app_addr_in = rd_addr_ff;
                    app_cmd_in  = CMD_READ;
                    app_en_in   = 1'b1;
                    state_in    = S_RD_CMD;
                end
                else if (wr_pending) begin
                    app_addr_in = wr_addr_lat;
                    app_cmd_in  = CMD_WRITE;
                    app_en_in   = 1'b1;
                    state_in    = S_WR_CMD;
                end
                else if (prime_rd_pending && !prime_rd_in_flight_ff) begin
                    app_addr_in = prime_rd_word_addr_w;
                    app_cmd_in  = CMD_READ;
                    app_en_in   = 1'b1;
                    state_in    = S_PRIME_RD_CMD;
                end
                else if (prime_wr_pending) begin
                    app_addr_in = prime_wr_word_addr_w;
                    app_cmd_in  = CMD_WRITE;
                    app_en_in   = 1'b1;
                    state_in    = S_PRIME_WR_CMD;
                end
                else begin
                    app_addr_in = app_addr_in;
                    app_cmd_in  = app_cmd_in;
                    app_en_in   = app_en_in;
                    state_in    = state_in;
                end
            end

            //==================================================================
            // S_RD_CMD
            //
            // Wait for MIG to accept one framebuffer read command.
            //==================================================================
            S_RD_CMD: begin
                if (app_rdy) begin
                    app_en_in       = 1'b0;
                    rd_in_flight_in = 1'b1;
                    rd_addr_in      = rd_addr_ff + ADDR_STEP;
                    rd_count_in     = rd_count_ff + 15'd1;

                    if (rd_count_ff == FRAME_WORDS - 15'd1) begin
                        rd_active_in = 1'b0;
                    end
                    else begin
                        rd_active_in = rd_active_in;
                    end

                    state_in = S_RD_WAIT;
                end
                else begin
                    app_en_in       = app_en_in;
                    rd_in_flight_in = rd_in_flight_in;
                    rd_addr_in      = rd_addr_in;
                    rd_count_in     = rd_count_in;
                    rd_active_in    = rd_active_in;
                    state_in        = state_in;
                end
            end

            //==================================================================
            // S_RD_WAIT
            //
            // Wait until the returned framebuffer read data has completed.
            //==================================================================
            S_RD_WAIT: begin
                if (!rd_in_flight_ff) begin
                    state_in = S_IDLE;
                end
                else begin
                    state_in = state_in;
                end
            end

            //==================================================================
            // S_WR_CMD
            //
            // Wait for MIG to accept one renderer write command.
            //==================================================================
            S_WR_CMD: begin
                if (app_rdy) begin
                    app_en_in = 1'b0;
                    state_in  = S_WR_D0;
                end
                else begin
                    app_en_in = app_en_in;
                    state_in  = state_in;
                end
            end

            //==================================================================
            // S_WR_D0
            //
            // Wait for the write-data path, then present renderer write data.
            //==================================================================
            S_WR_D0: begin
                if (app_wdf_rdy) begin
                    app_wdf_data_in = wr_data_lat;
                    app_wdf_mask_in = 8'h00;
                    app_wdf_wren_in = 1'b1;
                    app_wdf_end_in  = 1'b0;
                    state_in        = S_WR_D1;
                end
                else begin
                    app_wdf_data_in = app_wdf_data_in;
                    app_wdf_mask_in = app_wdf_mask_in;
                    app_wdf_wren_in = app_wdf_wren_in;
                    app_wdf_end_in  = app_wdf_end_in;
                    state_in        = state_in;
                end
            end

            //==================================================================
            // S_WR_D1
            //
            // Finish the single 64-bit renderer write beat.
            //==================================================================
            S_WR_D1: begin
                app_wdf_data_in = wr_data_lat;
                app_wdf_mask_in = 8'h00;
                app_wdf_wren_in = 1'b1;
                app_wdf_end_in  = 1'b1;
                state_in        = S_WR_NEXT;
            end

            //==================================================================
            // S_WR_NEXT
            //
            // Deassert the write-data strobe and return to idle. The completion
            // pulse is generated from state_ff == S_WR_NEXT.
            //==================================================================
            S_WR_NEXT: begin
                app_wdf_wren_in = 1'b0;
                state_in        = S_IDLE;
            end

            //==================================================================
            // S_PRIME_RD_CMD
            //
            // Issue one DDR read from the reserved prime-storage region.
            //==================================================================
            S_PRIME_RD_CMD: begin
                if (app_rdy) begin
                    app_en_in              = 1'b0;
                    prime_rd_in_flight_in  = 1'b1;
                    state_in               = S_PRIME_RD_WAIT;
                end
                else begin
                    app_en_in              = app_en_in;
                    prime_rd_in_flight_in  = prime_rd_in_flight_in;
                    state_in               = state_in;
                end
            end

            //==================================================================
            // S_PRIME_RD_WAIT
            //
            // Wait until prime read data returns on the MIG read channel.
            //==================================================================
            S_PRIME_RD_WAIT: begin
                if (!prime_rd_in_flight_ff) begin
                    state_in = S_IDLE;
                end
                else begin
                    state_in = state_in;
                end
            end

            //==================================================================
            // S_PRIME_WR_CMD
            //
            // Issue one DDR write into the reserved prime-storage region.
            //==================================================================
            S_PRIME_WR_CMD: begin
                if (app_rdy) begin
                    app_en_in = 1'b0;
                    state_in  = S_PRIME_WR_D0;
                end
                else begin
                    app_en_in = app_en_in;
                    state_in  = state_in;
                end
            end

            //==================================================================
            // S_PRIME_WR_D0
            //
            // Write one prime value into one 64-bit DDR word.
            //==================================================================
            S_PRIME_WR_D0: begin
                if (app_wdf_rdy) begin
                    app_wdf_data_in = {32'd0, prime_wr_data_lat};
                    app_wdf_mask_in = 8'hF0;
                    app_wdf_wren_in = 1'b1;
                    app_wdf_end_in  = 1'b1;
                    state_in        = S_PRIME_WR_NEXT;
                end
                else begin
                    app_wdf_data_in = app_wdf_data_in;
                    app_wdf_mask_in = app_wdf_mask_in;
                    app_wdf_wren_in = app_wdf_wren_in;
                    app_wdf_end_in  = app_wdf_end_in;
                    state_in        = state_in;
                end
            end

            //==================================================================
            // S_PRIME_WR_NEXT
            //
            // Deassert prime write strobes and return to idle.
            //==================================================================
            S_PRIME_WR_NEXT: begin
                app_wdf_wren_in = 1'b0;
                app_wdf_end_in  = 1'b0;
                state_in        = S_IDLE;
            end

            //==================================================================
            // Unknown state recovery
            //==================================================================
            default: begin
                state_in = S_INIT;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Sequential state update
    //
    // All registered FSM, FIFO, framebuffer read, clear, prime-read, and MIG
    // output state updates on ui_clk.
    //--------------------------------------------------------------------------
    always @(posedge ui_clk) begin
        // Reset all engine state and MIG outputs.
        if (ui_rst) begin
            state_ff              <= S_INIT;
            ready                 <= 1'b0;

            fifo_wr_data          <= 64'd0;
            fifo_wr_en            <= 1'b0;
            fifo_rst              <= 1'b0;

            fifo_rst_cnt_ff       <= 5'd0;
            drain_cnt_ff          <= 8'd0;

            rd_addr_ff            <= 27'd0;
            rd_count_ff           <= 15'd0;
            rd_active_ff          <= 1'b0;
            rd_in_flight_ff       <= 1'b0;
            rd_start_pending_ff   <= 1'b0;

            clear_addr_ff         <= 27'd0;
            clear_count_ff        <= 16'd0;

            prime_rd_data         <= 32'd0;
            prime_rd_data_valid   <= 1'b0;
            prime_rd_in_flight_ff <= 1'b0;

            app_addr              <= 27'd0;
            app_cmd               <= CMD_WRITE;
            app_en                <= 1'b0;
            app_wdf_data          <= 64'd0;
            app_wdf_end           <= 1'b0;
            app_wdf_mask          <= 8'h00;
            app_wdf_wren          <= 1'b0;
        end
        // Normal operation loads all computed next-state values.
        else begin
            state_ff              <= state_in;
            ready                 <= ready_in;

            fifo_wr_data          <= fifo_wr_data_in;
            fifo_wr_en            <= fifo_wr_en_in;
            fifo_rst              <= fifo_rst_in;

            fifo_rst_cnt_ff       <= fifo_rst_cnt_in;
            drain_cnt_ff          <= drain_cnt_in;

            rd_addr_ff            <= rd_addr_in;
            rd_count_ff           <= rd_count_in;
            rd_active_ff          <= rd_active_in;
            rd_in_flight_ff       <= rd_in_flight_in;
            rd_start_pending_ff   <= rd_start_pending_in;

            clear_addr_ff         <= clear_addr_in;
            clear_count_ff        <= clear_count_in;

            prime_rd_data         <= prime_rd_data_in;
            prime_rd_data_valid   <= prime_rd_data_valid_in;
            prime_rd_in_flight_ff <= prime_rd_in_flight_in;

            app_addr              <= app_addr_in;
            app_cmd               <= app_cmd_in;
            app_en                <= app_en_in;
            app_wdf_data          <= app_wdf_data_in;
            app_wdf_end           <= app_wdf_end_in;
            app_wdf_mask          <= app_wdf_mask_in;
            app_wdf_wren          <= app_wdf_wren_in;
        end
    end

endmodule