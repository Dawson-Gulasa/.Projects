# Optimus Prime — Architecture and verification notes

## Technology

Digilent Nexys A7-100T · Vivado 2024.2 · Verilog RTL · Xilinx MIG DDR2 · VGA 640×480 · PS/2 mouse and keypad · SD interface.

## Major module boundaries

- **Top-level:** `rtl/top/top.v` integrates clocks, reset, I/O, rendering, prime computation, storage, and SD verification.
- **Prime engine:** `rtl/prime_engine/prime_check_core.v`, `prime_controller.v`, `prime_subsystem.v`, and storage/frontend bridge modules.
- **Memory / video:** `rtl/memory/` and `rtl/common/vga_output.v` implement DDR2 transactions, CDC, and VGA timing; `rtl/ui/` produces menus, parameter fields, results, and overlays.
- **Input:** `rtl/input/` and `rtl/mouse/` handle key decode, debouncing, PS/2 protocol and cursor state.
- **SD verification:** `rtl/sd_card/` includes byte source, synchronization, parser, feeder and Test Mode controller.
- **IP:** `ip/mig/` and `ip/pll/` preserve the configuration sources required for FPGA-specific core generation.

## Clock-domain crossings

Data and events cross domains through synchronizers, pulse synchronizers, asynchronous FIFOs, and explicit handshakes/CDC modules. The documented clocks include 100 MHz logic, 25 MHz VGA, 50 MHz SD, 200 MHz DDR2 reference, and MIG-generated user clock. Check generated IP for the exact configured implementation.

## Test evidence

Eleven directed/self-checking benches are included under [`sim/`](../sim/), spanning arithmetic, controller behavior, memory bridging, mouse, SD Test Mode, and top-level smoke tests. Hardware demonstrations and the recorded timing/utilization results are summarized in [the README](../README.md).

**Known limitation:** Reported implementation WNS was about **−4.9 ns**, so the final design did **not** meet static timing closure even though functionality was demonstrated on hardware. Any future board reproduction should rerun synthesis/place-and-route, correct timing, and validate clock-domain constraints.

**Source evidence:** [Full final report](Optimus_Prime_Final_Report.pdf). No new Vivado run, FPGA build, hardware test, or simulation has been claimed as part of this documentation update.
