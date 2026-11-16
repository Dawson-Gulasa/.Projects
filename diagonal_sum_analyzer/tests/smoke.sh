#!/bin/sh
# Small regression test for the course-provided 5x5 matrix, sum 10.
set -eu
test -f examples/in1.txt || { echo "Run from the diagonal_sum_analyzer directory" >&2; exit 1; }
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
./proj4.out examples/in1.txt "$tmp" 10 2
diff -u examples/correctOut1.txt "$tmp"
printf 'PASS: in1.txt, target 10, 2 threads\n'
