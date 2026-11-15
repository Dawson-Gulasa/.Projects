// div_ucode_rom.v
// Read-only storage for the four assembled SCC division microinstructions.
//
// Responsibilities:
// - Load the byte-oriented image generated from assembly/ucode_div.asm.
// - Convert a two-bit microinstruction word address to a byte address.
// - Present the selected 32-bit instruction to div_controller.v.
//
// Microprogram layout (one 32-bit word per step):
//   0: CLR R12 - initialization marker
//   1: DIV R0,R0,R0 - signed division marker
//   2: NOP - quotient writeback marker
//   3: HALT - remainder/completion marker
//
// The ROM instruction fields are control markers, NOT additional architectural
// instructions. The controller must decode and use them before this ROM can
// be considered part of the active division control path.

module div_ucode_rom (
    input  wire [1:0] div_ucode_addr_v,
    output wire [31:0] div_ucode_inst_v
);

    // Four 32-bit instructions stored as 16 consecutive bytes.
    // These entries are initialized once and are never written at runtime.
    reg [7:0] memory [0:15];

    initial begin
        $readmemh("div_ucode.mem", memory);
    end

    // Multiply the word index by four using a two-bit left shift.
    wire [3:0] byte_addr_v;
    assign byte_addr_v = {div_ucode_addr_v, 2'b00};

    // Rebuild one instruction in big-endian instruction-byte order.
    // For word index k, read bytes 4*k through 4*k+3.
    assign div_ucode_inst_v = {
        memory[byte_addr_v],
        memory[byte_addr_v + 4'd1],
        memory[byte_addr_v + 4'd2],
        memory[byte_addr_v + 4'd3]
    };

endmodule
