# run_f26_demo.ps1
# Runs this semester's class testcases (F26_Testcases, from the class GitHub
# CP5_Testing/Testcases) on our SCC, then optionally forces an error in each.
#
# Run from CP5_RunningTestcases:
#   .\verification\run_f26_demo.ps1                      # all nine, normal (expect PASS)
#   .\verification\run_f26_demo.ps1 -Force               # all nine, fault injected (expect DETECTED)
#   .\verification\run_f26_demo.ps1 -Test box_calc       # one testcase
#   .\verification\run_f26_demo.ps1 -Test box_calc -Force
#
# Notes
# - Every testbench instantiates scc_f26_top directly; no adapter is needed.
# - Group 1's tb_scc_f26_top_g4.v and Group 2's bit_packed_physics_updater_tb_g4.v are copies
#   whose waveform/debug wires were remapped to our hierarchy (their originals reference the
#   authors' internal names, e.g. uut.instruction_and_data.memory). No check was changed.
# - Group 1's testbench only checks that the program ends with a clean HALT; the group checks
#   results by comparing scc_out.txt against the emulator. So for Group 1 a test passes only
#   when the testbench passes AND SelfChecker reports Data Memory: PASS.
# - temp.asm never stores its result to memory, so a wrong result cannot be detected by any
#   check; its forced error therefore breaks HALT (NOHALT) instead.
# - Every run also prints SelfChecker against the emulator output in verification\golden\.
# - Final CP6 stack base is 0xFFC0 (R13 reset); the historical 0xE000 comment was stale.
# - Passing an application testcase does not imply full memory equivalence.

param(
    [switch]$Force,
    [string]$Test = '',
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot

# F26_Testcases may sit next to CP5_RunningTestcases or one folder higher.
$caseRoot = @((Join-Path '..' 'F26_Testcases'), (Join-Path '..' (Join-Path '..' 'F26_Testcases'))) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $caseRoot) { Pop-Location; throw 'F26_Testcases folder not found next to or above CP5_RunningTestcases.' }
$goldenDir = Join-Path 'verification' 'golden'
$selfChecker = Join-Path '..' (Join-Path 'SelfChecker' 'SelfChecker.py')
$resultsDir = Join-Path $PSScriptRoot $(if ($Force) { 'results_f26_forced' } else { 'results_f26' })
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

# NeedsEmu = result checking is done with SelfChecker against the emulator (Group 1's method).
$cases = @(
    @{ Group = 'Group1'; Name = 'sqrt';                       Tb = 'tb_scc_f26_top_g4.v';                 Pass = 'SUCCESS: program ended as expected';           NeedsEmu = $true;  Fault = 'MUL' },
    @{ Group = 'Group1'; Name = 'temp';                       Tb = 'tb_scc_f26_top_g4.v';                 Pass = 'SUCCESS: program ended as expected';           NeedsEmu = $true;  Fault = 'NOHALT' },
    @{ Group = 'Group2'; Name = 'bit_packed_physics_updater'; Tb = 'bit_packed_physics_updater_tb_g4.v'; Pass = 'ALL 10 ENTITY MEMORY RESULTS MATCHED';         NeedsEmu = $false; Fault = 'LOAD' },
    @{ Group = 'Group2'; Name = 'sensor_log_analyzer';        Tb = 'sensor_log_analyzer_tb.v';           Pass = 'SENSOR LOG ANALYZER: all 25 results matched';  NeedsEmu = $false; Fault = 'DIV' },
    @{ Group = 'Group3'; Name = 'box_calc';                   Tb = 'box_calc_tb.v';                      Pass = 'BOX CALCULATOR: all 35 words match';           NeedsEmu = $false; Fault = 'MUL' },
    @{ Group = 'Group3'; Name = 'max_find';                   Tb = 'max_find_tb.v';                      Pass = 'MAX FIND TEST PASSED';                         NeedsEmu = $false; Fault = 'LOAD' },
    @{ Group = 'Group4'; Name = 'bubble_sort';                Tb = 'tb_bubble_sort.v';                   Pass = 'CP5 PORTABLE BUBBLE SORT TEST PASSED';         NeedsEmu = $false; Fault = 'LOAD' },
    @{ Group = 'Group4'; Name = 'array_stats_mul';            Tb = 'tb_array_stats_mul.v';               Pass = 'CP5 PORTABLE ARRAY STATS TEST PASSED';         NeedsEmu = $false; Fault = 'LOAD' },
    @{ Group = 'Group4'; Name = 'receipt_calculator';         Tb = 'tb_receipt_calculator.v';            Pass = 'RECEIPT TEST PASSED';                          NeedsEmu = $false; Fault = 'POP' }
)

if ($Test -ne '') {
    $cases = @($cases | Where-Object { $_.Name -eq $Test -or $_.Group -eq $Test })
    if ($cases.Count -eq 0) { Pop-Location; throw "Unknown test '$Test'." }
}

$preservedFiles = @('output.mem', 'output.lst', 'scc_out.txt')
$saved = @{}
$good = 0
$bad = 0
$badNames = @()

try {
    foreach ($file in $preservedFiles) {
        $saved[$file] = Test-Path -LiteralPath $file
        if ($saved[$file]) { Copy-Item -LiteralPath $file -Destination (Join-Path $resultsDir ('saved_' + $file)) -Force }
    }

    foreach ($c in $cases) {
        $dir = Join-Path $caseRoot $c.Group
        $tbFile = Join-Path $dir $c.Tb
        Write-Host "`n========================================"
        if ($Force) { Write-Host "Running: $($c.Group) $($c.Name)  FORCED FAULT: $($c.Fault)" }
        else        { Write-Host "Running: $($c.Group) $($c.Name)" }
        Write-Host '========================================'

        $passed = $false
        $note = ''
        try {
            Remove-Item output.mem, output.lst, scc_out.txt -ErrorAction SilentlyContinue
            $asmText = (& $Python (Join-Path '..' (Join-Path 'Assembler' 'assembler.py')) (Join-Path $dir ($c.Name + '.asm')) (Join-Path '..' (Join-Path 'Assembler' 'instructions.json')) 2>&1) -join "`n"
            if (($LASTEXITCODE -ne 0) -or ($asmText -match '(?i)syntax error|traceback') -or -not (Test-Path 'output.mem')) {
                throw "Assembly failed: $asmText"
            }

            $top = (Select-String -Path $tbFile -Pattern '^\s*module\s+(\w+)' | Select-Object -First 1).Matches[0].Groups[1].Value

            
            # Optional fault injection settings.
            # Keep compiler options separate from Verilog source files.
            $faultArgs = @()
            $faultSources = @()

            if ($Force) {
                $instMatch = Select-String -Path $tbFile `
                    -Pattern '^\s*scc_f26_top\s+(?:#\(.*?\)\s*)?(\w+)\s*\(' |
                    Select-Object -First 1

                if (-not $instMatch) {
                    throw 'Could not find SCC instance for fault injection'
                }

                $inst = $instMatch.Matches[0].Groups[1].Value

                $faultArgs = @(
                    '-s', 'fault_inject',
                    "-DFAULT_$($c.Fault)",
                    "-DDUTP=$top.$inst.scc"
                )

                $faultSources = @(
                    (Join-Path 'verification' 'fault_inject.v')
                )
            }

            # Select output file for compiled simulation.
            $vvpFile = Join-Path $resultsDir ($c.Name + '.vvp')

            # Compiler settings and top-level modules.
            $compileArgs = @(
                '-g2012',
                '-Wall',
                '-Wno-timescale',
                '-s', $top
            )

            # Add optional fault-injection settings.
            $compileArgs += $faultArgs

            # Output option must precede source filenames.
            $compileArgs += @('-o', $vvpFile)

            # Add regular testbench and RTL source files.
            $compileArgs += @($tbFile)
            $compileArgs += $rtl

            # Add the fault-injection module only in forced mode.
            $compileArgs += $faultSources

            # Prevent accidentally running a stale compiled simulation.
            Remove-Item -LiteralPath $vvpFile -Force -ErrorAction SilentlyContinue

            # Compile using the complete argument array.
            $compileOutput = & iverilog @compileArgs 2>&1

            if ($LASTEXITCODE -ne 0) {
                $compileOutput | ForEach-Object {
                    Write-Host $_
                }
                throw 'Compile failed'
            }


            $job = Start-Job -ScriptBlock { param($wd, $v) Set-Location $wd; & vvp -n $v 2>&1; "VVP_EXIT=$LASTEXITCODE" } -ArgumentList (Get-Location).Path, (Resolve-Path $vvpFile).Path
            if (-not (Wait-Job $job -Timeout 180)) { Stop-Job $job; $simOutput = @('SIMULATION TIMEOUT (no HALT within 180 s)') }
            else { $simOutput = Receive-Job $job }
            Remove-Job $job -Force
            $simText = ($simOutput -join "`n") -replace "\x1b\[[0-9;]*m", ''
            $simText | Set-Content (Join-Path $resultsDir ($c.Name + '.log'))
            $simText -split "`n" | Where-Object { $_ -notmatch '^\s*\[?PASS\]?:? ' -or $_ -match 'TEST PASSED|MATCHED|all \d+' } | ForEach-Object { Write-Host $_ }

            $tbPassed = ($simText -match [regex]::Escape($c.Pass)) -and
                        -not ($simText -match '(?im)\[FAIL\]|^\s*FAIL[: @]|TEST FAILED|FAILURE:|SIMULATION TIMEOUT|VVP_EXIT=[1-9]')

            $emuPassed = $true
            if (Test-Path 'scc_out.txt') {
                Copy-Item 'scc_out.txt' (Join-Path $resultsDir ($c.Name + '_scc_out.txt')) -Force
                Write-Host '--- SelfChecker: SCC memory vs Rust emulator ---'
                $sc = (& $Python $selfChecker -s 'scc_out.txt' -v (Join-Path $goldenDir ('F26_' + $c.Name + '_memoutput.csv')) -c 2>&1) -replace "\x1b\[[0-9;]*m", ''
                $sc | Select-Object -First 8 | ForEach-Object { Write-Host $_ }
                $emuPassed = (($sc -join "`n") -match 'Data Memory: PASS')
            } elseif ($c.NeedsEmu) {
                $emuPassed = $false
            }

            $passed = $tbPassed -and ((-not $c.NeedsEmu) -or $emuPassed)
        } catch {
            $note = $_.Exception.Message
        }

        if ($Force) {
            if ($note -ne '') { $bad++; $badNames += $c.Name; Write-Host "RESULT: ERROR - $($c.Name) ($note)" }
            elseif (-not $passed) { $good++; Write-Host "RESULT: DETECTED - $($c.Group) $($c.Name) caught fault $($c.Fault)" }
            else { $bad++; $badNames += $c.Name; Write-Host "RESULT: UNDETECTED - $($c.Name) still passed with fault $($c.Fault)" }
        } else {
            if ($passed) { $good++; Write-Host "RESULT: PASS - $($c.Group) $($c.Name)" }
            else { $bad++; $badNames += $c.Name; Write-Host "RESULT: FAIL - $($c.Group) $($c.Name) $note" }
        }
    }
} finally {
    foreach ($file in $preservedFiles) {
        if ($saved.ContainsKey($file)) {
            if ($saved[$file]) { Copy-Item -LiteralPath (Join-Path $resultsDir ('saved_' + $file)) -Destination $file -Force }
            else { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        }
    }
    Pop-Location
}

Write-Host "`n========================================"
if ($Force) {
    Write-Host 'F26 CLASS TESTCASES - FORCED-ERROR SUMMARY'
    Write-Host '========================================'
    Write-Host "Faults detected: $good / $($cases.Count)"
    if ($bad -ne 0) { $badNames | ForEach-Object { Write-Host "  - not detected: $_" }; exit 1 }
} else {
    Write-Host 'F26 CLASS TESTCASES SUMMARY'
    Write-Host '========================================'
    Write-Host "Passed: $good / $($cases.Count)"
    if ($bad -ne 0) { $badNames | ForEach-Object { Write-Host "  - failed: $_" }; exit 1 }
}
