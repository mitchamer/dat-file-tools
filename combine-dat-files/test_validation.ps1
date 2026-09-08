# Functional test for the pre-write checks, -DryRun, and the merge log.
#
# Loads only the functions it needs via the AST and stubs the two dialog
# functions, so the whole file runs unattended with no WinForms assembly.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Combine DAT files.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$want = 'Split-CsvLine', 'Get-FirstFieldRaw', 'Read-DataFileLines', 'Get-SortedDataRows',
        'Get-FileBomEncoding', 'Resolve-OutputEncoding', 'Start-MergeTimer', 'Show-SlowHintIfNeeded',
        'Backup-File', 'Test-NonAsciiCharacters', 'Invoke-CombineForPrimary'
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}

# Dialog stubs. Show-HeaderComparison is deliberately NOT loaded from the source:
# a real run always puts the row-1 comparison up, and the test answers Proceed.
function Show-Notification { param($Message, $Title, $Icon) }
function Show-HeaderComparison { param($PrimaryHeader, $SecondaryHeader, $PrimaryName, $SecondaryName, $RowNumber, $ComparisonTitle) return 'Proceed' }

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('val_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$ENVROW = '"TOA5","TM_Test","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","SAA1_DATA"'
$HDR = @($ENVROW, '"TIMESTAMP","RECORD","V1"', '"TS","RN","m"', '"","","Smp"')

function New-File([string]$Path, [string[]]$Rows, [string[]]$Header = $HDR) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllLines($Path, ([string[]]($Header + $Rows)), (New-Object System.Text.UTF8Encoding($false)))
}
function Row([string]$Ts, [int]$Rec, [string]$V = '1.5') { "`"$Ts`",$Rec,$V" }
function Case([string]$Name) {
    $d = Join-Path $root $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

Write-Host "`n=== -DryRun writes, moves and backs up nothing ===" -ForegroundColor Cyan
$d = Case 'dryrun'
$P = Join-Path $d 'X_SAA1_DATA.dat'
$S = Join-Path $d 'X_SAA1_DATA.dat.backup'
New-File $P @((Row '2026-09-01 01:00:00' 1), (Row '2026-09-01 02:00:00' 2))
New-File $S @((Row '2026-09-01 00:00:00' 0), (Row '2026-09-01 01:00:00' 1))
$before = [System.IO.File]::ReadAllBytes($P)
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -DryRun
Check 'primary byte-for-byte unchanged' (@(Compare-Object $before ([System.IO.File]::ReadAllBytes($P)) -SyncWindow 0).Count -eq 0) 'primary was rewritten'
Check 'secondary left in place' (Test-Path $S) 'secondary was moved'
Check 'no Backup folder created' (-not (Test-Path (Join-Path $d 'Backup'))) 'Backup folder created'
Check 'no merge log written' (-not (Test-Path "$P.merge-log.txt")) 'log written'
Check 'no .combining.tmp left' (@(Get-ChildItem $d -Filter '*.combining.tmp').Count -eq 0) 'temp left'
Check 'reports the one file that would merge' ($res.FilesProcessed -eq 1) $res.FilesProcessed
Check 'reports the row it would add (1 of 2 is a dupe)' ($res.RowsAdded -eq 1) $res.RowsAdded
Check 'reports the row count the primary would hold' ($res.FinalRows -eq 3) $res.FinalRows

Write-Host "`n=== -DryRun reports a row-2 mismatch instead of counting it ===" -ForegroundColor Cyan
$d = Case 'dryrun_mismatch'
$P = Join-Path $d 'Y.dat'
$S = Join-Path $d 'Y.dat.bak'
New-File $P @((Row '2026-09-01 01:00:00' 1))
New-File $S @((Row '2026-09-01 00:00:00' 0)) @($ENVROW, '"TIMESTAMP","RECORD","V1_RENAMED"', '"TS","RN","m"', '"","","Smp"')
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -DryRun
Check 'mismatched file is not counted as a merge' ($res.FilesProcessed -eq 0) $res.FilesProcessed
Check 'no rows counted' ($res.RowsAdded -eq 0) $res.RowsAdded

Write-Host "`n=== a real merge writes a log beside the primary ===" -ForegroundColor Cyan
$d = Case 'log'
$P = Join-Path $d 'Z_SAA1_DATA.dat'
$S = Join-Path $d 'Z_SAA1_DATA.dat.backup'
New-File $P @((Row '2026-09-01 01:00:00' 1))
New-File $S @((Row '2026-09-01 00:00:00' 0))
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -AutoProceedOnHeaderMatch
$logPath = "$P.merge-log.txt"
Check 'log written next to the primary' (Test-Path $logPath) 'no log'
Check 'result carries the log path' ($res.LogPath -eq $logPath) $res.LogPath
$log = Get-Content -LiteralPath $logPath -Raw
Check 'log names the merged secondary' ($log -match 'MERGED\s+.*Z_SAA1_DATA\.dat\.backup') 'secondary not in log'
Check 'log records rows read and contributed' ($log -match 'read 1, new 1') 'per-file counts missing'
Check 'log records the totals' ($log -match 'Files merged:\s+1 of 1' -and $log -match 'New rows added:\s+1') 'totals missing'
Check 'log records the pre-merge backup' ($log -match 'Pre-merge backup:') 'backup not logged'
Check 'secondary really was merged and moved' ((Test-Path (Join-Path $d 'Backup\Z_SAA1_DATA.dat.backup')) -and -not (Test-Path $S)) 'secondary not moved'

Write-Host "`n=== a non-ISO timestamp is reported, because the sort is textual ===" -ForegroundColor Cyan
$d = Case 'badts'
$P = Join-Path $d 'A.dat'
$S = Join-Path $d 'A.dat.bak'
New-File $P @((Row '2026-09-01 01:00:00' 1))
New-File $S @((Row '09/01/2026 00:00:00' 0))
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -AutoProceedOnHeaderMatch
Check 'warns that the secondary is not YYYY-MM-DD' (@($res.Warnings | Where-Object { $_ -match "first data timestamp is '09/01/2026" }).Count -eq 1) ($res.Warnings -join ' | ')
Check 'still merges - it is a warning, not a refusal' ($res.FilesProcessed -eq 1) $res.FilesProcessed

Write-Host "`n=== a column-count mismatch is reported ===" -ForegroundColor Cyan
$d = Case 'badcols'
$P = Join-Path $d 'B.dat'
$S = Join-Path $d 'B.dat.bak'
New-File $P @((Row '2026-09-01 01:00:00' 1))
New-File $S @('"2026-09-01 00:00:00",0')
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -AutoProceedOnHeaderMatch
Check 'warns 2 fields against a 3-column header' (@($res.Warnings | Where-Object { $_ -match 'has 2 field\(s\) but the header names 3' }).Count -eq 1) ($res.Warnings -join ' | ')

Write-Host "`n=== rows sharing a timestamp but differing are kept and counted ===" -ForegroundColor Cyan
$d = Case 'conflict'
$P = Join-Path $d 'C.dat'
$S = Join-Path $d 'C.dat.bak'
New-File $P @((Row '2026-09-01 00:00:00' 0 '1.5'), (Row '2026-09-01 01:00:00' 1 '1.5'))
New-File $S @((Row '2026-09-01 00:00:00' 0 '9.9'))
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -AutoProceedOnHeaderMatch
Check 'one timestamp conflict counted' ($res.TsConflicts -eq 1) $res.TsConflicts
Check 'the conflicting timestamp is named' (@($res.Warnings | Where-Object { $_ -match '2026-09-01 00:00:00' }).Count -eq 1) ($res.Warnings -join ' | ')
$kept = @(Get-Content -LiteralPath $P | Select-Object -Skip 4 | Where-Object { $_ })
Check 'both conflicting rows are kept' ($kept.Count -eq 3) $kept.Count

Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red }
Write-Host "fixtures: $root" -ForegroundColor DarkGray
if ($fail -gt 0) { exit 1 }
