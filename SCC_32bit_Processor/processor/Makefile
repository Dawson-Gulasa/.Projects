# =============================================================================
# SCC CP5 - portable application build and simulation (GNU Make)
# =============================================================================
# Run from the SCC portfolio processor/ directory (the directory containing this Makefile).
# This Makefile is OPTIONAL. The authoritative complete 19-test suite is:
#   .\verification\run_cp5_regression.ps1     (PowerShell)
#
# Examples:
#   make
#   make PROGRAM=bubble_sort TB=tb_cp5_bubble_sort_portable run
#   make PROGRAM=array_stats_mul TB=tb_cp5_array_stats_portable run
#   make compile
#   make unit-rom
#   make regression
#
# The assembly step intentionally runs on every application invocation to
# prevent a stale output.mem from executing a different application.
# Runtime file loads (output.mem, ucode.mem, div_ucode.mem) are relative to
# the working directory; execute make from the CP5_RunningTestcases root.
# =============================================================================

.DEFAULT_GOAL := run

PYTHON    ?= python
IVERILOG  ?= iverilog
VVP       ?= vvp
POWERSHELL ?= powershell.exe

PROGRAM   ?= bubble_sort
TB        ?= tb_cp5_bubble_sort_portable
BUILD_DIR := verification/make_build

ASSEMBLER := ../Assembler/assembler.py
ISA_JSON  := ../Assembler/instructions.json
ASSEMBLY  := assembly/$(PROGRAM).asm
TB_FILE   := verification/$(TB).v
VVP_FILE  := $(BUILD_DIR)/$(TB).vvp

# Exactly the same 24 named RTL inputs as run_cp5_regression.ps1.
# Do not use $(wildcard *.v): that can pull in verification or legacy modules.
RTL := \
    rtl/scc_f26_top.v rtl/scc.v rtl/if_stage.v rtl/id_control_stage.v rtl/id_stage.v \
    rtl/branch_control.v rtl/exe_cluster_stage.v rtl/exe_stage.v rtl/regs.v rtl/alu.v \
    rtl/error_status.v rtl/wb_cluster_stage.v rtl/mul_integration.v rtl/flags.v \
    rtl/ucode_controller.v rtl/mul_datapath.v rtl/ucode_rom.v rtl/div_controller.v rtl/div_datapath.v \
    rtl/div_ucode_rom.v rtl/stack_controller.v rtl/stack_datapath.v \
    rtl/stack_memory_bus.v rtl/Instruction_and_data.v

.PHONY: run compile assemble check list unit-rom regression

# Default flow: assemble selected program, compile its top-level testbench,
# then execute the test. Testbench itself reports architectural PASS/FAIL.
run: compile
	$(VVP) $(VVP_FILE)

# Mark compile phony because PROGRAM and TB are command-line selections;
# the correct program must be reassembled even when sources are unchanged.
compile: assemble
	$(IVERILOG) -g2005 -Wall -s $(TB) -o $(VVP_FILE) $(TB_FILE) $(RTL)

assemble: check
	$(PYTHON) $(ASSEMBLER) $(ASSEMBLY) $(ISA_JSON)

# Create build directory without depending on a POSIX mkdir command.
# The assembler and simulators require the specified input files to exist.
check:
	$(PYTHON) -c "from pathlib import Path; p=[Path(x) for x in ['$(ASSEMBLER)','$(ISA_JSON)','$(ASSEMBLY)','$(TB_FILE)','ucode.mem','div_ucode.mem']]; missing=[str(x) for x in p if not x.is_file()]; assert not missing, 'Missing input files: '+', '.join(missing); Path('$(BUILD_DIR)').mkdir(parents=True,exist_ok=True)"

# The ROM unit test is independent of output.mem and the full processor.
unit-rom:
	$(PYTHON) -c "from pathlib import Path; Path('$(BUILD_DIR)').mkdir(parents=True,exist_ok=True)"
	$(IVERILOG) -g2005 -Wall -s tb_div_ucode_rom -o $(BUILD_DIR)/tb_div_ucode_rom.vvp verification/tb_div_ucode_rom.v rtl/div_ucode_rom.v
	$(VVP) $(BUILD_DIR)/tb_div_ucode_rom.vvp

# Windows PowerShell version of the full suite; unlike `run`, this executes
# every program and all unit tests with exact PASS/FAIL marker checks.
regression:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass -File verification/run_cp5_regression.ps1

list:
	@echo CP5 Makefile targets: run compile assemble unit-rom regression list
	@echo Default: make PROGRAM=bubble_sort TB=tb_cp5_bubble_sort_portable run
	@echo Other:   make PROGRAM=array_stats_mul TB=tb_cp5_array_stats_portable run
	@echo Full:    make regression  [Windows PowerShell]
