# Functional test for the three things added for stacked-backup training data:
#
#   1. .1.backup / .2.backup grouping onto the primary
#   2. the recency check - primary must be newer by BOTH modified time and the
#      last timestamp in the file - and the "are you sure?" it raises
#   3. column alignment: NAN fill, dropped columns, re-order, and the refusals
#
# Loads the functions via the AST and stubs every dialog, so the whole file runs
# unattended with no window opening.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Combine DAT files.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$want = 'Split-CsvLine', 'Split-CsvFieldsRaw', 'Get-FirstFieldRaw', 'Read-DataFileLines',
        'Get-SortedDataRows', 'Get-FileBomEncoding', 'Resolve-OutputEncoding',
        'Start-MergeTimer', 'Show-SlowHintIfNeeded', 'Backup-File', 'Test-NonAsciiCharacters',
        'Get-Toa5EnvironmentFields', 'Get-DuplicateGroups', 'Add-Toa5SerialTableGroups',
        'Get-LastDataTimestamp', 'Test-PrimaryIsNewer', 'Get-ColumnAlignment',
        'ConvertTo-AlignedRow', 'Get-ColumnStats', 'Get-ColumnStatsTable',
        'Invoke-CombineForPrimary'
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}

# Dialog stubs. Each records what it was handed, so a test can assert on what the
# real dialog WOULD have offered rather than only on the answer given back.
$script:lastOffer = $null
$script:lastBlocked = $null
$script:statsShown = $null
$script:recencyAsked = $null
$script:headerAnswer = 'Proceed'
$script:statsAnswer = 'Proceed'
$script:recencyAnswer = $true
function Show-Notification { param($Message, $Title, $Icon) }
function Show-HeaderComparison {
    param($PrimaryHeader, $SecondaryHeader, $PrimaryName, $SecondaryName, $RowNumber, $ComparisonTitle, $AlignOffer, $AlignBlockedReason)
    if ($RowNumber -eq 2) { $script:lastOffer = $AlignOffer; $script:lastBlocked = $AlignBlockedReason }
    # Only ever answer Align when the real dialog would have had the button.
    if ($script:headerAnswer -eq 'Align' -and $RowNumber -eq 2) {
        return $(if ($AlignOffer) { 'Align' } else { 'Decline' })
    }
    return 'Proceed'
}
function Show-ColumnStatsComparison {
    param($StatRows, $PrimaryName, $SecondaryName, $FilledColumns, $DroppedColumns)
    $script:statsShown = $StatRows
    return $script:statsAnswer
}
function Confirm-RecencyOverride {
    param($PrimaryName, $SecondaryName, $Recency)
    $script:recencyAsked = $Recency.Reason
    return $script:recencyAnswer
}

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('aln_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$ENVROW = '"TOA5","TM_Test","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","cell_diag"'

function New-File {
    param([string]$Path, [string[]]$Names, [string[]]$Rows)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $units = (($Names | ForEach-Object { '""' }) -join ',')
    $hdr = @($ENVROW, (($Names | ForEach-Object { "`"$_`"" }) -join ','), $units, $units)
    [System.IO.File]::WriteAllLines($Path, ([string[]]($hdr + $Rows)), (New-Object System.Text.UTF8Encoding($false)))
    $last = [regex]::Match($Rows[-1], '^"?(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
    if ($last.Success) { (Get-Item -LiteralPath $Path).LastWriteTime = [datetime]$last.Groups[1].Value }
}
function Case([string]$Name) {
    $d = Join-Path $root $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}
function Get-DataRows([string]$Path) { @(Get-Content -LiteralPath $Path | Select-Object -Skip 4 | Where-Object { $_ }) }
function Reset { $script:lastOffer = $null; $script:lastBlocked = $null; $script:statsShown = $null
                 $script:recencyAsked = $null; $script:headerAnswer = 'Proceed'
                 $script:statsAnswer = 'Proceed'; $script:recencyAnswer = $true }

try {

# ---------------------------------------------------------------------------
Write-Host "`n=== 1. stacked backup suffixes group onto the primary ===" -ForegroundColor Cyan
$d = Case 'suffixes'
foreach ($n in 'X_cell_diag.dat', 'X_cell_diag.dat.backup', 'X_cell_diag.dat.1.backup',
               'X_cell_diag.dat.2.backup', 'X_cell_diag.dat.1', 'X_cell_diag.dat.bak.old') {
    New-File (Join-Path $d $n) @('TIMESTAMP', 'RECORD') @('"2026-01-01 00:00:00",0')
}
# Not a backup of anything: a different data file that happens to sit alongside.
New-File (Join-Path $d 'X_other.dat') @('TIMESTAMP', 'RECORD') @('"2026-01-01 00:00:00",0')

$g = @(Get-DuplicateGroups -Folder $d)
Check 'exactly one group' ($g.Count -eq 1) "$($g.Count) groups"
Check 'primary is the bare .dat' ([IO.Path]::GetFileName($g[0].Primary) -eq 'X_cell_diag.dat') $g[0].Primary
$secNames = @($g[0].Secondaries | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
Check '.1.backup matched' ($secNames -contains 'X_cell_diag.dat.1.backup') ($secNames -join ',')
Check '.2.backup matched' ($secNames -contains 'X_cell_diag.dat.2.backup') ($secNames -join ',')
Check 'plain .backup still matched' ($secNames -contains 'X_cell_diag.dat.backup') ($secNames -join ',')
Check 'all five backups matched' ($secNames.Count -eq 5) ($secNames -join ',')

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. the recency check ===" -ForegroundColor Cyan
$new = [datetime]'2026-09-16 09:00:00'
$old = [datetime]'2026-07-22 15:00:00'
$r = Test-PrimaryIsNewer -PrimaryModified $new -SecondaryModified $old -PrimaryLastTs '2026-09-16 12:00:00' -SecondaryLastTs '2026-07-22 18:00:00'
Check 'both newer -> Ok' ($r.Ok -and $r.MtimeOk -and $r.TsOk) $r.Reason

$r = Test-PrimaryIsNewer -PrimaryModified $old -SecondaryModified $new -PrimaryLastTs '2026-09-16 12:00:00' -SecondaryLastTs '2026-07-22 18:00:00'
Check 'older mtime -> not Ok' ((-not $r.Ok) -and (-not $r.MtimeOk) -and $r.TsOk) $r.Reason
Check 'mtime failure is named' ($r.Reason -match 'modified time') $r.Reason

$r = Test-PrimaryIsNewer -PrimaryModified $new -SecondaryModified $old -PrimaryLastTs '2026-07-22 18:00:00' -SecondaryLastTs '2026-09-16 12:00:00'
Check 'older last timestamp -> not Ok' ((-not $r.Ok) -and $r.MtimeOk -and (-not $r.TsOk)) $r.Reason
Check 'timestamp failure is named' ($r.Reason -match 'last timestamp') $r.Reason

$r = Test-PrimaryIsNewer -PrimaryModified $new -SecondaryModified $old -PrimaryLastTs '2026-09-16 12:00:00' -SecondaryLastTs '09/16/2026 11:00:00'
Check 'unreadable timestamp is a failure, not a pass' ((-not $r.Ok) -and (-not $r.TsOk)) $r.Reason

$r = Test-PrimaryIsNewer -PrimaryModified $new -SecondaryModified $new -PrimaryLastTs '2026-09-16 12:00:00' -SecondaryLastTs '2026-09-16 12:00:00'
Check 'equal on both counts is not "newer"' (-not $r.Ok) $r.Reason

# The dialog lays the four values out in a grid, so it needs them back, not just
# the verdict and a sentence.
$r = Test-PrimaryIsNewer -PrimaryModified $new -SecondaryModified $old -PrimaryLastTs '2026-09-16 12:00:00' -SecondaryLastTs '09/16/2026 11:00:00'
Check 'result carries the raw values for the dialog' `
    (($r.PrimaryModified -eq $new) -and ($r.SecondaryModified -eq $old) -and
     ($r.PrimaryLastTs -eq '2026-09-16 12:00:00') -and ($r.SecondaryLastTs -eq '09/16/2026 11:00:00')) 'values missing'
Check 'result says whether the timestamps were comparable at all' (-not $r.TsComparable) 'TsComparable wrong'

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. column alignment mapping ===" -ForegroundColor Cyan
$P2 = '"TIMESTAMP","RECORD","RSSI","cell_info"'
$S2 = '"TIMESTAMP","RECORD","RSSI","PingSpeed","PingResult","cell_info"'   # the cell_diag shape
$a = Get-ColumnAlignment -PrimaryHeaderRow $P2 -SecondaryHeaderRow $S2
Check 'subset: Ok' $a.Ok $a.Reason
Check 'subset: two columns dropped' (@($a.Dropped).Count -eq 2 -and $a.Dropped -contains 'PingSpeed') ($a.Dropped -join ',')
Check 'subset: nothing filled' (@($a.Filled).Count -eq 0) ($a.Filled -join ',')
Check 'subset: NOT a re-order' (-not $a.Reordered) 'flagged as re-order'
Check 'subset: map skips the dropped fields' ((($a.Map) -join ',') -eq '0,1,2,5') (($a.Map) -join ',')

$a = Get-ColumnAlignment -PrimaryHeaderRow $S2 -SecondaryHeaderRow $P2
Check 'superset: two columns filled NAN' (@($a.Filled).Count -eq 2 -and $a.Filled -contains 'PingResult') ($a.Filled -join ',')
Check 'superset: fills map to -1' ((($a.Map) -join ',') -eq '0,1,2,-1,-1,3') (($a.Map) -join ',')

$a = Get-ColumnAlignment -PrimaryHeaderRow '"TIMESTAMP","A","B"' -SecondaryHeaderRow '"TIMESTAMP","B","A"'
Check 're-order detected' ($a.Ok -and $a.Reordered) "Ok=$($a.Ok) Reordered=$($a.Reordered)"

$a = Get-ColumnAlignment -PrimaryHeaderRow '"TIMESTAMP","A"' -SecondaryHeaderRow '"timestamp","a"'
Check 'name match is case-insensitive, and a no-op' ($a.Ok -and $a.NoOp) "Ok=$($a.Ok) NoOp=$($a.NoOp)"

$a = Get-ColumnAlignment -PrimaryHeaderRow '"TIMESTAMP","A","A"' -SecondaryHeaderRow '"TIMESTAMP","A","B"'
Check 'duplicate column name refused' ((-not $a.Ok) -and $a.Reason -match 'repeats') $a.Reason

$a = Get-ColumnAlignment -PrimaryHeaderRow '"TIMESTAMP","A"' -SecondaryHeaderRow '"TS","A"'
Check 'unmatched first column refused' ((-not $a.Ok) -and $a.Reason -match "no column named") $a.Reason

$a = Get-ColumnAlignment -PrimaryHeaderRow '"TIMESTAMP","A"' -SecondaryHeaderRow '"X","Y"'
Check 'no shared names refused' (-not $a.Ok) $a.Reason

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. rewriting a data row ===" -ForegroundColor Cyan
$row = '"2026-01-01 00:00:00",5,-91,123,"Ping OK","a,b"'
$a = Get-ColumnAlignment -PrimaryHeaderRow $P2 -SecondaryHeaderRow $S2
$outRow = ConvertTo-AlignedRow -Line $row -Map $a.Map
Check 'quoting survives byte for byte' ($outRow -eq '"2026-01-01 00:00:00",5,-91,"a,b"') $outRow

$a2 = Get-ColumnAlignment -PrimaryHeaderRow $S2 -SecondaryHeaderRow $P2
Check 'missing columns become unquoted NAN' `
    ((ConvertTo-AlignedRow -Line '"2026-01-01 00:00:00",5,-91,"a,b"' -Map $a2.Map) -eq '"2026-01-01 00:00:00",5,-91,NAN,NAN,"a,b"') `
    (ConvertTo-AlignedRow -Line '"2026-01-01 00:00:00",5,-91,"a,b"' -Map $a2.Map)
Check 'a short row fills NAN rather than throwing' `
    ((ConvertTo-AlignedRow -Line '"2026-01-01 00:00:00",5' -Map $a.Map) -eq '"2026-01-01 00:00:00",5,NAN,NAN') `
    (ConvertTo-AlignedRow -Line '"2026-01-01 00:00:00",5' -Map $a.Map)

# ---------------------------------------------------------------------------
Write-Host "`n=== 5. column statistics ===" -ForegroundColor Cyan
$rows = @('"t",1,10', '"t",2,20', '"t",3,NAN', '"t",4,30')
$s = Get-ColumnStats -Rows $rows -Index 2
Check 'numeric column: n excludes NAN' ($s -match 'n=3') $s
Check 'numeric column: min/max' (($s -match 'min=10') -and ($s -match 'max=30')) $s
Check 'numeric column: NAN counted separately' ($s -match 'NAN/blank=1') $s
Check 'numeric column: mean' ($s -match 'mean=20') $s

$s = Get-ColumnStats -Rows @('"t","TRUE"', '"t","TRUE"', '"t","FALSE"', '"t",NAN') -Index 1
Check 'text column: counts by value' ($s -match '2x"TRUE"') $s
Check 'text column: NAN is missing, not a value' (($s -match 'uniq=2') -and ($s -match 'NAN/blank=1')) $s

# A timestamp column is all-distinct by definition. Listing every value at 1x
# would be the widest cell in the dialog and say nothing; the range says it all.
$s = Get-ColumnStats -Rows @('"2026-01-03 00:00:00",1', '"2026-01-01 00:00:00",2', '"2026-01-02 00:00:00",3') -Index 0
Check 'all-distinct text column reports its range, not 1x counts' `
    (($s -match 'all distinct') -and ($s -match 'first=2026-01-01 00:00:00') -and ($s -match 'last=2026-01-03 00:00:00')) $s
Check 'all-distinct column does not list per-value counts' ($s -notmatch '1x"') $s

# ---------------------------------------------------------------------------
Write-Host "`n=== 6. end to end: dropped columns go to RemovedColumns-NotMerged ===" -ForegroundColor Cyan
Reset
$d = Case 'dropped'
$P = Join-Path $d 'X_cell_diag.dat'
$S = Join-Path $d 'X_cell_diag.dat.backup'
New-File $P @('TIMESTAMP', 'RECORD', 'RSSI', 'cell_info')                         @('"2026-09-16 00:00:00",0,-91,"live"')
New-File $S @('TIMESTAMP', 'RECORD', 'RSSI', 'PingSpeed', 'PingResult', 'cell_info') @('"2026-09-13 00:00:00",0,-89,123,"Ping OK","old"')
$script:headerAnswer = 'Align'
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3

Check 'align was offered' ($null -ne $script:lastOffer) "blocked: $script:lastBlocked"
Check 'offer names the dropped columns' ($script:lastOffer -match 'PingSpeed') $script:lastOffer
Check 'no recency prompt - primary is newer' ($null -eq $script:recencyAsked) $script:recencyAsked
Check 'file merged' ($res.FilesProcessed -eq 1) $res.FilesProcessed
$out = Get-DataRows $P
Check 'primary holds both rows' ($out.Count -eq 2) $out.Count
Check 'merged row narrowed to the primary width' `
    (($out | Where-Object { $_ -match '^"2026-09-13' }) -eq '"2026-09-13 00:00:00",0,-89,"old"') `
    ($out | Where-Object { $_ -match '^"2026-09-13' })
Check 'secondary filed under RemovedColumns-NotMerged' `
    (Test-Path (Join-Path $d 'Backup\RemovedColumns-NotMerged\X_cell_diag.dat.backup')) 'not there'
Check 'and NOT in the ordinary Backup folder' `
    (-not (Test-Path (Join-Path $d 'Backup\X_cell_diag.dat.backup'))) 'also in Backup'
Check 'merge log names the dropped columns' `
    ((Get-Content "$P.merge-log.txt" -Raw) -match 'DROPPED \(not merged\): PingSpeed, PingResult') 'not in log'
Check 'no re-order, so no statistics dialog' ($null -eq $script:statsShown) 'stats shown'

# ---------------------------------------------------------------------------
Write-Host "`n=== 7. end to end: a re-order must be proved before it is written ===" -ForegroundColor Cyan
Reset
$d = Case 'reorder'
$P = Join-Path $d 'X_cell_diag.dat'
$S = Join-Path $d 'X_cell_diag.dat.backup'
# A and B hold plainly different quantities, so a bad map would be obvious.
New-File $P @('TIMESTAMP', 'A', 'B') @('"2026-09-16 00:00:00",10.0,200.0', '"2026-09-16 01:00:00",11.0,201.0')
New-File $S @('TIMESTAMP', 'B', 'A') @('"2026-09-13 00:00:00",202.0,12.0', '"2026-09-13 01:00:00",203.0,13.0')

# 7a. Declining at the statistics dialog must leave the primary untouched.
$script:headerAnswer = 'Align'
$script:statsAnswer = 'Decline'
$before = Get-Content -LiteralPath $P -Raw
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3
Check 'statistics were shown' ($null -ne $script:statsShown) 'not shown'
Check 'declining merges nothing' ($res.FilesProcessed -eq 0) $res.FilesProcessed
Check 'declining leaves the primary byte-identical' ((Get-Content -LiteralPath $P -Raw) -eq $before) 'primary changed'
Check 'declining leaves the secondary in place' (Test-Path $S) 'secondary moved'

# 7b. Accepting writes the aligned rows, columns swapped back into place.
$script:statsAnswer = 'Proceed'
$script:statsShown = $null
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3
Check 'accepting merges the file' ($res.FilesProcessed -eq 1) $res.FilesProcessed
$out = Get-DataRows $P
Check 'primary holds all four rows' ($out.Count -eq 4) $out.Count
$aVals = @($out | ForEach-Object { [double](($_ -split ',')[1]) })
Check 'column A holds only A values after the swap' (($aVals | Where-Object { $_ -gt 100 }).Count -eq 0) ($aVals -join ',')
$bVals = @($out | ForEach-Object { [double](($_ -split ',')[2]) })
Check 'column B holds only B values after the swap' (($bVals | Where-Object { $_ -lt 100 }).Count -eq 0) ($bVals -join ',')
$stat = @($script:statsShown | Where-Object { $_.Name -eq 'A' })[0]
Check 'the A statistics compare like with like' `
    (($stat.Before -match 'max=11') -and ($stat.Secondary -match 'max=13') -and ($stat.After -match 'max=13')) `
    "$($stat.Before) | $($stat.Secondary) | $($stat.After)"
Check 'statistics land in the merge log too' `
    ((Get-Content "$P.merge-log.txt" -Raw) -match 'before : n=2') 'not in log'

# ---------------------------------------------------------------------------
Write-Host "`n=== 8. a failed recency check blocks alignment outright ===" -ForegroundColor Cyan
Reset
$d = Case 'stale-primary'
$P = Join-Path $d 'X_cell_diag.dat'
$S = Join-Path $d 'X_cell_diag.dat.backup'
# The wrong way round on purpose: the SECONDARY holds the newer readings.
New-File $P @('TIMESTAMP', 'A', 'B') @('"2026-01-01 00:00:00",10.0,200.0')
New-File $S @('TIMESTAMP', 'B', 'A') @('"2026-09-13 00:00:00",202.0,12.0')
$script:headerAnswer = 'Align'
$script:recencyAnswer = $false
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3

Check 'the recency prompt was raised' ($null -ne $script:recencyAsked) 'not asked'
Check 'answering No merges nothing' ($res.FilesProcessed -eq 0) $res.FilesProcessed
Check 'secondary left where it was' (Test-Path $S) 'secondary moved'

# Same files, but this time say yes to the recency prompt. Alignment must STILL
# be unavailable - there is no override for it.
Reset
$script:headerAnswer = 'Align'
$script:recencyAnswer = $true
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3
Check 'align not offered even after confirming recency' ($null -eq $script:lastOffer) $script:lastOffer
Check 'and the reason given is the recency check' ($script:lastBlocked -match 'not newer') $script:lastBlocked
Check 'no statistics dialog, because nothing was aligned' ($null -eq $script:statsShown) 'stats shown'

# Same files again, this time answering Proceed Anyway (Enter) on the header
# dialog. That used to merge the re-ordered rows under the primary's names.
Reset
$script:headerAnswer = 'Proceed'
$script:recencyAnswer = $true
$before = Get-Content -LiteralPath $P -Raw
$res = Invoke-CombineForPrimary -PrimaryPath $P -SecondaryPaths @($S) -SpecialRowCount 3
Check 'blocked-align Proceed merges nothing' ($res.FilesProcessed -eq 0) $res.FilesProcessed
Check 'blocked-align Proceed leaves the primary byte-identical' ((Get-Content -LiteralPath $P -Raw) -eq $before) 'primary changed'
Check 'blocked-align Proceed leaves the secondary in place' (Test-Path $S) 'secondary moved'
Check 'align was blocked, not offered' ($null -eq $script:lastOffer -and $script:lastBlocked -match 'not newer') "$script:lastOffer / $script:lastBlocked"

} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red; exit 1 }
