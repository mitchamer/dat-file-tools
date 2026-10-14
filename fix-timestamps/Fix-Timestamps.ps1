<#
    Fix Timestamps
    --------------
    Rewrites the first column of time-series data files (.dat/.csv/.txt) into
    one canonical shape:

        YYYY-MM-DD HH:MM:SS

    It accepts the shapes these files arrive in - YYYY/M/D, YYYY-M-D, M/D/YYYY,
    D/M/YYYY, two-digit years, an ISO 'T' separator, AM/PM times, and rows with
    a date but no time - and it will not guess. The format of a file is decided
    by evidence, and a file it cannot decide is left exactly as it was with a
    '<name>_DATEFORMATERROR.txt' beside it saying why.

    WHY THIS EXISTS
    ===============
    Every other tool here sorts rows as TEXT, which is correct only while the
    first column is YYYY-MM-DD HH:MM:SS - fixed width, largest unit first. A
    file written as 9/1/2026 sorts into nonsense, and the damage is quiet: the
    rows are all present, just in the wrong order. Run this first, then merge or
    decimate.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    This script REWRITES DATA FILES IN PLACE. Licensed under GPL-3.0 and
    provided "as is" with no warranty of any kind (see LICENSE sections 15-17).
    You are responsible for verifying the result before relying on it.

      * the original is copied into a 'Backup' folder first (unless -NoBackup)
      * only the FIRST field of each data row is touched; the rest of the row,
        the header rows and the file's encoding are preserved byte for byte
      * a file that is already correct is not rewritten, backed up or touched
        in any way, so running this twice is the same as running it once
      * -DryRun reports every decision and writes nothing. Use it first.

    THE MONTH/DAY PROBLEM, AND HOW IT IS DECIDED
    ============================================
    01/09/2026 is the 1st of September or the 9th of January and the file alone
    cannot always say. Rather than trusting a format, this script decides the
    FIELD ORDER once per file, from the file's own contents:

      1. Each first field is split into its numbers. Where the 4-digit year
         sits narrows the candidates immediately: a leading year means the
         year-first readings, a trailing year means M/D/Y or D/M/Y, and an
         all-two-digit date could be either.
      2. A candidate that produces an IMPOSSIBLE DATE on any row is dropped -
         a 13 in the month slot settles it outright.
      3. A candidate whose dates do not run in ASCENDING order (ties allowed,
         repeated timestamps are normal) is dropped. This is the test that
         separates M/D from D/M in a file where every number is 12 or less.
      4. Exactly one candidate left -> that is the order, and the file is
         converted. None left, or two that disagree about what the dates mean
         -> the file is NOT touched and the reason is written out.

    Two candidates that survive and produce IDENTICAL output (every date has
    the same day and month, 2026-05-05) are not a conflict: there is nothing to
    be wrong about, so the conversion proceeds.

    ORDER OF PREFERENCE - AND WHY IT IS NOT A FLAT CONTEST
    ======================================================
    Readings are tried in tiers, and the first tier that works wins:

      1. Y-M-D   2026-09-01       the ISO ordering
      2. M/D/Y and D/M/Y          the two real-world year-last conventions
      3. Y-D-M   2026-01-09       year, then day, then month

    Tier 2 is where the genuine doubt lives: US and everywhere-else write the
    same two numbers in opposite orders, both are real, and a file that fits
    both readings differently is refused. That is the case worth protecting
    against.

    Tier 1 beating tier 3 is a deliberate choice, not an oversight. No locale
    or logger writes year-day-month, but as a flat candidate it would collide
    with Y-M-D on EVERY year-first file whose days are all 12 or less - so an
    ordinary 2026/9/1 file would be refused as "ambiguous" when nobody would
    ever read it the other way. Y-D-M is still available, but only once Y-M-D
    has been ruled out by an impossible date or by dates that run backwards.

    WHAT IS REFUSED, AND WHY
    ========================
      * ANY row whose first field will not parse - junk, NAN, a truncated line.
        One bad row refuses the whole file: a file that is part converted is
        worse than one that is untouched.
      * FRACTIONAL SECONDS (2026-09-01 00:00:00.5). The target format holds
        whole seconds, so converting would silently drop precision and could
        collapse two rows into apparent duplicates. These files are reported,
        never truncated.
      * Dates that run backwards under every candidate order - which usually
        means the file is already out of order rather than badly formatted.
        This script never sorts; it only rewrites field 1 in place.

    Blank lines are structural, not rows: they are preserved as they are and
    are not counted against the file.

    TWO-DIGIT YEARS
    ===============
    00-69 -> 2000-2069, 70-99 -> 1970-1999. Stated here because it is a guess
    with a cut-off, not a fact. The ascending test still has to pass with those
    values, so a wrong century that reorders the file is caught.

    INVOCATION
    ==========
      1) RIGHT-CLICK a folder, or inside one
         The context-menu entries pass the folder and nothing else, so the
         scan is THAT FOLDER ONLY - subfolders are never entered.
           "Fix Timestamp Format"               converts
           "Check Timestamp Format (no changes)" runs -DryRun

      2) TERMINAL - the same thing, plus -Depth to go deeper
           PS> .\Fix-Timestamps.ps1 'C:\Data\Site'
           PS> .\Fix-Timestamps.ps1 'C:\Data\Site' -DryRun
           PS> .\Fix-Timestamps.ps1 'C:\Data\Site' -Depth 2
           PS> .\Fix-Timestamps.ps1            (no path - a folder picker opens)

    PARAMETERS
    ==========
      -Path <folder|file>  What to process. A single file is allowed. Position 0.
      -Depth <int>         How many levels of subfolder to descend. 0 (default,
                           and what the right-click entries use) is the given
                           folder only; 1 adds its subfolders, and so on.
                           'Backup', 'Combined' and 'Sources' are always skipped.
      -Extensions <s[]>    Defaults to dat, csv, txt.
      -DryRun              Report every decision, write nothing.
      -NoBackup            Do not copy the original into Backup first. This
                           removes the only automatic undo.
      -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                           Default Auto, which writes the file back with the
                           byte-order mark it arrived with. A BOM in front of
                           the TOA5 row leaves LoggerNet unable to recognise
                           the file it is appending to, so Auto matters.
      -Unattended          Never open a dialog - no folder picker, no summary
                           box. For scheduled or scripted runs.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [Parameter()]
    [ValidateRange(0, 32)]
    [int]$Depth = 0,

    [Parameter()]
    [string[]]$Extensions = @('dat', 'csv', 'txt'),

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$NoBackup,

    [Parameter()]
    [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'ASCII', 'Unicode')]
    [string]$Encoding = 'Auto',

    [Parameter()]
    [switch]$Unattended
)

if (-not $Unattended) {
    Add-Type -AssemblyName System.Windows.Forms
}

#region Helper Functions

# --- Encoding -------------------------------------------------------------
# Same reasoning as the combine tool: LoggerNet data files carry no BOM, and a
# BOM ahead of the TOA5 row leaves LoggerNet unable to recognise the file it is
# appending to. It responds by renaming the file and starting a fresh one,
# which silently orphans everything that was written.

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

function Read-DataFileLines {
    param([string]$Path)
    # Markedly faster than Get-Content, which wraps every line in a PSObject.
    return [System.IO.File]::ReadAllLines($Path)
}

# --- Field 1 --------------------------------------------------------------

function Get-RawFirstField {
    <#
        Splits a row into its first field and everything after it, WITHOUT
        parsing the rest of the row. Returns $null for an empty line.

          Text       the field with any surrounding quotes removed
          Quoted     whether it was quoted, so the rewrite can put them back
          RestIndex  index in the line where the remainder starts (the comma),
                     so the rest of the row is copied through untouched rather
                     than re-serialised. A row of 2,157 fields is not worth
                     splitting to read field 1, and re-joining it risks
                     changing quoting that was none of our business.
    #>
    param([string]$Line)

    if ([string]::IsNullOrEmpty($Line)) { return $null }

    if ($Line[0] -eq '"') {
        $end = $Line.IndexOf('"', 1)
        if ($end -lt 0) { return $null }
        return [pscustomobject]@{
            Text      = $Line.Substring(1, $end - 1)
            Quoted    = $true
            RestIndex = $end + 1
        }
    }

    $comma = $Line.IndexOf(',')
    if ($comma -lt 0) {
        return [pscustomobject]@{ Text = $Line; Quoted = $false; RestIndex = $Line.Length }
    }
    return [pscustomobject]@{ Text = $Line.Substring(0, $comma); Quoted = $false; RestIndex = $comma }
}

function Set-FirstField {
    <#
        Returns the row with field 1 replaced and everything after it kept
        exactly as it was, including its original quoting.
    #>
    param([string]$Line, [object]$Field, [string]$NewText)

    $head = if ($Field.Quoted) { '"' + $NewText + '"' } else { $NewText }
    return $head + $Line.Substring($Field.RestIndex)
}

# --- Timestamp tokens -----------------------------------------------------

# One pattern for every accepted shape. The date separator may be - / or . ;
# the date and time may be separated by a space or a literal T; seconds and the
# whole time are optional; AM/PM and a trailing Z are allowed.
$script:TimestampPattern = '^(?<a>\d{1,4})[-/.](?<b>\d{1,2})[-/.](?<c>\d{1,4})(?:[ T]+(?<h>\d{1,2}):(?<mi>\d{1,2})(?::(?<s>\d{1,2})(?<frac>\.\d+)?)?\s*(?<ap>[AP]M)?)?\s*Z?$'

function ConvertFrom-TimestampField {
    <#
        Splits one first-field into its numbers. Returns $null when the text is
        not a date at all, which is how header rows are told apart from data.

        Nothing here decides what the numbers MEAN - that is one decision for
        the whole file, taken in Resolve-TimestampOrder.
    #>
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    if ($t -notmatch $script:TimestampPattern) { return $null }

    $m = $Matches
    return [pscustomobject]@{
        A       = [int]$m['a']
        B       = [int]$m['b']
        C       = [int]$m['c']
        AWidth  = $m['a'].Length
        CWidth  = $m['c'].Length
        Hour    = if ($m['h']) { [int]$m['h'] } else { 0 }
        Minute  = if ($m['mi']) { [int]$m['mi'] } else { 0 }
        Second  = if ($m['s']) { [int]$m['s'] } else { 0 }
        HasTime = [bool]$m['h']
        HasFrac = [bool]$m['frac']
        AmPm    = if ($m['ap']) { $m['ap'].ToUpperInvariant() } else { $null }
    }
}

function Get-PossibleOrders {
    <#
        Which field orders this single row could be, judged only on where a
        4-digit (or clearly-not-a-month-or-day) number sits. The real pruning
        happens later, across the whole file.
    #>
    param([object]$Token)

    if ($Token.AWidth -ge 3 -or $Token.A -gt 31) { return @('YMD', 'YDM') }
    if ($Token.CWidth -ge 3 -or $Token.C -gt 31) { return @('MDY', 'DMY') }
    # Everything is two digits or fewer: the year could be at either end.
    return @('YMD', 'YDM', 'MDY', 'DMY')
}

function Expand-TwoDigitYear {
    # 00-69 -> 2000s, 70-99 -> 1900s. A documented cut-off, not a fact.
    param([int]$Value, [int]$Width)
    if ($Width -ge 3) { return $Value }
    if ($Value -ge 70) { return 1900 + $Value }
    return 2000 + $Value
}

function ConvertTo-TimestampValue {
    <#
        Applies one candidate order to one row's numbers. Returns $null when
        that reading is not a real date and time - which is what lets an
        impossible month or a 31st of September kill a candidate outright.
    #>
    param([object]$Token, [string]$Order)

    switch ($Order) {
        'YMD' { $y = $Token.A; $yw = $Token.AWidth; $mo = $Token.B; $d = $Token.C }
        'YDM' { $y = $Token.A; $yw = $Token.AWidth; $d = $Token.B; $mo = $Token.C }
        'MDY' { $mo = $Token.A; $d = $Token.B; $y = $Token.C; $yw = $Token.CWidth }
        'DMY' { $d = $Token.A; $mo = $Token.B; $y = $Token.C; $yw = $Token.CWidth }
        default { return $null }
    }

    $y = Expand-TwoDigitYear -Value $y -Width $yw
    if ($y -lt 1 -or $y -gt 9999) { return $null }
    if ($mo -lt 1 -or $mo -gt 12) { return $null }
    if ($d -lt 1 -or $d -gt [datetime]::DaysInMonth($y, $mo)) { return $null }

    $h = $Token.Hour
    if ($Token.AmPm) {
        # A 12-hour clock cannot hold 13, so an AM/PM row with one is broken
        # rather than merely ambiguous.
        if ($h -lt 1 -or $h -gt 12) { return $null }
        if ($Token.AmPm -eq 'PM' -and $h -lt 12) { $h += 12 }
        elseif ($Token.AmPm -eq 'AM' -and $h -eq 12) { $h = 0 }
    }
    if ($h -lt 0 -or $h -gt 23) { return $null }
    if ($Token.Minute -gt 59 -or $Token.Second -gt 59) { return $null }

    return (New-Object DateTime $y, $mo, $d, $h, $Token.Minute, $Token.Second)
}

function Format-Timestamp {
    param([datetime]$Value)
    return $Value.ToString('yyyy-MM-dd HH:mm:ss')
}

#endregion

#region Decision

function Resolve-FileTimestamps {
    <#
        The whole decision for one file, as a pure function over its lines so
        it can be tested without touching a disk.

        Returns:
          Status      Convert | AlreadyCorrect | Refuse | NoTimestamps
          Order       the winning field order, when there is one
          HeaderRows  lines before the first data row
          RowCount    data rows considered
          Duplicates  rows whose timestamp equals the previous row's
          FirstValue / LastValue   as converted, for the console
          Reasons     why each candidate was dropped, or why it was refused
          NewLines    the converted file, when Status is Convert
    #>
    param([string[]]$Lines)

    $reasons = [System.Collections.Generic.List[string]]::new()
    $result = [pscustomobject]@{
        Status     = 'NoTimestamps'
        Order      = $null
        HeaderRows = 0
        RowCount   = 0
        Duplicates = 0
        FirstValue = $null
        LastValue  = $null
        Reasons    = $reasons
        NewLines   = $null
    }

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        $reasons.Add("The file is empty.")
        return $result
    }

    # 1. Header rows end at the first line whose field 1 reads as a date.
    $firstData = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = if ($i -eq 0) { $Lines[0].TrimStart([char]0xFEFF) } else { $Lines[$i] }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $field = Get-RawFirstField -Line $line
        if ($null -eq $field) { continue }
        if ($null -ne (ConvertFrom-TimestampField -Text $field.Text)) { $firstData = $i; break }
    }

    if ($firstData -lt 0) {
        $reasons.Add("No row in this file begins with something that reads as a date, so there is no timestamp column to fix.")
        return $result
    }
    $result.HeaderRows = $firstData

    # 2. Tokenise every data row. One unreadable row refuses the file: a
    #    part-converted file is worse than an untouched one.
    $tokens = [System.Collections.Generic.List[object]]::new()
    $indexes = [System.Collections.Generic.List[int]]::new()
    $orders = [System.Collections.Generic.List[string]]::new()
    $orders.AddRange([string[]]@('YMD', 'YDM', 'MDY', 'DMY'))

    for ($i = $firstData; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }   # structural, not a row

        $field = Get-RawFirstField -Line $line
        $token = if ($null -ne $field) { ConvertFrom-TimestampField -Text $field.Text } else { $null }

        if ($null -eq $token) {
            $raw = if ($null -ne $field) { $field.Text } else { $line }
            if ($raw.Length -gt 60) { $raw = $raw.Substring(0, 60) + '...' }
            $result.Status = 'Refuse'
            $reasons.Add("Line $($i + 1) does not start with a readable date: '$raw'. One unreadable row stops the whole file, because a half-converted file is worse than an untouched one.")
            return $result
        }

        if ($token.HasFrac) {
            $result.Status = 'Refuse'
            $reasons.Add("Line $($i + 1) carries a fractional second ('$($field.Text)'). The target format 'YYYY-MM-DD HH:MM:SS' holds whole seconds only, so converting would drop precision and could turn two distinct rows into apparent duplicates. Nothing was changed.")
            return $result
        }

        # Narrow the candidate orders by what this row allows. Rows disagreeing
        # about where the year sits empty the set, which is its own answer.
        $rowOrders = Get-PossibleOrders -Token $token
        for ($k = $orders.Count - 1; $k -ge 0; $k--) {
            if ($rowOrders -notcontains $orders[$k]) { [void]$orders.RemoveAt($k) }
        }

        $tokens.Add($token)
        $indexes.Add($i)
    }

    $result.RowCount = $tokens.Count
    if ($tokens.Count -eq 0) {
        $reasons.Add("No data rows were found after the $firstData header line(s).")
        return $result
    }

    if ($orders.Count -eq 0) {
        $result.Status = 'Refuse'
        $reasons.Add("The rows do not agree on where the year sits - some put a 4-digit year first and others put it last. A single file written two ways needs a human.")
        return $result
    }

    # 3. Test candidates in tiers, and stop at the first tier that works.
    #    Y-M-D outranks Y-D-M because nothing writes year-day-month, and as a
    #    flat candidate it would make every year-first file whose days are all
    #    12 or less look ambiguous. M/D/Y and D/M/Y share a tier because both
    #    are real conventions - that is where the doubt genuinely is.
    $tiers = @(@('YMD'), @('MDY', 'DMY'), @('YDM'))
    $valid = [System.Collections.Generic.List[object]]::new()

    foreach ($tier in $tiers) {
        $candidates = @($tier | Where-Object { $orders -contains $_ })
        if ($candidates.Count -eq 0) { continue }

        foreach ($order in $candidates) {
            $values = New-Object 'DateTime[]' $tokens.Count
            $ok = $true
            for ($n = 0; $n -lt $tokens.Count; $n++) {
                $v = ConvertTo-TimestampValue -Token $tokens[$n] -Order $order
                if ($null -eq $v) {
                    $ok = $false
                    $reasons.Add("$order rejected: line $($indexes[$n] + 1) is not a real date read that way.")
                    break
                }
                if ($n -gt 0 -and $v -lt $values[$n - 1]) {
                    $ok = $false
                    $reasons.Add("$order rejected: dates stop ascending at line $($indexes[$n] + 1) - $(Format-Timestamp $values[$n - 1]) is followed by $(Format-Timestamp $v).")
                    break
                }
                $values[$n] = $v
            }
            if ($ok) {
                $valid.Add([pscustomobject]@{ Order = $order; Values = $values })
            }
        }

        if ($valid.Count -gt 0) { break }
    }

    if ($valid.Count -eq 0) {
        $result.Status = 'Refuse'
        $reasons.Insert(0, "No reading of this file's dates is both a real calendar date on every row and in ascending order. If the rows are genuinely out of order, this tool is the wrong one - it never sorts, it only rewrites field 1 in place.")
        return $result
    }

    # 4. More than one survivor is only a problem when they disagree about what
    #    the dates ARE. Every date having the same day and month (2026-05-05)
    #    leaves nothing to be wrong about.
    $winner = $valid[0]
    if ($valid.Count -gt 1) {
        $differsAt = -1
        for ($n = 0; $n -lt $tokens.Count -and $differsAt -lt 0; $n++) {
            foreach ($cand in $valid) {
                if ($cand.Values[$n] -ne $winner.Values[$n]) { $differsAt = $n; break }
            }
        }

        if ($differsAt -ge 0) {
            $result.Status = 'Refuse'
            $names = ($valid | ForEach-Object { $_.Order }) -join ' and '
            $reasons.Insert(0, "Ambiguous: $names both give real dates in ascending order, and they disagree. Line $($indexes[$differsAt] + 1) reads as " +
                (($valid | ForEach-Object { "$($_.Order) -> $(Format-Timestamp $_.Values[$differsAt])" }) -join ', ') +
                ". Nothing in this file settles which is right, so nothing was changed.")
            return $result
        }
        $reasons.Add("$(($valid | ForEach-Object { $_.Order }) -join ' and ') both fit, but produce identical dates on every row, so there is nothing to be ambiguous about.")
    }

    # 5. Build the converted file.
    $newLines = New-Object 'string[]' $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) { $newLines[$i] = $Lines[$i] }

    $changed = 0
    $duplicates = 0
    for ($n = 0; $n -lt $tokens.Count; $n++) {
        $i = $indexes[$n]
        $line = $Lines[$i]
        $field = Get-RawFirstField -Line $line
        $text = Format-Timestamp $winner.Values[$n]
        if ($field.Text -cne $text) {
            $newLines[$i] = Set-FirstField -Line $line -Field $field -NewText $text
            $changed++
        }
        if ($n -gt 0 -and $winner.Values[$n] -eq $winner.Values[$n - 1]) { $duplicates++ }
    }

    $result.Order = $winner.Order
    $result.Duplicates = $duplicates
    $result.FirstValue = Format-Timestamp $winner.Values[0]
    $result.LastValue = Format-Timestamp $winner.Values[$tokens.Count - 1]
    $result.Status = if ($changed -eq 0) { 'AlreadyCorrect' } else { 'Convert' }
    $result.NewLines = $newLines
    return $result
}

#endregion

#region File handling

function Get-DateFormatErrorPath {
    param([string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    return (Join-Path $dir "${stem}_DATEFORMATERROR.txt")
}

function Write-DateFormatError {
    <#
        The note left beside a file that was not touched. It has to be enough to
        settle the question by eye: what was tried, what each reading said, and
        where it went wrong.
    #>
    param(
        [string]$FilePath,
        [object]$Decision,
        [string[]]$Lines
    )

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("DATE FORMAT NOT CHANGED")
    $out.Add("=======================")
    $out.Add("File:      $FilePath")
    $out.Add("Checked:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $out.Add("Header rows: $($Decision.HeaderRows)")
    $out.Add("Data rows:   $($Decision.RowCount)")
    $out.Add('')
    $out.Add("THE FILE WAS NOT MODIFIED. No backup was made, because nothing was written.")
    $out.Add('')
    $out.Add("Why:")
    foreach ($r in $Decision.Reasons) { $out.Add("  - $r") }
    $out.Add('')
    $out.Add("What was tried:")
    $out.Add("  YMD = year, month, day     (2026-09-01)   tried first")
    $out.Add("  MDY = month, day, year     (09/01/2026)   tried together, because")
    $out.Add("  DMY = day, month, year     (01/09/2026)   both are real conventions")
    $out.Add("  YDM = year, day, month     (2026-01-09)   tried last - no locale writes it")
    $out.Add("A reading is kept only if every row is a real calendar date under it AND the")
    $out.Add("dates never go backwards. Ties are allowed - repeated timestamps are normal.")
    $out.Add("The first tier that produces a working reading wins; a tier that produces TWO")
    $out.Add("working readings that disagree is the ambiguity this file ran into.")
    $out.Add('')

    # The rows themselves, so the question can be settled without opening the
    # file: the first few, which is usually where the answer is.
    $out.Add("First rows as they stand (line number, field 1):")
    $shown = 0
    for ($i = $Decision.HeaderRows; $i -lt $Lines.Count -and $shown -lt 8; $i++) {
        if ([string]::IsNullOrWhiteSpace($Lines[$i])) { continue }
        $f = Get-RawFirstField -Line $Lines[$i]
        $t = if ($null -ne $f) { $f.Text } else { $Lines[$i] }
        if ($t.Length -gt 60) { $t = $t.Substring(0, 60) + '...' }
        $out.Add(("  line {0,-7} {1}" -f ($i + 1), $t))
        $shown++
    }
    $out.Add('')
    $out.Add("What to do:")
    $out.Add("  * If you know which reading is right, fix the column yourself (or in Excel,")
    $out.Add("    being careful that it does not reinterpret the dates again on save) and")
    $out.Add("    re-run this script to confirm it now reads cleanly.")
    $out.Add("  * If the rows are simply out of order, this is the wrong tool: it never")
    $out.Add("    sorts. Fix the order first, then run it again.")
    $out.Add("  * Delete this file once the question is settled - it is regenerated on")
    $out.Add("    every run that still cannot decide, and removed automatically once the")
    $out.Add("    file converts cleanly.")

    $errPath = Get-DateFormatErrorPath -FilePath $FilePath
    [System.IO.File]::WriteAllLines($errPath, $out, (New-Object System.Text.UTF8Encoding($false)))
    return $errPath
}

function Backup-File {
    param([string]$FilePath, [string]$BackupFolder)

    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath)
    $dest = Join-Path $BackupFolder "${name}_${stamp}${ext}"
    Copy-Item -LiteralPath $FilePath -Destination $dest -Force
    return $dest
}

function Invoke-FixTimestampsForFile {
    <#
        Reads one file, decides, and acts. Returns a record for the summary.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Encoding = 'Auto',
        [switch]$NoBackup,
        [switch]$DryRun
    )

    $record = [pscustomobject]@{
        Path       = $FilePath
        Name       = [System.IO.Path]::GetFileName($FilePath)
        Status     = 'Skipped'
        Order      = $null
        RowCount   = 0
        Duplicates = 0
        First      = $null
        Last       = $null
        ErrorFile  = $null
        BackupFile = $null
        Detail     = $null
    }

    try {
        $lines = Read-DataFileLines $FilePath
    }
    catch {
        $record.Status = 'Unreadable'
        $record.Detail = $_.Exception.Message
        return $record
    }

    $decision = Resolve-FileTimestamps -Lines $lines
    $record.Status = $decision.Status
    $record.Order = $decision.Order
    $record.RowCount = $decision.RowCount
    $record.Duplicates = $decision.Duplicates
    $record.First = $decision.FirstValue
    $record.Last = $decision.LastValue
    $record.Detail = ($decision.Reasons -join ' ')

    $errPath = Get-DateFormatErrorPath -FilePath $FilePath

    switch ($decision.Status) {
        'NoTimestamps' { return $record }

        'AlreadyCorrect' {
            # Not rewritten, not backed up, not touched. Running twice is the
            # same as running once.
            if ((Test-Path -LiteralPath $errPath) -and -not $DryRun) {
                Remove-Item -LiteralPath $errPath -Force -ErrorAction SilentlyContinue
            }
            return $record
        }

        'Refuse' {
            if ($DryRun) {
                $record.ErrorFile = "$errPath (would be written)"
            }
            else {
                $record.ErrorFile = Write-DateFormatError -FilePath $FilePath -Decision $decision -Lines $lines
            }
            return $record
        }
    }

    # Convert.
    if ($DryRun) { return $record }

    $tempPath = "$FilePath.timestamps.tmp"
    try {
        if (-not $NoBackup) {
            $record.BackupFile = Backup-File -FilePath $FilePath -BackupFolder (Join-Path (Split-Path -Parent $FilePath) 'Backup')
        }

        # Written to a temp file and moved into place, so an interrupted run
        # cannot leave a half-written data file behind.
        $enc = Resolve-OutputEncoding -Name $Encoding -FilePath $FilePath
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $enc, 1048576)
        try {
            foreach ($line in $decision.NewLines) { $writer.WriteLine($line) }
        }
        finally { $writer.Dispose() }

        Move-Item -LiteralPath $tempPath -Destination $FilePath -Force -ErrorAction Stop
        $tempPath = $null

        if (Test-Path -LiteralPath $errPath) {
            # The question is settled; the old note is now wrong.
            Remove-Item -LiteralPath $errPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        $record.Status = 'WriteFailed'
        $record.Detail = $_.Exception.Message
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $record
}

function Get-TargetFiles {
    <#
        Files to consider, breadth-first, limited by -Depth. Depth 0 is the
        given folder only, which is what the right-click entries use.

        Never returned: anything inside Backup / Combined / Sources (this tool
        and its siblings write there), and the artefacts those tools leave -
        including this script's own _DATEFORMATERROR.txt notes, which are .txt
        files sitting right next to the data.
    #>
    param(
        [Parameter(Mandatory)][string]$Folder,
        [int]$Depth = 0,
        [string[]]$Extensions = @('dat', 'csv', 'txt')
    )

    $extSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $Extensions) { [void]$extSet.Add('.' + $e.TrimStart('.')) }

    $skipDirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in @('Backup', 'Combined', 'Sources')) { [void]$skipDirs.Add($n) }

    $files = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Dir = $Folder; Level = 0 })

    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()

        foreach ($f in @(Get-ChildItem -LiteralPath $item.Dir -File -ErrorAction SilentlyContinue)) {
            if (-not $extSet.Contains($f.Extension)) { continue }
            if ($f.Name -like '*_DATEFORMATERROR.txt') { continue }
            if ($f.Name -like '*.merge-log.txt') { continue }
            if ($f.Name -like '*.tmp') { continue }
            $files.Add($f)
        }

        if ($item.Level -ge $Depth) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $item.Dir -Directory -ErrorAction SilentlyContinue)) {
            if ($skipDirs.Contains($d.Name)) { continue }
            $queue.Enqueue([pscustomobject]@{ Dir = $d.FullName; Level = $item.Level + 1 })
        }
    }

    return @($files | Sort-Object -Property FullName)
}

#endregion

#region Dialogs

function Select-FolderDialog {
    param([string]$Description = "Select a folder", [string]$InitialDir)

    # The modern Explorer-style dialog in "folder pick" mode: it has an address
    # bar, shows mapped network drives, and accepts a typed or pasted UNC path.
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $Description
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.FileName = "Select Folder"
    $dlg.Filter = "Folders|`n"
    if ($InitialDir -and (Test-Path -LiteralPath $InitialDir)) { $dlg.InitialDirectory = $InitialDir }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = Split-Path -Parent $dlg.FileName
        if ([string]::IsNullOrWhiteSpace($selected)) { $selected = $dlg.FileName }
        if ($selected -and (Test-Path -LiteralPath $selected -PathType Container)) { return $selected }
    }
    return $null
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
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

    # Explorer hands the folder over as "%1" / "%V". A path ending in a
    # backslash (a drive root) escapes the closing quote, so a stray one can
    # arrive attached to the path.
    $supplied = if ($Path) { $Path.Trim('"') } elseif ($args.Count -gt 0) { "$($args[0])".Trim('"') } else { $null }

    $target = $null
    if ($supplied -and (Test-Path -LiteralPath $supplied)) { $target = $supplied }

    $singleFile = $null
    if ($target -and -not (Test-Path -LiteralPath $target -PathType Container)) {
        $singleFile = $target
        $target = Split-Path -Parent $singleFile
    }

    if (-not $target) {
        if ($Unattended) { throw "No path supplied, and -Unattended forbids the folder picker." }
        $target = Select-FolderDialog -Description "Select the folder whose timestamps should be fixed" -InitialDir $scriptDir
    }
    if (-not $target) {
        Write-Warning "No folder selected. Exiting."
        return
    }
    $target = [System.IO.Path]::GetFullPath($target).TrimEnd('\')

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "FIX TIMESTAMPS  ->  YYYY-MM-DD HH:MM:SS" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "Folder:     $target"
    if ($singleFile) { Write-Host "Single file: $singleFile" }
    Write-Host "Depth:      $Depth $(if ($Depth -eq 0) { '(this folder only - subfolders are not entered)' } else { "(this folder plus $Depth level(s) of subfolder)" })"
    Write-Host "Extensions: $($Extensions -join ', ')"
    Write-Host "Backup:     $(if ($NoBackup) { 'NO - -NoBackup removes the only automatic undo' } else { 'yes, into Backup\ before each rewrite' })"
    if ($DryRun) { Write-Host "Mode:       DRY RUN - nothing will be written" -ForegroundColor Yellow }
    Write-Host "$('=' * 70)" -ForegroundColor Cyan

    $files = if ($singleFile) { @(Get-Item -LiteralPath $singleFile) }
             else { Get-TargetFiles -Folder $target -Depth $Depth -Extensions $Extensions }

    if ($files.Count -eq 0) {
        $msg = "No .$($Extensions -join ', .') files found in:`n$target`n`nDepth $Depth. Backup, Combined and Sources folders are never scanned."
        Write-Warning ($msg -replace "`n", ' ')
        if (-not $Unattended) { Show-Notification -Title "Nothing to Check" -Icon Warning -Message $msg }
        return
    }

    Write-Host "`n$($files.Count) file(s) to check.`n" -ForegroundColor Cyan

    $records = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($f in $files) {
        $index++
        Write-Progress -Activity "Checking timestamps" -Status "$index of $($files.Count): $($f.Name)" `
            -PercentComplete (100 * $index / [Math]::Max($files.Count, 1))

        $rec = Invoke-FixTimestampsForFile -FilePath $f.FullName -Encoding $Encoding -NoBackup:$NoBackup -DryRun:$DryRun
        $records.Add($rec)

        switch ($rec.Status) {
            'Convert' {
                $verb = if ($DryRun) { 'WOULD CONVERT' } else { 'CONVERTED' }
                Write-Host "  $verb  $($rec.Name)" -ForegroundColor Green
                Write-Host "      read as $($rec.Order), $($rec.RowCount) row(s), $($rec.First) .. $($rec.Last)" -ForegroundColor DarkGray
            }
            'AlreadyCorrect' {
                Write-Host "  ok         $($rec.Name)  (already YYYY-MM-DD HH:MM:SS, untouched)" -ForegroundColor DarkGray
            }
            'Refuse' {
                Write-Host "  REFUSED    $($rec.Name)" -ForegroundColor Yellow
                Write-Host "      $($rec.Detail)" -ForegroundColor DarkYellow
            }
            'NoTimestamps' {
                Write-Host "  skipped    $($rec.Name)  (no timestamp column)" -ForegroundColor DarkGray
            }
            default {
                Write-Host "  FAILED     $($rec.Name): $($rec.Detail)" -ForegroundColor Red
            }
        }
    }
    Write-Progress -Activity "Checking timestamps" -Completed

    $converted = @($records | Where-Object { $_.Status -eq 'Convert' })
    $correct = @($records | Where-Object { $_.Status -eq 'AlreadyCorrect' })
    $refused = @($records | Where-Object { $_.Status -eq 'Refuse' })
    $skipped = @($records | Where-Object { $_.Status -eq 'NoTimestamps' })
    $failed = @($records | Where-Object { $_.Status -in @('WriteFailed', 'Unreadable') })

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Green
    Write-Host $(if ($DryRun) { "DRY RUN COMPLETE - NOTHING WAS WRITTEN" } else { "TIMESTAMP FIX COMPLETE" }) -ForegroundColor Green
    Write-Host "$('=' * 70)" -ForegroundColor Green
    Write-Host ("Files checked:   {0}" -f $records.Count)
    Write-Host ("$(if ($DryRun) { 'Would convert:  ' } else { 'Converted:      ' }) {0}" -f $converted.Count)
    Write-Host ("Already correct: {0}" -f $correct.Count)
    Write-Host ("Refused:         {0}{1}" -f $refused.Count, $(if ($refused.Count) { " (see the _DATEFORMATERROR.txt beside each)" } else { "" }))
    Write-Host ("No timestamps:   {0}" -f $skipped.Count)
    if ($failed.Count) { Write-Host ("Failed:          {0}" -f $failed.Count) -ForegroundColor Red }
    if ($converted.Count -gt 0) {
        $byOrder = $converted | Group-Object -Property Order | ForEach-Object { "$($_.Name) x$($_.Count)" }
        Write-Host ("Read as:         {0}" -f ($byOrder -join ', '))
    }
    Write-Host "$('=' * 70)" -ForegroundColor Green

    if ($refused.Count -gt 0) {
        Write-Host "`nRefused files (unchanged):" -ForegroundColor Yellow
        foreach ($r in $refused) { Write-Host "  - $($r.Name): $($r.Detail)" -ForegroundColor Yellow }
    }

    if (-not $Unattended) {
        $icon = if ($refused.Count -gt 0 -or $failed.Count -gt 0) { 'Warning' } else { 'Information' }
        Show-Notification -Icon $icon -Title $(if ($DryRun) { "Timestamp Check Complete" } else { "Timestamp Fix Complete" }) -Message (
            $(if ($DryRun) { "Dry run - nothing was written.`n`n" } else { "Finished.`n`n" }) +
            "Folder:`n$target`n`n" +
            "Files checked:   $($records.Count)`n" +
            "$(if ($DryRun) { 'Would convert:' } else { 'Converted:' })       $($converted.Count)`n" +
            "Already correct: $($correct.Count)`n" +
            "Refused:         $($refused.Count)`n" +
            "No timestamps:   $($skipped.Count)" +
            $(if ($refused.Count -gt 0) { "`n`nRefused files were NOT changed. A _DATEFORMATERROR.txt beside each one says why." } else { "" })
        )
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    $global:LASTEXITCODE = 1
}

#endregion
