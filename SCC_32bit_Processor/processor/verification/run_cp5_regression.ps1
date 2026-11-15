# run_cp5_regression.ps1
# SCC CP5 full automated regression and handoff verification.
#
# Run from CP5_RunningTestcases:
#   .\verification\run_cp5_regression.ps1
#
# Design rules:
# - Reassemble each application before running its testbench.
# - Compile every test with explicit sources and -g2005 -Wall.
# - Require the exact expected PASS marker and reject failure diagnostics.
# - Check process exit codes and write per-test logs.
# - Preserve and restore the user's output.mem, output.lst, and scc_out.txt.
# - Do not edit ucode.mem or div_ucode.mem.
# - Keep CP4 and CP5 cases independent for straightforward diagnosis.

$ErrorActionPreference = 'Stop'

# Always resolve paths relative to this script, not the caller's shell.
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot

$resultsDir = Join-Path $PSScriptRoot 'results_cp5'
$null = New-Item -ItemType Directory -Force -Path $resultsDir

$rtl = @(
    'rtl/scc_f26_top.v', 'rtl/scc.v', 'rtl/if_stage.v',
    'rtl/id_control_stage.v', 'rtl/id_stage.v', 'rtl/branch_control.v',
    'rtl/exe_cluster_stage.v', 'rtl/exe_stage.v', 'rtl/regs.v', 'rtl/alu.v',
    'rtl/error_status.v', 'rtl/wb_cluster_stage.v', 'rtl/mul_integration.v',
    'rtl/flags.v', 'rtl/ucode_controller.v', 'rtl/mul_datapath.v', 'rtl/ucode_rom.v',
    'rtl/div_controller.v', 'rtl/div_datapath.v', 'rtl/div_ucode_rom.v',
    'rtl/stack_controller.v', 'rtl/stack_datapath.v', 'rtl/stack_memory_bus.v',
    'rtl/Instruction_and_data.v'
)

# Each full-processor test names the application assembled into output.mem.
# Unit tests use a smaller, explicit module list and need no application.
$tests = @(
    @{ Name = 'CP4 Bubble Sort';                Top = 'tb_bubble_sort';                Program = 'bubble_sort';             Expected = 'CP4 BUBBLE SORT TEST PASSED';             Unit = $false },
    @{ Name = 'CP4 Four MUL Forms';             Top = 'tb_mul_integration';            Program = 'mul_forms';               Expected = 'MULTIPLICATION INTEGRATION TEST PASSED'; Unit = $false },
    @{ Name = 'CP4 MUL Edge Cases';            Top = 'tb_mul_edge_cases';             Program = 'mul_edge_cases';          Expected = 'MUL EDGE-CASE TEST PASSED';            Unit = $false },
    @{ Name = 'CP4 Array Statistics';          Top = 'tb_array_stats_mul';           Program = 'array_stats_mul';         Expected = 'ARRAY STATISTICS TEST PASSED';          Unit = $false },
    @{ Name = 'CP2 IF/ID';                     Top = 'tb_cp_if_id';                   Program = 'cp2_branch_regression';   Expected = 'RESULT: ALL TESTS PASSED';            Unit = $false },
    @{ Name = 'CP4 Unconditional Branch';      Top = 'tb_cp4_unconditional_branch';   Program = 'cp4_unconditional_branch'; Expected = 'CP4 UNCONDITIONAL BRANCH TEST PASSED'; Unit = $false },
    @{ Name = 'CP5 PUSH/POP Smoke';            Top = 'tb_cp5_push_pop_smoke';        Program = 'cp5_push_pop_smoke';      Expected = 'CP5 PUSH/POP SMOKE TEST PASSED';       Unit = $false },
    @{ Name = 'CP5 Stack Boundary';            Top = 'tb_cp5_stack_boundary';        Program = 'cp5_stack_boundary';      Expected = 'CP5 STACK BOUNDARY TEST PASSED';      Unit = $false },
    @{ Name = 'CP5 MOVF/SAVF';                 Top = 'tb_movf_savf';                  Program = 'movf_savf';              Expected = 'MOVF/SAVF TEST PASSED';                Unit = $false },
    @{ Name = 'CP5 DIV Instruction Forms';     Top = 'tb_cp5_div_integration';       Program = 'cp5_div_integration';     Expected = 'CP5 DIV INTEGRATION TEST PASSED';     Unit = $false },
    @{ Name = 'CP5 Divide By Zero';            Top = 'tb_cp5_div_zero';              Program = 'cp5_div_zero';           Expected = 'CP5 DIV ZERO TEST PASSED';            Unit = $false },
    @{ Name = 'CP5 Signed Divide Overflow';    Top = 'tb_cp5_div_overflow';          Program = 'cp5_div_overflow';       Expected = 'CP5 DIV OVERFLOW TEST PASSED';        Unit = $false },
    @{ Name = 'CP5 Division Pause/Reset';      Top = 'tb_cp5_div_pause_reset';       Program = 'cp5_div_integration';     Expected = 'CP5 DIV PAUSE/RESET TEST PASSED';     Unit = $false },
    @{ Name = 'CP5 Combined Flags/Stack/DIV';  Top = 'tb_cp5_flags_div_stack';       Program = 'cp5_flags_div_stack';    Expected = 'CP5 COMBINED FLAGS TEST PASSED';     Unit = $false },
    @{ Name = 'Portable Bubble Sort';          Top = 'tb_cp5_bubble_sort_portable';  Program = 'bubble_sort';             Expected = 'CP5 PORTABLE BUBBLE SORT TEST PASSED'; Unit = $false },
    @{ Name = 'Portable Array Statistics';     Top = 'tb_cp5_array_stats_portable';  Program = 'array_stats_mul';         Expected = 'CP5 PORTABLE ARRAY STATS TEST PASSED'; Unit = $false },
    @{ Name = 'Instruction Decoder Unit'; Top = 'tb_id_stage'; Program = ''; Expected = 'ID STAGE TEST PASSED'; Unit = $true },
    @{ Name = 'Division Controller Unit';      Top = 'tb_div_controller';            Program = '';                        Expected = 'CP5 DIV CONTROLLER TEST PASSED';     Unit = $true },
    @{ Name = 'Division ROM Unit';             Top = 'tb_div_ucode_rom';             Program = '';                        Expected = 'CP5 DIV UCODE ROM TEST PASSED';      Unit = $true },
    @{ Name = 'Division ROM Fault Injection';  Top = 'tb_div_ucode_fault';           Program = '';                        Expected = 'CP5 DIV UCODE FAULT TEST PASSED';    Unit = $true }
)

# Only the controller's own leaf sources are compiled for unit tests.
$unitSources = @{
    'tb_id_stage' = @('rtl/id_stage.v')
    'tb_div_controller'  = @('rtl/div_controller.v', 'rtl/div_datapath.v', 'rtl/div_ucode_rom.v')
    'tb_div_ucode_rom'   = @('rtl/div_ucode_rom.v')
    'tb_div_ucode_fault' = @('rtl/div_controller.v', 'rtl/div_datapath.v', 'rtl/div_ucode_rom.v')
}

$preservedFiles = @('output.mem', 'output.lst', 'scc_out.txt')
$saved = @{}
$passed = 0
$failed = 0
$failedNames = @()

try {
    # Validate inputs before changing the assembled program.
    if (($rtl | Select-Object -Unique).Count -ne $rtl.Count) {
        throw 'Duplicate RTL sources in CP5 regression script.'
    }
    foreach ($source in $rtl) {
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing RTL source: $source" }
    }
    foreach ($required in @('ucode.mem', 'div_ucode.mem', '..\Assembler\assembler.py', '..\Assembler\instructions.json')) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing required file: $required" }
    }
    foreach ($test in $tests) {
        $tbFile = Join-Path 'verification' ($test.Top + '.v')
        if (-not (Test-Path -LiteralPath $tbFile)) { throw "Missing testbench: $tbFile" }
        if (-not $test.Unit) {
            $asmFile = Join-Path 'assembly' ($test.Program + '.asm')
            if (-not (Test-Path -LiteralPath $asmFile)) { throw "Missing assembly program: $asmFile" }
        }
    }

    # Keep pre-existing output files intact, including after an exception.
    foreach ($file in $preservedFiles) {
        $exists = Test-Path -LiteralPath $file
        $saved[$file] = $exists
        if ($exists) {
            Copy-Item -LiteralPath $file -Destination (Join-Path $resultsDir ('saved_' + $file)) -Force
        }
    }

    foreach ($test in $tests) {
        $top = $test.Top
        Write-Host "`n========================================"
        Write-Host "Running: $($test.Name) [$top]"
        Write-Host '========================================'
        $testPassed = $false
        $reason = ''

        try {
            if (-not $test.Unit) {
                # Remove stale assembler products so an unsuccessful assembly
                # cannot accidentally run a previous program.
                Remove-Item output.mem, output.lst -ErrorAction SilentlyContinue
                $assemblyOutput = & python '..\Assembler\assembler.py' ("assembly\" + $test.Program + '.asm') '..\Assembler\instructions.json' 2>&1
                $assemblyText = $assemblyOutput -join "`n"
                if (($LASTEXITCODE -ne 0) -or
                    ($assemblyText -match '(?i)syntax error|traceback|error:') -or
                    (-not (Test-Path 'output.mem')) -or (-not (Test-Path 'output.lst'))) {
                    throw "Assembly failed: $($test.Program) $assemblyText"
                }
            }

            # The memory dump is output, not an input. Remove any previous
            # dump before every full-processor simulation to reject stale data.
            if (-not $test.Unit) {
                Remove-Item 'scc_out.txt' -ErrorAction SilentlyContinue
            }

#===========================================
# SELECT VERILOG SOURCE FILES
#===========================================
# Preserve the source list as a PowerShell array,
# even when a unit test uses only one RTL module.
#
# PowerShell can otherwise unwrap a single-element
# collection into a scalar string. Splatting that
# string into a native command can cause its
# characters to be interpreted as separate paths.
#
# Full-processor tests use the complete SCC RTL.
# Unit tests use only their explicitly required
# controller/datapath/ROM modules.

if ($test.Unit) {
    $sources = @($unitSources[$top])
} else {
    $sources = @($rtl)
}

# Reject missing or empty source lists before
# invoking the Verilog compiler.
if ($sources.Count -eq 0) {
    throw "No RTL sources defined for $top"
}            $vvpFile = Join-Path $resultsDir ($top + '.vvp')
            $compileOutput = & iverilog -g2005 -Wall -Wno-timescale -s $top -o $vvpFile ("verification\" + $top + '.v') @sources 2>&1
            $compileExit = $LASTEXITCODE
            if ($compileOutput) { $compileOutput | ForEach-Object { Write-Host $_ } }
            if ($compileExit -ne 0) { throw "Compile failed: $top" }

            $simulationOutput = & vvp $vvpFile 2>&1
            $simulationExit = $LASTEXITCODE
            $simulationText = $simulationOutput -join "`n"
            $simulationOutput | Set-Content (Join-Path $resultsDir ($top + '.log'))
            $simulationOutput | ForEach-Object { Write-Host $_ }

            # Match the marker as a complete line. Do not accept a substring
            # of 'TEST FAILED', or a PASS marker accompanied by other failures.
            $passPattern = '(?m)^\s*' + [regex]::Escape($test.Expected) + '\s*$'
            $hasPass = $simulationText -match $passPattern
            $hasFailure = $simulationText -match '(?im)\bFAIL:|TEST FAILED|REGRESSION FAILED|\berrors\s*=\s*[1-9][0-9]*\b|Verification errors\s*=\s*[1-9][0-9]*\b|Failed checks\s*:\s*[1-9][0-9]*\b'
            $testPassed = ($simulationExit -eq 0) -and $hasPass -and (-not $hasFailure)
            if (-not $testPassed) { $reason = 'Missing exact PASS marker, a FAIL diagnostic, or nonzero simulator exit.' }
        } catch {
            $reason = $_.Exception.Message
            $testPassed = $false
        }

        if ($testPassed) {
            $passed++
            Write-Host "RESULT: PASS - $($test.Name)"
        } else {
            $failed++
            $failedNames += $test.Name
            Write-Host "RESULT: FAIL - $($test.Name) ($reason)"
        }
    }
} finally {
    # Restore exact original directory state, even if a test throws.
    foreach ($file in $preservedFiles) {
        if ($saved.ContainsKey($file)) {
            if ($saved[$file]) {
                Copy-Item -LiteralPath (Join-Path $resultsDir ('saved_' + $file)) -Destination $file -Force
            } else {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Pop-Location
}

Write-Host "`n========================================"
Write-Host 'SCC CP5 FULL REGRESSION SUMMARY'
Write-Host '========================================'
Write-Host "Passed: $passed / $($tests.Count)"
Write-Host "Failed: $failed"
if ($failed -eq 0 -and $passed -eq $tests.Count) {
    Write-Host 'CP5 FULL REGRESSION PASSED'
} else {
    Write-Host 'CP5 FULL REGRESSION FAILED'
    foreach ($name in $failedNames) { Write-Host "  - $name" }
    exit 1
}
