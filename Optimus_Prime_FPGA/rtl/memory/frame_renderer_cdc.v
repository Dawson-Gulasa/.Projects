`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// frame_renderer_cdc.v
//
// Purpose:
//   Synchronize asynchronous/toggle-based control signals into the clk_cpu
//   domain and generate clean one-cycle control pulses for the renderer.
//
// Inputs:
//   ready_toggle   : Toggle from DDR controller when ready first rises
//   frame_done_ack : Toggle from DDR controller when buffer swap completes
//   back_buf_base  : Back-buffer base address from DDR controller
//   wr_ack         : Toggle-based write acknowledge from DDR controller
//   values_ready   : Indicates display values are valid and may be rendered
//
// Outputs:
//   frame_start       : One-cycle frame-start request in clk_cpu domain
//   back_base         : Synchronized back-buffer base address
//   wr_ack_pulse      : One-cycle pulse when wr_ack toggles
//   debug_fda_pending : Debug visibility of pending frame-start request
//   debug_fda_sync2   : Debug visibility of synchronized frame_done_ack
//
// Notes:
//   - ready_toggle, frame_done_ack, and wr_ack are all toggle-style CDC signals.
//   - Each toggle signal is synchronized through two flops before pulse detect.
//   - back_buf_base is synchronized through a two-stage bus pipeline.
//   - A one-cycle holdoff is inserted after a frame-start event so the
//     synchronized back_buf_base has time to settle before frame_start is
//     asserted to the renderer.
//------------------------------------------------------------------------------
module frame_renderer_cdc (
    input  wire        clk_cpu,
    input  wire        resetn,

    input  wire        ready_toggle,
    input  wire        frame_done_ack,
    input  wire [26:0] back_buf_base,
    input  wire        wr_ack,
    input  wire        values_ready,

    output wire        frame_start,
    output wire [26:0] back_base,
    output wire        wr_ack_pulse,
    output wire        debug_fda_pending,
    output wire        debug_fda_sync2
);

    //--------------------------------------------------------------------------
    // ready_toggle synchronizer + pulse detect
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg rp_sync1_ff;
    (* ASYNC_REG = "TRUE" *) reg rp_sync2_ff;
    reg                      rp_prev_ff;

    //--------------------------------------------------------------------------
    // frame_done_ack synchronizer + pulse detect
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg fda_sync1_ff;
    (* ASYNC_REG = "TRUE" *) reg fda_sync2_ff;
    reg                      fda_prev_ff;

    //--------------------------------------------------------------------------
    // wr_ack synchronizer + pulse detect
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg wr_ack_sync1_ff;
    (* ASYNC_REG = "TRUE" *) reg wr_ack_sync2_ff;
    reg                      wr_ack_prev_ff;

    //--------------------------------------------------------------------------
    // back_buf_base synchronizer
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [26:0] bbb_sync1_ff;
    (* ASYNC_REG = "TRUE" *) reg [26:0] bbb_sync2_ff;

    //--------------------------------------------------------------------------
    // Pending frame-start request + one-cycle holdoff
    //--------------------------------------------------------------------------
    reg fda_pending_ff;
    reg start_holdoff_ff;

    //--------------------------------------------------------------------------
    // Pulse detect wires
    //--------------------------------------------------------------------------
    wire rp_pulse_w;
    wire fda_pulse_w;
    wire wr_ack_toggle_w;

    assign rp_pulse_w      = rp_sync2_ff ^ rp_prev_ff;
    assign fda_pulse_w     = fda_sync2_ff ^ fda_prev_ff;
    assign wr_ack_toggle_w = wr_ack_sync2_ff ^ wr_ack_prev_ff;

    //--------------------------------------------------------------------------
    // Outputs
    //--------------------------------------------------------------------------
    assign wr_ack_pulse      = wr_ack_toggle_w;
    assign back_base         = bbb_sync2_ff;
    assign frame_start       = fda_pending_ff && !start_holdoff_ff && values_ready;
    assign debug_fda_pending = fda_pending_ff;
    assign debug_fda_sync2   = fda_sync2_ff;

    //--------------------------------------------------------------------------
    // Sequential synchronizers and pending-frame logic
    //--------------------------------------------------------------------------
    always @(posedge clk_cpu) begin
        // Top of major if-then-else:
        // Synchronous active-low reset initializes all CDC flops and pending
        // control state.
        if (!resetn) begin
            rp_sync1_ff      <= 1'b0;
            rp_sync2_ff      <= 1'b0;
            rp_prev_ff       <= 1'b0;

            fda_sync1_ff     <= 1'b0;
            fda_sync2_ff     <= 1'b0;
            fda_prev_ff      <= 1'b0;

            wr_ack_sync1_ff  <= 1'b0;
            wr_ack_sync2_ff  <= 1'b0;
            wr_ack_prev_ff   <= 1'b0;

            bbb_sync1_ff     <= 27'd153600;
            bbb_sync2_ff     <= 27'd153600;

            fda_pending_ff   <= 1'b0;
            start_holdoff_ff <= 1'b0;
        end
        else begin
            //------------------------------------------------------------------
            // Synchronize toggle inputs into clk_cpu domain
            //------------------------------------------------------------------
            rp_sync1_ff     <= ready_toggle;
            rp_sync2_ff     <= rp_sync1_ff;
            rp_prev_ff      <= rp_sync2_ff;

            fda_sync1_ff    <= frame_done_ack;
            fda_sync2_ff    <= fda_sync1_ff;
            fda_prev_ff     <= fda_sync2_ff;

            wr_ack_sync1_ff <= wr_ack;
            wr_ack_sync2_ff <= wr_ack_sync1_ff;
            wr_ack_prev_ff  <= wr_ack_sync2_ff;

            //------------------------------------------------------------------
            // Synchronize multi-bit back-buffer base bus
            //------------------------------------------------------------------
            bbb_sync1_ff    <= back_buf_base;
            bbb_sync2_ff    <= bbb_sync1_ff;

            //------------------------------------------------------------------
            // Frame-start request control
            //
            // Arm a pending frame request on:
            //   - the first ready toggle
            //   - any subsequent frame_done_ack toggle
            //
            // Also arm a one-cycle holdoff so the synchronized back-buffer base
            // is stable before frame_start is asserted.
            //------------------------------------------------------------------
            if (rp_pulse_w || fda_pulse_w) begin
                fda_pending_ff   <= 1'b1;
                start_holdoff_ff <= 1'b1;
            end
            else if (start_holdoff_ff) begin
                start_holdoff_ff <= 1'b0;
                fda_pending_ff   <= fda_pending_ff;
            end
            else if (fda_pending_ff && values_ready) begin
                fda_pending_ff   <= 1'b0;
                start_holdoff_ff <= start_holdoff_ff;
            end
            else begin
                fda_pending_ff   <= fda_pending_ff;
                start_holdoff_ff <= start_holdoff_ff;
            end
        end
    end

endmodule