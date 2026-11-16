# Parallel Diagonal Sum Analyzer (C)

**C · POSIX threads · Dynamic memory · Sliding windows · Matrix algorithms**

## Overview

A command-line C tool that searches a square grid for **contiguous segments on diagonals whose values sum to a selected target**. It considers both diagonal directions and writes an output grid retaining cells involved in matching segments. Work is divided across **1–3 POSIX threads** using explicit ranges of diagonals.

This is more than calculating the two full main-diagonal totals. The original README described the functionality incorrectly; this revised version follows the actual [`main.c`](main.c), [`proj4.c`](proj4.c) and [`proj4.h`](proj4.h).

## Engineering highlights

- Dynamically allocates 2D grid storage from a digit-grid input file and releases it after use.
- Enumerates positive-slope and negative-slope diagonal lines and searches contiguous windows for a **target sum**.
- Partitions diagonal indices over up to three workers with `pthread_create` / `pthread_join`.
- Writes a shape-preserving **output grid**, marking matching cells and writing zeros elsewhere.
- Times the parallel computation using `gettimeofday` for the course's performance experiments.

## Build

On Linux, WSL, or macOS with a C compiler, POSIX threads and GNU Make:

```bash
cd diagonal_sum_analyzer
make
```

The executable is **`proj4.out`**. No graphics hardware is needed.

## Run

```bash
./proj4.out inputFile outputFile targetSum numThreads
```

| Argument | Meaning |
|---|---|
| `inputFile` | Existing text file containing an `n × n` grid of digits 1–9, **without spaces** |
| `outputFile` | Path to create/overwrite with the resulting matching-cells grid |
| `targetSum` | Nonnegative integer target for contiguous diagonal windows |
| `numThreads` | **1, 2 or 3** (matching the supplied course interface) |

**Small example:**

```bash
./proj4.out examples/in1.txt out1.txt 10 2
diff -u examples/correctOut1.txt out1.txt
```

The accompanying `examples/in1.txt` and `examples/correctOut1.txt` were prepared for target sum **10**. A successful diff produces no output.

For a short smoke check, run `make test`; it compares the small example against its expected output. This portfolio update does **not** report newly measured thread-scaling speedups.

## Repository layout

```text
diagonal_sum_analyzer/
├── main.c                 # Course CLI and timing harness
├── proj4.c                # Parallel diagonal search implementation
├── proj4.h                # Shared data structures and function prototypes
├── Makefile               # Build / run / smoke-test targets
├── examples/              # Original inputs and expected outputs (some large)
├── tests/smoke.sh         # Minimal regression using in1/correctOut1
└── README.md
```

The larger `examples/in4.txt` / `in5.txt` datasets and corresponding expected outputs are retained as course stress-test artifacts; they account for much of the repository's file size.

## Technical notes and limitations

The program expects the original course format: one row per line, no separators, newline-terminated rows, and **1–9** digit data. It is not a CSV or free-form matrix parser. Because output cells are shared among diagonal workers, the implementation writes matching values into the shared output grid; each matched cell has the same original value across workers, but the original course code does not provide a general-purpose thread-safe matrix framework.

See the C implementation for its exact error handling and boundary assumptions. Original team/course starter code is preserved and not falsely attributed as independent creation.
