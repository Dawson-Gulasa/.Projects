# Audio-tracking vehicle — hardware and validation

This summary follows the Group 11 *ECSE 2920 Design Methodology* technical documentation supplied for the portfolio update (73 pages, Spring 2025). The full course development record should be consulted for actual schematics, pinout, and measured data. Earlier weekly PDFs remain under [`deliverables/`](course_deliverables/).

## Design architecture

- **Motor and GPIO protection:** Raspberry Pi 4 controls a two-wheel robot through GPIO, H-bridge driver stages and motor-enable logic. Inputs use documented pull resistors, protection and switch/encoder interfaces. Experimental motor timing coefficients were adjusted to improve turning and straight-line tracking.
- **Analog supplies:** The team evaluated a buffered MOSFET-based virtual-ground/dual-rail approach from a 24 V supply and used Multisim/breadboard measurements. The development report recorded physical rails around **±11.5 to ±12.5 V** during testing; these are experiment results, not guaranteed regulated outputs.
- **Acoustic conditioning:** Electret microphone response was characterized and active band-pass filtering was designed around musical note **C8 (~4186 Hz)**, later extended with a **C6** path. The notes distinguish earlier unsuccessful filter designs from the chosen narrow band-pass arrangement.
- **ADC/detection:** LM339 comparator and threshold arrangements digitized conditioned amplitude information for the Pi. The final control code in [`signalRead.py`](../implementation/signalRead.py) samples groups of three GPIO signals, averages repeated reads, and uses timed scans to find peak values.
- **PCB work:** The team captured a consolidated analog/digital schematic, routed a PCB in KiCad, exported Gerbers and reviewed manufacturer design-rule feedback/quote. The PDF shows this design process; it does **not** establish that an assembled custom PCB replaced the breadboard prototype.

## Verification notes

| Engineering activity | Documented evidence |
|---|---|
| GPIO tests and motor PWM direction | Development weeks 2–4; schematic revisions and motor tests |
| Microphone characterization and filtering | Weeks 3 and 7–9; oscilloscope, simulation and spectrum analyzer |
| Split-rail power stage | Weeks 5 and 7; Multisim and bench measurements |
| Sound-directed motion | Week 9; 360° scanning, threshold comparison, physical movement tests |
| Multiple-frequency integration | Week 10; C6/C8 paths and transistor switching |
| PCB/documentation | Week 11; integrated schematic, BOM, Gerbers/quote and flowchart |

**Scope:** Treat data as original course results. All GPIO pin mapping, load and motor specifications are specific to the prototype; the accompanying `hardware/datasheets/` include manufacturer reference documents, not original team-authored data.

## Current folder access

- [Technical documentation already in the repository](Technical%20Documentation%20-%20Group%2011.pdf)
- [Source code](../implementation/)
- [Original weekly deliverables](course_deliverables/)
- [Course video](https://www.youtube.com/watch?v=HQ8RJdJg2CQ)
