// ucode_rom.v
// Microcode read-only memory for multicycle signed
// multiplication instructions in the SCC processor
//
// Responsibilities:
// - Load the assembled microprogram from ucode.mem.
// - Store four 32-bit microinstructions as 16 bytes.
// - Accept a two-bit microinstruction word address.
// - Convert the word address into a byte-array address.
// - Reconstruct the selected 32-bit microinstruction.
// - Supply the instruction to the microcode controller.
//
// Design Notes:
// - The class assembler generates a byte-addressed image.
// - The ROM uses the same byte ordering as instruction memory.
// - Four microinstructions occupy 16 consecutive bytes.
// - The microcode controller determines the ROM address.
// - ROM reads are combinational and do not require a clock.
// - No architectural registers are stored in this module.
// - The controller, not the ROM, manages microcode sequencing.
//
// Microinstruction Layout:
// - Word 0: Bytes 0-3 -> Initialization operation.
// - Word 1: Bytes 4-7 -> Signed multiplication operation.
// - Word 2: Bytes 8-11 -> Lower-product writeback.
// - Word 3: Bytes 12-15 -> Upper-product writeback/completion

module ucode_rom (
    // Two-bit microinstruction address, expressed as a word index
    input wire [1:0] ucode_addr_v,

    // Selected 32-bit microinstruction supplied to the controller
    output wire [31:0] ucode_inst_v
);

//====================================
// MICROCODE READ-ONLY MEMORY STORAGE
//=====================================
// Store four 32-bit microinstructions as 16 individual bytes.
//
// The class assembler writes instruction data into a
// byte-addressed memory initialization file.
//
// Each consecutive group of four bytes represents one
// complete 32-bit microinstruction.
//
// Memory organization:
// - memory[0:3]   = Microinstruction 0
// - memory[4:7]   = Microinstruction 1
// - memory[8:11]  = Microinstruction 2
// - memory[12:15] = Microinstruction 3
//
// Although the array is declared as reg, it is not
// updated by any runtime clocked logic in this module

reg [7:0] memory [0:15];

//===============================
// MICROCODE ROM INITIALIZATION
//===============================
// Load the assembled microprogram once at simulation startup.
//
// The file ucode.mem must contain the expected byte-oriented
// machine-code image for the multiplication microprogram.
//
// The simulator resolves the relative filename from its
// current working directory.
//
// For the CP4 test commands, run the simulation from the
// CP4_EXE_COMPLETE directory containing ucode.mem.
//
// This initial block loads the ROM contents but does not
// implement a clocked state update.

initial begin
    $readmemh("ucode.mem", memory);
end

//==================================================
// MICROINSTRUCTION WORD-TO-BYTE ADDRESS CONVERSION
//====================================================
// The controller supplies a two-bit microinstruction index.
//
// Each microinstruction occupies four consecutive bytes.
// Therefore, multiply the word index by four to obtain
// the starting byte address.
//
// Concatenating two zero bits performs this conversion:
//
//   Word address 00 -> Byte address 0000 (0)
//   Word address 01 -> Byte address 0100 (4)
//   Word address 10 -> Byte address 1000 (8)
//   Word address 11 -> Byte address 1100 (12)
//
// The resulting four-bit address identifies the first
// byte of the selected microinstruction.
//
// The output is combinational and does not require
// an additional clock cycle.

wire [3:0] byte_addr_v;

assign byte_addr_v = {ucode_addr_v, 2'b00};

//====================================
// COMBINATIONAL MICROINSTRUCTION READ
//======================================
// Reconstruct the 32-bit microinstruction from four
// consecutive bytes in the microcode memory array.
//
// Byte ordering:
// - First byte -> Instruction bits [31:24]
// - Second byte -> Instruction bits [23:16]
// - Third byte -> Instruction bits [15:8]
// - Fourth byte -> Instruction bits [7:0]
//
// This matches the byte ordering used by the SCC's
// instruction and data-memory simulation model.
//
// Every valid two-bit word address selects four bytes
// within the declared 16-byte ROM array.
//
// A continuous assignment ensures the output reflects
// the selected ROM contents without clocked storage.

assign ucode_inst_v = {
    memory[byte_addr_v],
    memory[byte_addr_v + 4'd1],
    memory[byte_addr_v + 4'd2],
    memory[byte_addr_v + 4'd3]
};

endmodule
