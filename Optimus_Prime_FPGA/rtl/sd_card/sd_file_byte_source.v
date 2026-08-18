`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// sd_file_byte_source.v
//
// Purpose:
//   Board-level SD file byte source wrapper for the current project.
//
// High-level behavior:
//   - Instantiates the older sd_file_reader module.
//   - Uses the on-board microSD physical pins directly.
//   - Reads bytes from a named file on the SD card.
//   - Exposes byte_valid / byte_out / stream_done for downstream parsing.
//
// Notes:
//   - This wrapper intentionally keeps the hierarchy clean by isolating the
//     old SD protocol stack from the rest of the current project.
//   - The downstream parser/feeder/test controller can treat this as a generic
//     byte-stream source.
//   - DAT1/DAT2/DAT3 are held high because sd_file_reader only uses sdclk,
//     sdcmd, and sddat0.
//   - sd_reset_n is actively driven low to enable FPGA-side SD slot access.
//------------------------------------------------------------------------------
module sd_file_byte_source #(
    parameter integer    FILE_NAME_LEN = 18,
    parameter [52*8-1:0] FILE_NAME     = "CSEE4280Primes.txt"
)(
    //--------------------------------------------------------------------------
    // Clock / reset
    //--------------------------------------------------------------------------
    input  wire       clk_sd,
    input  wire       resetn,

    //--------------------------------------------------------------------------
    // Physical microSD slot pins
    //--------------------------------------------------------------------------
    output wire       sd_clk,
    inout  wire       sd_cmd,
    input  wire       sd_dat0,
    output wire       sd_dat1,
    output wire       sd_dat2,
    output wire       sd_dat3,
    output wire       sd_reset_n,
    input  wire       sd_card_detect,

    //--------------------------------------------------------------------------
    // Byte-stream output (clk_sd domain)
    //--------------------------------------------------------------------------
    output wire       byte_valid,
    output wire [7:0] byte_out,
    output wire       stream_done,

    //--------------------------------------------------------------------------
    // Status/debug
    //--------------------------------------------------------------------------
    output wire       file_found,
    output wire [2:0] filesystem_state,
    output wire [3:0] card_stat,
    output wire       card_inserted
);

    //--------------------------------------------------------------------------
    // Unused outputs from sd_file_reader
    //--------------------------------------------------------------------------
    wire [1:0] card_type_unused_w;
    wire [1:0] filesystem_type_unused_w;

    //--------------------------------------------------------------------------
    // Physical SD slot control
    //
    // Keep the slot enabled for FPGA-side access. The old SD protocol path only
    // uses sdclk, sdcmd, and sddat0, so hold DAT1..DAT3 high.
    //--------------------------------------------------------------------------
    assign sd_reset_n    = 1'b0;
    assign sd_dat1       = 1'b1;
    assign sd_dat2       = 1'b1;
    assign sd_dat3       = 1'b1;

    // Card-detect is expected active-low on this board path.
    assign card_inserted = ~sd_card_detect;

    //--------------------------------------------------------------------------
    // SD file reader instance
    //--------------------------------------------------------------------------
    sd_file_reader #(
        .FILE_NAME_LEN (FILE_NAME_LEN),
        .FILE_NAME     (FILE_NAME),
        .CLK_DIV       (3'd3),
        .SIMULATE      (0)
    ) u_sd_file_reader (
        .rstn            (resetn),
        .clk             (clk_sd),
        .sdclk           (sd_clk),
        .sdcmd           (sd_cmd),
        .sddat0          (sd_dat0),
        .card_stat       (card_stat),
        .card_type       (card_type_unused_w),
        .filesystem_type (filesystem_type_unused_w),
        .file_found      (file_found),
        .outen           (byte_valid),
        .outbyte         (byte_out),
        .filesystem_state(filesystem_state)
    );

    //--------------------------------------------------------------------------
    // Stream-done indication
    //
    // The old file reader uses filesystem_state == DONE (3'd6) as its terminal
    // state. Expose that as a simple downstream end-of-stream level.
    //--------------------------------------------------------------------------
    assign stream_done = (filesystem_state == 3'd6);

endmodule