`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// font_rom_ascii.v
//
// Purpose:
//   8x16 character ROM for printable ASCII 0x20 (space) through 0x7E (~).
//   Characters outside this range render as blank (all zeros).
//
// Interface summary:
//   char_code : 7-bit ASCII value (only bits [6:5] need to be non-zero for
//               printable range; values below 0x20 produce blank output).
//   row       : Glyph row 0..15 (0 = top, 15 = bottom).
//   pixel_row : Registered 8-bit pixel pattern. Bit [7] is the leftmost pixel.
//
// Storage map:
//   128 characters x 16 rows = 2048 bytes.
//   Address = { char_code[6:0], row[3:0] }  (11-bit address).
//   Initialized from font_rom_ascii.mem (one hex byte per line).
//
// Timing:
//   Output is registered. Callers must account for one-cycle read latency.
//------------------------------------------------------------------------------
module font_rom_ascii (
    input  wire        clk,          // System clock
    input  wire [6:0]  char_code,    // ASCII character code (0x20..0x7E)
    input  wire [3:0]  row,          // Glyph row within character (0..15)
    output reg  [7:0]  pixel_row     // Registered pixel row output, bit7=leftmost
);

    // -------------------------------------------------------------------------
    // ROM storage: 2048 entries of 8 bits
    // -------------------------------------------------------------------------
    reg [7:0] rom_r [0:2047];

    // -------------------------------------------------------------------------
    // ROM initialization from .mem file
    // -------------------------------------------------------------------------
    initial begin
        $readmemh("font_rom_ascii.mem", rom_r);
    end

    // -------------------------------------------------------------------------
    // Registered ROM read
    //
    // Address is formed from the full 7-bit char_code and 4-bit row.
    // Characters below 0x20 will map into the lower 32 entries which are
    // defined as all-zero blanks in the .mem file.
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        pixel_row <= rom_r[{char_code, row}];
    end

endmodule
