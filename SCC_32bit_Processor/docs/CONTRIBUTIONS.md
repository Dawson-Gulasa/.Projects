# Contributors and attribution

**University of Georgia · CSEE 4290 Computer Architecture · Fall 2026**

**Group 4:** Dawson Gulasa, Joshua Oh, Sam Baker.

The processor was a group project built across six checkpoints. The responsibilities below reflect the final report's group-member table and project schedule, not exclusive authorship of each module.

## Dawson Gulasa — RTL design and integration

- Developed early verification infrastructure and integrated the architectural register file with fetch/decode and memory interfaces.
- Contributed branch/ALU and execution integration; verified program control, conditional branches, memory writes and HALT behavior.
- Integrated signed division, the PUSH/POP stack, and register writeback.
- Completed feedback-driven final RTL corrections; moved signed multiplication arithmetic into a dedicated `mul_datapath.v`.
- Organized the final repository structure, documented implementation changes, and reviewed regression evidence.

## Joshua Oh — original interface, tests, and verification

- Developed the initial processor interface and contributed to multiplication controller integration and testing.
- Developed the Receipt Calculator application and self-checking testbench.
- Finalized and commented testbenches and verification sources; documented test methodology and coverage.

## Sam Baker — stages, verification, and architecture illustrations

- Contributed top-level wrapper, initial instruction decode/prefetch, and module-level verification.
- Integrated and evaluated cross-group tests, including reference comparisons.
- Produced architectural diagrams and contributed to final code review and documentation.

## Course-provided and cross-group material

- Course staff supplied the class-defined ISA, processor interface, Python assembler, reference emulator and other support tools.
- `F26_Testcases/Group1` through `Group4` retain programs and testbenches from those student groups. Group 4 materials are collaborative team assets.
- `SelfChecker/` and `Assembler/` are included for reproducibility and should not be interpreted as work solely authored by Dawson.

All materials are published under the stated academic portfolio redistribution permission with credit. No blanket project-wide reuse license is asserted for mixed-authorship code.

**Source:** [Group 4, *Checkpoint 6: SCC Project Complete*](Final_SCC_Report.pdf) (Nov. 2, 2026), especially the team responsibilities table (p. 6), development schedule (pp. 18–23), and final ownership section (pp. 23–24).
