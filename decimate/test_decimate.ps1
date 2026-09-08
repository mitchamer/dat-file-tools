# Exercises Decimate against the cases that mattered in review.
# Each case builds a fresh fixture, runs non-interactively, and asserts.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Decimate.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('dec_test_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host ("  [ok]   " + $name) -ForegroundColor DarkGray }
    else { Write-Host ("  [FAIL] " + $name + "  --> " + $detail) -ForegroundColor Red; $script:fail++ }
}

# TOA5-shaped fixture: 4 header rows then data at a given step/offset.
function New-Toa5 {
    param([string]$Path, [int]$StepMin, [int]$OffsetMin, [int]$Count, [string]$StampFmt = 'yyyy-MM-dd HH:mm:ss', [switch]$Bom)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('"TOA5","SAA-TEST","CR6","12345","CR6.Std.13.01","CPU:prog.CR6","1234","Data"')
    [void]$lines.Add('"TIMESTAMP","RECORD","BattV","PTemp"')
    [void]$lines.Add('"TS","RN","Volts","Deg C"')
    [void]$lines.Add('"","","Smp","Smp"')
    $t = [datetime]'2026-07-01 00:00:00'
    $t = $t.AddMinutes($OffsetMin)
    for ($i = 0; $i -lt $Count; $i++) {
        $stamp = $t.AddMinutes($i * $StepMin).ToString($StampFmt)
        [void]$lines.Add(('"{0}",{1},12.4{1},21.5' -f $stamp, $i))
    }
    $enc = New-Object System.Text.UTF8Encoding($Bom.IsPresent)
    [System.IO.File]::WriteAllLines($Path, $lines.ToArray(), $enc)
}
function Get-DataRowCount([string]$Path) {
    $n = 0
    foreach ($l in [System.IO.File]::ReadLines($Path)) { if ($l -match '^"20\d\d-') { $n++ } }
    return $n
}
function Test-HasBom([string]$Path) {
    $b = New-Object byte[] 3
    $s = [System.IO.File]::OpenRead($Path); try { $null = $s.Read($b,0,3) } finally { $s.Dispose() }
    return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

Write-Host "`n=== 1. 15-min data aligned to the hour, Hourly ===" -ForegroundColor Cyan
$d = Join-Path $root 'c1'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'aligned.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96   # 24 h
$r = & $script -Mode Hourly -Path $f
Check '96 rows in' ($r.RowsIn -eq 96) $r.RowsIn
Check '24 kept (one per hour)' ($r.RowsKept -eq 24) $r.RowsKept
Check 'header rows detected = 4' ($r.HeaderRows -eq 4) $r.HeaderRows
Check 'file now has 24 data rows' ((Get-DataRowCount $f) -eq 24) (Get-DataRowCount $f)
Check 'backup holds all 96' ((Get-DataRowCount (Join-Path $d 'Backup\aligned_fulldataset.dat')) -eq 96) 'backup wrong'
Check 'action = Decimated' ($r.Action -eq 'Decimated') $r.Action

Write-Host "`n=== 2. Fractional seconds (v2 could not parse these at all) ===" -ForegroundColor Cyan
$d = Join-Path $root 'c2'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'frac.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96 -StampFmt 'yyyy-MM-dd HH:mm:ss.fff'
$r = & $script -Mode Hourly -Path $f
Check 'parsed as data, not junk' ($r.RowsIn -eq 96) $r.RowsIn
Check '24 kept' ($r.RowsKept -eq 24) $r.RowsKept
Check 'no unparseable rows' ($r.Unparseable -eq 0) $r.Unparseable

Write-Host "`n=== 3. Data offset off the hour (:07) - must REFUSE ===" -ForegroundColor Cyan
$d = Join-Path $root 'c3'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'offset.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 7 -Count 96
$before = Get-DataRowCount $f
$r = & $script -Mode Hourly -Path $f -WarningAction SilentlyContinue
Check 'file left untouched' ((Get-DataRowCount $f) -eq $before) (Get-DataRowCount $f)
Check 'no backup folder created' (-not (Test-Path (Join-Path $d 'Backup'))) 'backup made'
Check 'no temp files left' (@(Get-ChildItem $d -Filter *.tmp).Count -eq 0) 'temp left'

Write-Host "`n=== 4. Same file with -Force - must proceed and empty it ===" -ForegroundColor Cyan
$r = & $script -Mode Hourly -Path $f -Force -WarningAction SilentlyContinue
Check '0 data rows kept' ((Get-DataRowCount $f) -eq 0) (Get-DataRowCount $f)
Check 'headers survived' ((Get-Content $f).Count -eq 4) (Get-Content $f).Count
Check 'backup has the full 96' ((Get-DataRowCount (Join-Path $d 'Backup\offset_fulldataset.dat')) -eq 96) 'backup wrong'

Write-Host "`n=== 5. No parseable timestamps anywhere - must skip, not no-op silently ===" -ForegroundColor Cyan
$d = Join-Path $root 'c5'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'bad.csv'
[System.IO.File]::WriteAllLines($f, [string[]]@('a,b,c','07/01/2026 00:00,1,2','07/01/2026 01:00,3,4'))
$before = (Get-Content $f).Count
$r = & $script -Mode Hourly -Path $f -WarningAction SilentlyContinue
Check 'file untouched' ((Get-Content $f).Count -eq $before) 'changed'
Check 'nothing emitted / not decimated' ($null -eq $r) 'emitted a result'
Check 'no temp left' (@(Get-ChildItem $d -Filter *.tmp).Count -eq 0) 'temp left'

Write-Host "`n=== 6. RetainFirst keeps leading rows regardless of interval ===" -ForegroundColor Cyan
$d = Join-Path $root 'c6'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'retain.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96
$r = & $script -Mode Daily -RetainFirst 5 -Path $f
# Daily alone keeps 1 (00:00). Retain 5 keeps rows 1-5; row 1 is 00:00 so it is
# both retained and on-interval -> 5 total.
Check '5 kept (retain 5, daily overlaps first)' ($r.RowsKept -eq 5) $r.RowsKept
Check 'file has 5 data rows' ((Get-DataRowCount $f) -eq 5) (Get-DataRowCount $f)

Write-Host "`n=== 7. -WhatIf must not write ===" -ForegroundColor Cyan
$d = Join-Path $root 'c7'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'whatif.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96
$r = & $script -Mode Hourly -Path $f -WhatIf
Check 'file untouched' ((Get-DataRowCount $f) -eq 96) (Get-DataRowCount $f)
Check 'no backup made' (-not (Test-Path (Join-Path $d 'Backup'))) 'backup made'
Check 'action = WhatIf' ($r.Action -eq 'WhatIf') $r.Action
Check 'no temp left' (@(Get-ChildItem $d -Filter *.tmp).Count -eq 0) 'temp left'

Write-Host "`n=== 8. File inside a Backup folder - must refuse ===" -ForegroundColor Cyan
$d = Join-Path $root 'c8\Backup'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'inbackup.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96
$r = & $script -Mode Hourly -Path $f -WarningAction SilentlyContinue
Check 'full copy untouched' ((Get-DataRowCount $f) -eq 96) (Get-DataRowCount $f)

Write-Host "`n=== 9. Encoding: BOM presence preserved (Auto) ===" -ForegroundColor Cyan
$d = Join-Path $root 'c9'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$fb = Join-Path $d 'withbom.dat'; New-Toa5 -Path $fb -StepMin 60 -OffsetMin 0 -Count 10 -Bom
$fn = Join-Path $d 'nobom.dat';   New-Toa5 -Path $fn -StepMin 60 -OffsetMin 0 -Count 10
Check 'fixture with BOM has one' (Test-HasBom $fb) 'no bom in fixture'
$null = & $script -Mode Hourly -Path $fb
$null = & $script -Mode Hourly -Path $fn
Check 'BOM file still has BOM' (Test-HasBom $fb) 'BOM lost'
Check 'no-BOM file still has none' (-not (Test-HasBom $fn)) 'BOM added'

Write-Host "`n=== 10. Wildcards and a missing path ===" -ForegroundColor Cyan
$d = Join-Path $root 'c10'; New-Item -ItemType Directory -Path $d -Force | Out-Null
1..3 | ForEach-Object { New-Toa5 -Path (Join-Path $d "w$_.dat") -StepMin 60 -OffsetMin 0 -Count 10 }
$r = @(& $script -Mode Hourly -Path (Join-Path $d '*.dat'), (Join-Path $d 'nope.dat') -WarningAction SilentlyContinue)
Check 'processed 3 via wildcard' ($r.Count -eq 3) $r.Count
Check 'all decimated' (@($r | Where-Object { $_.Action -eq 'Decimated' }).Count -eq 3) 'not all'

Write-Host "`n=== 11. v2 parameter aliases still bind ===" -ForegroundColor Cyan
$d = Join-Path $root 'c11'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'alias.dat'; New-Toa5 -Path $f -StepMin 15 -OffsetMin 0 -Count 96
$r = & $script -ModeParam Hourly -RetainParam 0 -FilesParam $f
Check 'legacy names accepted' ($r.RowsKept -eq 24) $r.RowsKept

Write-Host "`n=== 12. Unparseable rows mid-file are KEPT, not dropped ===" -ForegroundColor Cyan
$d = Join-Path $root 'c12'; New-Item -ItemType Directory -Path $d -Force | Out-Null
$f = Join-Path $d 'mixed.dat'
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('"TOA5","X","CR6","1","v","p","s","Data"')
[void]$lines.Add('"TIMESTAMP","RECORD"')
[void]$lines.Add('"TS","RN"')
[void]$lines.Add('"",""')
[void]$lines.Add('"2026-07-01 00:00:00",1')
[void]$lines.Add('"NAN garbage row",2')
[void]$lines.Add('"2026-07-01 00:15:00",3')
[void]$lines.Add('"2026-07-01 01:00:00",4')
[System.IO.File]::WriteAllLines($f, $lines.ToArray())
$r = & $script -Mode Hourly -Path $f -WarningAction SilentlyContinue
Check 'reported 1 unparseable' ($r.Unparseable -eq 1) $r.Unparseable
Check '3 timestamped rows counted' ($r.RowsIn -eq 3) $r.RowsIn
Check '2 on-hour kept' ($r.RowsKept -eq 2) $r.RowsKept
Check 'garbage row survived' ((Get-Content $f) -match 'NAN garbage').Count -ge 1 'garbage dropped'

Write-Host ''
if ($fail) { Write-Host "$fail check(s) FAILED" -ForegroundColor Red } else { Write-Host 'All checks passed.' -ForegroundColor Green }
Write-Host "fixtures: $root"
exit $fail
