# C-Projects

Snake.c:
  This project is a simple implementation of the classic Snake Game written in C. The game runs in the terminal and uses basic input/output and system functions to display the game board, control the snake's movements, and track the score. The player controls a snake that moves around the screen, trying to eat fruits (*) while avoiding walls and its own tail. The snake grows longer each time it eats a fruit, and the player's score increases. The game ends if the snake hits a wall or its own tail.
  
Key Functions
setup(): Initializes the game state, including the snake's starting position and the location of the first fruit.
MakeBoard(): Clears the screen and prints the game board, including walls, the snake, and the fruit.
input(): Handles user input for moving the snake and quitting the game.
logic(): Implements the game logic:
  - Updates the snake's position and moves the tail.
  - Detects collisions with walls and the snake’s own tail.
  - Checks if the snake has eaten the fruit, and if so, increases the score and length of the snake.
main(): The main game loop. It calls MakeBoard(), input(), and logic() repeatedly until the game is over.
Game Features
  - Random Fruit Generation: Fruits are placed randomly within the game board using the rand() function.
  - Snake Movement: The snake’s direction changes based on user input, and the body of the snake follows the head.
  - Collision Detection: The game ends when the snake collides with the boundary of the game board or its own body.
  - Score Tracking: The player's score increases by 10 points each time the snake eats a fruit.
