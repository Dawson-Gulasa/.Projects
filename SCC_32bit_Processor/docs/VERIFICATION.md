# Verification and reproducibility

## Original final-checkpoint evidence

| Suite | Recorded outcome | Interpretation |
|---|---|---|
| `processor/verification/run_cp5_regression.ps1` | **20/20 PASS**, zero failures | Directed, unit, processor/application regression cases |
| `processor/verification/run_f26_demo.ps1 -Force` | **9/9 injected faults detected** | Selected classwide tests rejected deliberately corrupted processor behavior |
| `processor/verification/run_f26_demo.ps1` | No new aggregate asserted | Normal classwide tests are retained for rerunning |

These numbers come from Group 4's submitted checkpoint report. **This curated copy has not yet been independently simulated**. Detection of intentionally injected faults is not the same as nine normal program passes; 20 tests cannot prove the full ISA for all possible inputs.

## Exact reproduction commands

Install Windows PowerShell, Python 3 (`python` on `PATH`), and Icarus Verilog (`iverilog`, `vvp`). Run from `SCC_32bit_Processor/processor/`:

```powershell
.\verification\run_cp5_regression.ps1
.\verification\run_f26_demo.ps1
.\verification\run_f26_demo.ps1 -Force
```

The final assembled programs write `output.mem`; the runtime reads the tracked `ucode.mem` and `div_ucode.mem`. Test results, VVP binaries, logs, and generated assembly outputs are excluded from version control.

## Test coverage

**Internal suite (20 testbenches):** Bubble Sort, MUL instruction forms/edge cases, Array Statistics, IF/ID, unconditional branches, PUSH/POP smoke and stack boundary, MOVF/SAVF, DIV instruction forms and divide-by-zero/signed overflow/pause/reset, flags-stack-DIV integration, portable Bubble Sort and Array Statistics, and four decoder/division unit tests.

**Nine Fall 2026 classwide testcases and fault categories:**

| Group | Test | Deliberate fault |
|---|---|---|
| 1 | sqrt | MUL |
| 1 | temp | NOHALT |
| 2 | bit_packed_physics_updater | LOAD |
| 2 | sensor_log_analyzer | DIV |
| 3 | box_calc | MUL |
| 3 | max_find | LOAD |
| 4 | bubble_sort | LOAD |
| 4 | array_stats_mul | LOAD |
| 4 | receipt_calculator | POP |

The classwide script optionally compares `scc_out.txt` with the checked-in `golden/F26_*_memoutput.csv` files using `SelfChecker/SelfChecker.py`. For Group 1, that memory comparison is part of acceptance; other cases use their testbench checks as the required pass criterion. A passing test is not automatically full-memory equivalence for every case.

## Changes in this curated portfolio copy

- Retain all 24 active Verilog modules, all 20 regression benches, the nine referenced classwide programs/testbenches, and required assembler, microcode, SelfChecker, and golden output files.
- Remove legacy inactive RTL, earlier-year provided tests, obsolete assembler ISA snapshots, and redundant generated outputs.
- Fix the optional `processor/Makefile` to include `rtl/mul_datapath.v`, which the full regression script already lists.
- Update the stale comment about the stack reset base in the copied `run_f26_demo.ps1` to `0xFFC0`.
- Replace the root `RUN_ALL_TESTS.ps1` with a launcher for the **retained** suites only.

**Validation required before merging:** run each command above and inspect summary markers and any failed compilation/test. The GitHub source has been compared structurally with the named dependency lists, not executed as a hardware simulation in this environment.

See [architecture](ARCHITECTURE.md), [contributors](CONTRIBUTIONS.md), and the [original source repository](https://github.com/Herring-UGACSEE-4290-F26/Group-Burger/tree/main/SCC/CP6-SCC_Complete).
