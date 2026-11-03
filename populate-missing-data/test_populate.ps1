# Functional test for Populate-MissingData: how columns are matched, which
# gaps are filled, which are left, and that nothing but a gap ever changes.
#
# Loads the script's functions via the AST, so no WinForms assembly is needed
# and nothing can open a dialog.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Populate-MissingData.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
# Script-scope settings (tolerances, the compiled core's source) are
# assignments rather than functions, so take them from the AST too - copying
# them into the test would let the two drift apart.
foreach ($a in $ast.EndBlock.Statements) {
    if ($a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Left.Extent.Text -like '$script:*') {
        . ([scriptblock]::Create($a.Extent.Text))
    }
}
if (-not $script:PopulateCoreSource) { throw "Could not lift PopulateCoreSource out of the script." }
Initialize-PopulateCore

$fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  [ok]   $name" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $name  --> $detail" -ForegroundColor Red; $script:fail++ }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('pm_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$inv = [System.Globalization.CultureInfo]::InvariantCulture

function Stamp([int]$k) { (Get-Date '2026-01-01').AddHours(6 * $k).ToString('yyyy-MM-dd HH:mm:ss') }

function New-Toa5 {
    <#
        Writes a TOA5 file. -Columns is an ordered list of name -> scriptblock
        taking the row index and returning the field text exactly as written.
    #>
    param([string]$Path, [int]$Rows, [System.Collections.Specialized.OrderedDictionary]$Columns,
        [switch]$Bom, [string]$Newline = "`r`n", [int[]]$Only)
    $names = @('"TIMESTAMP"', '"RECORD"') + @($Columns.Keys | ForEach-Object { "`"$_`"" })
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('"TOA5","Test","CR6","1","OS","prog","1","T"')
    $lines.Add($names -join ',')
    $lines.Add((@('"TS"', '"RN"') + @($Columns.Keys | ForEach-Object { '""' })) -join ',')
    $lines.Add((@('""', '""') + @($Columns.Keys | ForEach-Object { '"Smp"' })) -join ',')
    $ks = if ($Only) { $Only } else { 0..($Rows - 1) }
    foreach ($k in $ks) {
        $f = @("`"$(Stamp $k)`"", "$k") + @($Columns.Values | ForEach-Object { & $_ $k })
        $lines.Add($f -join ',')
    }
    $enc = New-Object System.Text.UTF8Encoding($Bom.IsPresent)
    [System.IO.File]::WriteAllText($Path, (($lines -join $Newline) + $Newline), $enc)
}

# Readings that vary row to row, distinct per column.
function Wave([double]$base, [double]$amp, [int]$k, [int]$seed) {
    ($base + $amp * [Math]::Sin(0.37 * $k + $seed)).ToString('0.000000', $inv)
}

function Map-Of($rec, [string]$target) { $rec.Map | Where-Object { $_.TargetName -eq $target } }
function Field([string]$Path, [int]$Line, [int]$Index) {
    (Split-CsvFieldsRaw ([System.IO.File]::ReadAllLines($Path)[$Line]))[$Index]
}

$N = 60
$gapRows = @(10, 11, 12, 40)

# --- shared fixture: target "CR6" names, source "DT2485" names, shuffled -----
$tCols = [ordered]@{
    'battery'  = { param($k) (12 + ($k % 3) * 0.1).ToString('0.00', $inv) }
    'Ch_1'     = { param($k) if ($gapRows -contains $k) { '"NAN"' } else { Wave 0.0035 0.0004 $k 1 } }
    'Ch_2'     = { param($k) if ($gapRows -contains $k) { '"NAN"' } else { Wave 0.0098 0.0004 $k 2 } }
    'Ch_3'     = { param($k) if ($gapRows -contains $k) { '"NAN"' } else { '5.5' } }        # constant temp
    'Ch_4'     = { param($k) if ($gapRows -contains $k) { '"NAN"' } else { Wave -0.0075 0.0004 $k 3 } }
    'Ch_5'     = { param($k) if ($gapRows -contains $k) { '"NAN"' } else { '0' } }          # constant, nothing after it
}

Write-Host "`n=== matching by values, names differ ===" -ForegroundColor Cyan
$d = Join-Path $root 'values'; New-Item -ItemType Directory $d -Force | Out-Null
# Different names, an extra column in front, and the constant Temp 1 sitting
# between Axis B 1 and Axis A 2 with the same spacing as Ch_3 between Ch_2 and
# Ch_4. 'Reset' is a constant 0 like Ch_5, which must NOT be taken as proof.
$sCols2 = [ordered]@{
    'Volts'    = { param($k) '3.71' }
    'Axis A 1' = { param($k) Wave 0.0035 0.0004 $k 1 }
    'Axis B 1' = { param($k) Wave 0.0098 0.0004 $k 2 }
    'Temp 1'   = { param($k) '5.500000' }
    'Axis A 2' = { param($k) Wave -0.0075 0.0004 $k 3 }
    'Reset'    = { param($k) '0' }
}
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $tCols
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $sCols2
$before = [System.IO.File]::ReadAllLines("$d\t.dat")
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'Ch_1 <- Axis A 1 by values' ((Map-Of $rec 'Ch_1').SourceName -eq 'Axis A 1' -and (Map-Of $rec 'Ch_1').Method -eq 'Values') ((Map-Of $rec 'Ch_1') | Out-String)
Check 'Ch_2 <- Axis B 1 by values' ((Map-Of $rec 'Ch_2').SourceName -eq 'Axis B 1') ((Map-Of $rec 'Ch_2').SourceName)
Check 'Ch_4 <- Axis A 2 by values' ((Map-Of $rec 'Ch_4').SourceName -eq 'Axis A 2') ((Map-Of $rec 'Ch_4').SourceName)
Check 'constant Ch_3 <- Temp 1 by its proven neighbours' ((Map-Of $rec 'Ch_3').SourceName -eq 'Temp 1' -and (Map-Of $rec 'Ch_3').Method -eq 'Between') ((Map-Of $rec 'Ch_3') | Out-String)
Check 'constant Ch_5 past the last proven column is NOT mapped' ((Map-Of $rec 'Ch_5').Source -lt 0 -and (Map-Of $rec 'Ch_5').Method -eq 'Constant') ((Map-Of $rec 'Ch_5') | Out-String)
Check 'RECORD is never mapped' ((Map-Of $rec 'RECORD').Method -eq 'Skipped') ((Map-Of $rec 'RECORD').Method)
Check 'battery (no agreeing source) is not mapped' ((Map-Of $rec 'battery').Source -lt 0) ((Map-Of $rec 'battery').SourceName)
Check 'filled 4 rows x 4 columns' ($rec.FieldsFilled -eq 16 -and $rec.RowsFilled -eq 4) "$($rec.FieldsFilled) / $($rec.RowsFilled)"
Check 'unmapped Ch_5 gaps counted' ($rec.GapsUnmappedColumn -eq 4) $rec.GapsUnmappedColumn
$after = $rec.Lines
$onlyGaps = $true
for ($n = 0; $n -lt $before.Count; $n++) {
    $b = Split-CsvFieldsRaw $before[$n]; $a = Split-CsvFieldsRaw $after[$n]
    for ($i = 0; $i -lt $b.Count; $i++) { if ($b[$i] -ne $a[$i] -and $b[$i] -ne '"NAN"') { $onlyGaps = $false } }
}
Check 'only NAN fields change, header and every other field identical' $onlyGaps ''
Check 'filled value is the source text, unquoted' ((Split-CsvFieldsRaw $after[4 + 10])[3] -eq (Wave 0.0035 0.0004 10 1)) ((Split-CsvFieldsRaw $after[14])[3])
Check 'constant gap filled from Temp 1' ((Split-CsvFieldsRaw $after[14])[5] -eq '5.500000') ((Split-CsvFieldsRaw $after[14])[5])
Check 'Invoke writes nothing' (([System.IO.File]::ReadAllLines("$d\t.dat") -join "`n") -eq ($before -join "`n")) ''

Write-Host "`n=== edge columns (first / last) ===" -ForegroundColor Cyan
$d = Join-Path $root 'edge'; New-Item -ItemType Directory $d -Force | Out-Null
# A constant temperature at the very end of the table, after its two proven
# axis columns; the source has the same three plus a logger column after.
$edT = [ordered]@{
    'Ch_1' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Ch_2' = { param($k) Wave 0.009 0.0004 $k 2 }
    'Ch_3' = { param($k) if ($k -in 10, 11) { '"NAN"' } else { '7.375' } }
}
$edS = [ordered]@{
    'Volts'    = { param($k) '3.71' }
    'Axis A 9' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Axis B 9' = { param($k) Wave 0.009 0.0004 $k 2 }
    'Temp 9'   = { param($k) '7.375000' }
    'Reset'    = { param($k) '0' }
}
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $edT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $edS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'last constant column placed from the two proven columns before it' ((Map-Of $rec 'Ch_3').Method -eq 'Edge' -and (Map-Of $rec 'Ch_3').SourceName -eq 'Temp 9') ((Map-Of $rec 'Ch_3') | Out-String)
Check 'its gaps filled from the column the spacing points to' ($rec.FieldsFilled -eq 2 -and (Split-CsvFieldsRaw $rec.Lines[14])[4] -eq '7.375000') (Split-CsvFieldsRaw $rec.Lines[14])[4]

# The same shape, but the column after the proven pair in the source is a
# temperature of 7.375 while the target's last column is a constant 0: the
# spacing points to a column that does not agree, so it stays unmapped - and
# is NOT matched to the source's constant-0 'Reset' further along.
$edT2 = [ordered]@{
    'Ch_1' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Ch_2' = { param($k) Wave 0.009 0.0004 $k 2 }
    'Spare' = { param($k) if ($k -eq 10) { '"NAN"' } else { '0' } }
}
New-Toa5 -Path "$d\t2.dat" -Rows $N -Columns $edT2
$rec = Invoke-PopulateMissingData -TargetPath "$d\t2.dat" -SourcePath "$d\s.dat"
Check 'last column whose spacing points to a disagreeing column stays unmapped' ((Map-Of $rec 'Spare').Source -lt 0 -and $rec.FieldsFilled -eq 0) ((Map-Of $rec 'Spare') | Out-String)

# Two constant columns past the proven pair: only the first is in reach.
$edT3 = [ordered]@{
    'Ch_1' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Ch_2' = { param($k) Wave 0.009 0.0004 $k 2 }
    'Ch_3' = { param($k) if ($k -eq 10) { '"NAN"' } else { '7.375' } }
    'Ch_4' = { param($k) if ($k -eq 10) { '"NAN"' } else { '0' } }
}
New-Toa5 -Path "$d\t3.dat" -Rows $N -Columns $edT3
$rec = Invoke-PopulateMissingData -TargetPath "$d\t3.dat" -SourcePath "$d\s.dat"
Check 'edge rule reaches one column past the proven pair, no further' ((Map-Of $rec 'Ch_3').Method -eq 'Edge' -and (Map-Of $rec 'Ch_4').Source -lt 0) "$((Map-Of $rec 'Ch_3').Method) / $((Map-Of $rec 'Ch_4').SourceName)"

# A constant column at the START, before its two proven columns.
$edT4 = [ordered]@{
    'T0'   = { param($k) if ($k -eq 10) { '"NAN"' } else { '7.375' } }
    'Ch_1' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Ch_2' = { param($k) Wave 0.009 0.0004 $k 2 }
}
$edS4 = [ordered]@{
    'Temp 9'   = { param($k) '7.375000' }
    'Axis A 9' = { param($k) Wave 0.004 0.0004 $k 1 }
    'Axis B 9' = { param($k) Wave 0.009 0.0004 $k 2 }
}
New-Toa5 -Path "$d\t4.dat" -Rows $N -Columns $edT4
New-Toa5 -Path "$d\s4.dat" -Rows $N -Columns $edS4
$rec = Invoke-PopulateMissingData -TargetPath "$d\t4.dat" -SourcePath "$d\s4.dat"
Check 'first constant column placed from the two proven columns after it' ((Map-Of $rec 'T0').Method -eq 'Edge' -and (Map-Of $rec 'T0').SourceName -eq 'Temp 9' -and $rec.FieldsFilled -eq 1) ((Map-Of $rec 'T0') | Out-String)

Write-Host "`n=== matching by name ===" -ForegroundColor Cyan
$d = Join-Path $root 'name'; New-Item -ItemType Directory $d -Force | Out-Null
$nameT = [ordered]@{ 'Level' = { param($k) if ($k -eq 5) { 'NAN' } else { Wave 100 3 $k 4 } } }
$nameS = [ordered]@{ 'Other' = { param($k) Wave 7 1 $k 9 }; 'level' = { param($k) Wave 100 3 $k 4 } }
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $nameT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $nameS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'same name, any case, is used' ((Map-Of $rec 'Level').Method -eq 'Name' -and (Map-Of $rec 'Level').SourceName -eq 'level') ((Map-Of $rec 'Level') | Out-String)
Check 'unquoted NAN is a gap too' ($rec.FieldsFilled -eq 1) $rec.FieldsFilled

$nameS2 = [ordered]@{ 'Level' = { param($k) Wave 50 3 $k 4 } }
New-Toa5 -Path "$d\s2.dat" -Rows $N -Columns $nameS2
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s2.dat"
Check 'same name but values disagree -> refused' ((Map-Of $rec 'Level').Method -eq 'NameDisagrees' -and $rec.FieldsFilled -eq 0) ((Map-Of $rec 'Level') | Out-String)

Write-Host "`n=== ambiguity ===" -ForegroundColor Cyan
$d = Join-Path $root 'ambig'; New-Item -ItemType Directory $d -Force | Out-Null
# Two source columns each agree with the target on 97% of rows, but on
# different rows, so they agree with each other on only 94%.
$M = 100
$ambT = [ordered]@{ 'X' = { param($k) if ($k -eq 50) { 'NAN' } else { Wave 2 1 $k 5 } } }
$ambS = [ordered]@{
    'P' = { param($k) if ($k % 33 -eq 1) { '9.9' } else { Wave 2 1 $k 5 } }
    'Q' = { param($k) if ($k % 33 -eq 2) { '9.9' } else { Wave 2 1 $k 5 } }
}
New-Toa5 -Path "$d\t.dat" -Rows $M -Columns $ambT
New-Toa5 -Path "$d\s.dat" -Rows $M -Columns $ambS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat" -MinAgreement 0.95
Check 'two qualifiers that disagree with each other -> Ambiguous, not filled' ((Map-Of $rec 'X').Method -eq 'Ambiguous' -and $rec.FieldsFilled -eq 0) ((Map-Of $rec 'X') | Out-String)

Write-Host "`n=== two copies of one reading ===" -ForegroundColor Cyan
$d = Join-Path $root 'copies'; New-Item -ItemType Directory $d -Force | Out-Null
$cpT = [ordered]@{ 'T' = { param($k) if ($k -in 20, 21) { '"NAN"' } else { (5 + 0.25 * [Math]::Sin($k)).ToString('0.0000', $inv) } } }
$cpS = [ordered]@{
    'T rounded' = { param($k) if ($k -eq 21) { '"NAN"' } else { (5 + 0.25 * [Math]::Sin($k)).ToString('0.00', $inv) } }
    'T full'    = { param($k) if ($k -eq 20) { '"NAN"' } else { (5 + 0.25 * [Math]::Sin($k)).ToString('0.000000', $inv) } }
}
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $cpT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $cpS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'full-precision copy preferred over rounded one' ((Map-Of $rec 'T').SourceName -eq 'T full') ((Map-Of $rec 'T').SourceName)
Check 'the copies agree, so not ambiguous' ((Map-Of $rec 'T').Method -eq 'Values') ((Map-Of $rec 'T').Method)
Check 'gap where the chosen copy is NAN falls back to the other copy' ((Split-CsvFieldsRaw $rec.Lines[4 + 20])[2] -eq (5 + 0.25 * [Math]::Sin(20)).ToString('0.00', $inv)) ((Split-CsvFieldsRaw $rec.Lines[24])[2])
Check 'both gaps filled' ($rec.FieldsFilled -eq 2) $rec.FieldsFilled

Write-Host "`n=== values never copied ===" -ForegroundColor Cyan
$d = Join-Path $root 'skip'; New-Item -ItemType Directory $d -Force | Out-Null
# Readings near 1, so 0.999998 is inside the column's range and only the
# skip list can stop it; -0.999998 is outside it either way.
$skT = [ordered]@{ 'A' = { param($k) if ($k -in 3, 4, 5, 6) { '"NAN"' } else { Wave 1 0.0005 $k 7 } } }
$skS = [ordered]@{ 'A' = { param($k) switch ($k) { 3 { '0.999998' } 4 { '-0.999998' } 5 { '2.147484E+09' } 6 { '"NAN"' } default { Wave 1 0.0005 $k 7 } } } }
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $skT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $skS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'sensor-error 0.999998, -0.999998, 2.147484E+09 and NAN are not copied' ($rec.FieldsFilled -eq 0 -and $rec.GapsSourceMissing -eq 4) "$($rec.FieldsFilled) filled, $($rec.GapsSourceMissing) missing"
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat" -SkipSourceValues @()
Check '-SkipSourceValues @() lets an in-range 0.999998 through, still not the 1e9 code' ($rec.FieldsFilled -eq 1 -and $rec.GapsOutOfRange -eq 1) "$($rec.FieldsFilled) filled, $($rec.GapsOutOfRange) out of range"

$d = Join-Path $root 'range'; New-Item -ItemType Directory $d -Force | Out-Null
# A temperature that reads ~5 everywhere; the source has a 163 error reading
# (below the 1e9 code cut-off) and a plausible 5.2 in two of the gaps.
$rgT = [ordered]@{ 'T' = { param($k) if ($k -in 30, 31, 32) { '"NAN"' } else { (5 + 0.2 * [Math]::Sin($k)).ToString('0.000', $inv) } } }
$rgS = [ordered]@{ 'T' = { param($k) switch ($k) { 30 { '163' } 31 { '-7.224803E+08' } default { (5 + 0.2 * [Math]::Sin($k)).ToString('0.000', $inv) } } } }
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $rgT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $rgS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'values far outside the column''s own range (163, -7.2E+08) are not copied' ($rec.GapsOutOfRange -eq 2 -and $rec.FieldsFilled -eq 1) "$($rec.GapsOutOfRange) out of range, $($rec.FieldsFilled) filled"

Write-Host "`n=== repeated timestamps in the source ===" -ForegroundColor Cyan
$d = Join-Path $root 'dups'; New-Item -ItemType Directory $d -Force | Out-Null
$dpT = [ordered]@{ 'A' = { param($k) if ($k -in 7, 8) { '"NAN"' } else { Wave 1 0.5 $k 8 } } }
$dpS = [ordered]@{ 'A' = { param($k) Wave 1 0.5 $k 8 } }
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $dpT
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $dpS
$sl = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllLines("$d\s.dat"))
$sl.Add("`"$(Stamp 7)`",999,1.234")              # same time as row 7, different (plausible) value
$sl.Add("`"$(Stamp 8)`",998,$(Wave 1 0.5 8 8))")  # same time as row 8, same value
[System.IO.File]::WriteAllLines("$d\s.dat", $sl)
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'repeated time with different values -> not filled' ($rec.GapsSourceConflict -eq 1) $rec.GapsSourceConflict
Check 'repeated time with the same value -> filled' ($rec.FieldsFilled -eq 1) $rec.FieldsFilled

Write-Host "`n=== refusals ===" -ForegroundColor Cyan
$d = Join-Path $root 'refuse'; New-Item -ItemType Directory $d -Force | Out-Null
New-Toa5 -Path "$d\t.dat" -Rows 10 -Columns ([ordered]@{ 'A' = { param($k) 'NAN' } })
$noOverlap = [ordered]@{ 'A' = { param($k) '1' } }
New-Toa5 -Path "$d\s.dat" -Rows 10 -Columns $noOverlap
$s = [System.IO.File]::ReadAllText("$d\s.dat").Replace('2026-01-0', '2025-01-0')
[System.IO.File]::WriteAllText("$d\s.dat", $s)
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Check 'no shared timestamps -> NoOverlap' ($rec.Status -eq 'NoOverlap') $rec.Status
[System.IO.File]::WriteAllLines("$d\raw.dat", [string[]]@('Model,DT2485', 'x,y', '1,2', '3,4', '5,6'))
$threw = $false
try { [void](Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\raw.dat") } catch { $threw = $_.Exception.Message -like '*not a TOA5*' }
Check 'non-TOA5 source -> refused' $threw ''

Write-Host "`n=== round-trip fidelity ===" -ForegroundColor Cyan
$d = Join-Path $root 'fidelity'; New-Item -ItemType Directory $d -Force | Out-Null
$fT = [ordered]@{ 'A' = { param($k) if ($k -eq 3) { '"NAN"' } else { Wave 1 0.5 $k 8 } }; 'Note' = { param($k) '"a, ""quoted"" note"' } }
$fS = [ordered]@{ 'A' = { param($k) Wave 1 0.5 $k 8 } }
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $fT -Bom -Newline "`n"
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $fS
$rec = Invoke-PopulateMissingData -TargetPath "$d\t.dat" -SourcePath "$d\s.dat"
Write-PopulatedFile -FilePath "$d\t.dat" -Lines $rec.Lines
$bytes = [System.IO.File]::ReadAllBytes("$d\t.dat")
$text = [System.IO.File]::ReadAllText("$d\t.dat")
Check 'BOM kept' ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) ''
Check 'LF line endings kept' (-not $text.Contains("`r`n")) ''
Check 'quoted field with comma and "" survives' ((Field "$d\t.dat" 7 3) -eq '"a, ""quoted"" note"') (Field "$d\t.dat" 7 3)
Check 'gap filled' ((Field "$d\t.dat" 7 2) -eq (Wave 1 0.5 3 8)) (Field "$d\t.dat" 7 2)

Write-Host "`n=== the script end to end ===" -ForegroundColor Cyan
$d = Join-Path $root 'e2e'; New-Item -ItemType Directory $d -Force | Out-Null
New-Toa5 -Path "$d\t.dat" -Rows $N -Columns $tCols
New-Toa5 -Path "$d\s.dat" -Rows $N -Columns $sCols2
$orig = [System.IO.File]::ReadAllBytes("$d\t.dat")
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src "$d\t.dat" "$d\s.dat" -DryRun -Unattended *> $null
Check '-DryRun writes nothing, makes no Backup' ((-not (Test-Path "$d\Backup")) -and ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$d\t.dat")) -eq [Convert]::ToBase64String($orig))) ''
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $src "$d\t.dat" "$d\s.dat" -Unattended *> $null
$bk = @(Get-ChildItem "$d\Backup" -Filter '*.dat' -ErrorAction SilentlyContinue)
$log = @(Get-ChildItem "$d\Backup" -Filter '*.populate-log.txt' -ErrorAction SilentlyContinue)
Check 'real run: original copied into Backup' ($bk.Count -eq 1 -and [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($bk[0].FullName)) -eq [Convert]::ToBase64String($orig)) "$($bk.Count) backup(s)"
Check 'real run: log written beside it' ($log.Count -eq 1) "$($log.Count) log(s)"
Check 'real run: gaps filled in place' ((Field "$d\t.dat" 14 3) -eq (Wave 0.0035 0.0004 10 1)) (Field "$d\t.dat" 14 3)
Check 'source file untouched' ([System.IO.File]::ReadAllLines("$d\s.dat")[14] -notmatch 'NAN') ''

Remove-Item -LiteralPath $root -Recurse -Force
Write-Host ''
if ($fail -eq 0) { Write-Host "All checks passed." -ForegroundColor Green }
else { Write-Host "$fail check(s) FAILED." -ForegroundColor Red; exit 1 }
