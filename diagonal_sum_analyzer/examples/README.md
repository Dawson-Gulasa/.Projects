# Original matrix fixtures

Files are numbered pairs: `inN.txt` is a square grid of digit characters and `correctOutN.txt` is the corresponding output grid for the original course testcase.

Example 1 uses a **target diagonal-window sum of 10**, confirmed by the matching output pattern:

```bash
make
./proj4.out examples/in1.txt out1.txt 10 2
diff -u examples/correctOut1.txt out1.txt
```

The remaining fixtures are retained as original examples, but their target sums/thread settings are not documented here, so do not assume the same `10` target for all cases. Input files 4 and 5 are large stress datasets. See [project README](../README.md).
