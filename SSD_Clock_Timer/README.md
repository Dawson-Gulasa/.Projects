# Seven-Segment Display Clock & Timer

**Raspberry Pi–Driven Multi-Mode Clock with Calibrated Software Timing**

This project implements a fully functional clock and timer system on a Raspberry Pi, driving four DFF-latched seven-segment displays and a 4×4 matrix keypad. The system supports IDLE, AUTO (real system time), and MANUAL (user-entered time) modes, and includes a custom-calibrated busy-loop timing function that was benchmarked against Python's `time.sleep()` over a 2-hour continuous accuracy test.

Beyond just building a working clock, the project focused on characterizing *why* software timing drifts on a general-purpose OS, and quantifying the tradeoffs between a CPU-driven busy-loop timing approach and the standard library's blocking `sleep()` call.

---

## Demo

Timelapse videos of both 2-hour accuracy tests are available here:

**[Demo Videos](media/demo_video/README.md)**

---

## Features

* Three operating states: **IDLE**, **AUTO** (real-time clock), and **MANUAL** (user time entry)
* Four DFF-latched seven-segment displays, each driven by a dedicated per-digit clock line
* 4×4 matrix keypad input with software debouncing
* Digit-blink UI feedback during MANUAL time entry
* PM indicator (dot) and display ON/OFF toggle (`#` key)
* "BBB" triple-press reset sequence to force the system back to IDLE
* Custom calibrated busy-loop timing function (`manual_tick_nonblocking`) as an alternative to `time.sleep(1)`
* Empirically characterized and compared both timing methods over a 2-hour continuous test

---

## System Overview

```text
Keypad (4x4 matrix)
   │
   v
Keypad Scan / Debounce
   │
   v
Main Loop (FSM)
   │
   ├──> IDLE    -> waits for mode selection (A = AUTO, B = MANUAL)
   ├──> AUTO    -> reads system real-time clock, renders to display
   └──> MANUAL  -> time entry phase, then runs calibrated timing loop
                       │
                       v
                 manual_tick_nonblocking()
                 (busy-loop timing, calibrated
                  to ITERATIONS_PER_SECOND)
                       │
                       v
              Display Memory [H1, H2, M1, M2]
                       │
                       v
        DFF-Latched Seven-Segment Displays (4x)
```

---

## Hardware

* **Raspberry Pi 4 Model B** — GPIO control for keypad scanning, segment driving, and per-digit clock lines
* **4× Seven-segment displays**, driven through **D-type flip-flop (DFF) latches** (TI CD74HCT574) — segment lines are shared across all four digits, with each digit individually latched via its own clock pulse
* **4×4 matrix keypad** — row/column scanning with internal pull-down resistors
* Error/status LED for invalid key presses

---

## Timing Function Design

The MANUAL mode's clock does **not** use `time.sleep(1)` to advance time. Instead, it uses a calibrated busy-loop approach:

1. **Calibration constant** — `ITERATIONS_PER_SECOND` (final calibrated value: **2,600,000**) represents how many busy-loop iterations correspond to ~1 real second while the full program is running (GPIO updates, keypad scanning, display refresh included).
2. **Chunked execution** — each main loop pass burns a small slice of iterations (`step_iters`) rather than blocking for a full second, keeping the program responsive to keypad input (critical for detecting the BBB reset sequence mid-count).
3. **Accumulator-based rollover** — iteration counts accumulate until they cross `ITERATIONS_PER_SECOND`, at which point the internal second/minute/hour counters increment with standard 60/24 rollover logic.
4. **Display updates once per minute** (on second-rollover) rather than every second, reducing GPIO/display overhead.

This constant was calibrated empirically: a target time was entered, a stopwatch was started on final digit entry, and the constant was proportionally corrected based on how long the displayed clock took to roll over one minute, then verified again over a 3-minute window for stability.

### Manual Timing vs. `time.sleep()` — 2-Hour Accuracy Test

| Method | Total Drift (2 hrs) | Drift per Hour | Percent Error |
|---|---|---|---|
| Calibrated busy-loop (manual) | 55 sec | 27.5 sec/hr | 0.764% |
| `time.sleep(1)` | 295 sec | 147.5 sec/hr | 4.097% |

The calibrated busy-loop timing function was **~5.36× more accurate** than the `time.sleep()`-based implementation over a continuous 2-hour run, and it remained more responsive since it could still scan for keypad input (like the BBB reset) during timing accumulation — `sleep()` blocks the program entirely for the duration of the call.

Both methods showed **linear drift over time** rather than random jitter, indicating a systematic calibration/scheduling error rather than noise. The busy-loop method's actual drift (55s) exceeded its theoretical prediction (12.72s), suggesting the short calibration window didn't fully capture long-run CPU scheduling and overhead effects.

---

## Finite State Machine

The program runs a continuous main loop implementing a 3-state FSM:

* **IDLE** — displays `00:00`; waits for `A` (enter AUTO) or `B` (enter MANUAL); does not advance time.
* **AUTO** — continuously reads and renders the Pi's system real-time clock.
* **MANUAL** — two phases:
  1. **Entry phase** — user enters a time via keypad; the actively-edited digit blinks; invalid entries trigger the error LED.
  2. **Run phase** — once entry is complete, `manual_tick_nonblocking()` advances the clock using the calibrated busy-loop timing described above.

Keypad scanning and global actions (display toggle, BBB reset) are checked every loop iteration regardless of state, so the system never blocks on a single task for long.

---

## Debouncing

A simple software debounce was used rather than a hardware (capacitor-based) solution, to keep the already-extensive wiring complexity down. After a key press is detected, the program waits for the input line to go low (button release) before allowing another read, followed by a short fixed delay to suppress mechanical contact bounce.

---

## Repository Structure

```text
ssd_clock_timer/
├── README.md
│
├── src/
│   ├── final/
│   │   └── full_clock_module.py           # Final integrated FSM clock (IDLE/AUTO/MANUAL)
│   │
│   └── development/                       # Incremental build-up / bring-up scripts
│       ├── SSD_test.py                    # Initial SSD + DFF clock pulse bring-up
│       ├── SSD_Keypad.py                  # Initial keypad matrix scan test
│       ├── button_To_Display.py           # Single-digit keypad -> SSD integration
│       ├── four_SSD.py                    # Multi-digit (4x SSD) keypad integration
│       ├── clock_test.py                  # Clock logic test
│       ├── current_time_display.py        # AUTO mode (real system time) prototype
│       ├── timing_function.py             # Busy-loop timing calibration script
│       └── time_dot_sleep_timing.py       # time.sleep()-based timing comparison
│
├── docs/
│   └── Group7_SSD_Clock_Timer_Report.pdf  # Full technical report
│
└── media/
    ├── demo_video/
    │   └── README.md                      # Links to 2-hour test timelapse videos
    │
    └── screenshots/
        ├── hardware_setup.png             # Photo of finalized hardware setup
        ├── manual_timing_drift_graph.png  # Drift graph — calibrated busy-loop timing
        ├── manual_2hr_test_result.png     # Display photo at end of manual 2-hr test
        ├── sleep_timing_drift_graph.png   # Drift graph — time.sleep() timing
        └── sleep_2hr_test_result.png      # Display photo at end of sleep 2-hr test
```

---

## Documentation

The full design report, including detailed calibration procedures, raw test data, and FSM diagrams, is available here:

**[Seven Segment Display Clock & Timer — Full Report](docs/Group7_SSD_Clock_Timer_Report.pdf)**

---

## My Contributions

This project was completed as a three-person team for ECSE 4230: Embedded Systems I.

My contributions included:

* Writing Python source code for keypad scanning, display driving, and FSM logic
* Building and wiring the physical circuit (keypad, DFF-latched SSDs, breadboard integration)
* Debugging and testing hardware/software integration across development iterations
* Contributing to result documentation and the final technical report

Timing function characterization and calibration were led by a teammate, with the full team collaboratively debugging the FSM integration and shared global-state issues that arose after combining IDLE/AUTO/MANUAL modes.

---

## Tools & Technologies

* Python
* RPi.GPIO
* Raspberry Pi 4 Model B
* Seven-segment displays (common segment lines, DFF-latched per digit)
* D-type flip-flop latches (TI CD74HCT574)
* 4×4 matrix keypad
* Software debouncing
* Finite state machine (FSM) design
* Empirical timing calibration & characterization

---

## Authors

**Dawson Gulasa**
Computer Systems Engineering
University of Georgia

**Derrick Cannon**
**Ian Garrison**

Developed for **ECSE 4230: Embedded Systems I** at the University of Georgia.
