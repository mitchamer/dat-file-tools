# Functional test for the unattended append path: 'Combine DAT files.ps1'
# -SecondaryFile/-Unattended, and the name pairing in Append-NewData.ps1.
#
# Unlike the other suites this one runs the scripts as CHILD PROCESSES rather
# than loading their functions, because what is under test is exactly what the
# in-process suites stub out: that no dialog is raised, and that the exit code
# says whether every file merged. A dialog in an unattended run would hang the
# child, so each run is given a time limit and a timeout counts as a failure.
$ErrorActionPreference = 'Stop'
$combine = Join-Path $PSScriptRoot 'Combine DAT files.ps1'
$append  = Join-Path $PSScriptRoot 'Append-NewData.ps1'
$psHost  = (Get-Process -Id $PID).Path
$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('unatt_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null

# Runs one of the scripts and returns its exit code and console output. A run
# that is still alive after the limit is killed and reported as a timeout: that
# is what a dialog waiting for a click looks like from out here.
function Invoke-Script([string]$Script, [string[]]$ScriptArgs, [int]$LimitMs = 120000) {
    $stem = Join-Path $root ('run_' + [guid]::NewGuid().ToString('N').Substring(0,6))
    $quoted = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$Script`"") +
              ($ScriptArgs | ForEach-Object { if ($_ -like '-*') { $_ } else { "`"$_`"" } })
    $p = Start-Process -FilePath $psHost -ArgumentList $quoted -NoNewWindow -PassThru `
                       -RedirectStandardOutput "$stem.out" -RedirectStandardError "$stem.err"
    if (-not $p.WaitForExit($LimitMs)) {
        try { $p.Kill() } catch { }
        return @{ Code = -1; Out = 'TIMED OUT - the run is waiting on something, probably a dialog.' }
    }
    $out = (Get-Content -LiteralPath "$stem.out" -Raw -ErrorAction SilentlyContinue) +
           (Get-Content -LiteralPath "$stem.err" -Raw -ErrorAction SilentlyContinue)
    return @{ Code = $p.ExitCode; Out = [string]$out }
}

# A TOA5 fixture. Station name (row 1 field 2) and table name (row 1 field 8)
# are separate knobs because the unattended path treats them differently. The
# modified time follows the last row, the way a file being collected into does,
# so "which file is newer" is a real question and not an artefact of the test.
function New-Dat {
    param(
        [string]$Path,
        [string]$Station = '18421',
        [string]$Table = 'SAA1_DATA',
        [string[]]$Cols = @('"BattV"', '"PTemp"'),
        [datetime]$Start = ([datetime]'2026-01-01 00:00:00'),
        [int]$Count = 5,
        [int]$RecBase = 0,
        [switch]$Bom
    )
    $hdr = @(
        ('"TOA5","{0}","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","{1}"' -f $Station, $Table),
        ((@('"TIMESTAMP"', '"RECORD"') + $Cols) -join ','),
        ((@('"TS"', '"RN"') + ($Cols | ForEach-Object { '"Volts"' })) -join ','),
        ((@('""', '""')     + ($Cols | ForEach-Object { '"Smp"' })) -join ',')
    )
    $vals = ($Cols | ForEach-Object { '12.4' }) -join ','
    $rows = 1..$Count | ForEach-Object {
        '"' + $Start.AddMinutes(($_ - 1) * 60).ToString('yyyy-MM-dd HH:mm:ss') + '",' + ($RecBase + $_ - 1) + ',' + $vals
    }
    [System.IO.File]::WriteAllLines($Path, [string[]]($hdr + $rows), (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
    (Get-Item -LiteralPath $Path).LastWriteTime = [datetime]([regex]::Match($rows[-1], '^"([^"]+)"').Groups[1].Value)
}
function Get-DataRows([string]$p) { @(Get-Content -LiteralPath $p | Select-Object -Skip 4 | Where-Object { $_ }) }
function Test-Bom([string]$p) {
    $b = New-Object byte[] 3
    $s = [System.IO.File]::OpenRead($p); try { $null = $s.Read($b, 0, 3) } finally { $s.Dispose() }
    return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}
function New-Case([string]$Name) {
    $d = Join-Path $root $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

Write-Host "`n=== a newer download appends into the older long-lived file, unasked ===" -ForegroundColor Cyan
# The direction the interactive script warns about: the NEW data is in the
# secondary. The long-lived name is what downstream software reads, so the
# merged result has to stay in the primary, under its own name.
$d = New-Case 'append'
$P = Join-Path $d '18421_SAA1_DATA.dat'
$S = Join-Path $d 'CR6_SAA_SAA1_DATA.dat'
New-Dat -Path $P -Station '18421'   -Start ([datetime]'2026-01-01 00:00:00') -Count 5 -Bom
New-Dat -Path $S -Station 'CR6_SAA' -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
$r = Invoke-Script $combine @('-PrimaryFile', $P, '-SecondaryFile', $S, '-Unattended')

Check 'exits 0' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"
Check 'the long-lived file keeps its own name' (Test-Path -LiteralPath $P) 'primary gone'
Check 'the download''s rows are in it (5 + 5)' ((Get-DataRows $P).Count -eq 10) (Get-DataRows $P).Count
Check 'a differing station name (row 1 field 2) is no obstacle' ($r.Out -notmatch 'Skipping') 'the file was skipped'
Check 'download moved into Backup' ((Test-Path (Join-Path $d 'Backup\CR6_SAA_SAA1_DATA.dat')) -and -not (Test-Path $S)) 'download not moved'
Check 'the primary''s BOM survived' (Test-Bom $P) 'BOM stripped - LoggerNet would abandon the file'

Write-Host "`n=== the recency check is logged, not asked ===" -ForegroundColor Cyan
$logPath = "$P.merge-log.txt"
Check 'merge log written' (Test-Path -LiteralPath $logPath) 'no merge log'
$log = Get-Content -LiteralPath $logPath -Raw
Check 'log records the back-to-front recency as an unattended append' ($log -match 'RECENCY.*unattended append') 'recency not logged'
Check 'console says it was expected rather than asking' ($r.Out -match 'expected when appending') $r.Out

Write-Host "`n=== row 2 differs: skipped, not aligned ===" -ForegroundColor Cyan
# An extra column is the case where the interactive script would OFFER to align.
# Unattended there is nobody to read the column table, so the file is skipped.
$d = New-Case 'row2'
$P = Join-Path $d '18421_SAA1_DATA.dat'
$S = Join-Path $d 'CR6_SAA_SAA1_DATA.dat'
New-Dat -Path $P -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $S -Station 'CR6_SAA' -Cols @('"BattV"', '"PTemp"', '"Extra"') -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
$r = Invoke-Script $combine @('-PrimaryFile', $P, '-SecondaryFile', $S, '-Unattended')

Check 'exits 1' ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
Check 'says the header row differs' ($r.Out -match 'row 2\) differs') $r.Out
# The validation warning may still NAME alignment as the interactive fix; what
# must not happen is the alignment itself.
Check 'nothing was aligned' ($r.Out -notmatch 'aligned to primary columns') 'the rows were aligned unattended'
Check 'no RemovedColumns backup' (-not (Test-Path (Join-Path $d 'Backup\RemovedColumns-NotMerged'))) 'columns were dropped by an alignment'
Check 'primary left alone' ((Get-DataRows $P).Count -eq 5) (Get-DataRows $P).Count
Check 'download left where it was' (Test-Path -LiteralPath $S) 'download was moved despite the skip'

Write-Host "`n=== row 1: the table name decides, the station name does not ===" -ForegroundColor Cyan
$d = New-Case 'table'
$P = Join-Path $d '18421_SAA1_DATA.dat'
$S = Join-Path $d 'CR6_SAA_SAA1_DATA.dat'
New-Dat -Path $P -Table 'SAA1_DATA' -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $S -Station 'CR6_SAA' -Table 'SAA2_DATA' -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
$r = Invoke-Script $combine @('-PrimaryFile', $P, '-SecondaryFile', $S, '-Unattended')

Check 'exits 1' ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
Check 'says the TOA5 table name differs' ($r.Out -match 'table name') $r.Out
Check 'primary left alone' ((Get-DataRows $P).Count -eq 5) (Get-DataRows $P).Count

Write-Host "`n=== -Unattended with nothing to merge is refused, not left to a picker ===" -ForegroundColor Cyan
$d = New-Case 'noargs'
$P = Join-Path $d '18421_SAA1_DATA.dat'
New-Dat -Path $P
$r = Invoke-Script $combine @('-PrimaryFile', $P, '-Unattended')
Check 'exits 1 instead of opening the file dialog' ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
Check 'says what it needs' ($r.Out -match '-Unattended needs') $r.Out

Write-Host "`n=== Append-NewData pairs on the longest matching ending ===" -ForegroundColor Cyan
# 'CR6_SAA_SAA1_DATA.dat' ends with both '_DATA.dat' and '_SAA1_DATA.dat'. The
# longer target name is the right one; the shorter must not be touched.
$d = New-Case 'pairing'
$bait = Join-Path $d '18421_DATA.dat'
$saa1 = Join-Path $d '18421_SAA1_DATA.dat'
$diag = Join-Path $d '18421_SAA_DIAGNOSTICS.dat'
New-Dat -Path $bait -Table 'DATA'            -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $saa1 -Table 'SAA1_DATA'       -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $diag -Table 'SAA_DIAGNOSTICS' -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path (Join-Path $d 'CR6_SAA_SAA1_DATA.dat')       -Station 'CR6_SAA' -Table 'SAA1_DATA'       -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
New-Dat -Path (Join-Path $d 'CR6_SAA_SAA_DIAGNOSTICS.dat') -Station 'CR6_SAA' -Table 'SAA_DIAGNOSTICS' -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
$r = Invoke-Script $append @('-Folder', $d, '-Prefix', '18421_')

Check 'exits 0 when every download merged' ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"
Check 'SAA1 download went to 18421_SAA1_DATA.dat' ((Get-DataRows $saa1).Count -eq 10) (Get-DataRows $saa1).Count
Check 'the shorter-ending file was not the match' ((Get-DataRows $bait).Count -eq 5) (Get-DataRows $bait).Count
Check 'diagnostics download went to its own file' ((Get-DataRows $diag).Count -eq 10) (Get-DataRows $diag).Count
Check 'both downloads are in Backup' (@(Get-ChildItem (Join-Path $d 'Backup') -Filter 'CR6_SAA_*').Count -eq 2) 'downloads not backed up'
Check 'no download left in the folder' (@(Get-ChildItem $d -Filter 'CR6_SAA_*' -File).Count -eq 0) 'download left behind'

Write-Host "`n=== one bad download does not hold up the rest ===" -ForegroundColor Cyan
$d = New-Case 'partial'
$A = Join-Path $d '18421_A_DATA.dat'
$B = Join-Path $d '18421_B_DATA.dat'
$inA = Join-Path $d 'CR6_A_DATA.dat'
$inB = Join-Path $d 'CR6_B_DATA.dat'
$orphan = Join-Path $d 'CR6_NOTHING_LIKE_IT.dat'
New-Dat -Path $A -Table 'A_DATA' -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $B -Table 'B_DATA' -Start ([datetime]'2026-01-01 00:00:00') -Count 5
New-Dat -Path $inA -Station 'CR6_SAA' -Table 'A_DATA' -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
# B's download carries an extra column, so that pair must fail.
New-Dat -Path $inB -Station 'CR6_SAA' -Table 'B_DATA' -Cols @('"BattV"', '"PTemp"', '"Extra"') -Start ([datetime]'2026-01-01 05:00:00') -Count 5 -RecBase 5
New-Dat -Path $orphan -Station 'CR6_SAA' -Table 'ORPHAN'
$r = Invoke-Script $append @('-Folder', $d, '-Prefix', '18421_')

Check 'exits 1 because not every download merged' ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
Check 'the good pair still merged' ((Get-DataRows $A).Count -eq 10) (Get-DataRows $A).Count
Check 'the good download moved to Backup' (Test-Path (Join-Path $d 'Backup\CR6_A_DATA.dat')) 'not backed up'
Check 'the bad pair left both files alone' (((Get-DataRows $B).Count -eq 5) -and (Test-Path -LiteralPath $inB)) 'bad pair touched'
Check 'a download matching no target is reported' ($r.Out -match 'NO MATCH') $r.Out
Check 'and is left where it is' (Test-Path -LiteralPath $orphan) 'unmatched download moved'
Check 'the count of failures is reported' ($r.Out -match '2 of 3 file') $r.Out

Write-Host "`n=== a folder with nothing new is a failure, not a quiet success ===" -ForegroundColor Cyan
# Exit 0 has to mean "the downloads are in"; an empty folder usually means the
# collection did not happen, which a scheduled caller needs to hear about.
$d = New-Case 'empty'
New-Dat -Path (Join-Path $d '18421_SAA1_DATA.dat')
$r = Invoke-Script $append @('-Folder', $d, '-Prefix', '18421_')
Check 'exits 1' ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
Check 'says there was nothing to append' ($r.Out -match 'nothing to append') $r.Out

Write-Host ''
if ($fail) { Write-Host "$fail check(s) FAILED" -ForegroundColor Red } else { Write-Host 'All checks passed.' -ForegroundColor Green }
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
exit $fail
