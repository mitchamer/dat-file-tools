<#
    Populate Missing Data
    ---------------------
    Fills the gaps in one TOA5 data file (the TARGET) with readings from
    another TOA5 file (the SOURCE) that logged the same measurements at the
    same times - typically a CR6 table whose Modbus reads of a DT2485/DT85
    logger dropped out, and the DT2485's own download, which did not.

    A gap is a field that is NAN (any case, quoted or not) or empty. A gap is
    filled only from a SOURCE row with the identical timestamp, and only in a
    column that has been PROVEN to hold the same measurement.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    This script REWRITES THE TARGET FILE IN PLACE. Licensed under GPL-3.0 and
    provided "as is" with no warranty of any kind (see LICENSE sections 15-17).
    You are responsible for verifying the result before relying on it.

      * the original is copied into a 'Backup' folder first (unless -NoBackup)
      * ONLY missing fields change. Header rows, row order, every existing
        value, quoting, line endings and the byte-order mark are preserved
      * rows are never added, removed or sorted - a SOURCE timestamp the
        TARGET does not have is reported, not inserted
      * the SOURCE file is only read, never written
      * you see the column mapping and the counts and must approve them before
        anything is written. -DryRun shows the same and writes nothing

    HOW COLUMNS ARE MATCHED
    =======================
    The two files rarely share column names (DT85-1_Ch-1 in one, Axis A 1 in
    the other), so a name alone is not trusted and is not required. Every
    mapping must be backed by the rows both files already have values for:

      1. SAME NAME   A source column with the same name (case-insensitive) is
                     used, unless the shared rows show its values disagree.
      2. VALUES      Otherwise each target column is compared with every
                     source column on the shared timestamps. A source column
                     qualifies when at least -MinAgreement of at least
                     -MinOverlap shared readings agree (see TOLERANCE). The
                     best qualifier wins - higher agreement, then smaller
                     median difference. If a runner-up nearly as good
                     disagrees with the winner, the column is AMBIGUOUS and
                     left alone. Two qualifiers that agree with each other (the
                     same reading logged twice at different precision) are
                     not a conflict.
      3. BETWEEN     A column whose values barely change (a temperature that
                     reads 5.5 for five years) cannot be told apart from any
                     other constant by its values. It is mapped only when it
                     sits BETWEEN two proven columns that both keep the same
                     column spacing in the source, and the column that spacing
                     points to also agrees on the shared rows. Nothing is
                     inferred past the last proven column.

    RECORD and the timestamp column are never filled: a record number belongs
    to the logger that wrote it. A target column that none of the rules settles
    is left as it is and listed in the report.

    TOLERANCE
    =========
    Two readings agree when |target - source| <= 0.00001 + 0.2% of |target|.
    That absorbs the rounding between loggers (5.4375 vs 5.435) while two
    different inclinometer axes still differ by orders of magnitude more.

    VALUES NEVER COPIED
    ===================
      * NAN or empty in the source - there is nothing to copy
      * any value listed in -SkipSourceValues (default 0.999998 and -0.999998,
        the DT2485 sensor-error reading) and anything of magnitude 1e9 or more
        (the 2147483647 family of "no reading" codes)
      * a value far outside the TARGET column's own readings - beyond its 1st
        to 99th percentile widened by that spread again on each side (and by
        at least 10% of the value). Matching proves two columns hold the same
        measurement, not that every source value is a reading: a logger can
        write 163 for a temperature that never leaves 5-6, or -7.2E+08 when a
        Modbus read fails, and both are below the 1e9 code cut-off
      * a timestamp the source holds more than once with DIFFERENT values in
        that column - there is no telling which is right

    INVOCATION
    ==========
      1) RIGHT-CLICK the file to fill -> "Populate Missing Data"
         A file picker asks for the source, then the mapping is shown for
         approval.

      2) TERMINAL
           PS> .\Populate-MissingData.ps1 'C:\Data\Site.dat' 'C:\Data\DT2485_TOA5.dat'
           PS> .\Populate-MissingData.ps1 'C:\Data\Site.dat' 'C:\Data\DT2485_TOA5.dat' -DryRun

    PARAMETERS
    ==========
      -Path <file>           The TARGET - the file to fill. Position 0.
      -Source <file>         The file to fill it from. Position 1. A file
                             picker opens if it is not given.
      -DryRun                Report the mapping and counts, write nothing.
      -NoBackup              Do not copy the original into Backup first. This
                             removes the only automatic undo.
      -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                             Default Auto: write the file back with the
                             byte-order mark it arrived with.
      -MinAgreement <0.5-1>  Share of shared readings that must agree for a
                             column to match. Default 0.95.
      -MinOverlap <int>      Shared readings needed before values can prove a
                             match. Default 20.
      -SkipSourceValues <s[]>  Source values never copied. Default 0.999998,
                             -0.999998.
      -Unattended            Never open a dialog: no picker, no approval, no
                             summary box. Requires -Source. For scripted runs.

    A log of the mapping and counts is written into Backup\ beside the backup
    copy on every real run.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter(Position = 1)]
    [string]$Source,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$NoBackup,

    [Parameter()]
    [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'ASCII', 'Unicode')]
    [string]$Encoding = 'Auto',

    [Parameter()]
    [ValidateRange(0.5, 1.0)]
    [double]$MinAgreement = 0.95,

    [Parameter()]
    [ValidateRange(2, 1000000)]
    [int]$MinOverlap = 20,

    [Parameter()]
    [string[]]$SkipSourceValues = @('0.999998', '-0.999998'),

    [Parameter()]
    [switch]$Unattended
)

if (-not $Unattended) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

#region Helper Functions

# --- Encoding -------------------------------------------------------------
# LoggerNet data files carry no BOM, and a BOM ahead of the TOA5 row leaves
# LoggerNet unable to recognise the file it is appending to. Auto keeps
# whatever the file arrived with.

function Get-FileBomEncoding {
    param([string]$FilePath)

    $bytes = New-Object byte[] 4
    $read = 0
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try { $read = $stream.Read($bytes, 0, 4) } finally { $stream.Dispose() }
    }
    catch {
        return (New-Object System.Text.UTF8Encoding($false))
    }

    if ($read -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return (New-Object System.Text.UnicodeEncoding($false, $true))
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return (New-Object System.Text.UnicodeEncoding($true, $true))
    }
    return (New-Object System.Text.UTF8Encoding($false))
}

function Resolve-OutputEncoding {
    param([string]$Name, [string]$FilePath)

    switch ($Name) {
        'Auto' { return (Get-FileBomEncoding -FilePath $FilePath) }
        'UTF8' { return (New-Object System.Text.UTF8Encoding($false)) }
        'UTF8BOM' { return (New-Object System.Text.UTF8Encoding($true)) }
        'ASCII' { return ([System.Text.Encoding]::ASCII) }
        'Unicode' { return (New-Object System.Text.UnicodeEncoding($false, $true)) }
    }
    return (New-Object System.Text.UTF8Encoding($false))
}

function Get-FileNewline {
    <#
        CRLF unless the file is plainly LF-only. Written back the same way, so
        the rows this tool does not touch stay byte-identical.
    #>
    param([string]$FilePath)

    $text = [System.IO.File]::ReadAllText($FilePath)
    if ($text.Contains("`r`n") -or -not $text.Contains("`n")) { return "`r`n" }
    return "`n"
}

# --- Compiled core --------------------------------------------------------
# Matching columns compares every target column with every source column over
# thousands of shared rows - tens of millions of comparisons. As PowerShell
# loops that takes minutes; compiled it takes about a second. Only the
# arithmetic lives here; every decision is made in the PowerShell below.

$script:PopulateCoreSource = @'
using System;
using System.Collections.Generic;
using System.Globalization;

public static class PopulateCore
{
    // Fields EXACTLY as written, quotes and all, so a row re-joined after a
    // gap is filled is identical to the original everywhere else. A doubled
    // "" inside a quoted field toggles twice and lands back inside.
    public static string[] SplitRaw(string line)
    {
        var fields = new List<string>();
        int start = 0;
        bool inQuotes = false;
        for (int i = 0; i < line.Length; i++)
        {
            char ch = line[i];
            if (ch == '"') inQuotes = !inQuotes;
            else if (ch == ',' && !inQuotes)
            {
                fields.Add(line.Substring(start, i - start));
                start = i + 1;
            }
        }
        fields.Add(line.Substring(start));
        return fields.ToArray();
    }

    public static string Unquote(string field)
    {
        string t = (field ?? "").Trim();
        if (t.Length >= 2 && t[0] == '"' && t[t.Length - 1] == '"')
            return t.Substring(1, t.Length - 2).Replace("\"\"", "\"");
        return t;
    }

    public static bool IsMissing(string field)
    {
        string v = Unquote(field);
        return v.Length == 0 || string.Equals(v, "NAN", StringComparison.OrdinalIgnoreCase);
    }

    // NaN for anything that is not a reading: NAN, empty, text, or a
    // magnitude of 1e9+ (the 2147483647 family of "no reading" codes).
    public static double Reading(string field)
    {
        double d;
        if (!double.TryParse(Unquote(field), NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return double.NaN;
        if (double.IsInfinity(d) || Math.Abs(d) >= 1e9) return double.NaN;
        return d;
    }

    public static double[] ReadColumn(object[] rows, int index)
    {
        var output = new double[rows.Length];
        for (int k = 0; k < rows.Length; k++)
        {
            var f = (string[])rows[k];
            output[k] = index < f.Length ? Reading(f[index]) : double.NaN;
        }
        return output;
    }

    // { pairs compared, share within tolerance, median |difference|,
    //   mean |difference| over the pairs that agree }. The last separates a
    //   full-precision copy of a reading from a rounded one, whose medians
    //   often tie.
    public static double[] Agreement(double[] a, double[] b, int step, double absTol, double relTol)
    {
        var diffs = new List<double>();
        int ok = 0;
        double okSum = 0;
        for (int k = 0; k < a.Length && k < b.Length; k += Math.Max(1, step))
        {
            if (double.IsNaN(a[k]) || double.IsNaN(b[k])) continue;
            double d = Math.Abs(a[k] - b[k]);
            diffs.Add(d);
            if (d <= absTol + relTol * Math.Abs(a[k])) { ok++; okSum += d; }
        }
        int n = diffs.Count;
        if (n == 0) return new double[] { 0, 0, double.NaN, double.NaN };
        diffs.Sort();
        return new double[] { n, (double)ok / n, diffs[(n - 1) / 2], ok > 0 ? okSum / ok : double.NaN };
    }

    // The value to put in one gap, from the source rows sharing its timestamp.
    // Columns are tried in order (the chosen one, then its proven
    // equivalents); the first that yields a usable reading decides. Returns
    // { "ok", value } | { "missing", null } | { "range", null } |
    // { "conflict", null }. "range" when the only readings fall outside
    // [lo, hi]; "conflict" when a repeated timestamp gives different readings.
    public static string[] PickFill(System.Collections.IList rows, int[] cols, double[] skip, double lo, double hi)
    {
        var values = new List<string>();
        bool outOfRange = false;
        foreach (int j in cols)
        {
            foreach (object o in rows)
            {
                var s = (string[])o;
                if (j >= s.Length) continue;
                string v = s[j].Trim();
                double r = Reading(v);
                if (double.IsNaN(r) || Array.IndexOf(skip, r) >= 0) continue;
                if (r < lo || r > hi) { outOfRange = true; continue; }
                if (!values.Contains(v)) values.Add(v);
            }
            if (values.Count > 0) break;
        }
        if (values.Count == 0) return new string[] { outOfRange ? "range" : "missing", null };
        if (values.Count > 1) return new string[] { "conflict", null };
        return new string[] { "ok", values[0] };
    }

    // The span a fill value must fall inside: the target column's own 1st to
    // 99th percentile, widened by that spread again on each side (and by at
    // least 10% of the value's size, for a column that barely moves).
    // Percentiles, not min/max, so a few error codes already in the column
    // cannot stretch it. { lo, hi }, or { -inf, +inf } with no readings.
    public static double[] PlausibleRange(double[] values)
    {
        var v = new List<double>();
        foreach (double x in values) if (!double.IsNaN(x)) v.Add(x);
        if (v.Count == 0) return new double[] { double.NegativeInfinity, double.PositiveInfinity };
        v.Sort();
        double p01 = v[(int)Math.Floor(0.01 * (v.Count - 1))];
        double p99 = v[(int)Math.Ceiling(0.99 * (v.Count - 1))];
        double pad = Math.Max(p99 - p01, 0.1 * Math.Max(Math.Abs(p01), Math.Abs(p99)));
        pad = Math.Max(pad, 1e-5);
        return new double[] { p01 - pad, p99 + pad };
    }

    public static int DistinctCount(double[] values, int limit)
    {
        var seen = new HashSet<double>();
        foreach (double v in values)
        {
            if (double.IsNaN(v)) continue;
            seen.Add(v);
            if (seen.Count >= limit) break;
        }
        return seen.Count;
    }
}
'@

function Initialize-PopulateCore {
    if (-not ('PopulateCore' -as [type])) {
        Add-Type -TypeDefinition $script:PopulateCoreSource -Language CSharp
    }
}

# --- Rows -----------------------------------------------------------------

function Split-CsvFieldsRaw {
    param([string]$Line)
    return , [PopulateCore]::SplitRaw($Line)
}

function Get-Unquoted {
    param([string]$Field)
    return [PopulateCore]::Unquote($Field)
}

function Test-MissingField {
    param([string]$Field)
    return [PopulateCore]::IsMissing($Field)
}

function ConvertTo-Reading {
    <#
        A field as a number, or $null for anything that is not a reading:
        NAN, empty, text, or a magnitude of 1e9+.
    #>
    param([string]$Field)
    $d = [PopulateCore]::Reading($Field)
    if ([double]::IsNaN($d)) { return $null }
    return $d
}

function Read-Toa5File {
    <#
        A TOA5 file: row 1 the environment row, row 2 the column names, rows
        3-4 units and processing, data from row 5. Returns the raw lines and
        the column names; throws on anything that is not TOA5.
    #>
    param([string]$FilePath)

    $lines = [System.IO.File]::ReadAllLines($FilePath)
    if ($lines.Count -lt 4 -or (Get-Unquoted (Split-CsvFieldsRaw $lines[0])[0]) -ne 'TOA5') {
        throw "'$([System.IO.Path]::GetFileName($FilePath))' is not a TOA5 file (row 1 does not start with TOA5)."
    }
    $raw = Split-CsvFieldsRaw $lines[1]
    $names = @($raw | ForEach-Object { Get-Unquoted $_ })
    if ($names.Count -lt 2) {
        throw "'$([System.IO.Path]::GetFileName($FilePath))' has no data columns in its header row."
    }
    return [pscustomobject]@{
        Path      = $FilePath
        Lines     = $lines
        Names     = $names
        DataStart = 4
    }
}

function Get-RowsByTimestamp {
    <#
        Timestamp -> list of split rows. A timestamp can legitimately appear
        more than once (a logger clock stepping back), so every row is kept.
    #>
    param([object]$File)

    $map = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    for ($i = $File.DataStart; $i -lt $File.Lines.Count; $i++) {
        $line = $File.Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $f = [PopulateCore]::SplitRaw($line)
        $key = [PopulateCore]::Unquote($f[0])
        if (-not $map.ContainsKey($key)) { $map[$key] = [System.Collections.Generic.List[object]]::new() }
        $map[$key].Add($f)
    }
    return $map
}

# --- Column matching ------------------------------------------------------

$script:AbsTolerance = 0.00001
$script:RelTolerance = 0.002

function Get-ColumnReadings {
    <#
        One column's readings over the shared timestamps, as a double[] with
        NaN where there is no reading. Only the FIRST row of a repeated
        timestamp is used for proof.
    #>
    param([System.Collections.Generic.List[object]]$Rows, [int]$Index)
    return , [PopulateCore]::ReadColumn($Rows.ToArray(), $Index)
}

function Measure-Agreement {
    <#
        How well two columns of readings agree where both have one.
        Rate is the share within tolerance; Median the median |difference|.
        -Step samples every Nth pair for a cheap first pass.
    #>
    param([double[]]$TargetValues, [double[]]$SourceValues, [int]$Step = 1)

    $r = [PopulateCore]::Agreement($TargetValues, $SourceValues, $Step, $script:AbsTolerance, $script:RelTolerance)
    return [pscustomobject]@{ N = [int]$r[0]; Rate = $r[1]; Median = $r[2]; Mean = $r[3] }
}

function Get-DistinctCount {
    param([double[]]$Values, [int]$Limit = 3)
    return [PopulateCore]::DistinctCount($Values, $Limit)
}

function Get-RankedCandidates {
    <#
        Best first. Agreement decides, but rates within half a percent are a
        tie - one stray row should not pick a 2-decimal copy of a reading over
        the full-precision copy - and a tie goes to the smaller mean difference
        over the agreeing readings, which rounding inflates.
    #>
    param([object[]]$Candidates)

    $sorted = @($Candidates | Where-Object { $_ } |
        Sort-Object -Property @{ Expression = 'Rate'; Descending = $true }, @{ Expression = 'Mean'; Descending = $false })
    if ($sorted.Count -lt 2) { return , $sorted }
    $top = $sorted[0].Rate
    $best = @($sorted | Where-Object { $_.Rate -ge $top - 0.005 } | Sort-Object -Property Mean)[0]
    return , (@($best) + @($sorted | Where-Object { $_ -ne $best }))
}

function Resolve-ColumnMap {
    <#
        Decides which source column, if any, fills each target column.

        Returns one record per target column (except the timestamp):
          Target / TargetName
          Source / SourceName   -1 / $null when unmapped
          Method                Name | Values | Between | (unmapped) Skipped |
                                Constant | Ambiguous | NoMatch | NameDisagrees
          Rate / Median / N     the evidence on the shared rows
          Alternates            other source columns proven to hold the same
                                reading (a second copy at another precision);
                                used, in order, where Source has no usable value
          Note                  a sentence for the report
    #>
    param(
        [object]$Target,
        [object]$SourceFile,
        [System.Collections.Generic.List[object]]$TargetRows,
        [System.Collections.Generic.List[object]]$SourceRows,
        [double]$MinAgreement,
        [int]$MinOverlap
    )

    $tCount = $Target.Names.Count
    $sCount = $SourceFile.Names.Count
    $tRead = @{}; $sRead = @{}
    for ($i = 1; $i -lt $tCount; $i++) { $tRead[$i] = Get-ColumnReadings -Rows $TargetRows -Index $i }
    for ($j = 1; $j -lt $sCount; $j++) { $sRead[$j] = Get-ColumnReadings -Rows $SourceRows -Index $j }

    $sourceByName = @{}
    for ($j = 1; $j -lt $sCount; $j++) {
        $nm = $SourceFile.Names[$j].ToLowerInvariant()
        if (-not $sourceByName.ContainsKey($nm)) { $sourceByName[$nm] = $j }
    }

    # Sampled first pass keeps the all-pairs comparison cheap; only columns
    # that look close are measured in full.
    $step = [Math]::Max(1, [int][Math]::Floor($TargetRows.Count / 400))

    $result = @{}
    $candidates = @{}   # target index -> qualifying source candidates, best first

    for ($i = 1; $i -lt $tCount; $i++) {
        $name = $Target.Names[$i]
        $rec = [pscustomobject]@{
            Target = $i; TargetName = $name; Source = -1; SourceName = $null
            Method = 'NoMatch'; Rate = $null; Median = $null; N = 0; Alternates = @(); Note = ''
        }
        $result[$i] = $rec

        if ($name -ieq 'RECORD') {
            $rec.Method = 'Skipped'
            $rec.Note = 'record numbers belong to the logger that wrote them'
            continue
        }

        # 1. Same name
        $nm = $name.ToLowerInvariant()
        if ($sourceByName.ContainsKey($nm)) {
            $j = $sourceByName[$nm]
            $m = Measure-Agreement -TargetValues $tRead[$i] -SourceValues $sRead[$j]
            if ($m.N -lt $MinOverlap -or $m.Rate -ge $MinAgreement) {
                $rec.Source = $j; $rec.SourceName = $SourceFile.Names[$j]; $rec.Method = 'Name'
                $rec.Rate = $m.Rate; $rec.Median = $m.Median; $rec.N = $m.N
                $rec.Note = if ($m.N -lt $MinOverlap) { "same name; only $($m.N) shared reading(s) to check it against" } else { 'same name, values agree' }
                $candidates[$i] = @([pscustomobject]@{ Source = $j; Rate = $m.Rate; Median = $m.Median; Mean = $m.Mean; N = $m.N })
                continue
            }
            $rec.Method = 'NameDisagrees'
            $rec.Note = "source column '$($SourceFile.Names[$j])' has the same name but only {0:P1} of {1} shared readings agree" -f $m.Rate, $m.N
            continue
        }

        # 2. Values
        $found = [System.Collections.Generic.List[object]]::new()
        for ($j = 1; $j -lt $sCount; $j++) {
            if ($SourceFile.Names[$j] -ieq 'RECORD') { continue }
            $quick = Measure-Agreement -TargetValues $tRead[$i] -SourceValues $sRead[$j] -Step $step
            if ($quick.N -ge 5 -and $quick.Rate -lt $MinAgreement - 0.1) { continue }
            $m = Measure-Agreement -TargetValues $tRead[$i] -SourceValues $sRead[$j]
            if ($m.N -ge $MinOverlap -and $m.Rate -ge $MinAgreement) {
                $found.Add([pscustomobject]@{ Source = $j; Rate = $m.Rate; Median = $m.Median; Mean = $m.Mean; N = $m.N })
            }
        }
        $sorted = Get-RankedCandidates -Candidates $found
        $candidates[$i] = $sorted

        if ((Get-DistinctCount -Values $tRead[$i]) -lt 3) {
            # Agreement with a constant proves nothing - 0 matches every other
            # 0. Left for the Between rule.
            $rec.Method = 'Constant'
            $rec.Note = 'its values barely change, so they cannot prove which source column it is'
            continue
        }
        if ($sorted.Count -eq 0) {
            $rec.Note = 'no source column agrees with it on the shared rows'
            continue
        }

        $best = $sorted[0]
        $rival = $null
        $alternates = [System.Collections.Generic.List[int]]::new()
        foreach ($c in $sorted | Select-Object -Skip 1) {
            $same = Measure-Agreement -TargetValues $sRead[$best.Source] -SourceValues $sRead[$c.Source]
            if ($same.Rate -ge $MinAgreement) { $alternates.Add($c.Source) }
            elseif ($c.Rate -ge $best.Rate - 0.02) { $rival = $c; break }
        }
        if ($rival) {
            $rec.Method = 'Ambiguous'
            $rec.Note = "'{0}' ({1:P1}) and '{2}' ({3:P1}) both agree with it and with each other they do not" -f `
                $SourceFile.Names[$best.Source], $best.Rate, $SourceFile.Names[$rival.Source], $rival.Rate
            continue
        }
        $rec.Source = $best.Source; $rec.SourceName = $SourceFile.Names[$best.Source]; $rec.Method = 'Values'
        $rec.Rate = $best.Rate; $rec.Median = $best.Median; $rec.N = $best.N
        $rec.Alternates = $alternates.ToArray()
        $rec.Note = '{0:P2} of {1} shared readings agree, median difference {2:G3}' -f $best.Rate, $best.N, $best.Median
    }

    # 3. Between: settle constant (or otherwise unproven) columns from the
    # column spacing of the proven ones on either side.
    $proven = @($result.Values | Where-Object { $_.Method -in @('Name', 'Values') } | ForEach-Object { $_.Target } | Sort-Object)
    foreach ($i in 1..($tCount - 1)) {
        $rec = $result[$i]
        if ($rec.Method -notin @('Constant', 'NoMatch')) { continue }
        $left = @($proven | Where-Object { $_ -lt $i }) | Select-Object -Last 1
        $right = @($proven | Where-Object { $_ -gt $i }) | Select-Object -First 1
        if ($null -eq $left -or $null -eq $right) { continue }

        $proposals = @{}
        foreach ($cl in $candidates[$left]) {
            foreach ($cr in $candidates[$right]) {
                if (($cr.Source - $cl.Source) -ne ($right - $left)) { continue }
                $j = $cl.Source + ($i - $left)
                if ($j -lt 1 -or $j -ge $sCount -or $proposals.ContainsKey($j)) { continue }
                if ($SourceFile.Names[$j] -ieq 'RECORD') { continue }
                $m = Measure-Agreement -TargetValues $tRead[$i] -SourceValues $sRead[$j]
                if ($m.N -ge $MinOverlap -and $m.Rate -ge $MinAgreement) {
                    $proposals[$j] = [pscustomobject]@{ Source = $j; Rate = $m.Rate; Median = $m.Median; Mean = $m.Mean; N = $m.N }
                }
            }
        }
        if ($proposals.Count -eq 0) { continue }
        $sorted = Get-RankedCandidates -Candidates @($proposals.Values)
        $best = $sorted[0]
        $conflict = $false
        foreach ($c in $sorted | Select-Object -Skip 1) {
            if ((Measure-Agreement -TargetValues $sRead[$best.Source] -SourceValues $sRead[$c.Source]).Rate -lt $MinAgreement) { $conflict = $true; break }
        }
        if ($conflict) {
            $rec.Method = 'Ambiguous'
            $rec.Note = 'the proven columns either side point to source columns that disagree with each other'
            continue
        }
        $rec.Source = $best.Source; $rec.SourceName = $SourceFile.Names[$best.Source]; $rec.Method = 'Between'
        $rec.Rate = $best.Rate; $rec.Median = $best.Median; $rec.N = $best.N
        $rec.Alternates = @($sorted | Select-Object -Skip 1 | ForEach-Object { $_.Source })
        $rec.Note = "between proven '{0}' and '{1}', same column spacing; {2:P2} of {3} shared readings agree" -f `
            $Target.Names[$left], $Target.Names[$right], $best.Rate, $best.N
    }

    foreach ($r in $result.Values) {
        if ($r.Alternates.Count -gt 0) {
            $r.Note += '; falls back to ' + (($r.Alternates | ForEach-Object { "'$($SourceFile.Names[$_])'" }) -join ', ')
        }
    }
    return @(1..($tCount - 1) | ForEach-Object { $result[$_] })
}

# --- Filling --------------------------------------------------------------

function Invoke-PopulateMissingData {
    <#
        Reads both files, matches columns, fills gaps in memory. Writes
        nothing. Returns a record with the mapping, the counts and the new
        lines.
    #>
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$SourcePath,
        [double]$MinAgreement = 0.95,
        [int]$MinOverlap = 20,
        [string[]]$SkipSourceValues = @('0.999998', '-0.999998')
    )

    Initialize-PopulateCore
    $target = Read-Toa5File -FilePath $TargetPath
    $sourceFile = Read-Toa5File -FilePath $SourcePath
    $tMap = Get-RowsByTimestamp -File $target
    $sMap = Get-RowsByTimestamp -File $sourceFile

    $shared = @($tMap.Keys | Where-Object { $sMap.ContainsKey($_) })
    $rec = [pscustomobject]@{
        Target = $TargetPath; Source = $SourcePath
        SharedTimestamps = $shared.Count
        SourceOnlyTimestamps = @($sMap.Keys | Where-Object { -not $tMap.ContainsKey($_) }).Count
        Map = @(); RowsFilled = 0; FieldsFilled = 0
        GapsNoSourceRow = 0; GapsSourceMissing = 0; GapsOutOfRange = 0; GapsSourceConflict = 0; GapsUnmappedColumn = 0
        FirstFilled = $null; LastFilled = $null
        Lines = $target.Lines; Status = 'Ok'; Detail = ''
    }
    if ($shared.Count -eq 0) {
        $rec.Status = 'NoOverlap'
        $rec.Detail = 'The two files share no timestamps. Both must be YYYY-MM-DD HH:MM:SS - run Fix Timestamps on them first.'
        return $rec
    }

    $tRows = [System.Collections.Generic.List[object]]::new()
    $sRows = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $shared) { $tRows.Add($tMap[$k][0]); $sRows.Add($sMap[$k][0]) }

    $rec.Map = Resolve-ColumnMap -Target $target -SourceFile $sourceFile -TargetRows $tRows -SourceRows $sRows `
        -MinAgreement $MinAgreement -MinOverlap $MinOverlap
    $mapped = @($rec.Map | Where-Object { $_.Source -ge 0 })
    $unmapped = @($rec.Map | Where-Object { $_.Source -lt 0 -and $_.Method -ne 'Skipped' } | ForEach-Object { $_.Target })

    # NAN, empty, text and 1e9+ codes are never readings; these are the
    # additional values that look like readings but are not.
    [double[]]$skipNumbers = @($SkipSourceValues | ForEach-Object { ConvertTo-Reading $_ } | Where-Object { $null -ne $_ })
    # Per mapped column: the source columns to try, chosen one first.
    $fillCols = @{}
    foreach ($m in $mapped) { $fillCols[$m.Target] = [int[]](@($m.Source) + @($m.Alternates)) }

    # Per mapped column: the span a fill must fall in, from the target's OWN
    # readings in every row. Agreement proves the columns are the same
    # measurement, but not that every source value is a reading - a CR6 can
    # log 163 for a temperature or -7.2E+08 when a Modbus read fails, and
    # those are below the 1e9 code cut-off.
    $allTargetRows = [System.Collections.Generic.List[object]]::new()
    foreach ($list in $tMap.Values) { foreach ($r in $list) { $allTargetRows.Add($r) } }
    $ranges = @{}
    foreach ($m in $mapped) {
        $ranges[$m.Target] = [PopulateCore]::PlausibleRange((Get-ColumnReadings -Rows $allTargetRows -Index $m.Target))
    }

    # Plain counters: properties on the record are slow to bump in a loop.
    $rowsFilled = 0; $fieldsFilled = 0
    $noRow = 0; $noReading = 0; $outOfRange = 0; $conflict = 0; $unmappedGaps = 0

    $lines = [string[]]$target.Lines.Clone()
    for ($n = $target.DataStart; $n -lt $lines.Count; $n++) {
        $line = $lines[$n]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # Most rows have no gap at all; skip them without splitting.
        if ($line -notmatch '(?i)nan|,,|,""|,\s*$') { continue }
        $f = [PopulateCore]::SplitRaw($line)
        $key = [PopulateCore]::Unquote($f[0])
        # Assigned directly: an if-expression would unroll a one-row list
        # into that row's fields.
        $sList = $null
        if ($sMap.ContainsKey($key)) { $sList = $sMap[$key] }
        $changed = $false

        foreach ($i in $unmapped) {
            if ($i -lt $f.Count -and [PopulateCore]::IsMissing($f[$i])) { $unmappedGaps++ }
        }
        foreach ($m in $mapped) {
            $i = $m.Target
            if ($i -ge $f.Count -or -not [PopulateCore]::IsMissing($f[$i])) { continue }
            if (-not $sList) { $noRow++; continue }

            $rg = $ranges[$i]
            $pick = [PopulateCore]::PickFill($sList, $fillCols[$i], $skipNumbers, $rg[0], $rg[1])
            if ($pick[0] -eq 'missing') { $noReading++; continue }
            if ($pick[0] -eq 'range') { $outOfRange++; continue }
            if ($pick[0] -eq 'conflict') { $conflict++; continue }

            $f[$i] = $pick[1]
            $fieldsFilled++
            $changed = $true
        }
        if ($changed) {
            $lines[$n] = $f -join ','
            $rowsFilled++
            if (-not $rec.FirstFilled) { $rec.FirstFilled = $key }
            $rec.LastFilled = $key
        }
    }
    $rec.Lines = $lines
    $rec.RowsFilled = $rowsFilled; $rec.FieldsFilled = $fieldsFilled
    $rec.GapsNoSourceRow = $noRow; $rec.GapsSourceMissing = $noReading; $rec.GapsOutOfRange = $outOfRange
    $rec.GapsSourceConflict = $conflict; $rec.GapsUnmappedColumn = $unmappedGaps
    if ($mapped.Count -eq 0) {
        $rec.Status = 'NoColumns'
        $rec.Detail = 'No target column could be matched to a source column.'
    }
    elseif ($rec.FieldsFilled -eq 0) {
        $rec.Status = 'NothingToFill'
        $rec.Detail = 'Columns matched, but the source has no reading for any of the target''s gaps.'
    }
    return $rec
}

function Backup-File {
    param([string]$FilePath, [string]$BackupFolder, [string]$Stamp)

    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath)
    $dest = Join-Path $BackupFolder "${name}_${Stamp}${ext}"
    Copy-Item -LiteralPath $FilePath -Destination $dest -Force
    return $dest
}

function Write-PopulatedFile {
    <#
        Writes beside the target, then swaps it in, so a failure part way
        through never leaves a half-written data file.
    #>
    param([string]$FilePath, [string[]]$Lines, [string]$Encoding = 'Auto')

    $enc = Resolve-OutputEncoding -Name $Encoding -FilePath $FilePath
    $nl = Get-FileNewline -FilePath $FilePath
    $tmp = "$FilePath.populate.tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, (($Lines -join $nl) + $nl), $enc)
        Move-Item -LiteralPath $tmp -Destination $FilePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Format-MapReport {
    param([object[]]$Map)

    $lines = [System.Collections.Generic.List[string]]::new()
    $w = ($Map | ForEach-Object { $_.TargetName.Length } | Measure-Object -Maximum).Maximum
    foreach ($m in $Map) {
        $left = $m.TargetName.PadRight($w)
        if ($m.Source -ge 0) {
            $lines.Add(("  {0}  <-  {1,-22} [{2}] {3}" -f $left, $m.SourceName, $m.Method, $m.Note))
        }
        else {
            $lines.Add(("  {0}      (not filled: {1}) {2}" -f $left, $m.Method, $m.Note))
        }
    }
    return $lines
}

function Format-Summary {
    param([object]$Rec)

    $mapped = @($Rec.Map | Where-Object { $_.Source -ge 0 }).Count
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("Target:  $($Rec.Target)")
    $out.Add("Source:  $($Rec.Source)")
    $out.Add('')
    $out.Add("Shared timestamps:           $($Rec.SharedTimestamps)")
    $out.Add("Columns matched:             $mapped of $($Rec.Map.Count)")
    $out.Add("Rows that get values:        $($Rec.RowsFilled)")
    $out.Add("Fields filled:               $($Rec.FieldsFilled)")
    if ($Rec.FirstFilled) { $out.Add("Filled range:                $($Rec.FirstFilled) .. $($Rec.LastFilled)") }
    $out.Add('')
    $out.Add('Gaps left as they are:')
    $out.Add("  no source row at that time:      $($Rec.GapsNoSourceRow)")
    $out.Add("  source has no usable reading:    $($Rec.GapsSourceMissing)")
    $out.Add("  source value outside the column's range: $($Rec.GapsOutOfRange)")
    $out.Add("  source repeats the time, values differ: $($Rec.GapsSourceConflict)")
    $out.Add("  column not matched:              $($Rec.GapsUnmappedColumn)")
    $out.Add("Source timestamps not in target (not added): $($Rec.SourceOnlyTimestamps)")
    $out.Add('')
    $out.Add('Column mapping (target <- source):')
    foreach ($l in (Format-MapReport -Map $Rec.Map)) { $out.Add($l) }
    return $out
}

#endregion

#region Dialogs

function Select-SourceFile {
    param([string]$InitialDir, [string]$TargetName)

    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Pick the file to fill '$TargetName' FROM"
    $dlg.Filter = 'Data files (*.dat;*.csv;*.txt)|*.dat;*.csv;*.txt|All files (*.*)|*.*'
    if ($InitialDir -and (Test-Path -LiteralPath $InitialDir)) { $dlg.InitialDirectory = $InitialDir }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return $null
}

function Show-ApprovalDialog {
    <#
        The mapping and counts, with Proceed / Cancel. Cancel is the default:
        the column mapping is the part worth reading before saying yes.
    #>
    param([string[]]$Text, [string]$Title, [switch]$ReadOnly)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(1000, 700)
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Dock = 'Fill'
    $box.Text = $Text -join "`r`n"

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.FlowDirection = 'RightToLeft'
    $panel.Height = 44
    $panel.Padding = New-Object System.Windows.Forms.Padding(6)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = if ($ReadOnly) { 'Close' } else { 'Cancel' }
    $cancel.Width = 110
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $panel.Controls.Add($cancel)
    $form.CancelButton = $cancel
    $form.AcceptButton = $cancel

    if (-not $ReadOnly) {
        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = 'Fill gaps'
        $ok.Width = 110
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $panel.Controls.Add($ok)
    }

    $form.Controls.Add($box)
    $form.Controls.Add($panel)
    $form.Add_Shown({ $box.SelectionLength = 0; $cancel.Focus() })
    return ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
}

function Show-Notification {
    param([string]$Message, [string]$Title = "Notice", $Icon = 'Information')
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    ) | Out-Null
}

#endregion

#region Main

try {
    # Explorer hands the file over as "%1"; a stray quote can arrive attached.
    $targetPath = if ($Path) { $Path.Trim('"') } elseif ($args.Count -gt 0) { "$($args[0])".Trim('"') } else { $null }
    if (-not $targetPath -or -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Give the file to fill as the first argument (got '$targetPath')."
    }
    $targetPath = [System.IO.Path]::GetFullPath($targetPath)

    $sourcePath = if ($Source) { $Source.Trim('"') } else { $null }
    if (-not $sourcePath) {
        if ($Unattended) { throw "-Unattended needs -Source: there is no picker to ask with." }
        $sourcePath = Select-SourceFile -InitialDir (Split-Path -Parent $targetPath) -TargetName (Split-Path -Leaf $targetPath)
        if (-not $sourcePath) { Write-Warning "No source file selected. Exiting."; return }
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Source file not found: $sourcePath" }
    $sourcePath = [System.IO.Path]::GetFullPath($sourcePath)
    if ($sourcePath -ieq $targetPath) { throw "The source and the target are the same file." }

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "POPULATE MISSING DATA" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "Target (filled):  $targetPath"
    Write-Host "Source (read):    $sourcePath"
    Write-Host "Backup:           $(if ($NoBackup) { 'NO - -NoBackup removes the only automatic undo' } else { 'yes, into Backup\ before writing' })"
    if ($DryRun) { Write-Host "Mode:             DRY RUN - nothing will be written" -ForegroundColor Yellow }
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "Matching columns on the shared timestamps ..." -ForegroundColor Cyan

    $rec = Invoke-PopulateMissingData -TargetPath $targetPath -SourcePath $sourcePath `
        -MinAgreement $MinAgreement -MinOverlap $MinOverlap -SkipSourceValues $SkipSourceValues
    $summary = Format-Summary -Rec $rec
    Write-Host ''
    $summary | ForEach-Object { Write-Host $_ }
    Write-Host ''

    if ($rec.Status -ne 'Ok') {
        Write-Warning $rec.Detail
        if (-not $Unattended) { Show-Notification -Title 'Nothing Filled' -Icon Warning -Message "$($rec.Detail)`n`nThe target was not changed." }
        return
    }

    if ($DryRun) {
        Write-Host "DRY RUN - nothing was written." -ForegroundColor Yellow
        if (-not $Unattended) { [void](Show-ApprovalDialog -Text (@('DRY RUN - nothing will be written.', '') + $summary) -Title 'Populate Missing Data - check' -ReadOnly) }
        return
    }

    if (-not $Unattended) {
        $approved = Show-ApprovalDialog -Text (@('Read the column mapping before approving: only these columns are filled.', '') + $summary) `
            -Title 'Populate Missing Data - approve'
        if (-not $approved) { Write-Host "Cancelled - nothing was written." -ForegroundColor Yellow; return }
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFolder = Join-Path (Split-Path -Parent $targetPath) 'Backup'
    $backup = $null
    if (-not $NoBackup) { $backup = Backup-File -FilePath $targetPath -BackupFolder $backupFolder -Stamp $stamp }
    Write-PopulatedFile -FilePath $targetPath -Lines $rec.Lines -Encoding $Encoding

    if (-not (Test-Path -LiteralPath $backupFolder)) { New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null }
    $logPath = Join-Path $backupFolder ("{0}_{1}.populate-log.txt" -f [System.IO.Path]::GetFileNameWithoutExtension($targetPath), $stamp)
    $log = @("POPULATE MISSING DATA", "Run:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Backup:  $(if ($backup) { $backup } else { 'none (-NoBackup)' })", '') + $summary
    [System.IO.File]::WriteAllLines($logPath, [string[]]$log, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "$('=' * 70)" -ForegroundColor Green
    Write-Host "FILLED $($rec.FieldsFilled) field(s) in $($rec.RowsFilled) row(s)" -ForegroundColor Green
    if ($backup) { Write-Host "Original: $backup" }
    Write-Host "Log:      $logPath"
    Write-Host "$('=' * 70)" -ForegroundColor Green

    if (-not $Unattended) {
        Show-Notification -Title 'Populate Missing Data - done' -Message (
            "Filled $($rec.FieldsFilled) field(s) in $($rec.RowsFilled) row(s).`n`n" +
            "$(if ($backup) { "Original saved as:`n$backup`n`n" } else { '' })Log:`n$logPath")
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    if (-not $Unattended) {
        try { Show-Notification -Title 'Populate Missing Data - error' -Icon Error -Message "$_`n`nThe target was not changed." } catch { }
    }
    $global:LASTEXITCODE = 1
}

#endregion
