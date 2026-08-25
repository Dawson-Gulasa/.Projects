# Projects Repository

A curated collection of my academic and research projects demonstrating skills in robotics, parallel programming, software development, and embedded systems.

## Repository Structure

```text
/
├── audio_tracking_autonomous_car/        # Autonomous audio-tracking vehicle on Raspberry Pi 4
├── optimus_prime_fpga/                   # Nexys A7 FPGA system with VGA UI, DDR2, SD card, and prime verification
├── ssd_clock_timer/                      # Raspberry Pi seven-segment display clock with calibrated software timing
├── reaction_time_training_button/        # Reaction-time training button system (Pico + sensors + OLED + IoT)
├── diagonal_sum_analyzer/                # C tool for computing diagonal sums in large matrices (parallelized)
├── game_show_quiz/                       # JavaFX-based interactive geography quiz application
├── snake_game/                           # Console-based Snake game implemented in C
├── Research_Documentation/               # Comprehensive research memo from Summer Research Assistant role
└── README.md                             # This file
```

## Getting Started

To explore any project:

1. **Clone this repository**:
   ```bash
   git clone https://github.com/yourusername/Projects.git
   cd Projects
   ```
2. **Navigate** into the project directory of interest, for example:
   ```bash
   cd diagonal_sum_analyzer
   ```
3. **Follow that project’s** README for build, run, and usage instructions.

## Projects at a Glance

- **audio_tracking_autonomous_car/**  
  Python-driven Raspberry Pi vehicle that seeks specified audio frequencies and executes navigational maneuvers.
  
- **optimus_prime_fpga/**  
  Verilog-based Nexys A7 FPGA system featuring four prime-computation modes, a mouse/keypad-controlled VGA interface, DDR2 framebuffer and prime storage, SD-card verification, multiple clock domains, and self-checking RTL testbenches.

- **ssd_clock_timer/**  
  Raspberry Pi–driven multi-mode clock (IDLE/AUTO/MANUAL) built on DFF-latched seven-segment displays and a matrix keypad, featuring a custom calibrated busy-loop timing function benchmarked against time.sleep() over a 2-hour accuracy test.

- **reaction_time_training_button/**  
  Battery-powered reaction-time training system using a Raspberry Pi Pico, FSR-based input, SSD1306 OLED UI, and optional ThingSpeak uploads for logging/leaderboard use.  

- **diagonal_sum_analyzer/**  
  Performance-optimized C program using pthreads and sliding-window algorithms to compute main and secondary diagonal sums of \(n\times n\) matrices.  

- **game_show_quiz/**  
  JavaFX application presenting a geography quiz sourced from a CSV dataset, complete with scoring and persistence.  

- **snake_game/**  
  Classic console-based Snake game in C showcasing real-time input handling and game-loop design.  

- **research_assistant/**  
  Full research documentation (Summer 2025) for robotics lab work under Dr. Hongyue Sun, encapsulating code references, design rationale, and demo links.  

---

*For more details, open the README in each subdirectory. Feel free to reach out via GitHub issues or pull requests.*
