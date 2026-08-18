`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// prime_storage_mem.v
//
// Purpose:
//   DDR2-backed storage adapter for prime results.
//
//   The prime subsystem expects a simple storage backend with write-enable,
//   read-enable, read-data, and read-data-valid behavior. This module preserves
//   that simple storage-style interface while forwarding the actual storage
//   operations to the external DDR2 bridge.
//
// Storage command algorithm:
//   1) While idle, accept one write or read command.
//   2) For a write, latch the address/data, pulse ddr_wr_req, and wait for
//      ddr_wr_ack.
//   3) For a read, latch the address, pulse ddr_rd_req, and wait for
//      ddr_rd_data_valid.
//   4) When read data returns, capture it and pulse rd_data_valid for one clock.
//   5) Return to idle and accept the next command.
//
// Example:
//   If wr_en is pulsed with wr_addr = 5 and wr_data = 17, this module pulses
//   ddr_wr_req with address 5 and data 17. It then waits until ddr_wr_ack
//   returns before accepting another storage command.
//
// Notes:
//   - This module runs in the CPU/subsystem clock domain.
//   - DDR clock-domain crossing is handled outside this module by
//     prime_ddr_bridge.v.
//   - Only one storage command is outstanding at a time.
//   - If wr_en and rd_en are asserted together while idle, write has priority.
//------------------------------------------------------------------------------

module prime_storage_mem #(
    parameter integer DATA_WIDTH = 32,    // Width of stored prime data
    parameter integer ADDR_WIDTH = 16,    // Width of storage address/index
    parameter integer DEPTH      = 65536  // Maximum logical storage depth
)(
    input  wire                    clk,                // CPU / subsystem clock
    input  wire                    rst_n,              // Active-low synchronized reset

    input  wire                    wr_en,              // One-clock write enable request
    input  wire [ADDR_WIDTH-1:0]   wr_addr,            // Write address/index
    input  wire [DATA_WIDTH-1:0]   wr_data,            // Write data value

    input  wire                    rd_en,              // One-clock read enable request
    input  wire [ADDR_WIDTH-1:0]   rd_addr,            // Read address/index

    output wire [DATA_WIDTH-1:0]   rd_data,            // Returned read data
    output wire                    rd_data_valid,      // One-clock pulse when rd_data is valid
    output wire                    cmd_ready,          // High when a new command can be accepted

    //--------------------------------------------------------------------------
    // DDR2 bridge interface
    //--------------------------------------------------------------------------
    output wire                    ddr_wr_req,         // One-clock DDR write request
    output wire [ADDR_WIDTH-1:0]   ddr_wr_addr,        // DDR write address/index
    output wire [DATA_WIDTH-1:0]   ddr_wr_data,        // DDR write data value
    input  wire                    ddr_wr_ack,         // One-clock DDR write acknowledge

    output wire                    ddr_rd_req,         // One-clock DDR read request
    output wire [ADDR_WIDTH-1:0]   ddr_rd_addr,        // DDR read address/index
    input  wire [DATA_WIDTH-1:0]   ddr_rd_data,        // DDR read data returned by bridge
    input  wire                    ddr_rd_data_valid   // One-clock DDR read-data-valid pulse
);

    //--------------------------------------------------------------------------
    // Storage adapter FSM state encoding
    //
    // The FSM accepts one command while idle and then waits for the matching DDR
    // response before returning to idle.
    //--------------------------------------------------------------------------
    localparam [1:0] S_IDLE         = 2'd0; // Ready to accept a read or write
    localparam [1:0] S_WAIT_WR_ACK  = 2'd1; // Write request issued, waiting for ACK
    localparam [1:0] S_WAIT_RD_DATA = 2'd2; // Read request issued, waiting for data

    //--------------------------------------------------------------------------
    // Registered state and output registers
    //
    // Address/data/request signals are registered so the DDR bridge sees stable
    // command information when a request pulse is issued.
    //--------------------------------------------------------------------------
    reg [1:0]              state_ff;         // Current FSM state
    reg [1:0]              state_n;          // Next FSM state

    reg [ADDR_WIDTH-1:0]   ddr_wr_addr_ff;   // Registered DDR write address
    reg [ADDR_WIDTH-1:0]   ddr_wr_addr_n;    // Next DDR write address

    reg [DATA_WIDTH-1:0]   ddr_wr_data_ff;   // Registered DDR write data
    reg [DATA_WIDTH-1:0]   ddr_wr_data_n;    // Next DDR write data

    reg                    ddr_wr_req_ff;    // Registered DDR write request pulse
    reg                    ddr_wr_req_n;     // Next DDR write request pulse

    reg [ADDR_WIDTH-1:0]   ddr_rd_addr_ff;   // Registered DDR read address
    reg [ADDR_WIDTH-1:0]   ddr_rd_addr_n;    // Next DDR read address

    reg                    ddr_rd_req_ff;    // Registered DDR read request pulse
    reg                    ddr_rd_req_n;     // Next DDR read request pulse

    reg [DATA_WIDTH-1:0]   rd_data_ff;       // Registered readback data
    reg [DATA_WIDTH-1:0]   rd_data_n;        // Next readback data

    reg                    rd_data_valid_ff; // Registered one-cycle read-valid pulse
    reg                    rd_data_valid_n;  // Next read-valid pulse

    //--------------------------------------------------------------------------
    // Output assignments
    //
    // All command and data outputs are registered. cmd_ready is high only while
    // the adapter is idle and able to accept a new request.
    //--------------------------------------------------------------------------
    assign ddr_wr_req    = ddr_wr_req_ff;
    assign ddr_wr_addr   = ddr_wr_addr_ff;
    assign ddr_wr_data   = ddr_wr_data_ff;

    assign ddr_rd_req    = ddr_rd_req_ff;
    assign ddr_rd_addr   = ddr_rd_addr_ff;

    assign rd_data       = rd_data_ff;
    assign rd_data_valid = rd_data_valid_ff;
    assign cmd_ready     = (state_ff == S_IDLE);

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // Updates FSM state and all registered command/data outputs.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        // Reset the adapter to idle with all request pulses cleared.
        if (!rst_n) begin
            state_ff         <= S_IDLE;
            ddr_wr_addr_ff   <= {ADDR_WIDTH{1'b0}};
            ddr_wr_data_ff   <= {DATA_WIDTH{1'b0}};
            ddr_wr_req_ff    <= 1'b0;
            ddr_rd_addr_ff   <= {ADDR_WIDTH{1'b0}};
            ddr_rd_req_ff    <= 1'b0;
            rd_data_ff       <= {DATA_WIDTH{1'b0}};
            rd_data_valid_ff <= 1'b0;
        end
        // Normal operation loads the next-state values.
        else begin
            state_ff         <= state_n;
            ddr_wr_addr_ff   <= ddr_wr_addr_n;
            ddr_wr_data_ff   <= ddr_wr_data_n;
            ddr_wr_req_ff    <= ddr_wr_req_n;
            ddr_rd_addr_ff   <= ddr_rd_addr_n;
            ddr_rd_req_ff    <= ddr_rd_req_n;
            rd_data_ff       <= rd_data_n;
            rd_data_valid_ff <= rd_data_valid_n;
        end
    end

    //--------------------------------------------------------------------------
    // Storage adapter FSM next-state logic
    //
    // Request pulses default low so ddr_wr_req, ddr_rd_req, and rd_data_valid
    // remain one-clock pulses.
    //--------------------------------------------------------------------------
    always @(*) begin
        state_n         = state_ff;
        ddr_wr_addr_n   = ddr_wr_addr_ff;
        ddr_wr_data_n   = ddr_wr_data_ff;
        ddr_wr_req_n    = 1'b0;
        ddr_rd_addr_n   = ddr_rd_addr_ff;
        ddr_rd_req_n    = 1'b0;
        rd_data_n       = rd_data_ff;
        rd_data_valid_n = 1'b0;

        case (state_ff)
            //==================================================================
            // S_IDLE
            //
            // Accept one new command. Write has priority if wr_en and rd_en are
            // both asserted in the same cycle.
            //==================================================================
            S_IDLE: begin
                // Start a write command and wait for DDR acknowledge.
                if (wr_en) begin
                    ddr_wr_addr_n = wr_addr;
                    ddr_wr_data_n = wr_data;
                    ddr_wr_req_n  = 1'b1;
                    state_n       = S_WAIT_WR_ACK;
                end
                // Start a read command and wait for returned DDR data.
                else if (rd_en) begin
                    ddr_rd_addr_n = rd_addr;
                    ddr_rd_req_n  = 1'b1;
                    state_n       = S_WAIT_RD_DATA;
                end
                // No command is present, so remain ready.
                else begin
                    state_n = state_ff;
                end
            end

            //==================================================================
            // S_WAIT_WR_ACK
            //
            // A write request has been issued. Wait until the DDR path confirms
            // the write was accepted.
            //==================================================================
            S_WAIT_WR_ACK: begin
                // Write completed, return to idle for the next command.
                if (ddr_wr_ack) begin
                    state_n = S_IDLE;
                end
                // Keep waiting for the write acknowledge.
                else begin
                    state_n = state_ff;
                end
            end

            //==================================================================
            // S_WAIT_RD_DATA
            //
            // A read request has been issued. Wait until the DDR path returns
            // valid read data.
            //==================================================================
            S_WAIT_RD_DATA: begin
                // Capture returned data and pulse rd_data_valid for one cycle.
                if (ddr_rd_data_valid) begin
                    rd_data_n       = ddr_rd_data;
                    rd_data_valid_n = 1'b1;
                    state_n         = S_IDLE;
                end
                // Keep waiting for DDR read data.
                else begin
                    state_n = state_ff;
                end
            end

            //==================================================================
            // Unknown state recovery
            //==================================================================
            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

endmodule