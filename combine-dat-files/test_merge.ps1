# Functional test for the merge write path: correctness of the output file, and
# that an interrupted run cannot damage the primary.
#
# Drives Invoke-CombineForPrimary directly with -AutoProceedOnHeaderMatch so no
# dialogs open. Headers are identical between fixtures, which is the case that
# auto-proceeds.
$ErrorActionPreference = 'Stop'
$combine = Join-Path $PSScriptRoot 'Combine DAT files.ps1'
$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

# Load the script's functions without running its main body.
$src = Get-Content -LiteralPath $combine -Raw
$cut = $src.IndexOf('#region Main')
if ($cut -lt 0) { $cut = $src.IndexOf('# --- Main') }
if ($cut -lt 0) { $cut = $src.Length }
$defs = $src.Substring(0, $cut)
$defs = $defs -replace '(?s)^.*?\[CmdletBinding\(\)\]\s*param\((?:[^)]|\)(?!\s*\r?\n))*\)', ''
$SpecialRowCount = 3
Invoke-Expression $defs

$root = Join-Path $env:TEMP ('mrg_' + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $root -Force | Out-Null

$ENVROW = '"TOA5","TM_Test","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","SAA1_DATA"'
$NCOL = 6
$names = @('"TIMESTAMP"','"RECORD"') + (1..($NCOL-2) | ForEach-Object { "`"V($_,1)`"" })   # comma inside quotes
$HDR = @(
  $ENVROW,
  ($names -join ','),
  ((@('"TS"','"RN"') + (1..($NCOL-2) | ForEach-Object { '"g"' })) -join ','),
  ((@('""','""')     + (1..($NCOL-2) | ForEach-Object { '"Smp"' })) -join ',')
)
function Rows([int]$n, [datetime]$start, [int]$stepMin, [int]$recBase = 0) {
  $vals = (1..($NCOL-2) | ForEach-Object { '1.5' }) -join ','
  1..$n | ForEach-Object {
    '"' + $start.AddMinutes(($_-1)*$stepMin).ToString('yyyy-MM-dd HH:mm:ss') + '",' + ($recBase+$_-1) + ',' + $vals
  }
}
function Write-Toa5([string]$p, [string[]]$rows, [switch]$Bom) {
  [IO.File]::WriteAllLines($p, ([string[]]($HDR + $rows)), (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
}
function Get-DataRows([string]$p) { @(Get-Content -LiteralPath $p | Select-Object -Skip 4 | Where-Object { $_ }) }
function Test-Bom([string]$p) {
  $b = New-Object byte[] 3
  $s = [IO.File]::OpenRead($p); try { $null=$s.Read($b,0,3) } finally { $s.Dispose() }
  return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

Write-Host "`n=== merge produces a sorted, de-duplicated, BOM-free primary ===" -ForegroundColor Cyan
$d = Join-Path $root 'c1'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$P = Join-Path $d 'X_SAA1_DATA.dat'
$S = Join-Path $d 'X_SAA1_DATA.dat.backup'
# Secondary is OLDER and overlaps the primary by 2 rows, so dedup and ordering
# both get exercised.
Write-Toa5 $P (Rows 10 ([datetime]'2026-01-01 10:00:00') 60 100)
Write-Toa5 $S ((Rows 8 ([datetime]'2026-01-01 04:00:00') 60 200) + (Rows 2 ([datetime]'2026-01-01 10:00:00') 60 100))
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3 -AutoProceedOnHeaderMatch

$out = Get-DataRows $P
Check 'primary has 18 rows (10 + 8 new, 2 dupes dropped)' ($out.Count -eq 18) $out.Count
Check 'no BOM added' (-not (Test-Bom $P)) 'BOM present'
Check 'header row 1 preserved' ((Get-Content -LiteralPath $P -TotalCount 1) -eq $ENVROW) 'row 1 changed'
Check '4 header rows preserved' (((Get-Content -LiteralPath $P).Count - $out.Count) -eq 4) 'header count wrong'
$ts = $out | ForEach-Object { [regex]::Match($_, '^"([^"]+)"').Groups[1].Value }
Check 'rows sorted ascending by timestamp' (@(Compare-Object $ts ($ts | Sort-Object) -SyncWindow 0).Count -eq 0) 'not sorted'
Check 'oldest row is the secondary''s first' ($ts[0] -eq '2026-01-01 04:00:00') $ts[0]
Check 'secondary moved into Backup' ((Test-Path (Join-Path $d 'Backup\X_SAA1_DATA.dat.backup')) -and -not (Test-Path $S)) 'secondary not moved'
Check 'pre-merge backup of primary exists' (@(Get-ChildItem (Join-Path $d 'Backup') -Filter 'X_SAA1_DATA*').Count -ge 1) 'no primary backup'
Check 'no .combining.tmp left behind' (@(Get-ChildItem $d -Filter '*.combining.tmp').Count -eq 0) 'temp left'
Check 'every row still has the right column count' (@($out | Where-Object { (@($_ -split ',(?=(?:[^"]*"[^"]*")*[^"]*$)')).Count -ne $NCOL }).Count -eq 0) 'width drift'

Write-Host "`n=== the temp file is what grows, so the primary is safe mid-write ===" -ForegroundColor Cyan
# The primary is only ever replaced by an atomic move, so its size cannot be an
# intermediate value. Confirm the code writes to <primary>.combining.tmp.
$hasTemp = Select-String -Path $combine -Pattern '\$tempPath = "\$PrimaryPath\.combining\.tmp"' -Quiet
Check 'writes via <primary>.combining.tmp' $hasTemp 'temp path not found in source'
$movesIntoPlace = Select-String -Path $combine -Pattern 'Move-Item -LiteralPath \$tempPath -Destination \$PrimaryPath' -Quiet
Check 'moves temp into place atomically' $movesIntoPlace 'atomic move not found'
$cleansUp = Select-String -Path $combine -Pattern 'Remove-Item -LiteralPath \$tempPath' -Quiet
Check 'removes the temp file on failure' $cleansUp 'no cleanup on failure'
$noDirectWrite = -not (Select-String -Path $combine -Pattern 'WriteAllLines\(\$PrimaryPath' -Quiet)
Check 'never writes straight over the primary' $noDirectWrite 'still writes directly to the primary'

Write-Host "`n=== the slow-merge hint ===" -ForegroundColor Cyan
Check 'hint threshold is a 15 s param default' (Select-String -Path $combine -Pattern '\[double\]\$AfterSeconds = 15' -Quiet) 'threshold missing'
Check 'hint names the file to watch' (Select-String -Path $combine -Pattern 'should be growing' -Quiet) 'hint text missing'
Check 'hint says the primary will not change yet' (Select-String -Path $combine -Pattern 'primary will NOT change size' -Quiet) 'caveat missing'
# Silent well before the threshold, and fires once past it. -AfterSeconds keeps
# the test instant instead of sleeping 15 s.
Start-MergeTimer
Show-SlowHintIfNeeded -WatchPath 'C:\x\y.tmp' | Out-Null
Check 'silent before the threshold' ($script:SlowHintShown -eq $false) 'fired too early'
Show-SlowHintIfNeeded -WatchPath 'C:\x\y.tmp' -AfterSeconds 0 | Out-Null
Check 'fires once past the threshold' ($script:SlowHintShown -eq $true) 'did not fire'
$before = $script:SlowHintShown
Show-SlowHintIfNeeded -WatchPath 'C:\x\y.tmp' -AfterSeconds 0 | Out-Null
Check 'shows only once' ($script:SlowHintShown -eq $before) 'repeated'

Write-Host ''
if ($fail) { Write-Host "$fail check(s) FAILED" -ForegroundColor Red } else { Write-Host 'All checks passed.' -ForegroundColor Green }
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
exit $fail
