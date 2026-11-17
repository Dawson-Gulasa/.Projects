# Micromouse — schematic notes and design review

A navigational index to the [November 16, 2026 five-sheet schematic](Micromouse_Schematics.pdf).

| Page | Sheet title | Main IC / topic | Key considerations |
|---|---|---|---|
| 1 | IMU | BNO080 | I²C address selection, interrupt/reset signals, local clocking, pull-ups |
| 2 | MCU | STM32F405RGT6W | VCAP capacitors, VDD/VDDA decoupling, SWD, UART, oscillator, reset, BOOT0 |
| 3 | Voltage Regulators | Two battery-fed buck converters | 3.3 V / 5 V rail sizing, fuse/protection provision, switching layout |
| 4 | IR Sensors | TSAL6200 emitters x6 and receiver networks x6 | Emitter resistor values, receiver biasing, sensor geometry, GPIO mapping |
| 5 | Motor Driver | DRV8833PWP | PWM channels, motor connectors, nSLEEP/nFAULT, VM supply, startup state |

**Design review priorities**

1. Confirm both motor-input pairs have safe, defined states before the MCU is initialized. Page 5 explicitly flags that a pull-up enables the driver by default.
2. Verify regulator layout and component selection against vendor application guidance, particularly thermal margin, placement of input/output capacitors and high-current return paths.
3. Cross-check power and IR interface GPIO levels with the selected MCU and the actual voltage domains.
4. Validate the combined board's SWD and UART access, reset, oscillators, IMU initialization and encoder connections.
5. Reconcile the final PCB revision with the schematics and BOM prior to manufacturing.

These are project-specific design notes derived from the supplied schematic, **not a completed electrical audit**. See the [README](../README.md) for the project's scope and status.
