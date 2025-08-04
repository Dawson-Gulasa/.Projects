# Audio-Tracking Autonomous Car

## Project Overview

This Python-based project transforms a Raspberry Pi 4 into an autonomous audio-seeking vehicle. It continuously samples microphone input, isolates target frequencies (e.g., C6, C8) via analog filters, and issues real‑time drive commands (straight, square, figure‑eight) to motor controllers based on detected audio cues.

## Prerequisites

- **Hardware:**
  - Raspberry Pi 4 with Raspbian OS
  - Two DC motors and motor driver (L293 or SN754410)
  - Audio input circuit (microphone with push–pull driver, band‑pass filters, ADC)
  - GPIO pin wiring (refer to `datasheets/` for pin assignments)

- **Software & Libraries:**
  - Python 3.7+
  - `gpiozero` or `RPi.GPIO` for GPIO control
  - `numpy`, `scipy` for signal processing (optional)
  - `matplotlib` for offline data visualization (optional)

## Directory Structure

```
audio_tracking_autonomous_car/
├── implementation/        # Core application scripts
│   ├── driveControls.py
│   ├── readAndRun.py
│   └── signalRead.py
│
├── tests/                 # Hardware/software test scripts
│   ├── figureTest.py
│   ├── gpioSequence.py
│   ├── MotorReader.py
│   ├── MotorTest.py
│   ├── readSwitchboard.py
│   └── switchTest.py
│
├── datasheets/            # Reference datasheets and pin mappings
│   ├── DCMotor.pdf
│   ├── GPIO Pin Occupations.xlsx
│   ├── l293.pdf
│   ├── raspberry-pi-4-datasheet.pdf
│   ├── sn754410.pdf
│   └── tl084a.pdf
│
├── deliverables/          # Design Methodology deliverables (PDFs)
│   ├── Deliverable2.pdf
│   ├── Deliverable3.pdf
│   ├── Deliverable4.pdf
│   ├── Deliverable5.pdf
│   ├── Deliverable6.pdf
│   ├── Deliverable7.pdf
│   ├── Deliverable8.pdf
│   ├── Deliverable10.pdf
│   └── Deliverable11.pdf
│
├── docs/                  # Final documentation and user manual
│   ├── Technical Documentation - Group 11.pdf  
│   └── UserManualVideo.txt  # Link to the video tutorial
│
└── README.md              # Project documentation (this file)
```

## Getting Started

1. **Clone the repository** and navigate into the project root:
   ```bash
   git clone https://github.com/yourusername/Projects.git
   cd Projects/audio_tracking_autonomous_car
   ```

2. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install python3-pip
   pip3 install gpiozero numpy scipy
   ```

3. **Wire hardware** according to `datasheets/GPIO Pin Occupations.xlsx` and your motor driver (L293 or SN754410).

## Running the Vehicle

Launch the main script:
```bash
python3 implementation/readAndRun.py
```

This will invoke `signalRead.py` for audio processing and `driveControls.py` for maneuvers.

## Running Tests

Execute individual tests to validate subsystems:
```bash
python3 tests/MotorTest.py
python3 tests/switchTest.py
```

## Technical Documentation & User Manual

- **Full Technical Documentation:**  
  `docs/Technical Documentation - Group 11.pdf`  
  Detailed design rationale, schematics, and development history fileciteturn13file0

- **User Manual Video:**  
  A step‑by‑step demo of setup and operation:  
  https://www.youtube.com/watch?v=HQ8RJdJg2CQ

## Author

Dawson Gulasa  
*Explore more projects at [github.com/yourusername](https://github.com/yourusername).*

