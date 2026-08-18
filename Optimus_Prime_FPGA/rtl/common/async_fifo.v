`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// async_fifo.v
//
// Purpose:
//   Dual-clock asynchronous FIFO used to move data safely between two unrelated
//   clock domains.
//
//   The write side runs on wr_clk and the read side runs on rd_clk. Because
//   binary counters can glitch when sampled across clock domains, this FIFO uses
//   Gray-coded pointers and two-flop synchronizers for full/empty detection.
//
// FIFO algorithm:
//   1) Write domain maintains a binary write pointer for memory addressing.
//   2) Read domain maintains a binary read pointer for memory addressing.
//   3) Each binary pointer is converted to Gray code.
//   4) Gray-coded pointers cross clock domains through two synchronizer flops.
//   5) Read side asserts empty when the next read pointer equals the synchronized
//      write pointer.
//   6) Write side asserts full when the next write pointer equals the synchronized
//      read pointer with the two MSBs inverted.
//
// Example:
//   If the write pointer catches up to the read pointer after wrapping around
//   the FIFO depth, the full comparison detects that the FIFO has no free slots
//   and wr_full asserts. This prevents overwriting unread data.
//
// Interface behavior:
//   - wr_en writes wr_data only when wr_full is low.
//   - rd_en advances the read pointer only when rd_empty is low.
//   - rd_data is valid when rd_empty is low.
//   - wr_rst and rd_rst are active-high resets in their own clock domains.
//
// Notes:
//   - FIFO depth is 2^ADDR_WIDTH.
//   - Memory write is synchronous to wr_clk.
//   - Memory read is asynchronous/combinational from the current read pointer.
//------------------------------------------------------------------------------

module async_fifo #(
    parameter DATA_WIDTH = 64, // Width of each FIFO entry
    parameter ADDR_WIDTH = 4   // FIFO depth = 2^ADDR_WIDTH
)(
    //--------------------------------------------------------------------------
    // Write side, wr_clk domain
    //--------------------------------------------------------------------------
    input  wire                    wr_clk,   // Write-domain clock
    input  wire                    wr_rst,   // Active-high reset synchronized to wr_clk
    input  wire [DATA_WIDTH-1:0]   wr_data,  // Data to push into FIFO
    input  wire                    wr_en,    // Write enable request
    output wire                    wr_full,  // High when FIFO cannot accept data

    //--------------------------------------------------------------------------
    // Read side, rd_clk domain
    //--------------------------------------------------------------------------
    input  wire                    rd_clk,   // Read-domain clock
    input  wire                    rd_rst,   // Active-high reset synchronized to rd_clk
    output wire [DATA_WIDTH-1:0]   rd_data,  // Data at current read pointer
    input  wire                    rd_en,    // Read enable request
    output wire                    rd_empty  // High when FIFO has no valid data
);

    //--------------------------------------------------------------------------
    // FIFO depth
    //--------------------------------------------------------------------------
    localparam DEPTH = 1 << ADDR_WIDTH;

    //--------------------------------------------------------------------------
    // Dual-port FIFO memory
    //
    // Write side:
    //   Data is written synchronously on wr_clk when wr_advance is true.
    //
    // Read side:
    //   rd_data is driven combinationally from the current read pointer.
    //--------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    //--------------------------------------------------------------------------
    // Cross-domain Gray pointer synchronizers
    //
    // The read pointer crosses into wr_clk for full detection.
    // The write pointer crosses into rd_clk for empty detection.
    //--------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2;

    //--------------------------------------------------------------------------
    // Write-domain pointer and full flag
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH:0] wr_ptr_bin;  // Binary write pointer used for memory address
    reg [ADDR_WIDTH:0] wr_ptr_gray; // Gray-coded write pointer for CDC
    reg                wr_full_ff;  // Registered full flag in wr_clk domain

    assign wr_full = wr_full_ff;

    //--------------------------------------------------------------------------
    // Read-domain pointer and empty flag
    //--------------------------------------------------------------------------
    reg [ADDR_WIDTH:0] rd_ptr_bin;  // Binary read pointer used for memory address
    reg [ADDR_WIDTH:0] rd_ptr_gray; // Gray-coded read pointer for CDC
    reg                rd_empty_ff; // Registered empty flag in rd_clk domain

    assign rd_empty = rd_empty_ff;

    //--------------------------------------------------------------------------
    // FIFO advance enables
    //
    // A write advances only when requested and not full.
    // A read advances only when requested and not empty.
    //--------------------------------------------------------------------------
    wire wr_advance = wr_en & ~wr_full_ff;
    wire rd_advance = rd_en & ~rd_empty_ff;

    //--------------------------------------------------------------------------
    // Next-pointer math
    //
    // The binary pointer increments when that side advances. The next Gray
    // pointer is computed from the next binary value:
    //
    //   gray = (binary >> 1) ^ binary
    //--------------------------------------------------------------------------
    wire [ADDR_WIDTH:0] wr_ptr_bin_next  = wr_ptr_bin + wr_advance;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    wire [ADDR_WIDTH:0] rd_ptr_bin_next  = rd_ptr_bin + rd_advance;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    //--------------------------------------------------------------------------
    // Full detection in write clock domain
    //
    // The FIFO is full when the next write pointer would equal the synchronized
    // read pointer with the two most significant bits inverted.
    //--------------------------------------------------------------------------
    wire wr_full_next =
        (wr_ptr_gray_next ==
            {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
              rd_gray_sync2[ADDR_WIDTH-2:0]});

    //--------------------------------------------------------------------------
    // Empty detection in read clock domain
    //
    // The FIFO is empty when the next read pointer equals the synchronized write
    // pointer.
    //--------------------------------------------------------------------------
    wire rd_empty_next = (rd_ptr_gray_next == wr_gray_sync2);

    //--------------------------------------------------------------------------
    // Asynchronous read data
    //
    // rd_data reflects the memory word at the current read pointer. External
    // logic should only treat rd_data as valid when rd_empty is low.
    //--------------------------------------------------------------------------
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    //--------------------------------------------------------------------------
    // FIFO memory write
    //
    // Writes happen only when wr_advance is true, meaning a write was requested
    // and space was available.
    //--------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        // Store the new word into the current write address.
        if (wr_advance) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
        // No write this cycle; memory contents are held.
        else begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= mem[wr_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end

    //--------------------------------------------------------------------------
    // Write-domain pointer and full-flag update
    //
    // Updates the write pointer and full flag using the synchronized read
    // pointer from the read domain.
    //--------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        // Reset write pointer and clear full flag.
        if (wr_rst) begin
            wr_ptr_bin  <= { (ADDR_WIDTH+1){1'b0} };
            wr_ptr_gray <= { (ADDR_WIDTH+1){1'b0} };
            wr_full_ff  <= 1'b0;
        end
        // Normal write-side pointer update.
        else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            wr_full_ff  <= wr_full_next;
        end
    end

    //--------------------------------------------------------------------------
    // Synchronize read Gray pointer into write clock domain
    //
    // This allows the write side to determine whether the FIFO is full.
    //--------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        // Clear synchronized read pointer during write-domain reset.
        if (wr_rst) begin
            rd_gray_sync1 <= { (ADDR_WIDTH+1){1'b0} };
            rd_gray_sync2 <= { (ADDR_WIDTH+1){1'b0} };
        end
        // Two-flop synchronizer for the read Gray pointer.
        else begin
            rd_gray_sync1 <= rd_ptr_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    //--------------------------------------------------------------------------
    // Read-domain pointer and empty-flag update
    //
    // Updates the read pointer and empty flag using the synchronized write
    // pointer from the write domain.
    //--------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        // Reset read pointer and mark FIFO empty.
        if (rd_rst) begin
            rd_ptr_bin  <= { (ADDR_WIDTH+1){1'b0} };
            rd_ptr_gray <= { (ADDR_WIDTH+1){1'b0} };
            rd_empty_ff <= 1'b1;
        end
        // Normal read-side pointer update.
        else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            rd_empty_ff <= rd_empty_next;
        end
    end

    //--------------------------------------------------------------------------
    // Synchronize write Gray pointer into read clock domain
    //
    // This allows the read side to determine whether the FIFO is empty.
    //--------------------------------------------------------------------------
    always @(posedge rd_clk) begin
        // Clear synchronized write pointer during read-domain reset.
        if (rd_rst) begin
            wr_gray_sync1 <= { (ADDR_WIDTH+1){1'b0} };
            wr_gray_sync2 <= { (ADDR_WIDTH+1){1'b0} };
        end
        // Two-flop synchronizer for the write Gray pointer.
        else begin
            wr_gray_sync1 <= wr_ptr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

endmodule