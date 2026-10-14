# Functional test for Fix-Timestamps: which readings it accepts, which it
# refuses, and that a refusal really does leave the file alone.
#
# Loads the script's functions via the AST, so no WinForms assembly is needed
# and nothing can open a dialog.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Fix-Timestamps.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$want = 'Get-FileBomEncoding', 'Resolve-OutputEncoding', 'Read-DataFileLines', 'Get-RawFirstField',
        'Set-FirstField', 'ConvertFrom-TimestampField', 'Get-PossibleOrders', 'Expand-TwoDigitYear',
        'ConvertTo-TimestampValue', 'Format-Timestamp', 'Resolve-FileTimestamps',
        'Get-DateFormatErrorPath', 'Write-DateFormatError', 'Backup-File',
        'Invoke-FixTimestampsForFile', 'Get-TargetFiles'
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}
# The pattern is a script-scope assignment rather than a function, so take it
# from the AST too - copying it into the test would let the two drift apart.
foreach ($a in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    if ($a.Left.Extent.Text -eq '$script:TimestampPattern') { . ([scriptblock]::Create($a.Extent.Text)) }
}
if (-not $script:TimestampPattern) { throw "Could not lift TimestampPattern out of the script." }

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('ts_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$ENVROW = '"TOA5","TM_Test","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","SAA1_DATA"'
$HDR = @($ENVROW, '"TIMESTAMP","RECORD","V1"', '"TS","RN","m"', '"","","Smp"')

function New-File {
    param([string]$Path, [string[]]$Stamps, [string[]]$Header = $HDR, [switch]$Unquoted, [switch]$Bom)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $n = 0
    $rows = foreach ($s in $Stamps) {
        $n++
        if ($Unquoted) { "$s,$n,1.5" } else { "`"$s`",$n,1.5" }
    }
    [System.IO.File]::WriteAllLines($Path, ([string[]]($Header + $rows)), (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
}
function Stamps([string]$FilePath) {
    @(Get-Content -LiteralPath $FilePath | Select-Object -Skip 4 | Where-Object { $_ } |
        ForEach-Object { (Get-RawFirstField -Line $_).Text })
}
function Case([string]$Name) {
    $d = Join-Path $root $Name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

Write-Host "`n=== the shapes it should accept ===" -ForegroundColor Cyan
$accept = @(
    @{ n = 'YYYY/M/D'        ; i = @('2026/9/1 0:00:00', '2026/9/1 1:00:00', '2026/10/12 2:30:05')
                               o = @('2026-09-01 00:00:00', '2026-09-01 01:00:00', '2026-10-12 02:30:05'); ord = 'YMD' }
    @{ n = 'YYYY-M-D'        ; i = @('2026-9-1 00:00:00', '2026-9-2 00:00:00'); o = @('2026-09-01 00:00:00', '2026-09-02 00:00:00'); ord = 'YMD' }
    @{ n = 'M/D/YYYY (day>12 proves it)' ; i = @('9/1/2026 00:00:00', '9/13/2026 00:00:00'); o = @('2026-09-01 00:00:00', '2026-09-13 00:00:00'); ord = 'MDY' }
    @{ n = 'D/M/YYYY (day>12 proves it)' ; i = @('13/9/2026 00:00:00', '14/9/2026 00:00:00'); o = @('2026-09-13 00:00:00', '2026-09-14 00:00:00'); ord = 'DMY' }
    @{ n = 'two-digit year'  ; i = @('26-09-01 00:00:00', '26-09-13 00:00:00'); o = @('2026-09-01 00:00:00', '2026-09-13 00:00:00'); ord = 'YMD' }
    @{ n = 'AM/PM'           ; i = @('2026/9/1 11:05:00 AM', '2026/9/1 1:05:00 PM'); o = @('2026-09-01 11:05:00', '2026-09-01 13:05:00'); ord = 'YMD' }
    @{ n = "ISO 'T'"         ; i = @('2026-09-01T00:00:00', '2026-09-13T23:59:59'); o = @('2026-09-01 00:00:00', '2026-09-13 23:59:59'); ord = 'YMD' }
    @{ n = 'date only'       ; i = @('2026/9/1', '2026/9/13'); o = @('2026-09-01 00:00:00', '2026-09-13 00:00:00'); ord = 'YMD' }
    @{ n = 'no seconds'      ; i = @('2026/9/1 00:00', '2026/9/13 23:59'); o = @('2026-09-01 00:00:00', '2026-09-13 23:59:00'); ord = 'YMD' }
    @{ n = 'repeated timestamps (ties allowed)' ; i = @('2026/9/1 00:00:00', '2026/9/1 00:00:00', '2026/9/13 00:00:00')
                               o = @('2026-09-01 00:00:00', '2026-09-01 00:00:00', '2026-09-13 00:00:00'); ord = 'YMD' }
)
foreach ($c in $accept) {
    $d = Case ('acc_' + ($c.n -replace '[^A-Za-z0-9]', '_'))
    $p = Join-Path $d 'X.dat'
    New-File -Path $p -Stamps $c.i
    $rec = Invoke-FixTimestampsForFile -FilePath $p
    $got = Stamps $p
    $same = (@(Compare-Object $got $c.o -SyncWindow 0).Count -eq 0)
    Check "$($c.n): converted, read as $($c.ord)" ($rec.Status -eq 'Convert' -and $rec.Order -eq $c.ord -and $same) "status=$($rec.Status) order=$($rec.Order) got=$($got -join '|')"
}

Write-Host "`n=== month/day decided by the ascending test, not by hope ===" -ForegroundColor Cyan
$d = Case 'ascending'
# Every number is <= 12, so the shape alone cannot say which is the month.
# Read as D/M: 9 Jan, 3 Feb, 12 Feb - ascending.
# Read as M/D: 1 Sep, 3 Mar, 2 Dec - which goes backwards at row 2.
# Only one reading survives, so the file converts without a human.
$p = Join-Path $d 'A.dat'
New-File -Path $p -Stamps @('9/1/2026 00:00:00', '3/2/2026 00:00:00', '12/2/2026 00:00:00')
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'only-D/M-ascends file is read as DMY' ($rec.Order -eq 'DMY') "order=$($rec.Order) detail=$($rec.Detail)"
Check 'and converts to ascending ISO dates' ((Stamps $p) -join '|' -eq '2026-01-09 00:00:00|2026-02-03 00:00:00|2026-02-12 00:00:00') ((Stamps $p) -join '|')

$d = Case 'ascending_only_mdy'
# The mirror: read as M/D these are 9 Jan, 3 Feb - ascending; read as D/M they
# are 1 Sep then 2 Mar, which goes backwards.
$p = Join-Path $d 'A2.dat'
New-File -Path $p -Stamps @('1/9/2026 00:00:00', '2/3/2026 00:00:00')
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'only-M/D-ascends file is read as MDY' ($rec.Order -eq 'MDY') "order=$($rec.Order) detail=$($rec.Detail)"
Check 'and converts to ascending ISO dates' ((Stamps $p) -join '|' -eq '2026-01-09 00:00:00|2026-02-03 00:00:00') ((Stamps $p) -join '|')

$d = Case 'ascending_mdy'
$p = Join-Path $d 'B.dat'
# The mirror image: as M/D these ascend through September; as D/M they jump
# 1 Sep -> 1 Oct -> 1 Nov... which also ascends. Both fit and they disagree,
# so this must be refused rather than guessed.
New-File -Path $p -Stamps @('9/1/2026 00:00:00', '10/1/2026 00:00:00', '11/1/2026 00:00:00')
$before = [System.IO.File]::ReadAllBytes($p)
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'genuinely ambiguous file is REFUSED' ($rec.Status -eq 'Refuse') "status=$($rec.Status)"
Check 'and left byte-for-byte unchanged' (@(Compare-Object $before ([System.IO.File]::ReadAllBytes($p)) -SyncWindow 0).Count -eq 0) 'file was modified'
Check 'error file written beside it' (Test-Path (Join-Path $d 'B_DATEFORMATERROR.txt')) 'no error file'
$err = Get-Content -LiteralPath (Join-Path $d 'B_DATEFORMATERROR.txt') -Raw
Check 'error file names both readings and their dates' ($err -match 'MDY -> 2026-09-01' -and $err -match 'DMY -> 2026-01-09') $err
Check 'error file says the file was not modified' ($err -match 'THE FILE WAS NOT MODIFIED') 'missing statement'
Check 'no backup made for a refused file' (-not (Test-Path (Join-Path $d 'Backup'))) 'backup created'

Write-Host "`n=== Y-M-D outranks Y-D-M, so ordinary year-first files are not 'ambiguous' ===" -ForegroundColor Cyan
$d = Case 'tier'
$p = Join-Path $d 'T.dat'
# Every number <= 12, so Y-D-M would also ascend (9 Jan, 10 Jan, 11 Jan) and a
# flat contest would refuse this. Nobody writes year-day-month, so Y-M-D wins.
New-File -Path $p -Stamps @('2026/9/1 00:00:00', '2026/10/1 00:00:00', '2026/11/1 00:00:00')
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'converted as YMD rather than refused' ($rec.Status -eq 'Convert' -and $rec.Order -eq 'YMD') "status=$($rec.Status) order=$($rec.Order)"
Check 'dates are month-first' ((Stamps $p)[0] -eq '2026-09-01 00:00:00') ((Stamps $p)[0])

$d = Case 'tier_fallback'
$p = Join-Path $d 'U.dat'
# Y-M-D is impossible here (month 25), so the last-resort Y-D-M is reached.
New-File -Path $p -Stamps @('2026/25/9 00:00:00', '2026/26/9 00:00:00')
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'falls back to YDM only when YMD cannot be read' ($rec.Status -eq 'Convert' -and $rec.Order -eq 'YDM') "status=$($rec.Status) order=$($rec.Order)"
Check 'and reads day-then-month' ((Stamps $p)[0] -eq '2026-09-25 00:00:00') ((Stamps $p)[0])

Write-Host "`n=== what it refuses ===" -ForegroundColor Cyan
$refuse = @(
    @{ n = 'fractional seconds'; s = @('2026/9/1 00:00:00.5', '2026/9/13 00:00:00.5'); m = 'fractional second' }
    @{ n = 'an unreadable row' ; s = @('2026/9/1 00:00:00', 'NAN', '2026/9/13 00:00:00'); m = 'does not start with a readable date' }
    @{ n = 'rows out of order' ; s = @('2026-09-13 00:00:00', '2026-09-01 00:00:00'); m = 'ascending' }
    @{ n = 'an impossible date'; s = @('2026-13-45 00:00:00', '2026-13-46 00:00:00'); m = 'is not a real date read that way' }
)
foreach ($c in $refuse) {
    $d = Case ('ref_' + ($c.n -replace '[^A-Za-z0-9]', '_'))
    $p = Join-Path $d 'C.dat'
    New-File -Path $p -Stamps $c.s
    $before = [System.IO.File]::ReadAllBytes($p)
    $rec = Invoke-FixTimestampsForFile -FilePath $p
    $unchanged = (@(Compare-Object $before ([System.IO.File]::ReadAllBytes($p)) -SyncWindow 0).Count -eq 0)
    Check "$($c.n): not converted, file unchanged" ($rec.Status -ne 'Convert' -and $unchanged) "status=$($rec.Status)"
    Check "$($c.n): reason explains it" ($rec.Detail -match [regex]::Escape($c.m)) $rec.Detail
}

Write-Host "`n=== an already-correct file is not touched at all ===" -ForegroundColor Cyan
$d = Case 'idempotent'
$p = Join-Path $d 'D.dat'
New-File -Path $p -Stamps @('2026-09-01 00:00:00', '2026-09-13 00:00:00')
$before = [System.IO.File]::ReadAllBytes($p)
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'reported as already correct' ($rec.Status -eq 'AlreadyCorrect') $rec.Status
Check 'byte-for-byte unchanged' (@(Compare-Object $before ([System.IO.File]::ReadAllBytes($p)) -SyncWindow 0).Count -eq 0) 'rewritten'
Check 'no Backup folder created' (-not (Test-Path (Join-Path $d 'Backup'))) 'backup created'

Write-Host "`n=== the rest of the row, the headers and the encoding survive ===" -ForegroundColor Cyan
$d = Case 'fidelity'
$p = Join-Path $d 'E.dat'
$rows = @('"2026/9/1 0:00:00",1,"a,b",,"he said ""hi""",1.5',
          '"2026/9/13 0:00:00",2,"c,d",,"x",2.5')
[System.IO.File]::WriteAllLines($p, ([string[]]($HDR + $rows)), (New-Object System.Text.UTF8Encoding($false)))
$rec = Invoke-FixTimestampsForFile -FilePath $p
$after = [System.IO.File]::ReadAllLines($p)
Check 'converted' ($rec.Status -eq 'Convert') $rec.Status
Check 'all 4 header rows byte-identical' ((@(Compare-Object $after[0..3] $HDR -SyncWindow 0).Count -eq 0)) 'headers changed'
Check 'everything after field 1 is untouched (commas, quotes and all)' ($after[4] -eq '"2026-09-01 00:00:00",1,"a,b",,"he said ""hi""",1.5') $after[4]
Check 'quoting of field 1 preserved' ($after[5] -like '"2026-09-13 00:00:00",*') $after[5]
$b = New-Object byte[] 3
$s = [IO.File]::OpenRead($p); try { $null = $s.Read($b, 0, 3) } finally { $s.Dispose() }
Check 'no BOM added' (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) 'BOM present'
Check 'original copied into Backup' (@(Get-ChildItem (Join-Path $d 'Backup') -Filter 'E_*.dat').Count -eq 1) 'no backup'

$d = Case 'unquoted'
$p = Join-Path $d 'F.dat'
New-File -Path $p -Stamps @('2026/9/1 0:00:00', '2026/9/13 0:00:00') -Unquoted
$null = Invoke-FixTimestampsForFile -FilePath $p
Check 'an unquoted first field stays unquoted' (([System.IO.File]::ReadAllLines($p))[4] -eq '2026-09-01 00:00:00,1,1.5') (([System.IO.File]::ReadAllLines($p))[4])

$d = Case 'bom'
$p = Join-Path $d 'G.dat'
New-File -Path $p -Stamps @('2026/9/1 0:00:00', '2026/9/13 0:00:00') -Bom
$null = Invoke-FixTimestampsForFile -FilePath $p
$s = [IO.File]::OpenRead($p); try { $null = $s.Read($b, 0, 3) } finally { $s.Dispose() }
Check 'a file that arrived with a BOM keeps it' ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'BOM lost'

Write-Host "`n=== -DryRun writes nothing ===" -ForegroundColor Cyan
$d = Case 'dryrun'
$p = Join-Path $d 'H.dat'
New-File -Path $p -Stamps @('2026/9/1 0:00:00', '2026/9/13 0:00:00')
$before = [System.IO.File]::ReadAllBytes($p)
$rec = Invoke-FixTimestampsForFile -FilePath $p -DryRun
Check 'reports what it would do' ($rec.Status -eq 'Convert' -and $rec.Order -eq 'YMD') "status=$($rec.Status)"
Check 'file unchanged' (@(Compare-Object $before ([System.IO.File]::ReadAllBytes($p)) -SyncWindow 0).Count -eq 0) 'file written'
Check 'no Backup folder' (-not (Test-Path (Join-Path $d 'Backup'))) 'backup created'
$p2 = Join-Path $d 'I.dat'
New-File -Path $p2 -Stamps @('9/1/2026 00:00:00', '10/1/2026 00:00:00', '11/1/2026 00:00:00')
$rec = Invoke-FixTimestampsForFile -FilePath $p2 -DryRun
Check 'a dry run does not write the error file either' (-not (Test-Path (Join-Path $d 'I_DATEFORMATERROR.txt'))) 'error file written'

Write-Host "`n=== a stale error note is cleared once the file converts ===" -ForegroundColor Cyan
$d = Case 'stale'
$p = Join-Path $d 'J.dat'
New-File -Path $p -Stamps @('9/1/2026 00:00:00', '10/1/2026 00:00:00', '11/1/2026 00:00:00')
$null = Invoke-FixTimestampsForFile -FilePath $p
Check 'ambiguous file leaves a note' (Test-Path (Join-Path $d 'J_DATEFORMATERROR.txt')) 'no note'
New-File -Path $p -Stamps @('9/1/2026 00:00:00', '9/13/2026 00:00:00')   # now provable
$null = Invoke-FixTimestampsForFile -FilePath $p
Check 'and the note is removed once it converts' (-not (Test-Path (Join-Path $d 'J_DATEFORMATERROR.txt'))) 'note left behind'

Write-Host "`n=== -Depth, and the folders that are never entered ===" -ForegroundColor Cyan
$d = Case 'depth'
New-File -Path (Join-Path $d 'top.dat') -Stamps @('2026/9/1 0:00:00')
New-File -Path (Join-Path $d 'sub\one.dat') -Stamps @('2026/9/1 0:00:00')
New-File -Path (Join-Path $d 'sub\deeper\two.dat') -Stamps @('2026/9/1 0:00:00')
New-File -Path (Join-Path $d 'Backup\old.dat') -Stamps @('2026/9/1 0:00:00')
New-File -Path (Join-Path $d 'Combined\c.dat') -Stamps @('2026/9/1 0:00:00')
Set-Content -LiteralPath (Join-Path $d 'K_DATEFORMATERROR.txt') -Value 'a previous note'
Set-Content -LiteralPath (Join-Path $d 'X.dat.merge-log.txt') -Value 'a merge log'
$names0 = @(Get-TargetFiles -Folder $d -Depth 0 | ForEach-Object { $_.Name })
$names1 = @(Get-TargetFiles -Folder $d -Depth 1 | ForEach-Object { $_.Name })
$names2 = @(Get-TargetFiles -Folder $d -Depth 2 | ForEach-Object { $_.Name })
Check 'Depth 0 is the given folder only' ($names0 -join ',' -eq 'top.dat') ($names0 -join ',')
Check 'Depth 1 adds one level' (($names1 -contains 'one.dat') -and -not ($names1 -contains 'two.dat')) ($names1 -join ',')
Check 'Depth 2 adds two levels' ($names2 -contains 'two.dat') ($names2 -join ',')
Check 'Backup is never entered' (-not ($names2 -contains 'old.dat')) 'Backup scanned'
Check 'Combined is never entered' (-not ($names2 -contains 'c.dat')) 'Combined scanned'
Check 'its own error notes are not treated as data' (-not ($names0 -contains 'K_DATEFORMATERROR.txt')) 'error note scanned'
Check 'merge logs are not treated as data' (-not ($names0 -contains 'X.dat.merge-log.txt')) 'merge log scanned'

Write-Host "`n=== files with no timestamp column are skipped quietly ===" -ForegroundColor Cyan
$d = Case 'notdata'
$p = Join-Path $d 'notes.txt'
Set-Content -LiteralPath $p -Value @('just some notes', 'no dates here at all')
$rec = Invoke-FixTimestampsForFile -FilePath $p
Check 'reported as having no timestamps' ($rec.Status -eq 'NoTimestamps') $rec.Status
Check 'no error file for a file that is simply not data' (-not (Test-Path (Join-Path $d 'notes_DATEFORMATERROR.txt'))) 'error file written'

Write-Host "`n=== two-digit year window ===" -ForegroundColor Cyan
Check '00 -> 2000' ((Expand-TwoDigitYear -Value 0 -Width 2) -eq 2000) (Expand-TwoDigitYear -Value 0 -Width 2)
Check '69 -> 2069' ((Expand-TwoDigitYear -Value 69 -Width 2) -eq 2069) (Expand-TwoDigitYear -Value 69 -Width 2)
Check '70 -> 1970' ((Expand-TwoDigitYear -Value 70 -Width 2) -eq 1970) (Expand-TwoDigitYear -Value 70 -Width 2)
Check '99 -> 1999' ((Expand-TwoDigitYear -Value 99 -Width 2) -eq 1999) (Expand-TwoDigitYear -Value 99 -Width 2)
Check '4-digit years are left alone' ((Expand-TwoDigitYear -Value 1926 -Width 4) -eq 1926) (Expand-TwoDigitYear -Value 1926 -Width 4)

Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red }
Write-Host "fixtures: $root" -ForegroundColor DarkGray
if ($fail -gt 0) { exit 1 }
