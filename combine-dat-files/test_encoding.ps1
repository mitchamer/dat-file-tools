# Verifies the encoding behaviour that matters for LoggerNet: merging must not
# add a byte-order mark to a data file. A BOM ahead of the TOA5 row leaves
# LoggerNet unable to recognise the file it is appending to, so it renames it to
# .dat.backup and starts fresh - silently orphaning the merge.
#
# Loads only the encoding helpers from the combine script, so no dialogs appear.
$ErrorActionPreference = 'Stop'
$combine = Join-Path $PSScriptRoot 'Combine DAT files_v9.ps1'
$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

# Pull in Get-FileBomEncoding / Resolve-OutputEncoding without running the script.
$src = Get-Content -LiteralPath $combine -Raw
$start = $src.IndexOf('function Get-FileBomEncoding')
$end = $src.IndexOf('function Select-FileDialog')
if ($start -lt 0 -or $end -le $start) { throw 'Could not locate the encoding helpers.' }
Invoke-Expression $src.Substring($start, $end - $start)

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('enc_test_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null

function New-Toa5([string]$Path, [switch]$Bom) {
    $lines = [string[]]@(
        '"TOA5","TM_Test","CR6","21202","CR6.Std.14.01","CPU:prog.cr6","12074","SAA1_DATA"',
        '"TIMESTAMP","RECORD","BattV"',
        '"TS","RN","Volts"',
        '"","","Smp"',
        '"2026-08-01 00:00:00",1,12.4'
    )
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
}
function Test-Bom([string]$Path) {
    $b = New-Object byte[] 3
    $s = [System.IO.File]::OpenRead($Path); try { $null = $s.Read($b,0,3) } finally { $s.Dispose() }
    return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}
# Simulates what the merge does: rewrite the file with the resolved encoding.
function Invoke-Rewrite([string]$Path, [string]$EncodingName) {
    $lines = [string[]](Get-Content -LiteralPath $Path)
    $enc = Resolve-OutputEncoding -Name $EncodingName -FilePath $Path
    [System.IO.File]::WriteAllLines($Path, $lines, $enc)
}

Write-Host "`n=== Auto preserves a BOM-less file (the LoggerNet case) ===" -ForegroundColor Cyan
$f = Join-Path $root 'nobom.dat'; New-Toa5 -Path $f
Check 'fixture starts without a BOM' (-not (Test-Bom $f)) 'fixture wrong'
Invoke-Rewrite $f 'Auto'
Check 'still no BOM after rewrite' (-not (Test-Bom $f)) 'a BOM was added - LoggerNet would abandon this file'
$first = (Get-Content -LiteralPath $f -TotalCount 1)
Check 'row 1 still begins with "TOA5' ($first.StartsWith('"TOA5')) $first

Write-Host "`n=== Auto preserves an existing BOM ===" -ForegroundColor Cyan
$f = Join-Path $root 'withbom.dat'; New-Toa5 -Path $f -Bom
Check 'fixture starts with a BOM' (Test-Bom $f) 'fixture wrong'
Invoke-Rewrite $f 'Auto'
Check 'BOM retained' (Test-Bom $f) 'BOM was stripped'

Write-Host "`n=== Explicit names mean the same on 5.1 and 7 ===" -ForegroundColor Cyan
$f = Join-Path $root 'explicit.dat'; New-Toa5 -Path $f
Invoke-Rewrite $f 'UTF8'
Check 'UTF8 writes NO BOM' (-not (Test-Bom $f)) 'UTF8 added a BOM'
Invoke-Rewrite $f 'UTF8BOM'
Check 'UTF8BOM writes a BOM' (Test-Bom $f) 'UTF8BOM produced no BOM'
Invoke-Rewrite $f 'UTF8'
Check 'UTF8 strips it again' (-not (Test-Bom $f)) 'BOM survived'

Write-Host "`n=== A missing file must not throw ===" -ForegroundColor Cyan
$enc = Resolve-OutputEncoding -Name 'Auto' -FilePath (Join-Path $root 'does_not_exist.dat')
Check 'falls back to UTF8 without a BOM' ($enc.GetPreamble().Length -eq 0) 'returned a BOM encoding'

Write-Host ''
if ($fail) { Write-Host "$fail check(s) FAILED" -ForegroundColor Red } else { Write-Host 'All checks passed.' -ForegroundColor Green }
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
exit $fail
