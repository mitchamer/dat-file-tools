# Functional test for CSV-to-TOA5: the header it builds, the columns it keeps
# and names, the values it writes, and what it refuses.
#
# Loads the script's functions via the AST, so no WinForms assembly is needed
# and nothing can open a dialog.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'CSV-to-TOA5.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
# Script-scope settings (patterns, the compiled core's source) are
# assignments rather than functions, so take them from the AST too - copying
# them into the test would let the two drift apart.
foreach ($a in $ast.EndBlock.Statements) {
    if ($a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -like '$script:*') {
        . ([scriptblock]::Create($a.Extent.Text))
    }
}
if (-not $script:Toa5CoreSource) { throw "Could not lift Toa5CoreSource out of the script." }
Initialize-Toa5Core

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('c2t_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $root -Force | Out-Null
function Save([string]$Name, [string[]]$Lines) {
    $p = Join-Path $root $Name
    [System.IO.File]::WriteAllText($p, (($Lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $p
}
function Names($rec) { @((Split-CsvFieldsRaw $rec.Lines[1]) | ForEach-Object { Get-Unquoted $_ }) }

# A cut-down DT2485 download: two sensors, the separator columns, the full-
# precision second block, the logger columns at the end. Sensor 2 is
# mislabelled "... 9" (its Modbus address is 2) while a real sensor 9 also
# exists - the fault seen in a real DH19-02 download.
$dt = @(
    'Model,DT2485 IPI Logger'
    'Name,IPI Logger DT2485 DH99-01'
    'Serial Number,DT12345'
    'Firmware Version,4.06,Software Version,1.20.0'
    'Start Time,2021/10/08,10:15:00'
    ''
    '"TIMESTAMP","RECORD","BATTERY","Axis A 1","Axis B 1","Temp 1","Axis A 9","Axis B 9","Temp 9","Axis A 9","Axis B 9","Temp 9",,,Serial (MB Addr),"111 (1)","111 (1)","111 (1)","222 (2)","222 (2)","222 (2)","999 (9)","999 (9)","999 (9)","LOGGER TEMP","STATUS 0x"'
    'Serial,,,"111",,,"222",,,"999",,,,,Unit Type," "'
    'MB Addr,,,"1",,,"2",,,"9",,,,,Input Units," "'
    '"UNITS->",,"Volts","sin(angle)","sin(angle)","deg C","sin(angle)","sin(angle)","deg C","sin(angle)","sin(angle)","deg C",,,,"sin(angle)","sin(angle)","deg C","sin(angle)","sin(angle)","deg C","sin(angle)","sin(angle)","deg C","deg C"'
    '2021/10/08 10:15:00,1,3.71,-0.003517,0.009798,5.50,0.001,0.002,4.00,0.003,0.004,3.93,,,,-0.003517,0.009798,5.500000,0.001000,0.002000,4.000000,0.003000,0.004000,3.935000,5.00,012'
    '2021/10/8 10:20,2,3.70,NAN,0.009790,5.50,0.001,0.002,4.00,0.003,0.004,3.93,,,,NAN,0.009790,5.500000,0.001000,0.002000,4.000000,0.003000,0.004000,3.935000,5.10,001'
    '2021/10/08 12:00:00,3,3.55,-0.003510,0.009802,5.50,0.001,0.002,4.00,0.003,0.004,3.93,,,,-0.003510,0.009802,5.500000,0.001000,0.002000,4.000000,0.003000,0.004000,3.935000,5.20,021'
)

Write-Host "`n=== DT2485 download ===" -ForegroundColor Cyan
$p = Save 'dt.csv' $dt
$rec = Convert-CsvToToa5 -FilePath $p
Check 'converted' ($rec.Status -eq 'Ok') "$($rec.Status): $($rec.Detail)"
Check 'row 1 from the metadata' ($rec.Lines[0] -eq '"TOA5","IPI Logger DT2485 DH99-01","DT2485","DT12345","4.06","","","DH99-01"') $rec.Lines[0]
$n = Names $rec
Check 'separators and the "Serial (MB Addr)" label dropped' (-not ($n -contains 'Serial (MB Addr)') -and -not ($n | Where-Object { $_ -like 'Column*' })) ($n -join '|')
Check 'mislabelled sensor renamed from its Modbus address' ($n[6] -eq 'Axis A 2' -and $n[7] -eq 'Axis B 2' -and $n[8] -eq 'Temp 2') ($n[6..8] -join '|')
Check 'the real sensor 9 keeps its name' ($n[9] -eq 'Axis A 9' -and $n[11] -eq 'Temp 9') ($n[9..11] -join '|')
Check 'renames are reported' ($rec.Renamed.Count -eq 3) ($rec.Renamed -join '; ')
Check 'second block named "<reading> SN<serial>"' ($n[12] -eq 'Axis A 1 SN111' -and $n[17] -eq 'Temp 2 SN222' -and $n[20] -eq 'Temp 9 SN999') ($n[12..20] -join '|')
Check 'every name unique' (($n | Group-Object | Where-Object Count -gt 1).Count -eq 0) ''
$u = @((Split-CsvFieldsRaw $rec.Lines[2]) | ForEach-Object { Get-Unquoted $_ })
Check 'units: TS, RN, then the UNITS-> row' ($u[0] -eq 'TS' -and $u[1] -eq 'RN' -and $u[2] -eq 'Volts' -and $u[5] -eq 'deg C' -and $u[14] -eq 'deg C') ($u -join '|')
Check 'processing row' ($rec.Lines[3] -match '^"","","Smp",') $rec.Lines[3]
$r1 = Split-CsvFieldsRaw $rec.Lines[4]; $r2 = Split-CsvFieldsRaw $rec.Lines[5]
Check 'timestamp quoted YYYY-MM-DD HH:MM:SS' ($r1[0] -eq '"2021-10-08 10:15:00"') $r1[0]
Check 'single-digit day and missing seconds normalised' ($r2[0] -eq '"2021-10-08 10:20:00"') $r2[0]
Check 'numbers copied exactly, unquoted' ($r1[3] -eq '-0.003517' -and $r1[5] -eq '5.50' -and $r1[14] -eq '5.500000') "$($r1[3]) $($r1[5]) $($r1[14])"
Check 'NAN quoted' ($r2[3] -eq '"NAN"') $r2[3]
Check 'leading-zero status code kept as text' ($r1[-1] -eq '"012"') $r1[-1]
Check 'rows kept in order, none dropped' ($rec.Rows -eq 3 -and $rec.Lines.Count -eq 7) "$($rec.Rows) rows"

Write-Host "`n=== a plain CSV ===" -ForegroundColor Cyan
$p = Save 'plain.csv' @(
    'Date/Time,Level,Level,Note'
    '2026-01-02 3:04:05 PM,1.5,2.5,ok'
    '2026-01-02 3:04:06 PM,1.6,2.6,'
)
$rec = Convert-CsvToToa5 -FilePath $p
$n = Names $rec
Check 'converted' ($rec.Status -eq 'Ok') "$($rec.Status): $($rec.Detail)"
Check 'no metadata -> station and table from the file name' ($rec.Lines[0] -eq '"TOA5","plain","","","","","","plain"') $rec.Lines[0]
Check 'first column named TIMESTAMP, repeated name gets _2' ($n[0] -eq 'TIMESTAMP' -and $n[1] -eq 'Level' -and $n[2] -eq 'Level_2') ($n -join '|')
Check 'PM time converted to 24-hour' ((Split-CsvFieldsRaw $rec.Lines[4])[0] -eq '"2026-01-02 15:04:05"') (Split-CsvFieldsRaw $rec.Lines[4])[0]
Check 'text quoted, empty kept empty' ((Split-CsvFieldsRaw $rec.Lines[4])[3] -eq '"ok"' -and (Split-CsvFieldsRaw $rec.Lines[5])[3] -eq '') $rec.Lines[5]

Write-Host "`n=== refusals ===" -ForegroundColor Cyan
$rec = Convert-CsvToToa5 -FilePath (Save 'ylast.csv' @('TIMESTAMP,A', '10/08/2021 10:15:00,1', '10/08/2021 10:20:00,2'))
Check 'year-last dates refused, pointing at Fix Timestamps' ($rec.Status -eq 'Refuse' -and $rec.Detail -like '*Fix Timestamps*') $rec.Detail
$rec = Convert-CsvToToa5 -FilePath (Save 'bad.csv' @('TIMESTAMP,A', '2021-10-08 10:15:00,1', '2021-10-08 10:20:00,2', 'garbage,3'))
Check 'a bad row refuses the file' ($rec.Status -eq 'Refuse' -and $rec.Detail -like 'Line 4*') $rec.Detail
$rec = Convert-CsvToToa5 -FilePath (Save 'short.csv' @('TIMESTAMP,A,B', '2021-10-08 10:15:00,1,2', '2021-10-08 10:20:00,2'))
Check 'a row with the wrong field count refuses the file' ($rec.Status -eq 'Refuse' -and $rec.Detail -like '*fields*') $rec.Detail
$rec = Convert-CsvToToa5 -FilePath (Save 'impossible.csv' @('TIMESTAMP,A', '2021-02-30 10:15:00,1', '2021-03-01 10:15:00,2'))
Check 'an impossible date refuses the file' ($rec.Status -eq 'Refuse') $rec.Detail
$rec = Convert-CsvToToa5 -FilePath (Save 'already.dat' @('"TOA5","x","","","","","","x"', '"TIMESTAMP","A"', '"TS",""', '"",""', '"2021-10-08 10:15:00",1'))
Check 'already TOA5 -> refused' ($rec.Status -eq 'Refuse' -and $rec.Detail -like '*already*') $rec.Detail
$rec = Convert-CsvToToa5 -FilePath (Save 'nonames.csv' @('a,b', '2021-10-08 10:15:00,1', '2021-10-08 10:20:00,2'))
Check 'no column-name row -> refused' ($rec.Status -eq 'Refuse' -and $rec.Detail -like '*column-name*') $rec.Detail

Write-Host "`n=== the script end to end ===" -ForegroundColor Cyan
$p = Save 'e2e.csv' $dt
$before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($p))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src $p -Unattended *> $null
$out = Join-Path $root 'e2e_TOA5.dat'
Check 'writes <name>_TOA5.dat beside the source' (Test-Path $out) ''
$bytes = [System.IO.File]::ReadAllBytes($out)
Check 'no BOM, starts with "TOA5"' ($bytes[0] -eq 0x22 -and [System.Text.Encoding]::ASCII.GetString($bytes, 1, 4) -eq 'TOA5') ''
Check 'CRLF line endings' ([System.IO.File]::ReadAllText($out).Contains("`r`n")) ''
Check 'source unchanged' ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($p)) -eq $before) ''
[System.IO.File]::WriteAllText($out, 'keep me')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src $p -Unattended *> $null
Check 'existing output not overwritten without -Force' ([System.IO.File]::ReadAllText($out) -eq 'keep me') ''
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src $p -Unattended -Force *> $null
Check '-Force overwrites it' ([System.IO.File]::ReadAllText($out).StartsWith('"TOA5"')) ''
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src (Join-Path $root 'ylast.csv') -Unattended *> $null
Check 'a refused file writes nothing' (-not (Test-Path (Join-Path $root 'ylast_TOA5.dat'))) ''

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red; exit 1 }
