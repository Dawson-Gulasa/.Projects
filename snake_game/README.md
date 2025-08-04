# Snake Game in C

## Project Overview

This console-based Snake game is implemented in C for Windows environments. Players control the snake to consume fruits, grow in length, and avoid collisions with walls or the snake’s own tail. The game demonstrates basic game-loop logic, real-time input handling, and dynamic board rendering.

## Prerequisites

- Windows OS
- C compiler supporting `<conio.h>` and `<windows.h>` (e.g., MinGW GCC or Microsoft Visual C++)

## Directory Layout

```
snake_game/
├── snake.c      # Source code for the Snake game
└── README.md    # Project documentation (this file)
```

## Building the Game

### Using MinGW GCC

1. Open Command Prompt and navigate to the `snake_game` directory:
   ```batch
   cd path\to\snake_game
   ```
2. Compile the source file:
   ```batch
   gcc snake.c -o snake.exe
   ```

### Using Microsoft Visual C++ (cl)

1. Open the "Developer Command Prompt for VS" and navigate to the project folder:
   ```batch
   cd path\to\snake_game
   ```
2. Compile with:
   ```batch
   cl snake.c
   ```

## Running the Game

1. Run the executable:
   ```batch
   snake.exe
   ```
2. Controls:
   - **W**: Move up
   - **A**: Move left
   - **S**: Move down
   - **D**: Move right
   - **X**: Exit game

3. Objective:
   - Collect `*` fruits to increase score by 10 and grow the snake.
   - Avoid colliding with `#` walls or your own `o` tail.

## How It Works

- **Game Loop**: Continuously renders the board, processes input, and updates game logic until a collision or exit command.
- **Board Rendering**: Uses `system("cls")` to clear the console and prints borders, the snake head (`0`), tail (`o`), and fruit (`*`).
- **Input Handling**: Non-blocking input via `kbhit()` and `getch()` from `<conio.h>`.
- **Logic**: Updates snake position, manages tail coordinates, checks for collisions, and respawns fruits at random positions.

## Author

Dawson Gulasa

