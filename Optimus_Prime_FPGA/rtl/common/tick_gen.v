`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// tick_gen.v
//
// Purpose:
//   Generates a one-clock pulse after a programmable number of input clock
//   cycles. This is used as a reusable timing source for slower sample enables,
//   such as debounce sampling.
//
// Operation:
//   The counter increments every clk cycle. When the counter reaches
//   TICKS_PER_PULSE - 1, the counter resets to zero and tick pulses high for
//   exactly one clk cycle.
//
// Example:
//   With clk = 100 MHz and TICKS_PER_PULSE = 500_000:
//
//       500,000 cycles / 100,000,000 cycles/sec = 0.005 sec = 5 ms
//
//   Therefore, tick pulses once every 5 ms.
//
// Interface summary:
//   - clk:
//       Clock used by the counter.
//   - rst_n:
//       Synchronized active-low reset.
//   - tick:
//       Registered one-clock output pulse.
//
// Notes:
//   - This module is not an FSM; it is a counter-based pulse generator.
//   - tick is registered, so downstream logic receives a clean synchronous pulse.
//   - TICKS_PER_PULSE should be greater than zero for normal operation.
//------------------------------------------------------------------------------

module tick_gen #(
    parameter integer TICKS_PER_PULSE = 500_000  // Number of clk cycles between tick pulses
)(
    input  wire clk,    // Clock driving the pulse counter
    input  wire rst_n,  // Synchronized active-low reset
    output wire tick    // One-clock pulse generated every TICKS_PER_PULSE cycles
);

    //--------------------------------------------------------------------------
    // Counter and output registers
    //
    // count_ff tracks the current cycle count. tick_ff is the registered output
    // pulse that goes high for one cycle when the terminal count is reached.
    //--------------------------------------------------------------------------
    reg [31:0] count_ff; // Current cycle count
    reg [31:0] count_n;  // Next cycle count

    reg tick_ff;         // Registered tick output
    reg tick_n;          // Next tick output

    //--------------------------------------------------------------------------
    // Counter next-state logic
    //
    // This block computes the next count value and the next tick pulse. The
    // default behavior is to keep counting and keep tick low unless reset or
    // terminal count occurs.
    //--------------------------------------------------------------------------
    always @(*) begin
        count_n = count_ff;
        tick_n  = 1'b0;

        // Reset counter and clear the output pulse.
        if (!rst_n) begin
            count_n = 32'd0;
            tick_n  = 1'b0;
        end
        else begin
            // Terminal count reached: wrap counter and generate one pulse.
            if (count_ff == (TICKS_PER_PULSE - 1)) begin
                count_n = 32'd0;
                tick_n  = 1'b1;
            end
            // Normal counting cycle: increment and keep tick low.
            else begin
                count_n = count_ff + 32'd1;
                tick_n  = 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential register update
    //
    // The counter and output pulse update together on the rising edge of clk.
    // Reset behavior is encoded in the next-state logic above.
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        count_ff <= count_n;
        tick_ff  <= tick_n;
    end

    //--------------------------------------------------------------------------
    // Output assignment
    //
    // tick is registered so it remains high for exactly one clk cycle.
    //--------------------------------------------------------------------------
    assign tick = tick_ff;

endmodule