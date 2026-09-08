# Functional test for folder-mode auto-matching: which files Get-DuplicateGroups
# pairs up, and which ambiguous groups it refuses to pair.
#
# Only the grouping functions are loaded (via the AST), so no WinForms assembly
# is needed and no dialog can open.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Combine DAT files_v9.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$want = 'Split-CsvLine','Get-Toa5EnvironmentFields','Get-DuplicateGroups','Add-Toa5SerialTableGroups'
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('grp_' + [guid]::NewGuid().ToString('N').Substring(0,6))
function New-Toa5 {
    param([string]$Path, [string]$Station, [string]$Serial, [string]$Table, [string[]]$Rows = @('"2026-09-01 00:00:00",1'))
    $lines = @(
        ('"TOA5","{0}","CR6","{1}","CR6.Std.14.01","prog.cr6","31248","{2}"' -f $Station, $Serial, $Table),
        '"TIMESTAMP","VALUE"', '"TS","m"', '"","Smp"'
    ) + $Rows
    [System.IO.File]::WriteAllLines($Path, $lines)
}

function Test-Case {
    param([string]$Name, [scriptblock]$Build, [hashtable]$Expected, [switch]$ExpectWarn)
    $dir = Join-Path $root $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & $Build $dir
    # Warnings come from nested helpers, so capture stream 3 and split it out.
    $emitted = @(Get-DuplicateGroups -Folder $dir 3>&1)
    $warnings = @($emitted | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } |
        ForEach-Object { $_.Message })
    $groups = @($emitted | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    $actual = @{}
    foreach ($g in $groups) {
        $actual[[System.IO.Path]::GetFileName($g.Primary)] =
            (($g.Secondaries | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ',')
    }
    $ok = $true
    foreach ($k in $Expected.Keys) {
        if ($actual[$k] -ne $Expected[$k]) { $ok = $false; Write-Host "    expected $k -> '$($Expected[$k])' got '$($actual[$k])'" }
    }
    foreach ($k in $actual.Keys) { if (-not $Expected.ContainsKey($k)) { $ok = $false; Write-Host "    unexpected group $k -> '$($actual[$k])'" } }
    if ($ExpectWarn -and $warnings.Count -eq 0) { $ok = $false; Write-Host "    expected a warning, got none" }
    if (-not $ExpectWarn -and $warnings.Count -gt 0) { $ok = $false; Write-Host "    unexpected warning(s): $($warnings -join ' | ')" }
    Write-Host ("{0} {1}" -f $(if ($ok) { '[PASS]' } else { '[FAIL]' }), $Name) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    if ($warnings.Count -gt 0) { $warnings | ForEach-Object { Write-Host "    warn: $_" -ForegroundColor DarkYellow } }
    return $ok
}

$results = @()

# 1. The folder from the screenshot: collected files named <serial>_<Table>.dat,
#    downloads named <station>_<Table>_<YYYY-MM-DD>.dat (date only, no time).
$results += Test-Case -Name 'screenshot_folder' -Build {
    param($d)
    New-Toa5 (Join-Path $d '18421_LLD_SAA_01_IData.dat') 'LLD_SAA1' '18421' 'LLD_SAA_01_IData'
    New-Toa5 (Join-Path $d '18421_LOGGER_DIAGNOSTICS.dat') 'LLD_SAA1' '18421' 'LOGGER_DIAGNOSTICS'
    New-Toa5 (Join-Path $d '18421_PROJECT_INFO.dat') 'LLD_SAA1' '18421' 'PROJECT_INFO'
    New-Toa5 (Join-Path $d '18421_SAA_DIAGNOSTICS.dat') 'LLD_SAA1' '18421' 'SAA_DIAGNOSTICS'
    New-Toa5 (Join-Path $d '18421_SAA1_DATA.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d '18421_SERIAL_ERRORS.dat') 'LLD_SAA1' '18421' 'SERIAL_ERRORS'
    New-Toa5 (Join-Path $d '18421_SAA_SAA_DIAGNOSTICS_2026-09-08.dat') '18421_SAA' '18421' 'SAA_DIAGNOSTICS'
    New-Toa5 (Join-Path $d '18421_SAA_SAA1_DATA_2026-09-08.dat') '18421_SAA' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d '18421_SAA_SERIAL_ERRORS_2026-09-08.dat') '18421_SAA' '18421' 'SERIAL_ERRORS'
    Set-Content -Path (Join-Path $d 'pref_project.txt') -Value 'not a data file'
    Set-Content -Path (Join-Path $d '1_Write new data rows to SAA1_DATA and PROJECT_INFO.txt') -Value ''
} -Expected @{
    '18421_SAA_DIAGNOSTICS.dat' = '18421_SAA_SAA_DIAGNOSTICS_2026-09-08.dat'
    '18421_SAA1_DATA.dat'       = '18421_SAA_SAA1_DATA_2026-09-08.dat'
    '18421_SERIAL_ERRORS.dat'   = '18421_SAA_SERIAL_ERRORS_2026-09-08.dat'
}

# 2. Classic LoggerNet stamp with a time, plus a renamed collected file.
$results += Test-Case -Name 'stamp_with_time_renamed_primary' -Build {
    param($d)
    New-Toa5 (Join-Path $d 'TM_MCL-02_Status_old_copy_KEEP.dat') 'TM_MCL-02' '13910' 'Status'
    New-Toa5 (Join-Path $d '13910_Status_2026-07-23T15-44.dat') 'TM_MCL-02' '13910' 'Status'
    New-Toa5 (Join-Path $d '13910_Status_2026-07-01T09-10-30.dat') 'TM_MCL-02' '13910' 'Status'
} -Expected @{
    'TM_MCL-02_Status_old_copy_KEEP.dat' = '13910_Status_2026-07-01T09-10-30.dat,13910_Status_2026-07-23T15-44.dat'
}

# 3. Same table name, different loggers -> never merged together.
$results += Test-Case -Name 'same_table_different_serial' -Build {
    param($d)
    New-Toa5 (Join-Path $d 'SiteA_Status.dat') 'SiteA' '13910' 'Status'
    New-Toa5 (Join-Path $d 'SiteB_Status.dat') 'SiteB' '20001' 'Status'
    New-Toa5 (Join-Path $d 'SiteA_Status_2026-09-08.dat') 'SiteA' '13910' 'Status'
    New-Toa5 (Join-Path $d 'SiteB_Status_2026-09-08.dat') 'SiteB' '20001' 'Status'
} -Expected @{
    'SiteA_Status.dat' = 'SiteA_Status_2026-09-08.dat'
    'SiteB_Status.dat' = 'SiteB_Status_2026-09-08.dat'
}

# 4. Two files that could each be the collected file -> skipped and reported.
$results += Test-Case -Name 'ambiguous_two_collected' -Build {
    param($d)
    New-Toa5 (Join-Path $d '18421_SAA1_DATA.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d 'SAA1_DATA_trimmed.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d '18421_SAA1_DATA_2026-09-08.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
} -Expected @{} -ExpectWarn

# 5. Dated downloads only, no collected file -> skipped and reported.
$results += Test-Case -Name 'downloads_only' -Build {
    param($d)
    New-Toa5 (Join-Path $d '18421_SAA1_DATA_2026-09-08.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d '18421_SAA1_DATA_2026-09-01.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
} -Expected @{} -ExpectWarn

# 6. Extensions must match; a .csv export is not merged into the .dat.
$results += Test-Case -Name 'extension_must_match' -Build {
    param($d)
    New-Toa5 (Join-Path $d '18421_SAA1_DATA.dat') 'LLD_SAA1' '18421' 'SAA1_DATA'
    New-Toa5 (Join-Path $d '18421_SAA1_DATA_2026-09-08.csv') 'LLD_SAA1' '18421' 'SAA1_DATA'
} -Expected @{}

# 7. Backup-suffix pass still works, including for non-TOA5 files.
$results += Test-Case -Name 'backup_suffix_pass' -Build {
    param($d)
    New-Toa5 (Join-Path $d 'X_DATA.dat') 'X' '11111' 'DATA'
    New-Toa5 (Join-Path $d 'X_DATA.dat.backup') 'X' '11111' 'DATA'
    Set-Content -Path (Join-Path $d 'plain.dat') -Value @('col1,col2', '1,2')
    Set-Content -Path (Join-Path $d 'plain.dat.1') -Value @('col1,col2', '3,4')
} -Expected @{
    'X_DATA.dat' = 'X_DATA.dat.backup'
    'plain.dat'  = 'plain.dat.1'
}

# 8. A download that also has its own .bak: merged as a primary, reported rather
#    than merged twice in one scan.
$results += Test-Case -Name 'download_is_itself_a_primary' -Build {
    param($d)
    New-Toa5 (Join-Path $d 'X_DATA.dat') 'X' '11111' 'DATA'
    New-Toa5 (Join-Path $d 'X_DATA_2026-09-08.dat') 'X' '11111' 'DATA'
    New-Toa5 (Join-Path $d 'X_DATA_2026-09-08.dat.bak') 'X' '11111' 'DATA'
} -Expected @{
    'X_DATA_2026-09-08.dat' = 'X_DATA_2026-09-08.dat.bak'
} -ExpectWarn

# 9. No TOA5 row 1 -> takes no part in serial/table matching.
$results += Test-Case -Name 'non_toa5_ignored' -Build {
    param($d)
    Set-Content -Path (Join-Path $d 'Site_Table.dat') -Value @('a,b', '1,2')
    Set-Content -Path (Join-Path $d 'Site_Table_2026-09-08.dat') -Value @('a,b', '3,4')
} -Expected @{}

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
$failed = @($results | Where-Object { -not $_ }).Count
Write-Host ""
Write-Host ("{0} of {1} cases passed." -f ($results.Count - $failed), $results.Count) -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
if ($failed) { exit 1 }
