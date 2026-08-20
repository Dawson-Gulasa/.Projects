# Optimus Prime FPGA

**Interactive Prime Computing & Verification System**

Optimus Prime is an FPGA-based prime computation system implemented in **Verilog** on the **Digilent Nexys A7-100T**. The project combines prime-number computation with a mouse- and keypad-controlled VGA interface, external DDR2 memory, SD-card verification, multiple clock domains, and a modular self-checking verification environment.

The goal was to build more than a simple prime finder. The final system behaves like a complete interactive FPGA application, with multiple operating modes, live graphical feedback, large external-memory storage, and hardware-based result verification.

---

## Demo

A full hardware walkthrough is available here:

**[Demo Video](media/demo_video/README.md)**

---

## Features

* Four operating modes:

  * **Range Mode** – finds all primes within a selected range
  * **Time Mode** – finds primes for a user-defined amount of time
  * **Single Mode** – determines whether one value is prime
  * **Test Mode** – compares generated primes against reference data from an SD card
* 640×480 VGA graphical user interface
* USB mouse navigation through the Nexys A7 PS/2 interface
* 4×4 Pmod keypad for parameter entry
* DDR2 storage for both prime data and the VGA framebuffer
* Double-buffered framebuffer architecture
* SD-card interface for independent result verification
* Multiple clock domains with explicit CDC handling
* Xilinx MIG DDR2 and Clocking Wizard IP integration
* Modular Verilog architecture
* Unit, integration, and system-level self-checking testbenches

---

## System Overview

The design is split into several major hardware subsystems:

```text
User Input
   │
   ├── Mouse
   ├── Keypad
   └── Pushbuttons
   │
   v
UI / Control FSM
   │
   ├───────────────┐
   v               v
Prime Engine    VGA Renderer
   │               │
   v               v
Prime Storage   Framebuffer
   │               │
   └───────┬───────┘
           v
          DDR2

SD Card ──> Parser / Feeder ──> Test Mode Verification
```

`top.v` integrates the input, computation, memory, SD-card, display, and clocking subsystems.

---

## Prime Computation

The prime engine uses a hardware-oriented **trial division algorithm**.

For each candidate, divisors are tested up to the square root of the number. Modulo operations are implemented through iterative subtraction rather than a dedicated divider, keeping the design straightforward and synthesizable.

The main prime-computation modules are:

```text
prime_subsystem.v
├── prime_controller.v
├── prime_check_core.v
├── prime_storage_frontend.v
└── prime_ddr_bridge.v
```

The controller handles Range, Time, and Single Mode behavior while also tracking prime counts, recent primes, and storage events.

---

## DDR2 & VGA

External DDR2 memory is used for two major functions:

* Storing generated prime values
* Storing the VGA framebuffer

The VGA interface runs at **640×480 @ 60 Hz** and uses a double-buffered framebuffer so one frame can be displayed while the next is being rendered.

The user interface includes:

* Main menu
* Parameter entry
* Generating screen
* Results screen
* Test Mode screen
* Controls screen
* Mouse cursor and sprite overlays

---

## SD-Card Test Mode

Test Mode provides an independent verification path for the prime engine.

Reference primes stored on the microSD card are streamed through the SD subsystem:

```text
SD Card
   ↓
sd_file_byte_source.v
   ↓
sd_byte_sync.v
   ↓
sd_prime_parser.v
   ↓
sd_prime_feeder.v
   ↓
test_mode_ctrl.v
```

The controller compares the SD reference values against primes previously generated and stored in DDR2.

The VGA interface reports either **PASS** or **FAIL**, along with mismatch information when applicable.

---

## Clock Domains

The system uses several clock domains:

| Clock     |     Frequency | Purpose                     |
| --------- | ------------: | --------------------------- |
| `clk_cpu` |       100 MHz | Main logic, UI, computation |
| `clk_vga` |        25 MHz | VGA timing                  |
| `clk_sd`  |        50 MHz | SD-card interface           |
| `clk_mem` |       200 MHz | DDR2 reference clock        |
| `ui_clk`  | MIG generated | DDR2 user interface         |

Clock-domain crossings are handled using synchronizers, pulse synchronization, asynchronous FIFOs, and dedicated CDC bridge modules.

---

## Verification

The project uses a bottom-up verification approach with self-checking testbenches.

Testing includes:

* Directed edge cases
* Randomized inputs
* Reference models
* Automated PASS/FAIL reporting
* Forced-failure testing
* Subsystem integration testing
* Top-level smoke testing

Included testbenches cover:

```text
tb_prime_check_core.v
tb_prime_controller.v
tb_prime_ddr_storage.v
tb_prime_subsystem.v
tb_sd_prime_parser.v
tb_sd_prime_feeder.v
tb_test_mode_ctrl.v
tb_input_ctrl.v
tb_mouse_subsystem.v
tb_vga_output_with_cursor.v
tb_top_smoke.v
```

All testbenches completed with zero errors during normal verification.

---

## Hardware Results

The final design was successfully tested on the Nexys A7 hardware.

Notable results include:

* **103,739 primes found during a 90-minute Time Mode run**
* **0–1,000,000 prime search completed in 48 minutes, 40 seconds**
* Approximately **15% LUT utilization**
* Approximately **6% BRAM utilization**

The design functioned correctly in hardware, although the final implementation did not fully meet timing closure, with a worst negative slack of approximately **-4.9 ns**. This leaves clear opportunities for future work involving pipelining and critical-path optimization.

---

## Repository Structure

```text
optimus_prime_fpga/
├── README.md
├── rtl/
│   ├── top/
│   ├── prime_engine/
│   ├── input/
│   ├── mouse/
│   ├── sd_card/
│   ├── memory/
│   ├── ui/
│   ├── common/
│   └── legacy/
├── sim/
├── mem/
├── constraints/
├── ip/
│   ├── mig/
│   └── pll/
├── docs/
│   └── Optimus_Prime_Final_Report.pdf
└── media/
    ├── demo_video/
    └── screenshots/
```

---

## Documentation

The full design report is available here:

**[Optimus Prime Final Report](docs/Optimus_Prime_Final_Report.pdf)**

It contains the complete system architecture, module descriptions, verification methodology, Vivado IP configuration, hardware results, resource utilization, timing analysis, and development reflections.

---

## My Contributions

This project was completed as a two-person team.

My primary contributions included:

* Prime engine integration
* Mouse and keypad input integration
* Cursor functionality
* SD-card communication
* Test Mode implementation
* Relevant self-checking testbenches
* Hardware integration and debugging

VGA, memory management, framebuffer development, and project documentation also included shared team work.

---

## Tools & Technologies

* Verilog HDL
* Xilinx Vivado
* Digilent Nexys A7-100T
* DDR2 SDRAM
* Xilinx MIG
* Xilinx Clocking Wizard
* VGA
* PS/2 mouse interface
* SPI / SD-card communication
* Pmod keypad
* FPGA clock-domain crossing
* RTL simulation and verification

---

## Authors

**Dawson Gulasa**
Computer Systems Engineering
University of Georgia

**Michael See**

Developed for **Advanced Digital Design (CSEE 4280)** at the University of Georgia.

