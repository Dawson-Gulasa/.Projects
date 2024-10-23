#include <conio.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

// define height and width of game screen
#define HEIGHT 20
#define WIDTH 40

//array to store coordinates of the snakes tail (x , y)
int snakeTailX[100], snakeTailY[100];

//variable to store length of snake tail
int snakeTailLen;

//score and signal flags
int gameover, key, score;

// coordinates of snake's head and fruit
int x, y, fruitx, fruity;


void setup()
{
    gameover = 0;
    score = 0;
// starting coordinates
    x = WIDTH/2;
    y = HEIGHT/2;

// starting fruit coordinates
    fruitx = rand() % WIDTH;
    fruity = rand() % HEIGHT;
    while(fruitx == 0)
    {
    fruitx = rand() % WIDTH;
    }
    while(fruity == 0)
    {
    fruity = rand() % HEIGHT;
    }

}

void MakeBoard()
{
    system("cls");

    // print the top boarder
    for(int j = 0; j < WIDTH + 2; j++)
    {
        printf("-");
    }
    printf("\n");

    // y-axis measured in i
    // x-axis measured in n
    for(int i = 0; i < HEIGHT; i++)
    {
        for(int n = 0; n <= WIDTH; n++)
        {
            // creates side walls (#)
            if(n == 0 || n == WIDTH)
            {
                printf("#");
            }
            // prints snake head (0)
            if(n == x && i == y)
            {
                printf("0");
            }
            // prints fruit (*)
            else if( n == fruitx && i == fruity)
            {
                printf("*");
            }else
            {
                int isSnakeTail = 0;
                for (int k = 0; k < snakeTailLen; k++)
                {
                    // prints snake tail (o)
                    if(snakeTailX[k] == n && snakeTailY[k] == i) 
                    {
                        printf("o");
                        isSnakeTail = 1;
                    }
                }
                 if(isSnakeTail == 0)
                    {
                        printf(" ");
                    }
            }
        }
         printf("\n");
    }
    // print the bottom boarder (-)
    for(int p = 0; p < WIDTH + 2; p++)
    {
        printf("-");
    }
    printf("\n");

    // updates score and instructions
    printf("score = %d\n", score);
    printf("Use W-A-S-D to move.");
    printf("\nPress X to exit the game.");

}

void input()
{
    // reads the keyboards input from user
    if(kbhit())
    {
        switch(tolower(getch()))
        {
            // can't go backwards
            case 'a':
            if(key != 2)
            {
                key = 1;
            }
            break;
            
            case 'd':
            if(key != 1)
            {
                key = 2;
            }
            break;

            case 'w':
            if(key != 4)
            {
                key = 3;
            }
            break;

            case 's':
            if(key != 3)
            {
                key = 4;
            }
            break;

            case 'x':
            gameover = 1;
            break;
        }
    }
}

void logic()
{
    int prevX, prevY, prev2X, prev2Y;

   prevX = snakeTailX[0];
   prevY = snakeTailY[0];

    snakeTailX[0] = x;
    snakeTailY[0] = y;

    // assign old location to new location
   for(int i = 1; i < snakeTailLen; i++)
   {
    prev2X = snakeTailX[i];
    prev2Y = snakeTailY[i];
    snakeTailX[i] = prevX;
    snakeTailY[i] = prevY;
    prevX = prev2X;
    prevY = prev2Y;
   }

    // changes x and y axis' based on key pressed
   switch(key)
   {
    case 1:
    x--;
    break;

    case  2:
    x++;
    break;

    case 3:
    y--;
    break;

    case 4:
    y++;
    break;
    
    default:
    break;
   }

    // if snake hits wall end game
   if(x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT)
   {
    gameover = 1;
   }

    // if snake hits itself end game
   for(int i = 0; i < snakeTailLen; i++)
   {
    if(snakeTailX[i] == x && snakeTailY[i] == y)
    {
        gameover = 1;
    }
   }

    // prints next fruit and increases score
    if(x == fruitx && y == fruity)
    {
        fruitx = rand() % WIDTH;
        fruity = rand() % HEIGHT;
        while(fruitx == 0)
        {
        fruitx = rand() % WIDTH;
        }
        while(fruity == 0)
        {
        fruity = rand() % HEIGHT;
        }

        score += 10;
        snakeTailLen++;
    }

}


void main()
{
    // set up initial gameboard
    setup();

    // loop until game is over
    while(!gameover)
    {
        MakeBoard();
        input();
        logic();
        Sleep(33);
    }
}

