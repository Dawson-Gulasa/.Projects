# Reaction-Time Training Button System

## Project Overview

This MicroPython-based project implements a battery-powered reaction-time training device using a Raspberry Pi Pico. The system waits a random amount of time, triggers a visual cue (LED), and measures the user’s response time when they press an FSR-based “button.” An SSD1306 OLED provides on-device instructions and results. If configured, the device can connect over WiFi and upload reaction-time results to ThingSpeak for logging/leaderboard use.

## Prerequisites

- **Hardware:**
  - Raspberry Pi Pico (MicroPython-capable; WiFi required if using ThingSpeak)
  - SSD1306-compatible OLED display (I2C)
  - LED indicator(s)
  - Force-Sensitive Resistor (FSR) + associated conditioning circuit
  - Power system per schematic/report (regulators, switch, etc.)
  - (Optional) Additional sensors/modules included in your build (see `Datasheets/`)

- **Software & Tools:**
  - MicroPython for Raspberry Pi Pico
  - Thonny **or** `mpremote` for file upload
  - (Optional) ThingSpeak account + API keys if using cloud logging

## Directory Structure

```text
reaction_time_training_button/
├── Datasheets/                       # Component datasheets (PDFs)
│   ├── Datasheet_FSR.pdf
│   ├── lm317.pdf
│   ├── ntcle100 (Thermistor).pdf
│   ├── oki-78sr (3.3V Step-Down Regulator).pdf
│   ├── os (Slide Switch).pdf
│   └── tcrt5000 (IR Sensor).pdf
│
├── bom/                              # Parts list + sourcing
│   └── Project_BOM.xlsx
│
├── docs/                             # Course spec + final report
│   ├── Course Project F2025.pdf      
│   └── Sensors_Project_Report.pdf
│
├── firmware/                         # Pico firmware (MicroPython)
│   ├── config/
│   │   ├── .gitignore
│   │   └── secrets_template.py       # Template for WiFi + ThingSpeak keys
│   ├── lib/
│   │   └── ssd1306.py                # OLED driver
│   └── src/
│       ├── main.py                   # Main program / state machine
│       ├── thingspeak_post.py        # ThingSpeak helper (upload results)
│       └── wifi_connect.py           # WiFi helper
│
├── hardware/                         # CAD, PCB files/renders, and wiring schematic
│   ├── enclosure/
│   │   ├── 3D_Renderings/
│   │   │   ├── Box_Screenshot.png
│   │   │   └── Lid_Screenshot.png
│   │   └── CAD/
│   │       ├── Box.3mf
│   │       └── Box Lid.3mf
│   ├── pcb/
│   │   ├── 3D_Renderings/
│   │   │   ├── 3D Rendering.png
│   │   │   ├── Routing.png
│   │   │   ├── TopView.png
│   │   │   └── full schematic.png
│   │   └── design_files/
│   │       └── Reaction_Time_PCB.3mf
│   └── wiring/
│       └── Circuit_Schematic.pdf
│
└── media/                            # Photos + demo link
    ├── photos/
    │   ├── Final_Product.jpg
    │   └── Final_circuit.jpg
    └── demo_video_link.txt
```

## Getting Started

1. **Clone the repository** and navigate into the project directory:
   ```bash
   git clone https://github.com/yourusername/Projects.git
   cd Projects/reaction_time_training_button
   ```

2. **Install / set up a tool to flash files to the Pico:**
   - Recommended: **Thonny**
   - Alternative: **mpremote** (from Python’s `pip`):
     ```bash
     pip install mpremote
     ```

3. **Wire hardware** according to:
   - `hardware/wiring/Circuit_Schematic.pdf`
   - Relevant references in `Datasheets/`

## Optional: ThingSpeak / Secrets Setup

If you are using WiFi + ThingSpeak, you’ll need credentials.

1. Copy the template:
   - `firmware/config/secrets_template.py` → `firmware/config/secrets.py`
2. Fill in your WiFi + ThingSpeak values in `secrets.py`
3. Keep `secrets.py` out of git (already handled by `firmware/config/.gitignore`)

> The most common/simple setup is to upload `secrets.py` to the Pico’s root alongside `main.py`, but match this to how your code imports secrets.

## Uploading / Deploying Firmware to the Pico

### Option A: Thonny (simple)

1. Plug in the Pico over USB and open Thonny
2. Select interpreter: **MicroPython (Raspberry Pi Pico)**
3. Upload the following files:
   - `firmware/src/main.py` → Pico root as `main.py`
   - `firmware/src/wifi_connect.py` → Pico root
   - `firmware/src/thingspeak_post.py` → Pico root
   - `firmware/lib/ssd1306.py` → Pico `/lib/ssd1306.py`
   - `firmware/config/secrets.py` → Pico root (if using WiFi/ThingSpeak)

### Option B: mpremote (repeatable)

From the repository root:

```bash
mpremote connect auto fs mkdir :/lib
mpremote connect auto fs cp firmware/lib/ssd1306.py :/lib/ssd1306.py

mpremote connect auto fs cp firmware/src/main.py :/main.py
mpremote connect auto fs cp firmware/src/wifi_connect.py :/wifi_connect.py
mpremote connect auto fs cp firmware/src/thingspeak_post.py :/thingspeak_post.py

# Only if using WiFi/ThingSpeak credentials
mpremote connect auto fs cp firmware/config/secrets.py :/secrets.py

mpremote connect auto reset
```

## Running the System

Once uploaded, the Pico will run `main.py` automatically on boot/reset.

Typical operation:
1. Device idles, showing instructions/status on the OLED
2. A random waiting period occurs
3. LED cue turns on
4. User presses the FSR “button”
5. Reaction time is computed and displayed
6. (Optional) result is uploaded to ThingSpeak

## Documentation & References

- **Final Report:**  
  `docs/Sensors_Project_Report.pdf`  
  Complete system overview, circuitry, and testing results.

- **Course Spec:**  
  `docs/Course Project F2025.pdf`

- **Circuit / Wiring:**  
  `hardware/wiring/Circuit_Schematic.pdf`

- **BOM:**  
  `bom/Project_BOM.xlsx`

- **Component Datasheets:**  
  `Datasheets/`

## Media / Demo

- **Build photos:**  
  `media/photos/`

- **Demo video link:**  
  `media/demo_video_link.txt`

## Notes / Future Improvements

- Convert breadboard prototypes to finalized PCB assembly (if not already)
- Add more robust debouncing / event validation for the FSR threshold
- Improve power integrity for WiFi bursts (decoupling + rail stability)
- Expand leaderboard features (local history, best-of-session, etc.)

## Author

Dawson Gulasa
