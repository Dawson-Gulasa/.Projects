#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include "proj4.h"

/*
 * Initialize the grid from a file
 * inputs:
 * - g: pointer the the grid structure to initialize
 * - fileName: Name of the input file containing the grid
 * Outputs:
 * - none
 * assume fileName refers to a valid file in the CWD, and the file contains a 
 * valid n by n grid of digits between 1 and 9
 */
void initializeGrid(grid *g, char *fileName)
{
  FILE *file = fopen(fileName, "r");
  if(!file)
    {
      perror("Error opening file");
      exit(EXIT_FAILURE);
    }

  char line[8192];
  unsigned int n = 0;

  // determine the grid dimensions
  while(fgets(line, sizeof(line), file))
    {
      if(n==0)
	{
	  g->n = strlen(line) - 1; // remove new line char
	}
      n++;
    }

  if(g->n != n)
    {
      fprintf(stderr, "Error: Grid dimensions do not form a square\n");
      fclose(file);
      exit(EXIT_FAILURE);
    }

  // allocate memory for the grid
  allocateGrid(g, n);

  // read grid values
  rewind(file);
  for(unsigned int i = 0; i < n; i++)
    {
      for(unsigned int j = 0; j < n; j++)
	{
	  int c = fgetc(file);
	  if(c == EOF)
	    {
	      fprintf(stderr, "Error reading file\n");
	      fclose(file);
	      exit(EXIT_FAILURE);
	    }
	  if(c < '1' || c > '9')
	    {
	      fprintf(stderr, "Error: Invalid character in grid\n");
	      fclose(file);
	      exit(EXIT_FAILURE);
	    }
	  g->p[i][j] = c - '0';
	}
      fgetc(file); // skip newline char
    }
  fclose(file);
}

/*
 * Allocate memory for the grid structure.
 * inputs:
 * - g: pointer to the grid structure to initialize
 * - n: size of the grid (number of rows and columns)
 * outputs:
 * - None
 * Assume g is a valid pointer and n is greater than 0
 */
void allocateGrid(grid *g, unsigned int n)
{
  g->n = n;
  g->p = malloc(n * sizeof(unsigned char *));
  if(!g->p)
    {
      perror("Memory allocation error");
      exit(EXIT_FAILURE);
    }
  for(unsigned int i = 0; i < n; i++)
    {
      g->p[i] = calloc(n, sizeof(unsigned char));
      if(!g->p[i])
	{
	  perror("Memory allocation error");
	  exit(EXIT_FAILURE);
	}
    }
}

/*
 * Helper function that each thread will execute to compute diagonal sums
 * function is called by pthread_create and does part of the computation based 
 * on its ThreadData
 * input:
 * - arg: pointer to ThreadData struct containing thread specific data
 * output:
 * - returns NULL
 * Assume arg is a valid pointer to a properly initialized ThreadData struct
 */
void *computeDiagonalSums(void *arg)
{
  ThreadData *data = (ThreadData *)arg;
  grid *input = data->input;
  grid *output = data->output;
  unsigned long s = data->s;
  unsigned int n = data->n;

  unsigned int start_diagonal = data->start_diagonal;
  unsigned int end_diagonal = data->end_diagonal;

  // process assigned diagonals
  for(unsigned int diagonal_index = start_diagonal; diagonal_index < end_diagonal; diagonal_index++)
    {
      if(diagonal_index < 2 * n - 1)
	{
	  // primary diagonals
	  int d = (int)diagonal_index - (int)(n - 1);
	  int start_i = d >= 0 ? d : 0;
	  int start_j = d >= 0 ? 0 : -d;
	  int length = n - abs(d);

	  int start = 0, end = 0;
	  unsigned long sum = 0;

	  // sliding window to find sub diagonals with sums equal to s
	  while(end < length)
	    {
	      int i = start_i + end;
	      int j = start_j + end;
	      sum += input->p[i][j];

	      // adjust the window if sum exceeds s
	      while(sum > s && start <= end)
		{
		  int si = start_i + start;
		  int sj = start_j + start;
		  sum -= input->p[si][sj];
		  start++;
		}

	      // mark cells if a matching sum is found
	      if(sum == s)
		{
		  for(int m = start; m <= end; m++)
		    {
		      int mi = start_i + m;
		      int mj = start_j + m;
		      output->p[mi][mj] = input->p[mi][mj];
		    }
		}
	      end++;
	    }
	}else
	{
	  // seconday diagonals
	  int d = (int)diagonal_index - (int)(2 * n - 1);
	  int diag_d = d;
	  int start_i = diag_d < n ? 0 : diag_d - (n - 1);
	  int start_j = diag_d < n ? diag_d : n - 1;
	  int length = diag_d < n ? diag_d + 1 : 2 * n - diag_d - 1;

	  int start = 0, end = 0;
	  unsigned long sum = 0;

	  // sliding window to fun sub-diagonals with sums equal to s
	  while(end < length)
	    {
	      int i = start_i + end;
	      int j = start_j - end;
	      sum += input->p[i][j];

	      // adjust the window if sum exceeds s
	      while(sum > s && start <= end)
		{
		  int si = start_i + start;
		  int sj = start_j - start;
		  sum -= input->p[si][sj];
		  start++;
		}

	      //mark the cells if a matching sum is found
	      if(sum == s)
		{
		  for(int m = start; m <= end; m++)
		    {
		      int mi = start_i + m;
		      int mj = start_j - m;
		      output->p[mi][mj] = input->p[mi][mj];
		    }
		}
	      end++;
	    }
	}
    }
  return NULL;
}

/*
 * Compute all diagonal sums in input that equal s using t threads
 * and stores the resulting diagonal sums in output
 * input:
 * - intput: pointer to the input grid
 * - s: target sum to find in diagonals
 * - output: pointer to the output grid
 * - t: number of threads to use
 * Output:
 * - None
 * Assume input and output are valid pointers to initialized grid and
 * 1 <= t <= 3
 */
void diagonalSums(grid *input, unsigned long s, grid *output, int t)
{
  allocateGrid(output, input->n);

  // initialize output grid to zeros
  for(unsigned int i = 0; i < output->n; i++)
    {
      memset(output->p[i], 0, output->n * sizeof(unsigned char));
    }

  pthread_t threads[t];
  ThreadData threadData[t];
  unsigned int n = input->n;
  unsigned int total_diagonals = 4 * n - 2;
  unsigned int diagonals_per_thread = (total_diagonals + t - 1) / t;

  //divide diagonals among threads
  for(int i = 0; i < t; i++)
    {
      threadData[i].input = input;
      threadData[i].output = output;
      threadData[i].s = s;
      threadData[i].n = n;
      threadData[i].start_diagonal = i * diagonals_per_thread;
      threadData[i].end_diagonal = (i + 1) * diagonals_per_thread;
      if(threadData[i].end_diagonal > total_diagonals)
	{
	  threadData[i].end_diagonal = total_diagonals;
	}
      if(t > 1)
	{
	  pthread_create(&threads[i], NULL, computeDiagonalSums, &threadData[i]);
	} else
	{
	  // for a single thread, call the function directly
	  computeDiagonalSums(&threadData[i]);
	}
    }

  // wait for threads to finish
  if(t > 1)
    {
      for(int i = 0; i < t; i++)
	{
	  pthread_join(threads[i], NULL);
	}
    }
}

/*
 * write the contents of g to fileName in the PWD
 * input:
 * - g: pointer to the grid to write
 * - fileName: name of the output file
 * output:
 * - none
 * Assume g is a valid pointer to an initialize grid
 */
void writeGrid(grid *g, char *fileName)
{
  FILE *file = fopen(fileName, "w");
  if(!file)
    {
      perror("Error opening file for writing");
      exit(EXIT_FAILURE);
    }

  for(unsigned int i = 0; i < g->n; i++)
    {
      writeGridRow(file, g->p[i], g->n);
    }
  fclose(file);
}

/*
 * write a single row of the grid to the file
 * input:
 * - file: FILE pointer to the opened file
 * - row: pointer to the array representing the row
 * - n: number of elements in the row
 * output:
 * - none
 * assume file is a valid opened FILE pointer, and row is a valid pointer
 * to an array of size n
 */
void writeGridRow(FILE *file, unsigned char *row, unsigned int n)
{
  for(unsigned int j = 0; j < n; j++)
    {
      fprintf(file, "%hhu", row[j]);
    }
  fprintf(file, "\n");
}

/*
 * free up all dynamically allocated memory used by g.
 * input:
 * - g: pointer to the grid to free
 * output:
 * - none
 * Assume g is a valid pointer to an initialized grid
 */
void freeGrid(grid *g)
{
  for(unsigned int i = 0; i < g->n; i++)
    {
      free(g->p[i]);
    }
  free(g->p);
}
