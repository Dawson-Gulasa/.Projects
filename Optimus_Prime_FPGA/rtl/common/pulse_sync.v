`timescale 1ns / 1ps

// pulse_sync
// Moves a single-cycle pulse from src_clk domain into dst_clk domain using a toggle.
// - src side: toggles a bit whenever src_pulse is seen
// - dst side: double-syncs that toggle and edge-detects it into a 1-cycle dst_pulse
//
// Notes:
// - src_rst and dst_rst are ACTIVE-HIGH, synchronous to their respective clocks.
// - dst_pulse is one clk wide in the destination domain.

module pulse_sync (
    // Source clock domain
    input  wire src_clk,        // source clock
    input  wire src_rst,        // sync reset (active-high) in src_clk domain
    input  wire src_pulse,      // single-cycle pulse in src_clk domain

    // Destination clock domain
    input  wire dst_clk,        // destination clock
    input  wire dst_rst,        // sync reset (active-high) in dst_clk domain
    output wire dst_pulse       // single-cycle pulse in dst_clk domain
);

    // ------------------------------------------------------------------------
    // Source-domain toggle flop
    // ------------------------------------------------------------------------
    // Each time src_pulse is asserted, flip src_toggle.
    // This converts a pulse into a level change that can be safely synchronized.
    reg src_toggle;

    always @(posedge src_clk) begin
        // Reset behavior: clear toggle so we start from a known phase.
        if (src_rst) begin
            src_toggle <= 1'b0;

        end else begin
            // Default: hold the previous toggle value unless a pulse arrives.
            src_toggle <= src_toggle;

            // When a pulse arrives, flip the toggle.
            if (src_pulse) begin
                src_toggle <= ~src_toggle;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Destination-domain synchronizer (2-FF for CDC)
    // ------------------------------------------------------------------------
    // Bring src_toggle into dst_clk domain with two flops to reduce metastability risk.
    (* ASYNC_REG="TRUE" *) reg dst_sync1;
    (* ASYNC_REG="TRUE" *) reg dst_sync2;

    always @(posedge dst_clk) begin
        // Reset behavior: clear sync chain.
        if (dst_rst) begin
            dst_sync1 <= 1'b0;
            dst_sync2 <= 1'b0;

        end else begin
            // Default: update synchronizer every clock.
            dst_sync1 <= src_toggle;
            dst_sync2 <= dst_sync1;
        end
    end

    // ------------------------------------------------------------------------
    // Destination-domain edge detect (toggle change -> 1-cycle pulse)
    // ------------------------------------------------------------------------
    // Track previous synchronized toggle so we can XOR to create a pulse.
    reg dst_prev;

    always @(posedge dst_clk) begin
        // Reset behavior: clear prev so first edge is well-defined.
        if (dst_rst) begin
            dst_prev <= 1'b0;

        end else begin
            // Default: capture the current synced toggle for next-cycle compare.
            dst_prev <= dst_sync2;
        end
    end

    // If the synchronized toggle changed since last cycle, emit a 1-cycle pulse.
    assign dst_pulse = dst_sync2 ^ dst_prev;

endmodule