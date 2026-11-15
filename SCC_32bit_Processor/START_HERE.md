# Quick start: SCC 32-bit processor

1. Install Python 3 and Icarus Verilog (`python`, `iverilog`, and `vvp` on your PATH).
2. Keep `processor/`, `Assembler/`, `F26_Testcases/`, and `SelfChecker/` in the same project folder.
3. Open **Windows PowerShell** in `SCC_32bit_Processor/processor/`.
4. Run `.\verification\run_cp5_regression.ps1` (20 internal tests).
5. Run `.\verification\run_f26_demo.ps1` (nine normal classwide programs).
6. Run `.\verification\run_f26_demo.ps1 -Force` (nine deliberate fault-injection demonstrations).

`processor/ucode.mem` and `processor/div_ucode.mem` are required; `output.mem` is assembler-generated. Historical 20/20 and 9/9 results belong to the original submission, not to a fresh rerun of this copy. See [verification details](docs/VERIFICATION.md).
