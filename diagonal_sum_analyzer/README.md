# Project 4: Compilation and Execution Instructions

## Name: Dawson Gulasa

### How to Compile the Program(s):
1. Ensure the following files are in the current working directory:
   - `proj4.c`
   - `main.c`
   - `proj4.h`
   - The provided `MakeFile`
2. Ensure `examples.tar.gz` is in the current working directory and extract it by running:
   ```bash
   tar -xvf examples.tar.gz
   ```
3. Compile the program by running:
   ```bash
   make
   ```

### How to Run the Program(s):
1. Ensure all the source files have been compiled.
2. Run the program using the following command:
   ```bash
   ./proj4.out [input_grid] [output_grid] [desired_sum] [thread(s)]
   ```
   - **[input_grid]**: The file containing a number grid to compute diagonal sums.
   - **[output_grid]**: The file where the program will output the diagonal sums grid.
   - **[desired_sum]**: The desired diagonal sums to locate/compute.
   - **[thread(s)]**: The number of threads (1-3) you want the program to use.

3. To test the program's output against a correct output file, append the following command:
   ```bash
   diff [output_grid] [correctOut#.txt] | wc -c
   ```

### Performance Insight:
**Why does using 3 threads compute diagonal sums slower than 2 threads on smaller grids?**
- On smaller grids, the computational tasks are too trivial to benefit from multithreading. The overhead introduced by creating and managing additional threads outweighs any potential speed gains from parallel execution, leading to slower overall performance when using more threads.

