`timescale 1ns / 1ps
//----------------------------------------------------------------------------
// autobot_rom.v  --  32x32 monochrome bitmap ROM for menu corner logos
//
// Generated directly from the user-supplied 32x32 black/white Autobots sprite
// (1024 hex color samples, row-major).  '#000000' -> bit=1 (lit), every other
// color -> bit=0 (transparent).  Row 0 is topmost, bit 31 is leftmost pixel.
//
// screen_menu.v paints lit pixels as COL_RED and transparent pixels as the
// surrounding COL_NAVY background.
//----------------------------------------------------------------------------
module autobot_rom (
    input  wire [4:0]  row,
    output reg  [31:0] data
);
    always @(*) begin
        case (row)
            5'd0 : data = 32'h00000000;
            5'd1 : data = 32'h707FFE0E;
            5'd2 : data = 32'h7BFFFFDE;
            5'd3 : data = 32'h7BF81FDE;
            5'd4 : data = 32'h7BFC3FDE;
            5'd5 : data = 32'h7CFE7F3E;
            5'd6 : data = 32'h773FFCEE;
            5'd7 : data = 32'h31C7E38E;
            5'd8 : data = 32'h3E718E7C;
            5'd9 : data = 32'h33B66DCC;
            5'd10: data = 32'h3CF3EF3C;
            5'd11: data = 32'h3F3BCCFC;
            5'd12: data = 32'h0FDBDBF0;
            5'd13: data = 32'h37FBDFEC;
            5'd14: data = 32'h3BFBDF1C;
            5'd15: data = 32'h3803C01C;
            5'd16: data = 32'h3C03C03C;
            5'd17: data = 32'h3C0BD03C;
            5'd18: data = 32'h1F1BD8F8;
            5'd19: data = 32'h1FBBDDF8;
            5'd20: data = 32'h1FBBDDF8;
            5'd21: data = 32'h1FBBDDF8;
            5'd22: data = 32'h1FBBDDF8;
            5'd23: data = 32'h1FBBDDF8;
            5'd24: data = 32'h1FB81DF8;
            5'd25: data = 32'h1FBFFDF8;
            5'd26: data = 32'h1FBC3DF8;
            5'd27: data = 32'h0FBBDDF0;
            5'd28: data = 32'h03BBDDC0;
            5'd29: data = 32'h0033CC00;
            5'd30: data = 32'h0007E000;
            5'd31: data = 32'h00000000;
            default: data = 32'h00000000;
        endcase
    end
endmodule
