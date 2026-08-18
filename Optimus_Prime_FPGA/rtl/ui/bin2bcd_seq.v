`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// bin2bcd_seq.v - Sequential binary-to-BCD converter (double-dabble)
//
// Converts a 27-bit binary value to 8 BCD digits in 28 clock cycles.
// Uses only shifts and conditional add-3 — ZERO division hardware.
//
// bcd output: [31:28]=MSD (digit 0), [3:0]=LSD (digit 7)
//------------------------------------------------------------------------------
module bin2bcd_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [26:0] bin,
    input  wire        start,
    output reg  [31:0] bcd,
    output reg         done,
    output wire        ready
);

    reg [58:0] sr;     // {32-bit BCD, 27-bit binary}
    reg [4:0]  step;
    reg        busy;

    assign ready = ~busy;

    // --- One double-dabble iteration (combinational) ---
    // Add 3 to each BCD nibble >= 5, then shift left by 1.
    reg [58:0] adj;
    always @(*) begin
        adj = sr;
        if (adj[30:27] >= 4'd5) adj[30:27] = adj[30:27] + 4'd3;
        if (adj[34:31] >= 4'd5) adj[34:31] = adj[34:31] + 4'd3;
        if (adj[38:35] >= 4'd5) adj[38:35] = adj[38:35] + 4'd3;
        if (adj[42:39] >= 4'd5) adj[42:39] = adj[42:39] + 4'd3;
        if (adj[46:43] >= 4'd5) adj[46:43] = adj[46:43] + 4'd3;
        if (adj[50:47] >= 4'd5) adj[50:47] = adj[50:47] + 4'd3;
        if (adj[54:51] >= 4'd5) adj[54:51] = adj[54:51] + 4'd3;
        if (adj[58:55] >= 4'd5) adj[58:55] = adj[58:55] + 4'd3;
    end
    wire [58:0] shifted = adj << 1;

    // --- Sequential control ---
    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            step <= 5'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                sr   <= {32'd0, bin};
                step <= 5'd0;
                busy <= 1'b1;
            end else if (busy) begin
                sr   <= shifted;
                step <= step + 5'd1;
                if (step == 5'd26) begin
                    busy <= 1'b0;
                    bcd  <= shifted[58:27];
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
