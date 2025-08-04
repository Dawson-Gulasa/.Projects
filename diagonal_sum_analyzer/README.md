# Diagonal Sum Analyzer for Large Matrices

## Project Overview

This C-based utility computes the sums of the main and secondary diagonals for large \(n \times n\) matrices. It demonstrates efficient memory management, parallel computation with pthreads, and optimized sliding-window algorithms for sub-diagonal searches.

## Prerequisites

- A C compiler supporting C11 (e.g., `gcc`)
- POSIX threads library (`-lpthread`)
- Make utility for automated build

## Directory Layout

```
diagonal_sum_analyzer/
├── Makefile            # Build script
├── main.c              # Entry point; parses arguments and orchestrates computation
├── proj4.c             # Implementation of diagonal-sum algorithms
├── proj4.h             # Header definitions for proj4.c
├── examples/           # Sample inputs and expected outputs
│   ├── in1.txt         # Example input: whitespace-delimited matrix
│   ├── correctOut1.txt # Corresponding expected diagonal sums
│   └── ...             # Additional test cases
└── README.md           # Project documentation (this file)
```

## Build Instructions

From the `diagonal_sum_analyzer/` root directory, run:

```bash
make
```

This will produce the executable `diag_sum`.

## Usage

```bash
./diag_sum <input_file>
```

- `<input_file>`: Path to a text file containing an \(n \times n\) whitespace-delimited matrix.

### Example

```bash
./diag_sum examples/matrix1.in
# Output (stdout):
# Main diagonal sum: 15
# Secondary diagonal sum: 15
```

## Running Tests

To verify against all provided examples, you can script:

```bash
for f in examples/*.in; do
  echo "Testing $f"
  ./diag_sum "$f" | diff - examples/$(basename "$f" .in).out
  echo
  done
```

## Author

Dawson Gulasa

---

*For additional projects and source code, visit [github.com/yourusername](https://github.com/yourusername).*
