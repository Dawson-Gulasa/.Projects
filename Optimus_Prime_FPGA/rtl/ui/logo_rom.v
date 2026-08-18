`timescale 1ns / 1ps
//----------------------------------------------------------------------------
// logo_rom.v  --  256x32 monochrome bitmap ROM for menu title logo
// Generated from LOGO_256x32.bmp.  bit 255 = leftmost pixel of the row.
//----------------------------------------------------------------------------
module logo_rom (
    input  wire  [4:0]   row,
    output reg   [255:0] data
);
    always @(*) begin
        case (row)
            5'd0 : data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd1 : data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd2 : data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd3 : data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd4 : data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd5 : data = 256'h01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80;
            5'd6 : data = 256'h01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80;
            5'd7 : data = 256'h01fe00ffc0003e0000c301fe01c3fc3fc07fffe0007f8007f8703fc00f000080;
            5'd8 : data = 256'h01f0001fc0001e0000c301fe01c3fc3e001fffe0000f8000f8703fc00f000080;
            5'd9 : data = 256'h01f0001fc0001e0000c301fe01c3fc3e001fffe0000f8000f8701fc00f000080;
            5'd10: data = 256'h01e0000fc0000e0000c301fe01c3fc3e0007ffe000078000f8701fc00f000080;
            5'd11: data = 256'h01e0fe0fc3fe0ffc3fc300f001c3fc3c1f87ffe1ff0787f078700f800f1fff80;
            5'd12: data = 256'h0181ff07c3fe0ffc3fc300f001c3fc3c3f87ffe3ff078ff878700f800f0fff80;
            5'd13: data = 256'h0187ff87c3fe0ffc3fc300f041c3fc3e1fffffe3ff0787f078700f8c0f0fff80;
            5'd14: data = 256'h0187ff87c0000ffc3fc3083041c3fc3e007fffe000078000f870870c0f000780;
            5'd15: data = 256'h0187ff87c0001ffc3fc3082041c3fc3f801fffe0000f8003f870840c0f000780;
            5'd16: data = 256'h0187ff87c0001ffc3fc30c2041c3fc3f801fffe0000f8003f870c40c0f000780;
            5'd17: data = 256'h0187ff87c001fffc3fc30c21c1c3fc3ff807ffe000ff800ff870c43c0f000780;
            5'd18: data = 256'h0187ff87c3fffffc3fc30e01c1c3fc3fff83ffe1ffff8707f870c03c0f0fff80;
            5'd19: data = 256'h0181ff07c3fffffc3fc30e01c1c1fc3c3fc3ffe1ffff8783f870c03c0f0fff80;
            5'd20: data = 256'h01e0fe0fc3fffffc3fc30e01c1e1f83c1f83ffe1ffff87c0f870f03c0f1fff80;
            5'd21: data = 256'h01e0000fc3fffffc3fc30f03c1e0003e0007ffe1ffff87f0f870f07c0f000080;
            5'd22: data = 256'h01f0001fc3fffffc3fc30f0fc1f8007e0007ffe1ffff87f07870f07c0f000080;
            5'd23: data = 256'h01f0001fc3fffffc3fc30f0fc1f8007e0007ffe1ffff87f07870f07c0f000080;
            5'd24: data = 256'h01fe00ffc3fffffc3fc30f0fc1fc03ffc03fffe07fff81f80870f07c0f000080;
            5'd25: data = 256'h01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80;
            5'd26: data = 256'h01ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80;
            5'd27: data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd28: data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd29: data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd30: data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            5'd31: data = 256'h0000000000000000000000000000000000000000000000000000000000000000;
            default: data = 256'h0;
        endcase
    end
endmodule
