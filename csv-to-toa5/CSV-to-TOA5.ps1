<#
    CSV to TOA5
    -----------
    Converts a logger's own CSV download - a DT2485 IPI logger download is the
    case it was built for - into a Campbell Scientific TOA5 file, so the other
    tools here (Combine DAT files, Populate Missing Data, Decimate) can read it.

    The source file is NEVER changed. The result is written beside it as
    '<name>_TOA5.dat'.

    WHAT IT DOES
    ============
      * HEADER: the download's own header block (a DT2485 writes 26 rows of
        metadata, sensor settings and units) becomes the 4 TOA5 rows:
          row 1  "TOA5", station, model, serial, firmware, "", "", table
          row 2  column names
          row 3  units ("TS" for the timestamp, "RN" for RECORD)
          row 4  processing ("" for TIMESTAMP and RECORD, "Smp" for the rest)
        Station, model, serial and firmware come from the 'Name', 'Model',
        'Serial Number' and 'Firmware Version' rows if the download has them;
        the table is the last word of the station name. Without them the file
        name is used.
      * TIMESTAMPS: rewritten as "YYYY-MM-DD HH:MM:SS". Year-first dates only
        (2021/10/08, 2021-10-8 10:15) - those cannot be misread. A year-last
        date (10/08/2021) is month-first or day-first and the file has to say
        which, so the file is refused: run Fix Timestamps on it first.
      * VALUES: copied exactly. Numbers are written unquoted; NAN and text are
        quoted, as TOA5 does. A number with a leading zero (a status code such
        as 012) is text, so it stays 012 rather than becoming 12.
      * ROWS: every data row, in the order the logger wrote it - nothing is
        sorted, dropped or de-duplicated. A logger clock that stepped back
        stays stepped back; that is for a person to decide, not a converter.

    COLUMNS
    =======
      * Separator columns - no name, and empty in every data row - are dropped.
      * DT2485 downloads repeat every sensor reading at full precision in a
        second block whose columns are all named after the sensor serial
        ("83199 (1)" three times). Those become "<reading> SN<serial>" -
        "Axis A 1 SN83199", "Axis B 1 SN83199", "Temp 1 SN83199" - using the
        download's 'Serial' row to find which reading is which. The block's
        "Serial (MB Addr)" label column, empty in every row, is dropped.
      * Any other repeated name gets _2, _3, ... so every TOA5 name is unique.

    WHAT IS REFUSED
    ===============
    The output is not written if:
      * no column-name row can be found (one whose first field is TIMESTAMP,
        Date/Time, DateTime, Date or Time, followed by timestamped rows)
      * any data row's first field is not a year-first date and time - one bad
        row refuses the file, as a part-converted file is worse than none
      * a data row has a different number of fields from the name row
      * the file is already TOA5
    A '<name>_TOA5.dat' that already exists is not overwritten without -Force
    (or a Yes from the dialog).

    INVOCATION
    ==========
      1) RIGHT-CLICK a .csv, .dat or .txt download -> "Convert to TOA5"
      2) TERMINAL
           PS> .\CSV-to-TOA5.ps1 'C:\Data\DT2485_DT50583_20261008_103345_DH11-29.csv'
           PS> .\CSV-to-TOA5.ps1 'C:\Data\download.csv' -OutputPath 'C:\Data\Site.dat'

    PARAMETERS
    ==========
      -Path <file>        The download to convert. Position 0.
      -OutputPath <file>  Where to write. Default '<name>_TOA5.dat' beside it.
      -Force              Overwrite an existing output file.
      -Unattended         Never open a dialog. For scripted runs.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$Unattended
)

if (-not $Unattended) {
    Add-Type -AssemblyName System.Windows.Forms
}

#region Helper Functions

# --- Compiled core --------------------------------------------------------
# A DT2485 download is ~7,000 rows of ~80 fields. Formatting every field
# through a PowerShell function takes over a minute; compiled it takes about
# a second. Only per-field mechanics live here; every decision is made in the
# PowerShell below.

$script:Toa5CoreSource = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

public static class Toa5Core
{
    // Fields EXACTLY as written, quotes and all. A doubled "" inside a quoted
    // field toggles twice and lands back inside.
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

    public static string Quote(string text)
    {
        return "\"" + text.Replace("\"", "\"\"") + "\"";
    }

    static readonly Regex LeadingZero = new Regex(@"^[-+]?0\d", RegexOptions.Compiled);

    // A data field as TOA5 writes it: numbers bare, NAN and text quoted,
    // empty left empty. A leading-zero integer (012) is a code, not a number.
    public static string Value(string field)
    {
        string v = Unquote(field);
        if (v.Length == 0) return "";
        if (string.Equals(v, "NAN", StringComparison.OrdinalIgnoreCase)) return "\"NAN\"";
        double d;
        if (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out d) && !LeadingZero.IsMatch(v))
            return v;
        return Quote(v);
    }

    // One TOA5 data row: the converted timestamp, then the kept columns.
    public static string Row(string timestamp, string[] fields, int[] keep)
    {
        var sb = new StringBuilder();
        sb.Append(Quote(timestamp));
        for (int c = 1; c < keep.Length; c++)
        {
            sb.Append(',');
            sb.Append(Value(fields[keep[c]]));
        }
        return sb.ToString();
    }

    // Clears allEmpty[i] for every field of this row that holds something.
    public static void MarkNonEmpty(bool[] allEmpty, string[] fields)
    {
        for (int i = 0; i < fields.Length && i < allEmpty.Length; i++)
            if (allEmpty[i] && Unquote(fields[i]).Length > 0) allEmpty[i] = false;
    }
}
'@

function Initialize-Toa5Core {
    if (-not ('Toa5Core' -as [type])) {
        Add-Type -TypeDefinition $script:Toa5CoreSource -Language CSharp
    }
}

function Split-CsvFieldsRaw {
    <#
        Splits a row into its fields, each EXACTLY as written, quotes and all.
        (The same splitter Combine DAT files uses for column alignment.)
    #>
    param([string]$Line)
    return , [Toa5Core]::SplitRaw($Line)
}

function Get-Unquoted {
    param([string]$Field)
    return [Toa5Core]::Unquote($Field)
}

function Get-UnquotedRow {
    <#
        A header row's fields with quotes removed. Split first and loop over
        the result: piping the splitter straight into ForEach-Object would see
        its one wrapped array, not the fields.
    #>
    param([string]$Line)
    $raw = Split-CsvFieldsRaw $Line
    $out = New-Object string[] $raw.Count
    for ($i = 0; $i -lt $raw.Count; $i++) { $out[$i] = Get-Unquoted $raw[$i] }
    return , $out
}

function ConvertTo-QuotedField {
    param([string]$Text)
    return [Toa5Core]::Quote($Text)
}

# Year first, so the order is not in doubt: Y-M-D with - / or . between, an
# optional time (seconds optional), a space or T between, optional AM/PM.
$script:YearFirstPattern = '^(?<y>\d{4})[-/.](?<mo>\d{1,2})[-/.](?<d>\d{1,2})(?:[ T]+(?<h>\d{1,2}):(?<mi>\d{2})(?::(?<s>\d{2}))?\s*(?<ap>[AaPp][Mm])?)?\s*Z?$'
$script:YearLastPattern = '^\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}(?:[ T].*)?$'

function ConvertTo-Toa5Timestamp {
    <#
        "YYYY-MM-DD HH:MM:SS", or $null when the field is not a real year-first
        date and time.
    #>
    param([string]$Text)

    $m = [regex]::Match($Text.Trim(), $script:YearFirstPattern)
    if (-not $m.Success) { return $null }
    $h = if ($m.Groups['h'].Success) { [int]$m.Groups['h'].Value } else { 0 }
    $mi = if ($m.Groups['mi'].Success) { [int]$m.Groups['mi'].Value } else { 0 }
    $s = if ($m.Groups['s'].Success) { [int]$m.Groups['s'].Value } else { 0 }
    if ($m.Groups['ap'].Success) {
        if ($h -lt 1 -or $h -gt 12) { return $null }
        $pm = $m.Groups['ap'].Value -ieq 'PM'
        if ($h -eq 12) { $h = 0 }
        if ($pm) { $h += 12 }
    }
    try {
        $dt = New-Object DateTime ([int]$m.Groups['y'].Value), ([int]$m.Groups['mo'].Value), ([int]$m.Groups['d'].Value), $h, $mi, $s
    }
    catch { return $null }
    return $dt.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Test-TimestampLike {
    param([string]$Text)
    $t = $Text.Trim()
    return ($t -match $script:YearFirstPattern -or $t -match $script:YearLastPattern)
}

function ConvertTo-Toa5Value {
    <#
        A data field as TOA5 writes it: numbers bare, NAN and text quoted,
        empty left empty. A leading-zero integer (012) is a code, not a number.
    #>
    param([string]$Field)
    return [Toa5Core]::Value($Field)
}

function Read-CsvDownload {
    <#
        Works out the layout of a download: where the names are, where the
        units are, where the data starts, and the metadata above them.
        Returns $null and a reason via $Reason when it cannot.
    #>
    param([string[]]$Lines, [ref]$Reason)

    if ($Lines.Count -gt 0 -and (Get-Unquoted (Split-CsvFieldsRaw $Lines[0])[0]) -eq 'TOA5') {
        $Reason.Value = 'It is already a TOA5 file.'
        return $null
    }

    # Data starts at the first row that, with the row after it, begins with a
    # timestamp. Two in a row keeps a 'Start Time,2021/10/08' metadata row
    # from being mistaken for data.
    $dataStart = -1
    for ($i = 0; $i -lt [Math]::Min($Lines.Count, 500); $i++) {
        if ([string]::IsNullOrWhiteSpace($Lines[$i])) { continue }
        if (-not (Test-TimestampLike (Get-Unquoted (Split-CsvFieldsRaw $Lines[$i])[0]))) { continue }
        $next = $i + 1
        while ($next -lt $Lines.Count -and [string]::IsNullOrWhiteSpace($Lines[$next])) { $next++ }
        if ($next -ge $Lines.Count -or (Test-TimestampLike (Get-Unquoted (Split-CsvFieldsRaw $Lines[$next])[0]))) {
            $dataStart = $i; break
        }
    }
    if ($dataStart -lt 0) {
        $Reason.Value = 'No rows of timestamped data were found in the first 500 lines.'
        return $null
    }

    $nameRow = -1
    for ($i = $dataStart - 1; $i -ge 0; $i--) {
        $first = Get-Unquoted (Split-CsvFieldsRaw $Lines[$i])[0]
        if ($first -match '^(TIMESTAMP|TMSTAMP|TIME ?STAMP|DATE ?TIME|DATE/TIME|DATE|TIME)$') { $nameRow = $i; break }
    }
    if ($nameRow -lt 0) {
        $Reason.Value = 'No column-name row was found above the data (a row whose first field is TIMESTAMP, Date/Time, DateTime, Date or Time).'
        return $null
    }

    $unitsRow = -1; $serialRow = -1; $addrRow = -1
    for ($i = $nameRow + 1; $i -lt $dataStart; $i++) {
        $first = Get-Unquoted (Split-CsvFieldsRaw $Lines[$i])[0]
        if ($first -match '^UNITS(->|:)?$' -and $unitsRow -lt 0) { $unitsRow = $i }
        if ($first -ieq 'Serial' -and $serialRow -lt 0) { $serialRow = $i }
        if ($first -ieq 'MB Addr' -and $addrRow -lt 0) { $addrRow = $i }
    }

    $meta = @{}
    for ($i = 0; $i -lt $nameRow; $i++) {
        $f = Split-CsvFieldsRaw $Lines[$i]
        if ($f.Count -ge 2) {
            $k = Get-Unquoted $f[0]
            if ($k -and -not $meta.ContainsKey($k)) { $meta[$k] = Get-Unquoted $f[1] }
        }
    }

    return [pscustomobject]@{
        NameRow   = $nameRow
        UnitsRow  = $unitsRow
        SerialRow = $serialRow
        AddrRow   = $addrRow
        DataStart = $dataStart
        Meta      = $meta
    }
}

function Resolve-Toa5Columns {
    <#
        Which source columns to keep and what to call them. Returns a list of
        @{ Index; Name; Units }. Every name it corrects is added to -Notes.
    #>
    param(
        [string[]]$Names,
        [string[]]$Units,
        [string[]]$Serials,
        [string[]]$Addresses,
        [bool[]]$AllEmpty,
        [System.Collections.Generic.List[string]]$Notes
    )

    $names = [string[]]$Names.Clone()

    # DT2485 sensor names that the logger repeated. Some downloads label a
    # sensor with another's number - the sensor at Modbus address 7 written
    # as "Axis A 39" while the real sensor 39 is also "Axis A 39". The MB Addr
    # row says which sensor each is: it sits over each sensor's first reading,
    # and the sensor's readings are that column and the next two. Only a
    # REPEATED name whose number disagrees with its address is changed.
    if ($Addresses -and $Serials) {
        $count = @{}
        foreach ($n in $names) { if ($n) { $count[$n] = 1 + $(if ($count.ContainsKey($n)) { $count[$n] } else { 0 }) } }
        for ($s = 1; $s -lt [Math]::Min($Addresses.Count, $names.Count); $s++) {
            if ($Addresses[$s] -notmatch '^\d+$' -or $Serials.Count -le $s -or $Serials[$s] -notmatch '^\d+$') { continue }
            $addr = $Addresses[$s]
            for ($k = 0; $k -lt 3 -and $s + $k -lt $names.Count; $k++) {
                $old = $names[$s + $k]
                $m = [regex]::Match($old, '^(?<stem>.*\D)(?<num>\d+)$')
                if (-not $m.Success -or $m.Groups['num'].Value -eq $addr -or $count[$old] -lt 2) { continue }
                $new = $m.Groups['stem'].Value + $addr
                if ($count.ContainsKey($new)) { continue }   # would only make a new clash
                $names[$s + $k] = $new
                $Notes.Add("'$old' -> '$new' (column $($s + $k + 1): Modbus address $addr, serial $($Serials[$s]))")
            }
        }
    }

    # DT2485 second block: columns named "<serial> (<modbus address>)", three
    # in a row per sensor. The Serial row puts each serial over that sensor's
    # first reading in the first block, so the k-th repeat of a serial is the
    # reading k columns to the right of where the Serial row has it.
    $seen = @{}
    for ($i = 0; $i -lt $names.Count; $i++) {
        $m = [regex]::Match($names[$i], '^(?<sn>\d+) \(\d+\)$')
        if (-not $m.Success -or -not $Serials) { continue }
        $sn = $m.Groups['sn'].Value
        $homeCol = [array]::IndexOf($Serials, $sn)
        if ($homeCol -lt 0) { continue }
        $k = if ($seen.ContainsKey($sn)) { $seen[$sn] } else { 0 }
        $seen[$sn] = $k + 1
        if ($homeCol + $k -lt $names.Count -and $names[$homeCol + $k]) {
            $names[$i] = "$($names[$homeCol + $k]) SN$sn"
        }
    }

    $cols = [System.Collections.Generic.List[object]]::new()
    $used = @{}
    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        # Separators: unnamed, or the DT2485 block label, and empty throughout.
        if ($AllEmpty[$i] -and ($name.Length -eq 0 -or $name -match '^Serial \(MB Addr\)$')) { continue }
        if ($name.Length -eq 0) { $name = "Column$($i + 1)" }
        if ($i -eq 0) { $name = 'TIMESTAMP' }

        $unique = $name; $n = 1
        while ($used.ContainsKey($unique.ToLowerInvariant())) { $n++; $unique = "${name}_$n" }
        $used[$unique.ToLowerInvariant()] = $true

        $u = if ($i -eq 0) { 'TS' } elseif ($unique -ieq 'RECORD') { 'RN' } elseif ($Units -and $i -lt $Units.Count) { $Units[$i] } else { '' }
        $cols.Add([pscustomobject]@{ Index = $i; Name = $unique; Units = $u })
    }
    return , $cols.ToArray()
}

function Test-NotText {
    <#
        A reason when the file is not text at all, else $null. A copy that
        did not finish - to a network drive, or from a cloud placeholder - can
        be the right size but every byte zero, and without this it would be
        reported as having no timestamped rows.
    #>
    param([string]$FilePath)

    $buf = New-Object byte[] 65536
    $stream = [System.IO.File]::OpenRead($FilePath)
    try { $read = $stream.Read($buf, 0, $buf.Length) } finally { $stream.Dispose() }
    if ($read -eq 0) { return 'The file is empty.' }
    # UTF-16 text has zero bytes in it legitimately; it carries a BOM.
    if ($read -ge 2 -and (($buf[0] -eq 0xFF -and $buf[1] -eq 0xFE) -or ($buf[0] -eq 0xFE -and $buf[1] -eq 0xFF))) { return $null }

    $zeros = 0
    for ($i = 0; $i -lt $read; $i++) { if ($buf[$i] -eq 0) { $zeros++ } }
    if ($zeros -eq $read) {
        return "Every byte at the start of the file is zero - it is the right size but holds no data, which usually means a copy that did not finish. Copy the file again from the original download."
    }
    if ($zeros -gt 0) {
        return "The file contains zero (NUL) bytes, so it is not a text download - it may be damaged or only partly copied. Copy it again from the original download."
    }
    return $null
}

function Convert-CsvToToa5 {
    <#
        Reads the download and returns the TOA5 lines, or a refusal. Writes
        nothing.
    #>
    param([Parameter(Mandatory)][string]$FilePath)

    Initialize-Toa5Core
    $rec = [pscustomobject]@{
        Path = $FilePath; Status = 'Ok'; Detail = ''; Lines = $null
        Rows = 0; Columns = 0; Dropped = @(); First = $null; Last = $null; Station = $null; Renamed = @()
    }
    $damage = Test-NotText -FilePath $FilePath
    if ($damage) { $rec.Status = 'Refuse'; $rec.Detail = $damage; return $rec }

    $lines = [System.IO.File]::ReadAllLines($FilePath)
    $reason = ''
    $layout = Read-CsvDownload -Lines $lines -Reason ([ref]$reason)
    if (-not $layout) { $rec.Status = 'Refuse'; $rec.Detail = $reason; return $rec }

    $names = Get-UnquotedRow $lines[$layout.NameRow]
    $units = if ($layout.UnitsRow -ge 0) { Get-UnquotedRow $lines[$layout.UnitsRow] } else { $null }
    $serials = if ($layout.SerialRow -ge 0) { Get-UnquotedRow $lines[$layout.SerialRow] } else { $null }
    $addrs = if ($layout.AddrRow -ge 0) { Get-UnquotedRow $lines[$layout.AddrRow] } else { $null }

    # Parse every data row once: field count and timestamp are checked here,
    # and the same split rows are written out below.
    $rows = [System.Collections.Generic.List[object]]::new()
    $allEmpty = New-Object bool[] $names.Count
    for ($i = 0; $i -lt $names.Count; $i++) { $allEmpty[$i] = $true }
    for ($n = $layout.DataStart; $n -lt $lines.Count; $n++) {
        if ([string]::IsNullOrWhiteSpace($lines[$n])) { continue }
        $f = Split-CsvFieldsRaw $lines[$n]
        if ($f.Count -ne $names.Count) {
            $rec.Status = 'Refuse'
            $rec.Detail = "Line $($n + 1) has $($f.Count) fields; the name row (line $($layout.NameRow + 1)) has $($names.Count)."
            return $rec
        }
        $ts = ConvertTo-Toa5Timestamp (Get-Unquoted $f[0])
        if (-not $ts) {
            $raw = Get-Unquoted $f[0]
            $rec.Status = 'Refuse'
            $rec.Detail = if ($raw -match $script:YearLastPattern) {
                "Line $($n + 1) reads '$raw' - year last, so month-first or day-first. Run Fix Timestamps on this file first, then convert it."
            } else {
                "Line $($n + 1): '$raw' is not a date and time."
            }
            return $rec
        }
        $f[0] = $ts
        [Toa5Core]::MarkNonEmpty($allEmpty, $f)
        $allEmpty[0] = $false
        $rows.Add($f)
    }
    if ($rows.Count -eq 0) { $rec.Status = 'Refuse'; $rec.Detail = 'There are no data rows.'; return $rec }

    $notes = [System.Collections.Generic.List[string]]::new()
    $cols = Resolve-Toa5Columns -Names $names -Units $units -Serials $serials -Addresses $addrs -AllEmpty $allEmpty -Notes $notes
    $rec.Renamed = $notes.ToArray()
    $rec.Dropped = @(0..($names.Count - 1) | Where-Object { $i = $_; -not ($cols | Where-Object { $_.Index -eq $i }) } |
        ForEach-Object { "column $($_ + 1)$(if ($names[$_]) { " '$($names[$_])'" })" })

    $meta = $layout.Meta
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $station = if ($meta['Name']) { $meta['Name'] } else { $stem }
    $model = if ($meta['Model']) { ($meta['Model'] -split '\s+')[0] } else { '' }
    $serial = if ($meta['Serial Number']) { $meta['Serial Number'] } else { '' }
    $fw = if ($meta['Firmware Version']) { $meta['Firmware Version'] } else { '' }
    $table = if ($meta['Name']) { ($meta['Name'] -split '\s+')[-1] } else { $stem }

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add((@('TOA5', $station, $model, $serial, $fw, '', '', $table) | ForEach-Object { ConvertTo-QuotedField $_ }) -join ',')
    $out.Add(($cols | ForEach-Object { ConvertTo-QuotedField $_.Name }) -join ',')
    $out.Add(($cols | ForEach-Object { ConvertTo-QuotedField $_.Units }) -join ',')
    $out.Add(($cols | ForEach-Object { if ($_.Index -eq 0 -or $_.Name -ieq 'RECORD') { '""' } else { '"Smp"' } }) -join ',')

    $idx = [int[]]@($cols | ForEach-Object { $_.Index })
    foreach ($f in $rows) { $out.Add([Toa5Core]::Row($f[0], $f, $idx)) }

    $rec.Lines = $out.ToArray()
    $rec.Rows = $rows.Count
    $rec.Columns = $cols.Count
    $rec.First = $rows[0][0]
    $rec.Last = $rows[$rows.Count - 1][0]
    $rec.Station = $station
    return $rec
}

function Get-DefaultOutputPath {
    param([string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    return (Join-Path $dir ([System.IO.Path]::GetFileNameWithoutExtension($FilePath) + '_TOA5.dat'))
}

function Write-Toa5File {
    <#
        CRLF, no byte-order mark: LoggerNet does not recognise a TOA5 file
        with a BOM in front of row 1.
    #>
    param([string]$FilePath, [string[]]$Lines)
    $tmp = "$FilePath.toa5.tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, (($Lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $FilePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

#endregion

#region Dialogs

function Show-Notification {
    param([string]$Message, [string]$Title = "Notice", $Icon = 'Information')
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::$Icon
    ) | Out-Null
}

function Confirm-Overwrite {
    param([string]$FilePath)
    $r = [System.Windows.Forms.MessageBox]::Show(
        "This file already exists:`n$FilePath`n`nReplace it?", 'Convert to TOA5',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

#endregion

#region Main

try {
    # Explorer hands the file over as "%1"; a stray quote can arrive attached.
    $source = if ($Path) { $Path.Trim('"') } elseif ($args.Count -gt 0) { "$($args[0])".Trim('"') } else { $null }
    if (-not $source -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Give the file to convert as the first argument (got '$source')."
    }
    $source = [System.IO.Path]::GetFullPath($source)
    $target = if ($OutputPath) { [System.IO.Path]::GetFullPath($OutputPath.Trim('"')) } else { Get-DefaultOutputPath -FilePath $source }
    if ($target -ieq $source) { throw "The output would overwrite the file being converted." }

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "CSV TO TOA5" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "Source (read):   $source"
    Write-Host "Output (new):    $target"
    Write-Host "$('=' * 70)" -ForegroundColor Cyan

    $rec = Convert-CsvToToa5 -FilePath $source
    if ($rec.Status -ne 'Ok') {
        Write-Warning "NOT CONVERTED: $($rec.Detail)"
        if (-not $Unattended) { Show-Notification -Title 'Not Converted' -Icon Warning -Message "$($rec.Detail)`n`nNothing was written." }
        $global:LASTEXITCODE = 1
        return
    }

    if (Test-Path -LiteralPath $target) {
        $ok = if ($Force) { $true } elseif ($Unattended) { $false } else { Confirm-Overwrite -FilePath $target }
        if (-not $ok) {
            Write-Warning "Output already exists and was left as it is (use -Force to replace it): $target"
            $global:LASTEXITCODE = 1
            return
        }
    }
    Write-Toa5File -FilePath $target -Lines $rec.Lines

    $summary = @(
        "Station:  $($rec.Station)",
        "Rows:     $($rec.Rows), $($rec.First) .. $($rec.Last)",
        "Columns:  $($rec.Columns)"
    )
    if ($rec.Dropped.Count) { $summary += "Dropped (empty in every row): $($rec.Dropped -join ', ')" }
    if ($rec.Renamed.Count) {
        $summary += "Renamed (the logger repeated these names; corrected from the MB Addr row):"
        $summary += @($rec.Renamed | ForEach-Object { "  $_" })
    }

    Write-Host "CONVERTED" -ForegroundColor Green
    $summary | ForEach-Object { Write-Host "  $_" }
    Write-Host "  -> $target"
    if (-not $Unattended) {
        Show-Notification -Title 'Converted to TOA5' -Message (($summary -join "`n") + "`n`nWritten to:`n$target`n`nThe original was not changed.")
    }
}
catch {
    Write-Error "Fatal error: $_"
    if (-not $Unattended) {
        try { Show-Notification -Title 'Convert to TOA5 - error' -Icon Error -Message "$_`n`nNothing was written." } catch { }
    }
    $global:LASTEXITCODE = 1
}

#endregion
