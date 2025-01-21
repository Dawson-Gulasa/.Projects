#ifndef PROJ4_H
#define PROJ4_H

#include <pthread.h> // for multithreading

/*
 * The struct grid_t contains a pointer p to a 2D array of 
 * unsigned chars with n rows and n columns stored on
 * the heap of this process. Once this is initialized properly,
 * p[i][j] should be a valid unsigned char for all i = 0..(n-1)
 * and j = 0..(n-1).
 * Do not alter this typedef or struct in any way.
 */
typedef struct grid_t {
  unsigned int n;
  unsigned char **p;
} grid;


/*
 * Initialize g based on fileName, where fileName
 * is a name of file in the present working directory
 * that contains a valid n-by-n grid of digits, where each
 * digit in the grid is between 1 and 9 (inclusive).
 * Do not alter this function prototype in any way.
 */
void initializeGrid(grid * g, char * fileName);


/*
 * This function will compute all diagonal sums in input that equal s using
 * t threads, where 1 <= t <= 3, and store all of the resulting
 * diagonal sums in output. Each thread should do
 * roughly (doesn't have to be exactly) (100 / t) percent of the 
 * computations involved in calculating the diagonal sums. 
 * This function should call (or call another one of your functions that calls)
 * pthread_create and pthread_join when 2 <= t <= 3 to create additional POSIX
 * thread(s) to compute all diagonal sums. 
 * Do not alter this function prototype in any way.
 */
void diagonalSums(grid * input, unsigned long s, grid * output, int t);


/*
 * Write the contents of g to fileName in the present
 * working directory. If fileName exists in the present working directory, 
 * then this function should overwrite the contents in fileName.
 * If fileName does not exist in the present working directory,
 * then this function should create a new file named fileName
 * and assign read and write permissions to the owner. 
 * Do not alter this function prototype in any way.
 */
void writeGrid(grid * g, char * fileName);

/*
 * Free up all dynamically allocated memory used by g.
 * This function should be called when the program is finished using g.
 * Do not alter this function prototype in any way.
 */
void freeGrid(grid * g);

/*
 * You may add any additional function prototypes and any additional
 * things you need to complete this project below this comment. 
 * Anything you add to this file should be commented. 
 */

/*
 * The struct ThreadData is used to pass necessary information to each
 * thread, including portions of the grid, the target sum, and row
 * ranges that each thread will process.
 */
typedef struct
{
  grid *input;
  grid *output;
  unsigned long s;
  unsigned int start_diagonal; 
  unsigned int end_diagonal; 
  unsigned int n;
} ThreadData;

/*
 * Helper function that each thread will execute to compute diagnol sums.
 * This function is called by pthread_create and performs part of
 * the calculation based on its ThreadData.
 * Input
 * - arg - pointer to ThreadData struct containing thread-specific data
 * output:
 * - returns NULL
 * Assume arg is a valid pointer to a properly initialized ThreadData struct
 */
void *computeDiagonalSums(void *arg);

/*
 * Allocate memory for the grid strcuture
 * input: 
 * - g: pointer to the grid structure to initialize
 * - n: size of the grid (number of rows and columns)
 * output:
 * - None
 * Assume g is a valid pointer and n is greater than 0
 */
void allocateGrid(grid *g, unsigned int n);

/* 
 * write a single row of the grid to the file
 * input:
 * - file: FILE pointer to the opened file
 * - row: pointer to the array representing the row
 * - n: number of elements in the row
 * output:
 * - None
 * Assume file is a valid, opened FILE pointer, and row is a valid pointer to an 
 * array of size n
 */
void writeGridRow(FILE *file, unsigned char *row, unsigned int n);





#endif

