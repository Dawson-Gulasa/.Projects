`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// sync_ff.v
//
// Parameterized multi-bit 2-FF synchronizer for CDC (clock domain crossing).
// Safely transfers a slow-changing or quasi-static bus from one clock domain
// to another.  NOT suitable for gray-coded counters or pulse crossing — use
// pulse_sync for single-cycle events.
//------------------------------------------------------------------------------
module sync_ff #(
    parameter WIDTH     = 1,
    parameter RESET_VAL = 0
)(
    input  wire             dst_clk,
    input  wire             resetn,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);

    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync1_ff;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync2_ff;

    always @(posedge dst_clk) begin
        if (!resetn) begin
            sync1_ff <= RESET_VAL[WIDTH-1:0];
            sync2_ff <= RESET_VAL[WIDTH-1:0];
        end
        else begin
            sync1_ff <= d;
            sync2_ff <= sync1_ff;
        end
    end

    assign q = sync2_ff;

endmodule
