# Micromouse — electronics architecture

**Scope:** circuit architecture for the Micromouse PCB design snapshot dated November 16, 2026. Source: [five-sheet schematic PDF](Micromouse_Schematics.pdf). This is not a claim of final electrical or competitive validation.

## System-level interfaces

```text
              I²C (SCL/SDA) + INTN
[BNO080 IMU] ───────────────────────► [STM32F405 MCU]
                                           ▲
                IR_1 .. IR_6               │
[IR sensor array] ──────────────────────────┤
                                           │
               encoder feedback             │
[Two DC motors] ────────────────────────────┤
       ▲                                   │
       │        M1/M2 PWM pairs             │
    [DRV8833] ◄─────────────────────────────┘
        │
        └─ nSLEEP / nFAULT + motor power

[Battery] ──► protection provision ──► [3.3 V / 5 V buck rails]
[SWDIO / SWCLK + reset + BOOT0] ─────► programmer / debugger
[UART_TX / UART_RX] ─────────────────► Bluetooth/serial header
```

## STM32F405RGT6

Sheet 2 integrates the MCU power network, external crystal oscillator, reset pushbutton, BOOT0 strap and optional debug/programming header. Important mapped nets include:
- PB8/PB9: `SCL` / `SDA` for the IMU
- PA13/PA14: `SWDIO` / `SWCLK`
- PB10/PB11: `UART_TX` / `UART_RX`
- PA8–PA11: `M1_PWM_A`, `M1_PWM_B`, `M2_PWM_A`, `M2_PWM_B`
- PC8/PC9: `M_NSLEEP` and `M_NFAULT`
- PC0–PC3 and PA1/PA2: IR sensor inputs (see the source sheets for exact labels)

The source captures red/blue/green status LEDs and external capacitors on the MCU's VCAP supply pins.

## BNO080 inertial sensing

Sheet 1 includes BNO080 power, capacitors, 2.2 kΩ host I²C pull-ups, an interrupt signal, reset/BOOT and a low-frequency external oscillator. The project uses the IMU for heading/motion sensing within the proposed maze-navigation architecture. Sensor performance, calibration and motion-control accuracy are not asserted by this design snapshot.

## Infrared wall sensing

Sheet 4 shows six TSAL6200 infrared LEDs with series resistors and six separate IR receiver networks. Emitters and detectors are positioned around the perimeter of the round-ended board geometry to observe walls. Receiver types and analog threshold strategy must be confirmed in the full implementation; don't infer measured sensitivity from a schematic.

## Dual motor driver

Sheet 5 uses the DRV8833PWP, two PWM input pairs, two motor output pairs, `nSLEEP`, `nFAULT`, supply decoupling and connectors carrying motor channels and feedback signals. The schematic itself notes that the nSLEEP pull-up enables the driver by default, meaning **defined safe firmware startup levels are essential** to prevent unexpected motor activation. This caution is an engineering review item, not a completed safety test.

## Power distribution

Sheet 3 shows a battery input, fuse provision and two buck regulator stages creating 3.3 V and 5 V rails. The final regulator part numbers, input battery specifications, efficiency, load current, switching frequency and fabrication design rules must be confirmed from the final design before physical replication.

## CAD artifacts

- [PCB 3D render](../media/micromouse_pcb_3d.png)
- [PCB routing screenshot](../media/micromouse_pcb_layout.png)
- [Five schematic sheets](Micromouse_Schematics.pdf)
- [Schematic details](SCHEMATIC_NOTES.md)

This collection is intended to showcase **PCB layout and circuit integration**, not a turnkey firmware/robot release.
