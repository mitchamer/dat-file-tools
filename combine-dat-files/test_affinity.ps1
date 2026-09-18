# Functional test for the Combine Affinity Files bugs:
#   1. header-row count is detected per file, not from the first file in the tree
#   2. grouping and merge use the same encoding (UTF-8, BOM-aware) on PS 5.1
#   3. -MoveSources moves only files that were actually merged; Exit All writes
#      nothing and leaves every source in place
#
# Loads the functions via the AST and stubs the mismatch dialog, so the file
# runs unattended with no window opening.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Combine Affinity Files.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$want = 'Read-DataFileLines', 'Read-DataFileHead', 'Get-SortedDataRows', 'Split-CsvLine',
        'Get-FirstFieldRaw', 'Get-CanonicalDataName', 'Get-HeaderSignature',
        'Get-DetectedHeaderRowCount', 'Get-RecursiveMergeGroups', 'Get-ShortHash',
        'Invoke-CombineGroup', 'Get-FileBomEncoding', 'Resolve-OutputEncoding',
        'Start-MergeTimer', 'Show-SlowHintIfNeeded'
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($want -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}

$script:headerAnswer = 'Proceed'
function Show-HeaderComparison { param($PrimaryHeader, $SecondaryHeader, $PrimaryName, $SecondaryName, $RowNumber, $ComparisonTitle) return $script:headerAnswer }
function Show-Notification { param($Message, $Title, $Icon) }

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('aff_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Write-Toaci1 {
    param([string]$Path, [string[]]$Names = @('TIMESTAMP', 'RECORD', 'VALUE'), [string[]]$Rows, [switch]$Bom)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $hdr = @(
        '"TOACI1","Station","raw_readings"',
        (($Names | ForEach-Object { "`"$_`"" }) -join ',')
    )
    [System.IO.File]::WriteAllLines($Path, ([string[]]($hdr + $Rows)), (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
}
function Write-Toa5 {
    param([string]$Path, [string[]]$Names = @('TIMESTAMP', 'RECORD', 'VALUE'), [string[]]$Rows)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $units = (($Names | ForEach-Object { '""' }) -join ',')
    $hdr = @(
        '"TOA5","Station","CR6","1","os","prog","1","Table"',
        (($Names | ForEach-Object { "`"$_`"" }) -join ','),
        $units,
        $units
    )
    [System.IO.File]::WriteAllLines($Path, ([string[]]($hdr + $Rows)), (New-Object System.Text.UTF8Encoding($false)))
}
function Get-Groups([string]$Folder) {
    $problems = [System.Collections.Generic.List[string]]::new()
    $g = @(Get-RecursiveMergeGroups -Folder $Folder -Extensions @('csv', 'dat') -HeaderRows 2 `
            -HeaderRowsExplicit $false -Problems $problems)
    return @{ Groups = $g; Problems = $problems }
}

try {

# ---------------------------------------------------------------------------
Write-Host "`n=== 1. header-row count is detected per file ===" -ForegroundColor Cyan
$d = Join-Path $root 'mixed'
# Named so a TOA5 file enumerates first - the old tree-wide detector would then
# pin every file to 4 header rows and treat TOACI1 data rows as headers.
Write-Toa5 (Join-Path $d 'aaa_toa5.dat') -Rows @('"2026-01-01 00:00:00",1,1.5', '"2026-01-01 01:00:00",2,2.5')
Write-Toaci1 (Join-Path $d '20250101_mixed.csv') -Rows @('"2026-01-01 00:00:00",1,1.5')
Write-Toaci1 (Join-Path $d '20250102_mixed.csv') -Rows @('"2026-01-02 00:00:00",1,3.5')

Check 'TOACI1 detects 2 header rows' ((Get-DetectedHeaderRowCount -FilePath (Join-Path $d '20250101_mixed.csv')) -eq 2) 'not 2'
Check 'TOA5 detects 4 header rows' ((Get-DetectedHeaderRowCount -FilePath (Join-Path $d 'aaa_toa5.dat')) -eq 4) 'not 4'

$got = Get-Groups $d
$g = @($got.Groups)
Check 'mixed tree makes two datasets' ($g.Count -eq 2) "$($g.Count) groups: $(($g | ForEach-Object { "$($_.Name)[$($_.HeaderRows)hdr,$($_.Files.Count)f]" }) -join '; ')"
$mixed = @($g | Where-Object { $_.Name -eq 'mixed.csv' })[0]
$toa5 = @($g | Where-Object { $_.Name -eq 'aaa_toa5.dat' })[0]
Check 'TOACI1 files share a dataset' ($null -ne $mixed -and $mixed.Files.Count -eq 2) $(if ($mixed) { $mixed.Files.Count } else { 'no mixed.csv group' })
Check 'TOACI1 dataset keeps 2 header rows' ($null -ne $mixed -and $mixed.HeaderRows -eq 2) $(if ($mixed) { $mixed.HeaderRows } else { 'no mixed.csv group' })
Check 'TOA5 dataset keeps 4 header rows' ($null -ne $toa5 -and $toa5.HeaderRows -eq 4) $(if ($toa5) { $toa5.HeaderRows } else { 'no aaa_toa5.dat group' })

# Same canonical name, different header counts -> two outputs, not one mashed file.
$d2 = Join-Path $root 'same-name'
Write-Toaci1 (Join-Path $d2 '20250101_same.csv') -Rows @('"2026-01-01 00:00:00",1,1.5')
Write-Toa5   (Join-Path $d2 '20250102_same.csv') -Rows @('"2026-01-01 00:00:00",1,1.5')
$got = Get-Groups $d2
$g = @($got.Groups)
Check 'same name, different header counts -> two datasets' ($g.Count -eq 2) "$($g.Count) groups"
Check 'both names are hash-suffixed so neither overwrites' `
    (($g | Where-Object { $_.Name -match '_hdr-' }).Count -eq 2) (($g | ForEach-Object { $_.Name }) -join ',')
Check 'the split is reported' ($got.Problems.Count -ge 1 -and $got.Problems[0] -match 'different header layouts') ($got.Problems -join ' | ')

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. UTF-8 BOM does not look like a header mismatch ===" -ForegroundColor Cyan
$d = Join-Path $root 'bom'
$bom = Join-Path $d '20250101_enc.csv'
$plain = Join-Path $d '20250102_enc.csv'
Write-Toaci1 $bom   -Rows @('"2026-01-01 00:00:00",1,1.5') -Bom
Write-Toaci1 $plain -Rows @('"2026-01-02 00:00:00",1,2.5')

$sigBom = Get-HeaderSignature -FilePath $bom -Count 2
$sigPlain = Get-HeaderSignature -FilePath $plain -Count 2
Check 'BOM not left on the first header line' ($sigBom.Headers[0].StartsWith('"TOACI1')) $sigBom.Headers[0]
Check 'BOM and BOM-less files share a signature' ($sigBom.Signature -eq $sigPlain.Signature) 'signatures differ'

$got = Get-Groups $d
Check 'BOM and BOM-less files are one dataset' ($got.Groups.Count -eq 1 -and $got.Groups[0].Files.Count -eq 2) "$($got.Groups.Count) groups"

$out = Join-Path $d 'Combined'
$script:SourceRootFull = [IO.Path]::GetFullPath($d).TrimEnd('\')
$res = Invoke-CombineGroup -Group $got.Groups[0] -OutputFolder $out -Unattended
Check 'BOM group merges both files' ($res.FilesRead -eq 2 -and $res.FilesSkipped -eq 0) "read=$($res.FilesRead) skip=$($res.FilesSkipped)"
Check 'BOM group writes two unique rows' ($res.UniqueRows -eq 2) $res.UniqueRows
Check 'BOM group is not aborted' (-not $res.Aborted) 'aborted'

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. -MoveSources moves only merged files ===" -ForegroundColor Cyan
$d = Join-Path $root 'move'
$a = Join-Path $d 'a.csv'
$b = Join-Path $d 'b.csv'
$c = Join-Path $d 'c.csv'
Write-Toaci1 $a -Rows @('"2026-01-01 00:00:00",1,1.5')
Write-Toaci1 $b -Names @('TIMESTAMP', 'RECORD') -Rows @()   # headers only
Write-Toaci1 $c -Names @('TIMESTAMP', 'RECORD', 'OTHER') -Rows @('"2026-01-03 00:00:00",1,9.9')
$group = [pscustomobject]@{
    Name       = 'a.csv'
    Headers    = @('"TOACI1","Station","raw_readings"', '"TIMESTAMP","RECORD","VALUE"')
    HeaderRows = 2
    Signature  = 'x'
    SigHash    = 'x'
    Files      = [System.Collections.Generic.List[object]]::new()
}
foreach ($p in $a, $b, $c) { $group.Files.Add((Get-Item -LiteralPath $p)) }

$out = Join-Path $d 'Combined'
$script:SourceRootFull = [IO.Path]::GetFullPath($d).TrimEnd('\')
$script:headerAnswer = 'Proceed'
$res = Invoke-CombineGroup -Group $group -OutputFolder $out -Unattended -MoveSources
Check 'one file merged, two skipped' ($res.FilesRead -eq 1 -and $res.FilesSkipped -eq 2) "read=$($res.FilesRead) skip=$($res.FilesSkipped)"
Check 'combined file written' (Test-Path (Join-Path $out 'a.csv')) 'missing'
$written = @(Get-Content -LiteralPath (Join-Path $out 'a.csv') | Where-Object { $_ })
Check 'single unique row is written as one row, not as characters' ($written.Count -eq 3 -and $written[2] -eq '"2026-01-01 00:00:00",1,1.5') ($written.Count)
Check 'merged source was moved' (-not (Test-Path $a) -and (Test-Path (Join-Path $out 'Sources\a.csv'))) 'a.csv not in Sources'
Check 'headers-only source left in place' (Test-Path $b) 'b.csv was moved'
Check 'mismatched source left in place' (Test-Path $c) 'c.csv was moved'

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. Exit All writes nothing and moves nothing ===" -ForegroundColor Cyan
$d = Join-Path $root 'abort'
$p1 = Join-Path $d 'keep.csv'
$p2 = Join-Path $d 'mismatch.csv'
Write-Toaci1 $p1 -Rows @('"2026-01-01 00:00:00",1,1.5', '"2026-01-01 01:00:00",2,2.5')
Write-Toaci1 $p2 -Names @('TIMESTAMP', 'RECORD', 'OTHER') -Rows @('"2026-01-02 00:00:00",1,9.9')
$group = [pscustomobject]@{
    Name       = 'keep.csv'
    Headers    = @('"TOACI1","Station","raw_readings"', '"TIMESTAMP","RECORD","VALUE"')
    HeaderRows = 2
    Signature  = 'x'
    SigHash    = 'x'
    Files      = [System.Collections.Generic.List[object]]::new()
}
foreach ($p in $p1, $p2) { $group.Files.Add((Get-Item -LiteralPath $p)) }

$out = Join-Path $d 'Combined'
$script:SourceRootFull = [IO.Path]::GetFullPath($d).TrimEnd('\')
$script:headerAnswer = 'ExitAll'
$res = Invoke-CombineGroup -Group $group -OutputFolder $out -MoveSources
Check 'Exit All sets Aborted' ($res.Aborted) 'not aborted'
Check 'Exit All writes no combined file' (-not (Test-Path (Join-Path $out 'keep.csv'))) 'output exists'
Check 'already-read source left in place' (Test-Path $p1) 'keep.csv was moved'
Check 'unread mismatched source left in place' (Test-Path $p2) 'mismatch.csv was moved'
Check 'no Sources folder of moved files' (-not (Test-Path (Join-Path $out 'Sources'))) 'Sources exists'

} finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red; exit 1 }
