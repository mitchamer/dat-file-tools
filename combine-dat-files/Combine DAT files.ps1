<#
    Combine DAT Files
    -----------------
    Combines structured, timestamp-based data files (TOA5 .dat/.csv/.txt) into a
    single primary file. Preserves the primary file's header + special rows,
    visually compares headers before merging, de-duplicates and sorts data, and
    moves merged secondaries into a Backup folder.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    This script MODIFIES AND MOVES DATA FILES. Licensed under GPL-3.0 and
    provided "as is" with no warranty of any kind (see LICENSE sections 15-17).
    You are responsible for verifying merged output before relying on it.

    A merge cannot be undone automatically. Specifically:
      * the primary file is REWRITTEN in place - its data section is replaced by
        the merged, de-duplicated, re-sorted result, and original row order is
        not retained
      * secondary files are MOVED (not copied) into a Backup subfolder
      * de-duplication compares the WHOLE row, case-insensitively, so rows that
        differ only in letter case (NAN vs NaN) collapse to one
      * sorting is a TEXT sort on the first column - correct for
        YYYY-MM-DD HH:MM:SS, wrong for formats like M/D/YYYY
      * -NoBackup removes the only automatic undo

    Test on copies first, and read the comparison dialogs rather than clicking
    through them. Declining one file is cheap; un-merging one is not.

    THREE WAYS TO INVOKE
    ====================

    1) FOLDER MODE (auto-group duplicates)
       Run with NO primary file. A dialog appears - choose "Yes" to scan a folder.
       The script groups two kinds of duplicate, then for each group compares
       row 2 (header) then row 1 (file info):
         a) backup-style duplicates
            (.bak/.backup/.backup1/.1/.old/.orig/.copy), including STACKED
            suffixes as LoggerNet writes them - Foo.dat.backup, Foo.dat.1.backup
            and Foo.dat.2.backup all group onto Foo.dat, and
         b) data files that TOA5 row 1 says came from the SAME MODEL, the SAME
            LOGGER SERIAL and the SAME TABLE - matched on those three fields
            alone, so the file name plays no part in the match. Model is in the
            match because two different logger types can share a serial:
              18421_SAA_SAA1_DATA_2026-09-08.dat -> 18421_SAA1_DATA.dat
            Row 1 is what the logger itself wrote, so renamed files, local manual
            downloads and remote manual collections all match. Extensions must be
            the same. Within a group the primary is the one file whose name does
            NOT end in a date stamp (the file the logger software keeps appending
            to); if that leaves two candidates, or none, the group is reported
            and skipped rather than merged into a guess.
       Only files sitting directly in the chosen folder are scanned - subfolders
       are NOT entered.
         PS> .\'Combine DAT files.ps1'
         (then click "Yes" and pick a folder)

    2) MANUAL MODE (pick files yourself)
       Run with NO primary file and choose "No" at the mode prompt (or select a
       primary via the dialog). You pick the primary file, then one or more
       secondary files to merge into it.
         PS> .\'Combine DAT files.ps1'
         (then click "No", pick a primary, then pick secondaries)

    3) DIRECT / RIGHT-CLICK MODE (file or folder supplied up front)
       Pass a FILE as the first argument (or via -PrimaryFile) and the mode
       prompt is skipped - you go straight to picking secondary files.
       Pass a FOLDER as the first argument and the script runs FOLDER MODE on
       that folder directly (no prompt, no folder picker). This is what the
       right-click context-menu entries use.
         PS> .\'Combine DAT files.ps1' 'C:\Data\TM_Site_Diagnostics.dat'
         PS> .\'Combine DAT files.ps1' -PrimaryFile 'C:\Data\TM_Site_Diagnostics.dat'
         PS> .\'Combine DAT files.ps1' 'C:\Data\SiteFolder'   (folder mode)

    COMPARISON DIALOG BUTTONS
       Proceed              Merge this secondary into the primary as it stands.
                            Disabled (and not the Enter default) when the headers
                            differ and Align is unavailable - merging as-is would
                            put values under the wrong names. The file is skipped.
       Align Columns
         & Merge            Shown only when the headers differ, the column NAMES
                            can be matched, and the recency check below passed.
                            Rewrites the secondary's data rows into the primary's
                            column order first. See COLUMN ALIGNMENT.
       Decline (Skip File)  Skip this secondary only; the scan continues with the
                            next duplicate / next group. Esc or closing the window
                            does the same. Enter does this too when Align is
                            blocked, so a re-ordered secondary cannot be merged
                            under the primary's names by accident.
       Exit All             Stop immediately - no further files or groups are
                            processed. Already-merged files stay merged.

    THE RECENCY CHECK - "ARE YOU SURE?"
    ===================================
    Before a secondary is merged, the primary must be the newer file in BOTH
    senses: a later file modified time, AND a later last timestamp in column 1 of
    its last row. Both, because either alone can lie - copying a file forward
    moves its modified time without adding a reading, and a file can hold newer
    readings while sitting untouched on disk.

    When both hold, this is the ordinary merge: an old archive going into the
    file automatic collection is still appending to. When either fails, the files
    are probably the wrong way round - the newer data is in the SECONDARY, and
    merging it into the primary puts the combined result somewhere nothing
    collects into. The script says which check failed and asks "are you sure?",
    defaulting to No. Answering Yes merges anyway and records the override in the
    merge log.

    The primary's modified time and last timestamp are read ONCE, before the
    first merge. Re-reading them per secondary would be meaningless: the first
    merge rewrites the primary, so its modified time becomes "just now".

    COLUMN ALIGNMENT
    ================
    A secondary whose header row lists the same measurements in a different
    shape - columns added, removed, or re-ordered - cannot simply be merged: its
    fields would land under the wrong column names. "Align Columns & Merge"
    rewrites its data rows into the primary's column order first, matching on the
    column NAMES in row 2 (case-insensitive), which is the only thing in the file
    that says what a field means.

      * a primary column the secondary lacks   -> filled with NAN
      * a secondary column the primary lacks   -> DROPPED, named in the merge log,
                                                  and the whole secondary is filed
                                                  under Backup\RemovedColumns-NotMerged
                                                  rather than Backup, so the values
                                                  that did not merge stay recoverable
      * shared columns in a different order    -> re-ordered, and then PROVED: see below

    Alignment is refused outright, with no override, when:
      * the recency check above did not pass on BOTH counts. Rewriting every
        field of every row is only safe in the direction old-archive into
        live-file, and recency is the only evidence of which direction that is.
        There is no "are you sure" here - the file is skipped and the scan moves
        on to the next one.
      * a column name is repeated in either header, so a field cannot be matched
        to one source.
      * the secondary has no column matching the primary's first column, so its
        timestamps cannot be placed.

    THE RE-ORDER PROOF
    ==================
    Adding or removing a column leaves every other column where it was. A
    RE-ORDER moves every value in the file, and a wrong map is silent - the rows
    still parse, they are just wrong. So a re-order is not merged on trust: the
    merge is done in memory and each column's distribution is shown three ways
    side by side - the primary before, the secondary after alignment, and the
    merged result - as min / p5 / mean / p95 / max for numeric columns, and the
    commonest values with their counts (200x"NAN", 3x"TRUE") for text ones.
    A mis-mapped column shows up at once, because it reads like a different
    measurement than the column it now sits beside. Nothing has been written at
    that point; declining costs nothing. The same table goes into the merge log.

    OPTIONAL PARAMETERS (all modes)
       -SpecialRowCount <int>   Number of special/metadata rows after the header
                                (default 3 -> rows 2-4 are preserved as-is).
       -NoBackup                Do not create a pre-merge backup of the primary.
       -DryRun                  Report only - no dialogs, nothing written, moved
                                or backed up. Says which secondaries would merge,
                                how many rows each would add, and what the
                                validation checks found.
       -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                                Output encoding. Default Auto, which matches the
                                primary's existing byte-order mark so merging does
                                not change the file's encoding. ASCII also enables
                                non-ASCII character checks.
         PS> .\'Combine DAT files.ps1' -SpecialRowCount 3 -Encoding Auto

    WHAT IS CHECKED BEFORE IT WRITES
    ================================
    Three things are reported rather than silently baked into the primary:
      * TIMESTAMP FORMAT. Sorting is a text sort, which is only correct while the
        first column is YYYY-MM-DD... . The first data row of every file is
        checked and a different shape is called out, because the merged output
        would be mis-ordered rather than wrong-looking.
      * COLUMN COUNT. The first data row's field count against the header's. A
        file that disagrees is a file whose rows will not line up.
      * TIMESTAMP CONFLICTS. After the merge, rows that share a timestamp but
        differ anywhere else are counted and the first few named. They are all
        KEPT - only the sources can say which is right - but a non-zero count
        means the sources disagree and the primary now holds more than one row
        for some timestamps.

    THE MERGE LOG
    =============
    A successful merge writes '<primary>.merge-log.txt' beside the primary: every
    secondary, rows read, rows contributed, every warning raised, and the totals.
    It is the record of what went into the file after the console has scrolled
    away. A dry run writes no log (it writes nothing at all).

    A NOTE ON THE ENCODING DEFAULT
    ==============================
    Before this change the default was UTF8 via Set-Content, which under
    PowerShell 5.1 writes a byte-order mark. A BOM ahead of the TOA5 row leaves
    LoggerNet unable to recognise the data file it is appending to: it renames
    the file to .dat.backup and starts a fresh one, so a merge appeared to
    succeed while LoggerNet quietly stopped using the result. Auto avoids that
    by writing the file back the way it was found.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PrimaryFile,

    [Parameter()]
    [int]$SpecialRowCount = 3,

    [Parameter()]
    [switch]$NoBackup,

    # Report what a merge would do - which secondaries would merge, how many rows
    # each would add, and every validation warning - and write nothing. No dialog
    # is shown, nothing is backed up, no secondary is moved. This is the pass to
    # run first on a folder you have not merged before.
    [Parameter()]
    [switch]$DryRun,

    # Output encoding for the rewritten primary.
    #
    # 'Auto' (default) matches the primary's existing byte-order mark, so merging
    # does not change the file's encoding. This matters more than it looks:
    # Set-Content -Encoding UTF8 writes a BOM under PowerShell 5.1 (though not
    # under 7), and a BOM ahead of the TOA5 row leaves LoggerNet unable to
    # recognise the file it is appending to. It responds by renaming the file to
    # .dat.backup and starting a fresh one, silently orphaning everything that
    # was just merged.
    #
    # 'UTF8' now means UTF8 WITHOUT a BOM on every PowerShell version; ask for
    # 'UTF8BOM' if a BOM is actually wanted.
    [Parameter()]
    [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'ASCII', 'Unicode')]
    [string]$Encoding = 'Auto'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region Helper Functions

# Sniff a file's byte-order mark, so 'Auto' can write it back the way it came in.
# LoggerNet data files carry no BOM; adding one makes LoggerNet unable to
# recognise the file and it responds by abandoning it (renaming to .dat.backup
# and starting fresh), which silently orphans a merge.
function Get-FileBomEncoding {
    param([string]$FilePath)

    $bytes = New-Object byte[] 4
    $read = 0
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try { $read = $stream.Read($bytes, 0, 4) } finally { $stream.Dispose() }
    } catch {
        return (New-Object System.Text.UTF8Encoding($false))
    }

    if ($read -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))      # UTF8 with BOM
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return (New-Object System.Text.UnicodeEncoding($false, $true))
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return (New-Object System.Text.UnicodeEncoding($true, $true))
    }
    return (New-Object System.Text.UTF8Encoding($false))         # UTF8, no BOM
}

# Turn the -Encoding name into a concrete .NET encoding. Using explicit encoding
# objects rather than Set-Content's -Encoding keeps behaviour identical across
# PowerShell 5.1 and 7, where 'UTF8' means with-BOM and without-BOM respectively.
function Resolve-OutputEncoding {
    param([string]$Name, [string]$FilePath)

    switch ($Name) {
        'Auto'    { return (Get-FileBomEncoding -FilePath $FilePath) }
        'UTF8'    { return (New-Object System.Text.UTF8Encoding($false)) }
        'UTF8BOM' { return (New-Object System.Text.UTF8Encoding($true)) }
        'ASCII'   { return ([System.Text.Encoding]::ASCII) }
        'Unicode' { return (New-Object System.Text.UnicodeEncoding($false, $true)) }
    }
    return (New-Object System.Text.UTF8Encoding($false))
}

# ---------------------------------------------------------------------------
# Bulk data helpers
#
# These exist because a 55 MB merge used to take over five minutes, almost all of
# it in one line. See Get-SortedDataRows.
# ---------------------------------------------------------------------------

function Read-DataFileLines {
    param([string]$Path)
    # Markedly faster than Get-Content, which wraps every line in a PSObject and
    # attaches note properties. On a 20,000-row file of 2.7 KB rows that overhead
    # is most of the read time.
    return [System.IO.File]::ReadAllLines($Path)
}

function Get-SortedDataRows {
    param([System.Collections.Generic.HashSet[string]]$Rows)

    $values = New-Object 'string[]' $Rows.Count
    $Rows.CopyTo($values)

    # An ordinal sort of the whole row. The timestamp is the leading field and is
    # fixed width in TOA5, so this orders by timestamp exactly - and breaks ties
    # on the rest of the row rather than leaving equal-timestamp rows in an
    # arbitrary order, so repeated runs produce identical output.
    #
    # What this replaces:
    #
    #     $currentData | Sort-Object { ($_ -split ',')[0] }
    #
    # which split every row into all of its fields (275 of them on an SAA table)
    # just to read the first one, and paid PowerShell pipeline overhead on every
    # comparison. On a 55 MB merge that single line was the five minutes. This is
    # one .NET call with no per-row PowerShell work.
    [Array]::Sort($values, [System.StringComparer]::Ordinal)
    # Unary comma: a 1-element string[] must not unroll into a single string,
    # or the writer iterates characters and the output is garbage.
    return ,$values
}

# ---------------------------------------------------------------------------
# Reassurance for long merges
#
# A big merge looks indistinguishable from a hang, and someone killing it part
# way is how a primary file gets destroyed. After SLOW_HINT_SECONDS, say what is
# happening and name a file whose size actually moves.
# ---------------------------------------------------------------------------

$script:MergeStopwatch = $null
$script:SlowHintShown = $false

function Start-MergeTimer {
    $script:MergeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:SlowHintShown = $false
}

function Show-SlowHintIfNeeded {
    # The threshold is a parameter default rather than a script-level variable on
    # purpose. As a loose variable it could fall out of scope, and then
    # `elapsed -lt $null` compares against 0, which is always false - so the hint
    # would fire on every merge instead of only slow ones. A default cannot be
    # undefined.
    param(
        [string]$WatchPath,
        [double]$AfterSeconds = 15
    )

    if ($script:SlowHintShown -or -not $script:MergeStopwatch) { return }
    if ($script:MergeStopwatch.Elapsed.TotalSeconds -lt $AfterSeconds) { return }
    $script:SlowHintShown = $true

    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  Still working. Large files take a while - this is not stuck.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  To confirm it is progressing, open the folder in Explorer and' -ForegroundColor Yellow
    Write-Host '  press F5. This working file should be growing:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "      $WatchPath" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  It replaces the primary only when the merge finishes, so the' -ForegroundColor Yellow
    Write-Host '  primary will NOT change size until then. Closing this window now' -ForegroundColor Yellow
    Write-Host '  leaves the primary untouched.' -ForegroundColor Yellow
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
}

function Select-FileDialog {
    param(
        [string]$Title,
        [string]$InitialDir,
        [string]$Filter,
        [bool]$MultiSelect = $false
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.InitialDirectory = $InitialDir
    $dialog.Filter = $Filter
    $dialog.Multiselect = $MultiSelect

    if ($dialog.ShowDialog() -ne 'OK') {
        Write-Warning "File selection cancelled."
        return $null
    }

    if ($MultiSelect) {
        return $dialog.FileNames
    }
    else {
        return $dialog.FileName
    }
}

function Split-CsvLine {
    param([string]$Line)
    # Simple CSV split that respects double-quoted fields.
    $fields = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $inQuotes = $false

    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($ch -eq '"') {
            if ($inQuotes -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                [void]$sb.Append('"')
                $i++
            }
            else {
                $inQuotes = -not $inQuotes
            }
        }
        elseif ($ch -eq ',' -and -not $inQuotes) {
            [void]$fields.Add($sb.ToString())
            [void]$sb.Clear()
        }
        else {
            [void]$sb.Append($ch)
        }
    }
    [void]$fields.Add($sb.ToString())
    return $fields.ToArray()
}

function Get-FirstFieldRaw {
    <#
        Returns the first CSV field of a row, quotes stripped, without splitting
        the rest of the line. Called once per row by the timestamp-conflict scan,
        where splitting a 275-column row to read field 1 would dominate the run.
    #>
    param([string]$Line)

    if ([string]::IsNullOrEmpty($Line)) { return '' }
    if ($Line[0] -eq '"') {
        $end = $Line.IndexOf('"', 1)
        if ($end -lt 0) { return $Line.Substring(1) }
        return $Line.Substring(1, $end - 1)
    }
    $comma = $Line.IndexOf(',')
    if ($comma -lt 0) { return $Line }
    return $Line.Substring(0, $comma)
}

function Split-CsvFieldsRaw {
    <#
        Splits a row into its fields but returns each field EXACTLY as written,
        quotes and all. Split-CsvLine strips quoting, which is what you want to
        compare column NAMES; it is the wrong tool for moving DATA between
        columns, because re-joining its output would rewrite
        "2026-09-16 12:00:00" as 2026-09-16 12:00:00 and the row would then no
        longer de-duplicate against the primary's identical row. Column
        alignment shuffles these raw substrings, so a merged row is
        byte-identical to the one the logger wrote.
    #>
    param([string]$Line)

    $fields = [System.Collections.Generic.List[string]]::new()
    $start = 0
    $inQuotes = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($ch -eq '"') {
            # A doubled "" inside a quoted field toggles twice and lands back
            # inside, which is the behaviour the comma test needs.
            $inQuotes = -not $inQuotes
        }
        elseif ($ch -eq ',' -and -not $inQuotes) {
            [void]$fields.Add($Line.Substring($start, $i - $start))
            $start = $i + 1
        }
    }
    [void]$fields.Add($Line.Substring($start))
    return $fields.ToArray()
}

function Get-LastDataTimestamp {
    <#
        First column of the last non-blank row of an already-read file. That is
        the newest reading the file holds, and it is the half of the recency
        check that file modification time cannot give you: copying a file
        forward, restoring it from a backup or touching it on a share all move
        the modified time without adding a single reading.
    #>
    param([string[]]$Lines, [int]$DataStartIndex)

    for ($i = $Lines.Count - 1; $i -ge $DataStartIndex; $i--) {
        if (-not [string]::IsNullOrWhiteSpace($Lines[$i])) {
            return (Get-FirstFieldRaw -Line $Lines[$i])
        }
    }
    return $null
}

function Test-PrimaryIsNewer {
    <#
        The primary must be newer than the secondary in BOTH senses before a
        merge is anything other than a question:

          * file modified time, and
          * the last timestamp actually inside the file.

        Why both. When automatic collection is appending to the file the logger
        software owns, the current file is newer on both counts and the merge is
        the ordinary one - old archive into live file. When either count runs the
        other way the roles are probably reversed: the "primary" is the stale
        copy and merging into it puts the newly collected rows in a file nothing
        collects into, where the next collection will not find them.

        Timestamps compare as ordinal text, the same assumption the row sort
        already makes. A timestamp that is not YYYY-MM-DD cannot be compared
        that way, so it counts as a failure rather than a pass - an unreadable
        check is not a passed check.

        Returns Ok plus the two halves and a human-readable reason.
    #>
    param(
        [datetime]$PrimaryModified,
        [datetime]$SecondaryModified,
        [string]$PrimaryLastTs,
        [string]$SecondaryLastTs
    )

    $mtimeOk = ($PrimaryModified -gt $SecondaryModified)

    $comparable = ($PrimaryLastTs -match '^\d{4}-\d{2}-\d{2}') -and ($SecondaryLastTs -match '^\d{4}-\d{2}-\d{2}')
    $tsOk = $comparable -and ([string]::CompareOrdinal($PrimaryLastTs, $SecondaryLastTs) -gt 0)

    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $mtimeOk) {
        $reasons.Add(("file modified time: secondary $($SecondaryModified.ToString('yyyy-MM-dd HH:mm:ss')) is not older than primary $($PrimaryModified.ToString('yyyy-MM-dd HH:mm:ss'))"))
    }
    if (-not $comparable) {
        $reasons.Add("last timestamp: '$PrimaryLastTs' vs '$SecondaryLastTs' - not YYYY-MM-DD, so which is newer cannot be decided")
    }
    elseif (-not $tsOk) {
        $reasons.Add("last timestamp in file: secondary '$SecondaryLastTs' is not older than primary '$PrimaryLastTs'")
    }

    return [pscustomobject]@{
        Ok                = ($mtimeOk -and $tsOk)
        MtimeOk           = $mtimeOk
        TsOk              = $tsOk
        TsComparable      = $comparable
        Reason            = ($reasons -join '; ')
        # The raw values as well as the verdict, so the dialog can lay the two
        # files out side by side instead of re-parsing a sentence.
        PrimaryModified   = $PrimaryModified
        SecondaryModified = $SecondaryModified
        PrimaryLastTs     = $PrimaryLastTs
        SecondaryLastTs   = $SecondaryLastTs
        Summary           = ("primary modified $($PrimaryModified.ToString('yyyy-MM-dd HH:mm:ss')), last row '$PrimaryLastTs'" +
                             "`nsecondary modified $($SecondaryModified.ToString('yyyy-MM-dd HH:mm:ss')), last row '$SecondaryLastTs'")
    }
}

function Get-ColumnAlignment {
    <#
        Works out how to rewrite the secondary's data rows into the primary's
        column order, matching on the column NAMES in row 2 - the only thing in
        a TOA5 file that says what a field means. Position cannot be trusted
        here; that is the whole problem being solved.

        Three outcomes per column:
          * name found in the secondary        -> that field is copied across
          * primary column the secondary lacks -> filled with NAN
          * secondary column the primary lacks -> dropped (and named, so the
            merge log and the backup folder can say what was lost)

        Refused outright when the mapping would be a guess: a duplicated column
        name on either side, or a first column (the timestamp) with no match.

        Reordered is TRUE only when the columns the two files SHARE appear in a
        different relative order. Columns purely added or removed leave the rest
        in order and need no further proof; a genuine re-order does, because
        every value in the file moves and a wrong map is silent.

        Returns Ok, Reason, Map (one entry per primary column, -1 = fill NAN),
        Filled, Dropped, Reordered, and NoOp for headers that already agree.
    #>
    param([string]$PrimaryHeaderRow, [string]$SecondaryHeaderRow)

    $result = [pscustomobject]@{
        Ok        = $false
        Reason    = ''
        Map       = @()
        Filled    = @()
        Dropped   = @()
        Reordered = $false
        NoOp      = $false
    }

    $pn = @(Split-CsvLine -Line $PrimaryHeaderRow   | ForEach-Object { $_.Trim() })
    $sn = @(Split-CsvLine -Line $SecondaryHeaderRow | ForEach-Object { $_.Trim() })

    # A repeated column name makes "which field does this name mean" a guess,
    # and a guess is exactly what this function exists to avoid.
    $findDupes = {
        param([string[]]$Names)
        return @($Names | Group-Object -Property { $_.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })
    }
    $dupP = & $findDupes $pn
    $dupS = & $findDupes $sn
    if ($dupP.Count -gt 0 -or $dupS.Count -gt 0) {
        $side = if ($dupP.Count -gt 0) { 'primary' } else { 'secondary' }
        $dupes = if ($dupP.Count -gt 0) { $dupP } else { $dupS }
        $result.Reason = "the $side header repeats the column name(s) $(($dupes | ForEach-Object { "'$($_.Group[0])'" }) -join ', '), so a column cannot be matched to one source."
        return $result
    }

    $lookup = @{}
    for ($i = 0; $i -lt $sn.Count; $i++) { $lookup[$sn[$i].ToLowerInvariant()] = $i }

    $map = New-Object 'int[]' $pn.Count
    $filled = [System.Collections.Generic.List[string]]::new()
    $used = [System.Collections.Generic.HashSet[int]]::new()
    for ($i = 0; $i -lt $pn.Count; $i++) {
        $k = $pn[$i].ToLowerInvariant()
        if ($lookup.ContainsKey($k)) {
            $map[$i] = $lookup[$k]
            [void]$used.Add($map[$i])
        }
        else {
            $map[$i] = -1
            $filled.Add($pn[$i])
        }
    }

    if ($map.Count -eq 0 -or $map[0] -lt 0) {
        $result.Reason = "the secondary has no column named '$(if ($pn.Count) { $pn[0] } else { '' })', so its timestamps cannot be placed."
        return $result
    }
    if ($filled.Count -eq $pn.Count) {
        $result.Reason = "the two headers share no column names at all."
        return $result
    }

    $dropped = [System.Collections.Generic.List[string]]::new()
    for ($j = 0; $j -lt $sn.Count; $j++) {
        if (-not $used.Contains($j)) { $dropped.Add($sn[$j]) }
    }

    # Shared columns out of their original relative order = a real re-order.
    $reordered = $false
    $prev = -1
    foreach ($j in $map) {
        if ($j -lt 0) { continue }
        if ($j -lt $prev) { $reordered = $true; break }
        $prev = $j
    }

    $result.Ok = $true
    $result.Map = $map
    $result.Filled = $filled.ToArray()
    $result.Dropped = $dropped.ToArray()
    $result.Reordered = $reordered
    $result.NoOp = (-not $reordered -and $filled.Count -eq 0 -and $dropped.Count -eq 0)
    return $result
}

function ConvertTo-AlignedRow {
    param([string]$Line, [int[]]$Map)

    $raw = Split-CsvFieldsRaw -Line $Line
    $out = New-Object 'string[]' $Map.Length
    for ($i = 0; $i -lt $Map.Length; $i++) {
        $j = $Map[$i]
        # A short row - ragged output, a truncated download - fills NAN too
        # rather than throwing, which is the same answer as a missing column.
        $out[$i] = if ($j -ge 0 -and $j -lt $raw.Length) { $raw[$j] } else { 'NAN' }
    }
    return [string]::Join(',', $out)
}

function Get-ColumnStats {
    <#
        One column's distribution, as the proof that a re-order put the values
        where the names say they go. Numeric columns give n/min/p5/mean/p95/max;
        text columns give the commonest values with their counts. NAN and empty
        are missing values in a numeric column, not text.

        Percentiles are nearest-rank on the sorted values.
    #>
    # $Rows is left untyped so a HashSet can be passed straight in - typing it
    # [string[]] would make PowerShell copy the whole merged set into an array
    # once per column, which on a wide table is the cost of the merge again.
    param($Rows, [int]$Index, [int]$TopText = 3)

    $nums = [System.Collections.Generic.List[double]]::new()
    $text = @{}
    $missing = 0
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    foreach ($row in $Rows) {
        $f = Split-CsvFieldsRaw -Line $row
        if ($Index -ge $f.Length) { $missing++; continue }
        $v = $f[$Index].Trim().Trim('"')
        if ($v -eq '' -or $v -eq 'NAN' -or $v -eq 'NaN' -or $v -eq 'nan') { $missing++; continue }

        $d = 0.0
        if ([double]::TryParse($v, [System.Globalization.NumberStyles]::Float, $inv, [ref]$d)) {
            $nums.Add($d)
        }
        else {
            if ($text.ContainsKey($v)) { $text[$v]++ } else { $text[$v] = 1 }
        }
    }

    if ($text.Count -gt 0) {
        $total = 0
        foreach ($c in $text.Values) { $total += $c }
        $extra = if ($nums.Count -gt 0) { "  num=$($nums.Count)" } else { '' }

        # Every value distinct - a timestamp or an ID column. Counting them all
        # at 1x says nothing and is the widest cell in the grid; the range is the
        # thing worth seeing.
        if ($text.Count -eq $total) {
            $sorted = @($text.Keys | Sort-Object)
            return "n=$total  all distinct  first=$($sorted[0])  last=$($sorted[-1])  NAN/blank=$missing$extra"
        }

        $top = @($text.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Name |
            Select-Object -First $TopText | ForEach-Object { "$($_.Value)x`"$($_.Name)`"" })
        return "n=$total  uniq=$($text.Count)  $($top -join '  ')  NAN/blank=$missing$extra"
    }

    if ($nums.Count -eq 0) { return "n=0  NAN/blank=$missing" }

    $v = $nums.ToArray()
    [Array]::Sort($v)
    $pct = {
        param($p)
        $idx = [int][Math]::Ceiling($p / 100.0 * $v.Length) - 1
        return $v[[Math]::Max(0, [Math]::Min($v.Length - 1, $idx))]
    }
    $sum = 0.0
    foreach ($x in $v) { $sum += $x }
    $f6 = { param($x) '{0:G6}' -f $x }

    return ("n=$($v.Length)  min=$(& $f6 $v[0])  p5=$(& $f6 (& $pct 5))  mean=$(& $f6 ($sum / $v.Length))" +
            "  p95=$(& $f6 (& $pct 95))  max=$(& $f6 $v[$v.Length - 1])  NAN/blank=$missing")
}

function Show-HeaderComparison {
    <#
        Displays a side-by-side, column-by-column comparison of two lines.
        Returns one of:
          'Proceed' - merge this file as it stands
          'Align'   - rewrite the secondary's columns into the primary's order
                      first, then merge (offered only when -AlignOffer is set)
          'Decline' - skip this file and continue with the next one
          'ExitAll' - stop processing everything (remaining files and groups)

        -AlignOffer adds the "Align & Merge" button (and makes it the Enter
        default). -AlignBlockedReason greys that button out AND disables
        Proceed Anyway, with Decline as the Enter default: merging as-is would
        put values under the wrong names, which is the case Align exists to
        prevent.

        Row 1 is the TOA5 environment line. The grid labels each field with the
        same names ViewPro uses (File Format, Station Name, Model, CPU Serial
        Number, OS Version, Program Name, ProgSignature, Table Name).
    #>
    param(
        [string]$PrimaryHeader,
        [string]$SecondaryHeader,
        [string]$PrimaryName,
        [string]$SecondaryName,
        [int]$RowNumber,
        [string]$ComparisonTitle = "Header Comparison",
        [string]$AlignOffer,
        [string]$AlignBlockedReason
    )

    $primaryFields = Split-CsvLine -Line $PrimaryHeader
    $secondaryFields = Split-CsvLine -Line $SecondaryHeader
    $maxCols = [Math]::Max($primaryFields.Count, $secondaryFields.Count)

    $identical = ($PrimaryHeader -eq $SecondaryHeader)

    # Palette
    $clrBg = [System.Drawing.Color]::FromArgb(250, 250, 252)
    $clrCardBg = [System.Drawing.Color]::White
    $clrText = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $clrSubtle = [System.Drawing.Color]::FromArgb(110, 110, 120)
    $clrHeaderBg = [System.Drawing.Color]::FromArgb(45, 52, 64)
    $clrGridHead = [System.Drawing.Color]::FromArgb(238, 240, 244)
    $clrAltRow = [System.Drawing.Color]::FromArgb(247, 249, 251)
    $clrGreen = [System.Drawing.Color]::FromArgb(34, 139, 87)
    $clrRed = [System.Drawing.Color]::FromArgb(192, 57, 57)
    $clrDiffP = [System.Drawing.Color]::FromArgb(253, 235, 236)
    $clrDiffS = [System.Drawing.Color]::FromArgb(255, 248, 225)
    $clrBanner = if ($identical) { [System.Drawing.Color]::FromArgb(232, 245, 238) } else { [System.Drawing.Color]::FromArgb(253, 237, 237) }
    $clrBannerTxt = if ($identical) { $clrGreen } else { $clrRed }

    $fontUI = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontUIBold = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $fontBanner = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $fontMono = New-Object System.Drawing.Font("Consolas", 9)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$ComparisonTitle (Row $RowNumber)"
    $form.StartPosition = 'CenterScreen'
    # Row 1 adds a Meaning column (ViewPro's names for the TOA5 environment line).
    $form.Size = New-Object System.Drawing.Size($(if ($RowNumber -eq 1) { 940 } else { 820 }), 600)
    $form.MinimumSize = New-Object System.Drawing.Size($(if ($RowNumber -eq 1) { 720 } else { 600 }), 440)
    $form.TopMost = $true
    $form.BackColor = $clrBg
    $form.Font = $fontUI
    $form.Padding = New-Object System.Windows.Forms.Padding(0)

    # --- Title banner (dark) ---
    $titleBar = New-Object System.Windows.Forms.Panel
    $titleBar.Dock = 'Top'
    $titleBar.Height = 58
    $titleBar.BackColor = $clrHeaderBg

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "$ComparisonTitle"
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.AutoSize = $false
    $lblTitle.Dock = 'Fill'
    $lblTitle.TextAlign = 'MiddleLeft'
    $lblTitle.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0)

    $lblRowTag = New-Object System.Windows.Forms.Label
    $lblRowTag.Text = "Row $RowNumber"
    $lblRowTag.Font = $fontUIBold
    $lblRowTag.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 225)
    $lblRowTag.AutoSize = $false
    $lblRowTag.Dock = 'Right'
    $lblRowTag.Width = 110
    $lblRowTag.TextAlign = 'MiddleRight'
    $lblRowTag.Padding = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)

    $titleBar.Controls.Add($lblTitle)
    $titleBar.Controls.Add($lblRowTag)

    # --- Status banner (colored) ---
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 78
    $banner.BackColor = $clrBanner
    $banner.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Dock = 'Top'
    $lblStatus.Height = 24
    $lblStatus.Font = $fontBanner
    $lblStatus.ForeColor = $clrBannerTxt
    $lblStatus.Text = if ($identical) { "These values are IDENTICAL." } else { "These values DIFFER - differences are highlighted below." }

    $lblFiles = New-Object System.Windows.Forms.Label
    $lblFiles.Dock = 'Fill'
    $lblFiles.Font = $fontUI
    $lblFiles.ForeColor = $clrText
    $lblFiles.Text = "Primary:      $PrimaryName`nSecondary:  $SecondaryName"

    # Fill goes in first, then the edge-docked labels - same z-order rule the
    # form itself follows below, or the Fill control swallows their space.
    $banner.Controls.Add($lblFiles)
    $banner.Controls.Add($lblStatus)

    # Say in the banner what the Align button will or will not do. A tooltip
    # alone is a message nobody reads before clicking Proceed Anyway.
    if ($AlignOffer -or $AlignBlockedReason) {
        $banner.Height = 120
        $lblAlign = New-Object System.Windows.Forms.Label
        $lblAlign.Dock = 'Bottom'
        $lblAlign.Height = 40
        $lblAlign.Font = $fontUI
        $lblAlign.ForeColor = if ($AlignOffer) { [System.Drawing.Color]::FromArgb(40, 90, 170) } else { $clrRed }
        $lblAlign.Text = if ($AlignOffer) { "Align Columns & Merge:  $AlignOffer" } else { "Align Columns unavailable:  $AlignBlockedReason" }
        $banner.Controls.Add($lblAlign)
    }

    # Grid
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.ReadOnly = $true
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.BorderStyle = 'None'
    $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.BackgroundColor = $clrCardBg
    $grid.EnableHeadersVisualStyles = $false
    $grid.GridColor = [System.Drawing.Color]::FromArgb(232, 234, 238)
    $grid.Font = $fontUI
    $grid.RowTemplate.Height = 28
    $grid.ColumnHeadersHeight = 34
    $grid.ColumnHeadersBorderStyle = 'None'
    $grid.AlternatingRowsDefaultCellStyle.BackColor = $clrAltRow
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(225, 233, 245)
    $grid.DefaultCellStyle.SelectionForeColor = $clrText
    $grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $clrGridHead
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = $clrText
    $grid.ColumnHeadersDefaultCellStyle.Font = $fontUIBold
    $grid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)

    # ViewPro's names for TOA5 row 1, in CSV order. The fourth field is the
    # logger serial (CPU Serial Number), not the station name in the file name.
    $toa5Meanings = @(
        'File Format',
        'Station Name',
        'Model',
        'CPU Serial Number',
        'OS Version',
        'Program Name',
        'ProgSignature',
        'Table Name'
    )
    $showMeanings = ($RowNumber -eq 1)

    [void]$grid.Columns.Add("Col", "#")
    if ($showMeanings) { [void]$grid.Columns.Add("Meaning", "Meaning") }
    [void]$grid.Columns.Add("Primary", "Primary")
    [void]$grid.Columns.Add("Secondary", "Secondary")
    [void]$grid.Columns.Add("Status", "Status")
    $grid.Columns["Col"].FillWeight = $(if ($showMeanings) { 8 } else { 12 })
    $grid.Columns["Col"].DefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.Columns["Col"].DefaultCellStyle.ForeColor = $clrSubtle
    if ($showMeanings) {
        $grid.Columns["Meaning"].FillWeight = 28
        $grid.Columns["Meaning"].DefaultCellStyle.ForeColor = $clrSubtle
    }
    $grid.Columns["Primary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Secondary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Status"].FillWeight = $(if ($showMeanings) { 22 } else { 26 })

    for ($i = 0; $i -lt $maxCols; $i++) {
        $p = if ($i -lt $primaryFields.Count) { $primaryFields[$i] }   else { $null }
        $s = if ($i -lt $secondaryFields.Count) { $secondaryFields[$i] } else { $null }

        if ($null -eq $p) { $status = "Missing in Primary" }
        elseif ($null -eq $s) { $status = "Missing in Secondary" }
        elseif ($p -eq $s) { $status = "Match" }
        else { $status = "Different" }

        $pText = if ($null -eq $p) { "(none)" } else { $p }
        $sText = if ($null -eq $s) { "(none)" } else { $s }
        if ($showMeanings) {
            $meaning = if ($i -lt $toa5Meanings.Count) { $toa5Meanings[$i] } else { '' }
            $rowIndex = $grid.Rows.Add(($i + 1), $meaning, $pText, $sText, $status)
        }
        else {
            $rowIndex = $grid.Rows.Add(($i + 1), $pText, $sText, $status)
        }
        $row = $grid.Rows[$rowIndex]

        if ($status -ne "Match") {
            $row.Cells["Primary"].Style.BackColor = $clrDiffP
            $row.Cells["Secondary"].Style.BackColor = $clrDiffS
            $row.Cells["Status"].Style.ForeColor = $clrRed
            $row.Cells["Status"].Style.Font = $fontUIBold
        }
        else {
            $row.Cells["Status"].Style.ForeColor = $clrGreen
        }
    }

    # Wrap grid in a padded container so it reads like a card
    $gridHost = New-Object System.Windows.Forms.Panel
    $gridHost.Dock = 'Fill'
    $gridHost.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $gridHost.BackColor = $clrBg
    $gridHost.Controls.Add($grid)

    # Button panel (flow layout, right-aligned, always visible)
    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 64
    $panel.FlowDirection = 'RightToLeft'
    # Never wrap. The panel is 64px tall, so a button pushed onto a second row is
    # not a smaller layout, it is a button the user cannot see or click - and the
    # one that wraps is the last added, "Exit All".
    $panel.WrapContents = $false
    $panel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 247)

    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = if ($identical) { "Proceed" } else { "Proceed Anyway" }
    $btnProceed.Size = New-Object System.Drawing.Size(160, 36)
    $btnProceed.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnProceed.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $btnProceed.FlatStyle = 'Flat'
    $btnProceed.FlatAppearance.BorderSize = 0
    $btnProceed.BackColor = $clrGreen
    $btnProceed.ForeColor = [System.Drawing.Color]::White
    $btnProceed.Font = $fontUIBold
    $btnProceed.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnDecline = New-Object System.Windows.Forms.Button
    $btnDecline.Text = "Decline (Skip File)"
    $btnDecline.Size = New-Object System.Drawing.Size(160, 36)
    $btnDecline.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnDecline.DialogResult = [System.Windows.Forms.DialogResult]::No
    $btnDecline.FlatStyle = 'Flat'
    $btnDecline.FlatAppearance.BorderSize = 1
    $btnDecline.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 205)
    $btnDecline.BackColor = [System.Drawing.Color]::White
    $btnDecline.ForeColor = $clrText
    $btnDecline.Font = $fontUI
    $btnDecline.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnExitAll = New-Object System.Windows.Forms.Button
    $btnExitAll.Text = "Exit All (Stop Everything)"
    $btnExitAll.Size = New-Object System.Drawing.Size(180, 36)
    $btnExitAll.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnExitAll.DialogResult = [System.Windows.Forms.DialogResult]::Abort
    $btnExitAll.FlatStyle = 'Flat'
    $btnExitAll.FlatAppearance.BorderSize = 1
    $btnExitAll.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(214, 170, 170)
    $btnExitAll.BackColor = [System.Drawing.Color]::FromArgb(253, 240, 240)
    $btnExitAll.ForeColor = $clrRed
    $btnExitAll.Font = $fontUI
    $btnExitAll.Cursor = [System.Windows.Forms.Cursors]::Hand

    # RightToLeft flow: first added appears rightmost.
    if ($AlignOffer -or $AlignBlockedReason) {
        # A fourth button needs ~200px more than the three-button layout, and the
        # row does not wrap (see $panel.WrapContents), so the window has to give
        # it the room or Exit All falls off the right-hand edge.
        $form.Size = New-Object System.Drawing.Size(1010, 620)
        $form.MinimumSize = New-Object System.Drawing.Size(1010, 460)

        $btnAlign = New-Object System.Windows.Forms.Button
        $btnAlign.Size = New-Object System.Drawing.Size(210, 36)
        $btnAlign.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
        $btnAlign.FlatStyle = 'Flat'
        $btnAlign.FlatAppearance.BorderSize = 0
        $btnAlign.Font = $fontUIBold

        if ($AlignOffer) {
            $btnAlign.Text = "Align Columns && Merge"
            $btnAlign.DialogResult = [System.Windows.Forms.DialogResult]::Retry
            $btnAlign.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 170)
            $btnAlign.ForeColor = [System.Drawing.Color]::White
            $btnAlign.Cursor = [System.Windows.Forms.Cursors]::Hand
            $tip = New-Object System.Windows.Forms.ToolTip
            $tip.SetToolTip($btnAlign, $AlignOffer)
            # Aligning is the right answer whenever it is on offer, so it is the
            # button Enter presses - not "Proceed Anyway", which merges rows that
            # the grid above has just shown do not line up.
            $form.AcceptButton = $btnAlign
        }
        else {
            $btnAlign.Text = "Align Columns - unavailable"
            $btnAlign.Enabled = $false
            $btnAlign.BackColor = [System.Drawing.Color]::FromArgb(226, 226, 230)
            $btnAlign.ForeColor = $clrSubtle
            $tip = New-Object System.Windows.Forms.ToolTip
            $tip.SetToolTip($btnAlign, $AlignBlockedReason)
            # Proceed Anyway would merge the secondary's fields under the
            # primary's names without remapping. That is the silent-wrong-data
            # case Align exists to prevent, so it is not offered either.
            $btnProceed.Enabled = $false
            $btnProceed.BackColor = [System.Drawing.Color]::FromArgb(226, 226, 230)
            $btnProceed.ForeColor = $clrSubtle
            $btnProceed.Cursor = [System.Windows.Forms.Cursors]::Default
            $tip.SetToolTip($btnProceed, "Cannot merge as-is: columns would land under the wrong names. $AlignBlockedReason")
            $form.AcceptButton = $btnDecline
        }
        $panel.Controls.Add($btnAlign)
    }
    $panel.Controls.Add($btnProceed)
    $panel.Controls.Add($btnDecline)
    $panel.Controls.Add($btnExitAll)

    # Add the fill control first (lowest z-order) so docked panels are not overlapped.
    $form.Controls.Add($gridHost)
    $form.Controls.Add($panel)
    $form.Controls.Add($banner)
    $form.Controls.Add($titleBar)
    # Align, when on offer, is already AcceptButton. When it is blocked, Decline
    # is - Enter must not mean Proceed Anyway. Otherwise Proceed is the default.
    if (-not $AlignOffer -and -not $AlignBlockedReason) { $form.AcceptButton = $btnProceed }
    $form.CancelButton = $btnDecline

    $result = $form.ShowDialog()
    $form.Dispose()

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) { return 'Proceed' }
        ([System.Windows.Forms.DialogResult]::Retry) { return 'Align' }
        ([System.Windows.Forms.DialogResult]::Abort) { return 'ExitAll' }
        default { return 'Decline' }   # No / Esc / window closed = skip this file only
    }
}

function Get-ColumnStatsTable {
    <#
        Per-column distributions for the three row sets a re-order has to be
        judged on: the primary before this merge, the secondary after alignment,
        and the merged result. Computed once and used twice - the dialog the
        user reads, and the merge log that outlives the dialog.
    #>
    param(
        [Parameter(Mandatory)][string[]]$ColumnNames,
        [Parameter(Mandatory)]$PrimaryRows,
        [Parameter(Mandatory)]$AlignedRows,
        [Parameter(Mandatory)]$MergedRows,
        [string[]]$FilledColumns = @()
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $ColumnNames.Count; $i++) {
        $rows.Add([pscustomobject]@{
            Name      = $ColumnNames[$i]
            Before    = Get-ColumnStats -Rows $PrimaryRows -Index $i
            Secondary = if ($FilledColumns -contains $ColumnNames[$i]) { '(not in secondary - filled NAN)' }
                        else { Get-ColumnStats -Rows $AlignedRows -Index $i }
            After     = Get-ColumnStats -Rows $MergedRows -Index $i
        })
    }
    return $rows.ToArray()
}

function Show-ColumnStatsComparison {
    <#
        The proof shown before a RE-ORDERED secondary is written. Nothing has
        touched the disk at this point: the merge exists only in memory, so
        Decline here costs nothing.

        Per shared column, three distributions side by side - the primary on its
        own, the secondary's rows after alignment, and the merged result. A map
        that put values in the wrong column shows up immediately, because the
        secondary column reads like a different measurement than the primary
        column it sits beside (volts against degrees, a text column against a
        numeric one) and the merged column is visibly polluted by it.

        Returns 'Proceed' / 'Decline' / 'ExitAll', same vocabulary as the
        header comparison.
    #>
    param(
        [Parameter(Mandatory)][object[]]$StatRows,
        [string]$PrimaryName,
        [string]$SecondaryName,
        [string[]]$FilledColumns = @(),
        [string[]]$DroppedColumns = @()
    )

    $clrBg = [System.Drawing.Color]::FromArgb(250, 250, 252)
    $clrText = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $clrSubtle = [System.Drawing.Color]::FromArgb(110, 110, 120)
    $clrHeaderBg = [System.Drawing.Color]::FromArgb(45, 52, 64)
    $clrGreen = [System.Drawing.Color]::FromArgb(34, 139, 87)
    $clrRed = [System.Drawing.Color]::FromArgb(192, 57, 57)
    $fontUI = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontUIBold = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $fontMono = New-Object System.Drawing.Font("Consolas", 8.5)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Column Re-order Check"
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1180, 720)
    $form.MinimumSize = New-Object System.Drawing.Size(800, 500)
    $form.TopMost = $true
    $form.BackColor = $clrBg
    $form.Font = $fontUI

    $titleBar = New-Object System.Windows.Forms.Panel
    $titleBar.Dock = 'Top'
    $titleBar.Height = 58
    $titleBar.BackColor = $clrHeaderBg
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Columns were RE-ORDERED - check the numbers before writing"
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Dock = 'Fill'
    $lblTitle.TextAlign = 'MiddleLeft'
    $lblTitle.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0)
    $titleBar.Controls.Add($lblTitle)

    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 92
    $banner.BackColor = [System.Drawing.Color]::FromArgb(235, 241, 250)
    $banner.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Dock = 'Fill'
    $lblInfo.Font = $fontUI
    $lblInfo.ForeColor = $clrText
    $extra = @()
    if ($FilledColumns.Count -gt 0) { $extra += "$($FilledColumns.Count) column(s) filled with NAN: $($FilledColumns -join ', ')" }
    if ($DroppedColumns.Count -gt 0) { $extra += "$($DroppedColumns.Count) column(s) dropped: $($DroppedColumns -join ', ')" }
    $lblInfo.Text = ("Primary:      $PrimaryName`nSecondary:  $SecondaryName`n" +
        "Nothing has been written yet. Each column below should read like the same measurement in all three." +
        $(if ($extra.Count) { "`n" + ($extra -join '   |   ') } else { '' }))
    $banner.Controls.Add($lblInfo)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.ReadOnly = $true
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.BorderStyle = 'None'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.Font = $fontUI
    $grid.ScrollBars = 'Both'
    # Wrapped and row-sized rather than auto-widened. Six statistics per cell,
    # three cells per column: sized to content, the "Merged (after)" column - the
    # one the whole dialog exists to show - ends up off the right-hand edge, and
    # a check nobody scrolls to is a check nobody makes.
    $grid.AutoSizeColumnsMode = 'None'
    $grid.AutoSizeRowsMode = 'AllCells'
    $grid.DefaultCellStyle.WrapMode = 'True'
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(238, 240, 244)
    $grid.ColumnHeadersDefaultCellStyle.Font = $fontUIBold
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 251)

    [void]$grid.Columns.Add("Col", "#")
    [void]$grid.Columns.Add("Name", "Column")
    [void]$grid.Columns.Add("Before", "Primary only (before)")
    [void]$grid.Columns.Add("Sec", "Secondary, aligned")
    [void]$grid.Columns.Add("After", "Merged (after)")
    $grid.Columns["Col"].DefaultCellStyle.ForeColor = $clrSubtle
    $grid.Columns["Col"].Width = 38
    $grid.Columns["Name"].Width = 150
    $grid.Columns["Name"].DefaultCellStyle.Font = $fontUIBold
    foreach ($c in 'Before', 'Sec', 'After') {
        $grid.Columns[$c].DefaultCellStyle.Font = $fontMono
        $grid.Columns[$c].Width = 310
    }

    for ($i = 0; $i -lt $StatRows.Count; $i++) {
        $s = $StatRows[$i]
        $rowIndex = $grid.Rows.Add(($i + 1), $s.Name, $s.Before, $s.Secondary, $s.After)
        if ($FilledColumns -contains $s.Name) {
            $grid.Rows[$rowIndex].Cells["Sec"].Style.ForeColor = $clrSubtle
        }
    }

    $gridHost = New-Object System.Windows.Forms.Panel
    $gridHost.Dock = 'Fill'
    $gridHost.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $gridHost.BackColor = $clrBg
    $gridHost.Controls.Add($grid)

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 64
    $panel.FlowDirection = 'RightToLeft'
    $panel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 247)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Numbers look right - Merge"
    $btnOk.Size = New-Object System.Drawing.Size(210, 36)
    $btnOk.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $btnOk.FlatStyle = 'Flat'
    $btnOk.FlatAppearance.BorderSize = 0
    $btnOk.BackColor = $clrGreen
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.Font = $fontUIBold
    $btnOk.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "Decline (Skip File)"
    $btnNo.Size = New-Object System.Drawing.Size(160, 36)
    $btnNo.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No
    $btnNo.FlatStyle = 'Flat'
    $btnNo.BackColor = [System.Drawing.Color]::White
    $btnNo.ForeColor = $clrText
    $btnNo.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = "Exit All (Stop Everything)"
    $btnExit.Size = New-Object System.Drawing.Size(180, 36)
    $btnExit.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnExit.DialogResult = [System.Windows.Forms.DialogResult]::Abort
    $btnExit.FlatStyle = 'Flat'
    $btnExit.BackColor = [System.Drawing.Color]::FromArgb(253, 240, 240)
    $btnExit.ForeColor = $clrRed
    $btnExit.Cursor = [System.Windows.Forms.Cursors]::Hand

    $panel.Controls.Add($btnOk)
    $panel.Controls.Add($btnNo)
    $panel.Controls.Add($btnExit)

    $form.Controls.Add($gridHost)
    $form.Controls.Add($panel)
    $form.Controls.Add($banner)
    $form.Controls.Add($titleBar)
    # Decline is the default: a re-order is meant to be read, not Enter-ed past.
    $form.AcceptButton = $btnNo
    $form.CancelButton = $btnNo

    $result = $form.ShowDialog()
    $form.Dispose()

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) { return 'Proceed' }
        ([System.Windows.Forms.DialogResult]::Abort) { return 'ExitAll' }
        default { return 'Decline' }
    }
}

function Test-NonAsciiCharacters {
    # -NoPrompt reports and returns $true instead of asking. A dry run must not
    # block on a console prompt, and it is not deciding anything anyway.
    param([string]$FilePath, [switch]$NoPrompt)

    $lines = Get-Content $FilePath
    $nonAsciiLines = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '[^\x00-\x7F]') {
            $nonAsciiLines += ($i + 1)
        }
    }

    if ($nonAsciiLines.Count -gt 0) {
        Write-Warning "Non-ASCII characters found in '$FilePath' on lines: $($nonAsciiLines -join ', ')"
        if ($NoPrompt) { return $true }
        $response = Read-Host "Do you want to continue? (Y/N)"
        return ($response -match '^(y|yes)$')
    }

    return $true
}

function Backup-File {
    param(
        [string]$FilePath,
        [string]$BackupFolder
    )

    if (-not (Test-Path $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
        Write-Verbose "Created backup folder: $BackupFolder"
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $backupName = [System.IO.Path]::GetFileNameWithoutExtension($fileName) + "_$timestamp" + [System.IO.Path]::GetExtension($fileName)
    $backupPath = Join-Path $BackupFolder $backupName

    Copy-Item -Path $FilePath -Destination $backupPath -Force
    Write-Host "  Backed up to: $backupPath" -ForegroundColor Green

    return $backupPath
}

function Select-FolderDialog {
    param(
        [string]$Description = "Select a folder",
        [string]$InitialDir
    )

    # Use the modern Explorer-style OpenFileDialog in "folder pick" mode instead
    # of the classic FolderBrowserDialog tree. This gives an address bar, shows
    # "This PC" with mapped network drives, and lets you type / paste a path
    # (including UNC paths such as \\server\share).
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "$Description  -  open any folder, then click 'Select Folder'"
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.Multiselect = $false
    # A filter that matches no real files so only folders are shown to navigate.
    $dlg.Filter = "Folders|*.__select_folder__"
    $dlg.FileName = "Select Folder"
    if ($InitialDir -and (Test-Path $InitialDir)) {
        $dlg.InitialDirectory = $InitialDir
    }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # The returned FileName is "<chosen folder>\Select Folder"; strip the leaf.
        $selected = [System.IO.Path]::GetDirectoryName($dlg.FileName)
        if ([string]::IsNullOrWhiteSpace($selected)) {
            $selected = $dlg.FileName
        }
        if ($selected -and (Test-Path $selected -PathType Container)) {
            return $selected
        }
        Write-Warning "Selected path is not a valid folder: $selected"
        return $null
    }
    return $null
}

function Show-Notification {
    param(
        [string]$Message,
        [string]$Title = "Notice",
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK, $Icon
    ) | Out-Null
}

function Confirm-RecencyOverride {
    <#
        The "are you sure?" for a primary that is not the newer file.

        Built as a form rather than a MessageBox for two reasons. It reads like
        the rest of the tool - same dark title bar, same status banner, same grid
        - and a grid can put the two checks side by side and mark the one that
        failed, which a wall of MessageBox prose cannot. The user's question here
        is "which of the two is wrong, and by how much", and that is a table.

        Defaults to No, and No is also what Esc and the close box give. Someone
        clicking through dialogs should not be able to merge backwards by holding
        Enter.

        Returns $true only for an explicit Yes.
    #>
    param(
        [string]$PrimaryName,
        [string]$SecondaryName,
        [Parameter(Mandatory)]$Recency
    )

    $clrBg = [System.Drawing.Color]::FromArgb(250, 250, 252)
    $clrText = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $clrSubtle = [System.Drawing.Color]::FromArgb(110, 110, 120)
    $clrHeaderBg = [System.Drawing.Color]::FromArgb(45, 52, 64)
    $clrGreen = [System.Drawing.Color]::FromArgb(34, 139, 87)
    $clrRed = [System.Drawing.Color]::FromArgb(192, 57, 57)
    $clrAmber = [System.Drawing.Color]::FromArgb(176, 106, 20)
    $clrDiff = [System.Drawing.Color]::FromArgb(253, 235, 236)
    $fontUI = New-Object System.Drawing.Font("Segoe UI", 9)
    $fontUIBold = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
    $fontBanner = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
    $fontMono = New-Object System.Drawing.Font("Consolas", 9)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Are you sure?  -  the primary is not the newer file"
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(860, 560)
    $form.MinimumSize = New-Object System.Drawing.Size(700, 470)
    $form.TopMost = $true
    $form.BackColor = $clrBg
    $form.Font = $fontUI

    # --- Title bar (dark) ---
    $titleBar = New-Object System.Windows.Forms.Panel
    $titleBar.Dock = 'Top'
    $titleBar.Height = 58
    $titleBar.BackColor = $clrHeaderBg
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Are you sure?"
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Dock = 'Fill'
    $lblTitle.TextAlign = 'MiddleLeft'
    $lblTitle.Padding = New-Object System.Windows.Forms.Padding(18, 0, 0, 0)
    $lblTag = New-Object System.Windows.Forms.Label
    $lblTag.Text = "Recency check"
    $lblTag.Font = $fontUIBold
    $lblTag.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 225)
    $lblTag.Dock = 'Right'
    $lblTag.Width = 140
    $lblTag.TextAlign = 'MiddleRight'
    $lblTag.Padding = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)
    $titleBar.Controls.Add($lblTitle)
    $titleBar.Controls.Add($lblTag)

    # --- Status banner (red) ---
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 84
    $banner.BackColor = [System.Drawing.Color]::FromArgb(253, 237, 237)
    $banner.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 10)
    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Dock = 'Top'
    $lblStatus.Height = 24
    $lblStatus.Font = $fontBanner
    $lblStatus.ForeColor = $clrRed
    $lblStatus.Text = "The primary is NOT newer than the file being merged into it."
    $lblFiles = New-Object System.Windows.Forms.Label
    $lblFiles.Dock = 'Fill'
    $lblFiles.Font = $fontUI
    $lblFiles.ForeColor = $clrText
    $lblFiles.Text = "Primary:      $PrimaryName`nSecondary:  $SecondaryName"
    $banner.Controls.Add($lblFiles)
    $banner.Controls.Add($lblStatus)

    # --- The two checks, side by side ---
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.ReadOnly = $true
    $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.BorderStyle = 'None'
    $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.GridColor = [System.Drawing.Color]::FromArgb(232, 234, 238)
    $grid.Font = $fontUI
    $grid.RowTemplate.Height = 30
    $grid.ColumnHeadersHeight = 34
    $grid.ColumnHeadersBorderStyle = 'None'
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(238, 240, 244)
    $grid.ColumnHeadersDefaultCellStyle.Font = $fontUIBold
    $grid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    # Selection is neutralised. There are exactly two rows and nothing to select;
    # a highlighted first row would paint over the red that marks the failing
    # check, which is the only thing on screen the user needs to see.
    $grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::White
    $grid.DefaultCellStyle.SelectionForeColor = $clrText
    [void]$grid.Columns.Add("Check", "Check")
    [void]$grid.Columns.Add("Primary", "Primary")
    [void]$grid.Columns.Add("Secondary", "Secondary")
    [void]$grid.Columns.Add("Status", "Status")
    # The two value columns hold a fixed-width timestamp and nothing else, so the
    # words get the room: an elided "File modifie..." against "FAILED - ..." is a
    # dialog that has stopped saying anything.
    $grid.Columns["Check"].FillWeight = 26
    $grid.Columns["Primary"].FillWeight = 22
    $grid.Columns["Secondary"].FillWeight = 22
    $grid.Columns["Status"].FillWeight = 30
    $grid.Columns["Primary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Secondary"].DefaultCellStyle.Font = $fontMono

    $fmt = 'yyyy-MM-dd HH:mm:ss'
    $addCheck = {
        param($label, $primary, $secondary, $ok, $failText)
        $status = if ($ok) { "OK - primary newer" } else { $failText }
        $i = $grid.Rows.Add($label, $primary, $secondary, $status)
        $row = $grid.Rows[$i]
        $row.Cells["Status"].Style.Font = $fontUIBold
        # Selection colours are set alongside every normal colour. The grid
        # always has a current row, and without this the red on whichever row
        # happens to be selected - row 1, always - is painted over by it.
        if ($ok) {
            $row.Cells["Status"].Style.ForeColor = $clrGreen
            $row.Cells["Status"].Style.SelectionForeColor = $clrGreen
        }
        else {
            $row.Cells["Status"].Style.ForeColor = $clrRed
            $row.Cells["Status"].Style.SelectionForeColor = $clrRed
            foreach ($c in 'Primary', 'Secondary') {
                $row.Cells[$c].Style.BackColor = $clrDiff
                $row.Cells[$c].Style.SelectionBackColor = $clrDiff
            }
        }
    }
    & $addCheck "File modified time" `
        $Recency.PrimaryModified.ToString($fmt) $Recency.SecondaryModified.ToString($fmt) `
        $Recency.MtimeOk "FAILED - secondary is not older"
    & $addCheck "Last timestamp in file" `
        $Recency.PrimaryLastTs $Recency.SecondaryLastTs `
        $Recency.TsOk $(if ($Recency.TsComparable) { "FAILED - secondary is not older" } else { "CANNOT COMPARE - not YYYY-MM-DD" })

    $gridHost = New-Object System.Windows.Forms.Panel
    $gridHost.Dock = 'Fill'
    $gridHost.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $gridHost.BackColor = $clrBg
    $gridHost.Controls.Add($grid)

    # --- What it probably means ---
    $explain = New-Object System.Windows.Forms.Panel
    $explain.Dock = 'Bottom'
    $explain.Height = 132
    $explain.BackColor = $clrBg
    $explain.Padding = New-Object System.Windows.Forms.Padding(18, 6, 18, 12)
    $lblWhy = New-Object System.Windows.Forms.Label
    $lblWhy.Dock = 'Fill'
    $lblWhy.Font = $fontUI
    $lblWhy.ForeColor = $clrSubtle
    $lblWhy.Text = (
        "The primary is expected to be newer on BOTH counts: it is the file automatic collection keeps " +
        "appending to, so it holds the latest reading and was written most recently.`n`n" +
        "A failure usually means the two files are the wrong way round - the newer data is in the " +
        "secondary. Merging it into the primary would leave the combined result in a file nothing is " +
        "collecting into, where the next collection will not find it.`n`n" +
        "Merging anyway is recorded in the merge log. Column alignment stays unavailable either way."
    )
    $explain.Controls.Add($lblWhy)

    # --- Buttons ---
    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 64
    $panel.FlowDirection = 'RightToLeft'
    $panel.WrapContents = $false
    $panel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $panel.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 247)

    # The safe answer is the prominent one on the right, and the risky answer
    # wears the warning colours. This is the one dialog in the tool where the
    # rightmost button is NOT "carry on" - deliberately, because reflex is the
    # thing it exists to interrupt.
    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No - Skip This File"
    $btnNo.Size = New-Object System.Drawing.Size(180, 36)
    $btnNo.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnNo.DialogResult = [System.Windows.Forms.DialogResult]::No
    $btnNo.FlatStyle = 'Flat'
    $btnNo.FlatAppearance.BorderSize = 0
    $btnNo.BackColor = $clrGreen
    $btnNo.ForeColor = [System.Drawing.Color]::White
    $btnNo.Font = $fontUIBold
    $btnNo.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "Yes - Merge Anyway"
    $btnYes.Size = New-Object System.Drawing.Size(180, 36)
    $btnYes.Margin = New-Object System.Windows.Forms.Padding(8, 0, 8, 0)
    $btnYes.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $btnYes.FlatStyle = 'Flat'
    $btnYes.FlatAppearance.BorderSize = 1
    $btnYes.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(224, 188, 130)
    $btnYes.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 232)
    $btnYes.ForeColor = $clrAmber
    $btnYes.Font = $fontUI
    $btnYes.Cursor = [System.Windows.Forms.Cursors]::Hand

    $panel.Controls.Add($btnNo)
    $panel.Controls.Add($btnYes)

    # Fill first, then the docked panels - see Show-HeaderComparison. Among
    # controls sharing an edge the LAST added sits closest to it, so the buttons
    # go in after the explanation or they end up above it, with the explanation
    # running off the bottom of the window.
    $form.Controls.Add($gridHost)
    $form.Controls.Add($explain)
    $form.Controls.Add($panel)
    $form.Controls.Add($banner)
    $form.Controls.Add($titleBar)
    $form.AcceptButton = $btnNo
    $form.CancelButton = $btnNo

    $result = $form.ShowDialog()
    $form.Dispose()
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Get-Toa5EnvironmentFields {
    <#
        Returns the parsed row-1 (TOA5 environment line) fields of a data file, or
        $null when the file is unreadable / not a TOA5 file.

        TOA5 row 1 layout:
          0 "TOA5"  1 station  2 model  3 serial  4 os  5 program  6 signature  7 table
    #>
    param([string]$FilePath)

    try {
        $first = @(Get-Content -LiteralPath $FilePath -TotalCount 1 -ErrorAction Stop)
    }
    catch {
        return $null
    }

    if ($first.Count -eq 0 -or [string]::IsNullOrWhiteSpace($first[0])) { return $null }

    # Strip a UTF-8 BOM if the reader left one on the first character.
    $line = $first[0].TrimStart([char]0xFEFF)

    $fields = Split-CsvLine -Line $line
    if ($fields.Count -lt 8 -or $fields[0].Trim() -ne 'TOA5') { return $null }
    return $fields
}

function Get-DuplicateGroups {
    <#
        Scans the TOP LEVEL of a folder only (subfolders are never entered) and
        builds merge groups two ways:

        1) BACKUP SUFFIXES (by name) - files sharing the same canonical data-file
           name plus an extra suffix such as .bak, .backup, .backup1, .1, .old,
           .orig, .copy.

        2) SAME LOGGER, SAME TABLE (by TOA5 row 1) - data files whose row 1 gives
           the same MODEL, the same SERIAL and the same TABLE are one group,
           whatever they are named. Model is required because two different
           logger types can share a serial:
              18421_SAA_SAA1_DATA_2026-09-08.dat  ->  18421_SAA1_DATA.dat
           The dated downloads merge into the collected file. See
           Add-Toa5SerialTableGroups for how the primary is chosen and when a
           group is reported and skipped instead.

        Each returned group has:
          Key         - canonical data file name (e.g. Foo_SAA.dat)
          Primary     - full path of the canonical file (no backup suffix)
          Secondaries - list of full paths of the backup/duplicate files
    #>
    param([string]$Folder)

    $dataExt = 'dat|csv|txt'
    # One or more suffixes appended after the data extension, each marking a
    # backup/version. Repeated on purpose: LoggerNet stacks them, so a folder
    # holds Foo.dat.backup, Foo.dat.1.backup and Foo.dat.2.backup side by side.
    # A single-segment pattern matched only the first of those three.
    $suffixPattern = '^(\.(bak|backup\d*|\d+|old|orig|copy))+$'

    # Top-level files only - no -Recurse, so subfolders (Backup, scd,
    # superseded, and everything else) are never scanned.
    $allFiles = Get-ChildItem -Path $Folder -File -ErrorAction SilentlyContinue

    $groups = @{}

    foreach ($f in $allFiles) {
        $name = $f.Name
        # key = everything up to and including the first data extension; suffix = the rest
        if ($name -match "^(?<key>.*?\.(?:$dataExt))(?<suffix>\..+)?$") {
            $key = $Matches['key']
            $suffix = $Matches['suffix']
            $keyLower = $key.ToLowerInvariant()

            if (-not $groups.ContainsKey($keyLower)) {
                $groups[$keyLower] = [pscustomobject]@{
                    Key         = $key
                    Primary     = $null
                    Secondaries = [System.Collections.Generic.List[string]]::new()
                }
            }

            if ([string]::IsNullOrEmpty($suffix)) {
                # Exact data file (no trailing suffix) = the primary to retain.
                if (-not $groups[$keyLower].Primary) {
                    $groups[$keyLower].Primary = $f.FullName
                }
            }
            elseif ($suffix -match $suffixPattern) {
                $groups[$keyLower].Secondaries.Add($f.FullName)
            }
        }
    }

    # Second pass: same model + serial + table per TOA5 row 1.
    Add-Toa5SerialTableGroups -AllFiles $allFiles -Groups $groups -DataExt $dataExt

    # Only return groups that actually have a primary AND at least one duplicate.
    return $groups.Values | Where-Object { $_.Primary -and $_.Secondaries.Count -gt 0 }
}

function Add-Toa5SerialTableGroups {
    <#
        Adds local manual downloads and remote manual collections of a logger table to the merge
        groups, matched ONLY on the three pieces of hard evidence the datalogger
        itself wrote into TOA5 row 1:

            "TOA5","TM_MCL-02","CR6","13910","CR6.Std.14.01","prog.cr6","31248","Status"
             0      1 station    2 MODEL  3 SERIAL 4          5          6       7 TABLE

        Two files belong to the same group when row 1 gives them the SAME MODEL,
        the SAME SERIAL and the SAME TABLE (case-insensitive) - and they share
        an extension, so a merge never changes what kind of file the folder
        holds. Model is in the key because two different logger types can share
        a serial. The file NAME is not consulted for matching at all, so every
        naming convention works:

            18421_SAA_SAA1_DATA_2026-09-08.dat  ->  18421_SAA1_DATA.dat
            13910_Status_2026-07-23T15-44.dat   ->  TM_MCL-02_Status.dat
            SAA1_DATA (1).dat                   ->  18421_SAA1_DATA.dat

        WHICH FILE IS THE PRIMARY
        The primary must be the file the logger software keeps appending to -
        merging the other way round leaves the newly merged rows in a file
        nothing collects into. Model, serial and table cannot tell those apart
        (they are identical by definition here), so exactly one name-shaped rule decides
        the ROLE, never the match: a file whose name ends in a download date
        stamp (_YYYY-MM-DD, optionally with a time) is a download, and anything
        else is a collected file.

          * exactly one collected file in the group -> it is the primary and
            every dated download merges into it, oldest stamp first;
          * two or more collected files (two archives of one table in one
            folder) -> reported and skipped, never merged into a guess;
          * dated downloads only, no collected file -> reported and skipped;
            which download should become the archive is the user's call.

        Files with no readable TOA5 row 1 carry no model, serial or table, so they
        take no part in this pass (backup-suffix matching still covers them).

        $Groups is mutated in place (hashtable keyed by lowercase primary name).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllFiles,
        [Parameter(Mandatory)][hashtable]$Groups,
        [Parameter(Mandatory)][string]$DataExt
    )

    # A trailing download stamp: _2026-09-08, _2026-09-08T15-44, _2026-09-08T15-44-30,
    # and the underscore / dotted-time variants LoggerNet produces for automatic
    # collection, local manual downloads and remote manual collections.
    $stampSuffix = '_(?<stamp>\d{4}-\d{2}-\d{2}(?:[T_]\d{2}[-.]\d{2}(?:[-.]\d{2})?)?)$'

    # Every top-level data file that actually carries a TOA5 row 1. Row 1 is read
    # once per file - these folders often live on a slow network share.
    $members = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $AllFiles) {
        # The data extension must be LAST, so backup copies (Foo.dat.bak, Foo.dat.1)
        # fail here and stay with the backup-suffix pass that owns them.
        if ($f.Name -notmatch "^(?<base>.+)\.(?<ext>$DataExt)$") { continue }
        # Read $Matches before anything else can overwrite it.
        $base = $Matches['base']
        $ext = $Matches['ext'].ToLowerInvariant()

        $fields = Get-Toa5EnvironmentFields -FilePath $f.FullName
        if (-not $fields) { continue }
        $model = $fields[2].Trim()
        $serial = $fields[3].Trim()
        $table = $fields[7].Trim()
        if ([string]::IsNullOrWhiteSpace($model) -or
            [string]::IsNullOrWhiteSpace($serial) -or
            [string]::IsNullOrWhiteSpace($table)) { continue }

        $stamp = if ($base -match $stampSuffix) { $Matches['stamp'] } else { $null }

        $members.Add([pscustomobject]@{
            File   = $f
            Model  = $model
            Serial = $serial
            Table  = $table
            Ext    = $ext
            Stamp  = $stamp
        })
    }
    if ($members.Count -lt 2) { return }

    # Group on model + serial + table + extension, and nothing else.
    $sets = @{}
    foreach ($m in $members) {
        $key = '{0}|{1}|{2}|{3}' -f $m.Model.ToLowerInvariant(), $m.Serial.ToLowerInvariant(), $m.Table.ToLowerInvariant(), $m.Ext
        if (-not $sets.ContainsKey($key)) {
            $sets[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $sets[$key].Add($m)
    }

    foreach ($key in @($sets.Keys | Sort-Object)) {
        $set = @($sets[$key])
        if ($set.Count -lt 2) { continue }

        $label = "model $($set[0].Model), serial $($set[0].Serial), table '$($set[0].Table)' (.$($set[0].Ext))"
        $collected = @($set | Where-Object { -not $_.Stamp })
        # Oldest download first so merges happen in chronological order.
        $downloads = @(
            $set |
                Where-Object { $_.Stamp } |
                Sort-Object -Property @{ Expression = { $_.Stamp } }, @{ Expression = { $_.File.Name } }
        )

        if ($collected.Count -eq 0) {
            $names = ($downloads | ForEach-Object { $_.File.Name }) -join ', '
            Write-Warning ("Skipped $label`: every file is a dated download and none is the " +
                "collected file ($names). Merge them manually.")
            continue
        }
        if ($collected.Count -gt 1) {
            $names = ($collected | ForEach-Object { $_.File.Name }) -join ', '
            Write-Warning ("Skipped $label`: more than one file could be the collected file " +
                "($names). Merge them manually.")
            continue
        }
        if ($downloads.Count -eq 0) { continue }

        $primaryFile = $collected[0].File
        $keyLower = $primaryFile.Name.ToLowerInvariant()
        if (-not $Groups.ContainsKey($keyLower)) {
            $Groups[$keyLower] = [pscustomobject]@{
                Key         = $primaryFile.Name
                Primary     = $primaryFile.FullName
                Secondaries = [System.Collections.Generic.List[string]]::new()
            }
        }
        if (-not $Groups[$keyLower].Primary) { $Groups[$keyLower].Primary = $primaryFile.FullName }

        foreach ($d in $downloads) {
            # A download that is itself a primary elsewhere (it has its own .bak)
            # would be merged into and then moved to Backup in the same scan.
            $dKey = $d.File.Name.ToLowerInvariant()
            if ($Groups.ContainsKey($dKey) -and $Groups[$dKey].Secondaries.Count -gt 0 -and
                $Groups[$dKey].Primary -eq $d.File.FullName) {
                Write-Warning ("Skipped '$($d.File.Name)' as a secondary of " +
                    "'$($primaryFile.Name)': it has backup copies of its own and is merged " +
                    "as a primary in this scan. Merge it into '$($primaryFile.Name)' afterwards.")
                continue
            }
            if (-not $Groups[$keyLower].Secondaries.Contains($d.File.FullName)) {
                $Groups[$keyLower].Secondaries.Add($d.File.FullName)
            }
        }
    }
}


function Invoke-CombineForPrimary {
    <#
        Combines one or more secondary files into a single primary file.
        Performs the two-step comparison (row 2 header, then row 1 file info),
        merges/de-duplicates data, and moves merged secondaries to Backup.

        With -AutoProceedOnHeaderMatch, an identical row-2 header skips the
        header dialog, notifies the user, and proceeds directly to the row-1
        file-info comparison.

        With -DryRun nothing is written, moved or backed up and no dialog is
        shown: the two comparisons are made in code and reported, so the numbers
        are what a real run would produce.

        Returns an object with FilesProcessed, RowsAdded, FinalRows, TsConflicts,
        Warnings, LogPath, PrimaryPath, Aborted. Aborted is $true when the user
        pressed "Exit All", meaning the caller should stop processing any
        remaining primaries/groups too.
    #>
    param(
        [Parameter(Mandatory)][string]$PrimaryPath,
        [Parameter(Mandatory)][string[]]$SecondaryPaths,
        [int]$SpecialRowCount = 3,
        [string]$Encoding = 'Auto',
        [switch]$NoBackup,
        [switch]$AutoProceedOnHeaderMatch,
        [switch]$DryRun
    )

    $result = [pscustomobject]@{
        FilesProcessed = 0
        RowsAdded      = 0
        FinalRows      = 0
        TsConflicts    = 0
        Warnings       = [System.Collections.Generic.List[string]]::new()
        LogPath        = $null
        PrimaryPath    = $PrimaryPath
        Aborted        = $false
    }

    if (-not (Test-Path $PrimaryPath)) {
        Write-Warning "Primary file not found: $PrimaryPath"
        return $result
    }

    Start-MergeTimer
    $linesPrimary = Read-DataFileLines $PrimaryPath
    if ($linesPrimary.Count -lt 2) {
        Write-Warning "Primary '$PrimaryPath' needs at least 2 lines. Skipping."
        return $result
    }

    if ($Encoding -eq 'ASCII' -and -not (Test-NonAsciiCharacters -FilePath $PrimaryPath)) {
        Write-Host "Skipping primary (non-ASCII declined): $PrimaryPath" -ForegroundColor Yellow
        return $result
    }

    # Parse primary structure
    $specialCountPrimary = [Math]::Min($SpecialRowCount, $linesPrimary.Count - 1)
    $originalHeader = $linesPrimary[0]
    # @() so a single special row stays an array. Without it $linesPrimary[1..1]
    # is one string, and $originalSpecials[0] then indexes a character out of it
    # rather than returning row 2 - which is the row the comparison hinges on.
    $originalSpecials = @(if ($specialCountPrimary -gt 0) { $linesPrimary[1..$specialCountPrimary] } else { @() })
    $dataStartIndex = $specialCountPrimary + 1
    $currentData = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Indexed loop rather than $linesPrimary[$dataStartIndex..($count-1)]: the
    # range operator copies the whole tail of the array first, which on a 20,000
    # row file of wide rows is a pointless second copy of the file.
    for ($i = $dataStartIndex; $i -lt $linesPrimary.Count; $i++) {
        $line = $linesPrimary[$i]
        if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$currentData.Add($line) }
    }

    $primaryName = [System.IO.Path]::GetFileName($PrimaryPath)
    Write-Host "`nPrimary: $primaryName  ($($currentData.Count) unique data rows)" -ForegroundColor Cyan

    # Recency is measured ONCE, here, against the primary as it was found.
    # Re-reading it per secondary would be wrong: the first merge rewrites the
    # primary, so its modified time becomes "just now" and every later secondary
    # would sail through a check that has stopped meaning anything.
    $primaryModified = (Get-Item -LiteralPath $PrimaryPath).LastWriteTime
    $primaryLastTs = Get-LastDataTimestamp -Lines $linesPrimary -DataStartIndex $dataStartIndex

    $log = [System.Collections.Generic.List[string]]::new()
    $log.Add("Combine DAT Files - merge log")
    $log.Add("Generated:      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $log.Add("Primary:        $PrimaryPath")
    $log.Add("Rows before:    $($currentData.Count)")
    $log.Add("Header rows:    row 1 plus $specialCountPrimary special row(s)")
    $log.Add("Encoding:       $Encoding")
    $log.Add("Dry run:        $([bool]$DryRun)")
    $log.Add('')

    # Field count comes from row 2 - the column names - which is the row a
    # data row has to line up with.
    $headerFieldCount = (Split-CsvLine -Line $(
            if ($originalSpecials.Count -ge 1) { $originalSpecials[0] } else { $originalHeader }
        )).Count

    # The primary's own first data row is checked too: a text sort that is wrong
    # for the primary is wrong for the merged result regardless of the secondaries.
    if ($linesPrimary.Count -gt $dataStartIndex) {
        $pTs = Get-FirstFieldRaw -Line $linesPrimary[$dataStartIndex]
        if ($pTs -notmatch '^\d{4}-\d{2}-\d{2}') {
            $msg = "Primary '$primaryName' first data timestamp is '$pTs', not YYYY-MM-DD. Rows are sorted as TEXT, so the merged order will be wrong for this format."
            Write-Warning $msg
            $result.Warnings.Add($msg)
        }
    }

    $backupFolder = Join-Path (Split-Path -Parent $PrimaryPath) "Backup"
    $primaryBackupPath = $null
    if ($DryRun) {
        Write-Host "DRY RUN - nothing will be written, moved or backed up." -ForegroundColor Yellow
    }
    elseif (-not $NoBackup) {
        $primaryBackupPath = Backup-File -FilePath $PrimaryPath -BackupFolder $backupFolder
    }

    $filesProcessed = 0
    $totalRowsAdded = 0
    $aborted = $false
    # The last write's sorted rows, reused for the conflict scan so the merged
    # set is not sorted a second time.
    $lastSorted = $null

    $log.Add("Per-file detail (rows read / new unique rows contributed):")

    foreach ($secondaryPath in $SecondaryPaths) {
        Write-Host "`n$('=' * 70)" -ForegroundColor DarkGray
        Write-Host "Processing secondary: $secondaryPath" -ForegroundColor Cyan
        Write-Host "$('=' * 70)" -ForegroundColor DarkGray

        if (-not (Test-Path $secondaryPath)) {
            Write-Warning "Secondary not found: $secondaryPath"
            continue
        }

        $secondaryName = [System.IO.Path]::GetFileName($secondaryPath)
        $secondaryLines = Read-DataFileLines $secondaryPath

        if ($secondaryLines.Count -lt 2) {
            Write-Warning "Skipping - file needs at least 2 lines (header + data)."
            continue
        }

        if ($Encoding -eq 'ASCII' -and -not (Test-NonAsciiCharacters -FilePath $secondaryPath -NoPrompt:$DryRun)) {
            Write-Host "Skipping (non-ASCII declined): $secondaryName" -ForegroundColor Yellow
            continue
        }

        $header2 = $secondaryLines[0]
        $specialCount2 = [Math]::Min($SpecialRowCount, $secondaryLines.Count - 1)
        # @() for the same reason as the primary's specials, and because a
        # secondary holding exactly one data row is completely ordinary.
        $specials2 = @(if ($specialCount2 -gt 0) { $secondaryLines[1..$specialCount2] } else { @() })
        $dataStart2 = $specialCount2 + 1
        $data2 = @(if ($secondaryLines.Count -gt $dataStart2) { $secondaryLines[$dataStart2..($secondaryLines.Count - 1)] } else { @() })

        $primaryRow2 = if ($originalSpecials.Count -ge 1) { $originalSpecials[0] } else { $originalHeader }
        $secondaryRow2 = if ($specials2.Count -ge 1) { $specials2[0] } else { $header2 }

        # Shape checks on this file's FIRST data row only. Running them on every
        # row costs more than the merge itself, and a file that is malformed is
        # malformed from its first row.
        if ($data2.Count -gt 0) {
            $sTs = Get-FirstFieldRaw -Line $data2[0]
            if ($sTs -notmatch '^\d{4}-\d{2}-\d{2}') {
                $msg = "'$secondaryName' first data timestamp is '$sTs', not YYYY-MM-DD. Rows are sorted as TEXT, so merging it will mis-order the primary."
                Write-Warning $msg
                $result.Warnings.Add($msg)
            }
            $sFields = (Split-CsvLine -Line $data2[0]).Count
            if ($sFields -ne $headerFieldCount) {
                $msg = "'$secondaryName' first data row has $sFields field(s) but the header names $headerFieldCount. Its rows will not line up with the primary's - 'Align Columns & Merge' is the fix if the column names match."
                Write-Warning $msg
                $result.Warnings.Add($msg)
            }
        }

        # --- Is the primary actually the newer file? ---
        # Both halves must say yes. When they do not, this is very likely a
        # merge the wrong way round - see Test-PrimaryIsNewer.
        $secondaryModified = (Get-Item -LiteralPath $secondaryPath).LastWriteTime
        $secondaryLastTs = Get-LastDataTimestamp -Lines $secondaryLines -DataStartIndex $dataStart2
        $recency = Test-PrimaryIsNewer `
            -PrimaryModified   $primaryModified `
            -SecondaryModified $secondaryModified `
            -PrimaryLastTs     $primaryLastTs `
            -SecondaryLastTs   $secondaryLastTs

        # --- Could the secondary's columns be shifted into the primary's order? ---
        $align = Get-ColumnAlignment -PrimaryHeaderRow $primaryRow2 -SecondaryHeaderRow $secondaryRow2
        # Aligning has NO "are you sure". Rewriting every field of every row is
        # only ever safe in the direction old-archive -> live-file, and the
        # recency check is the only evidence of which direction that is. No
        # evidence, no alignment; the file is skipped and the scan moves on.
        $alignOffer = $null
        $alignBlocked = $null
        if ($align.NoOp) {
            # Headers already agree column for column - nothing to shift.
        }
        elseif (-not $recency.Ok) {
            $alignBlocked = "the primary is not newer than the secondary ($($recency.Reason)). Column shifting is not offered, and cannot be overridden."
        }
        elseif (-not $align.Ok) {
            $alignBlocked = $align.Reason
        }
        else {
            $bits = @()
            if ($align.Reordered) { $bits += "re-order $($align.Map.Count) column(s)" }
            if ($align.Filled.Count -gt 0) { $bits += "add $($align.Filled.Count) column(s) as NAN ($($align.Filled -join ', '))" }
            if ($align.Dropped.Count -gt 0) { $bits += "drop $($align.Dropped.Count) column(s) ($($align.Dropped -join ', '))" }
            $alignOffer = ($bits -join '; ') + '.'
        }

        # A dry run decides nothing and shows nothing: the two comparisons the
        # dialogs would put to you are made in code and reported instead.
        if ($DryRun) {
            $row2Same = ($primaryRow2 -eq $secondaryRow2)
            $row1Same = ($originalHeader -eq $header2)

            if (-not $recency.Ok) {
                Write-Host "  RECENCY CHECK FAILED: $($recency.Reason)" -ForegroundColor Yellow
                Write-Host "    $($recency.Summary -replace "`n", "`n    ")" -ForegroundColor DarkGray
                Write-Host "    A real run would ask 'are you sure?' before merging this file." -ForegroundColor DarkGray
                $log.Add("  RECENCY  $secondaryPath  -  $($recency.Reason)")
                $result.Warnings.Add("'$secondaryName': $($recency.Reason)")
            }

            if (-not $row2Same) {
                Write-Host "  WOULD ASK: header row (row 2) differs - a real run opens the comparison dialog here." -ForegroundColor Yellow
                if ($alignOffer) {
                    Write-Host "    'Align Columns & Merge' would be offered: $alignOffer" -ForegroundColor Cyan
                    $log.Add("  WOULD ASK  $secondaryPath  -  row 2 differs; align available: $alignOffer")
                }
                else {
                    Write-Host "    'Align Columns & Merge' would be UNAVAILABLE: $alignBlocked" -ForegroundColor DarkGray
                    $log.Add("  WOULD ASK  $secondaryPath  -  row 2 differs; align unavailable: $alignBlocked")
                }
                Write-Host "  Not counted below, because the answer would be yours." -ForegroundColor DarkGray
                continue
            }

            $rowsBefore = $currentData.Count
            foreach ($line in $data2) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$currentData.Add($line) }
            }
            $wouldAdd = $currentData.Count - $rowsBefore
            $totalRowsAdded += $wouldAdd
            $filesProcessed++

            Write-Host "  WOULD MERGE: $secondaryName" -ForegroundColor Green
            Write-Host "    row 2 matches$(if ($row1Same) { ', row 1 matches' } else { ', row 1 differs - a real run would ask about it' })" -ForegroundColor DarkGray
            Write-Host "    would add $wouldAdd new unique row(s); primary would hold $($currentData.Count)" -ForegroundColor DarkGray
            Write-Host "    would move to: $(Join-Path $backupFolder $secondaryName)" -ForegroundColor DarkGray
            $log.Add("  WOULD MERGE  $secondaryPath  -  read $($data2.Count), new $wouldAdd")
            continue
        }

        # STEP 0: the primary must be the newer file, on both counts.
        # Asked before the header dialogs rather than after them, because it is a
        # question about the whole merge: if the answer is no, the two header
        # comparisons were never worth reading.
        if (-not $recency.Ok) {
            $msg = "'$secondaryName' is not older than the primary - $($recency.Reason)"
            Write-Warning $msg
            $sure = Confirm-RecencyOverride `
                -PrimaryName   $primaryName `
                -SecondaryName $secondaryName `
                -Recency       $recency
            if (-not $sure) {
                Write-Host "Skipping $secondaryName (declined at the recency check)" -ForegroundColor Yellow
                $log.Add("  DECLINED $secondaryPath  -  recency check: $($recency.Reason)")
                continue
            }
            $result.Warnings.Add("$msg - merged anyway on confirmation.")
            $log.Add("  RECENCY  $secondaryPath  -  $($recency.Reason) - user confirmed")
        }

        $aligning = $false

        # STEP 1: Compare the header row (row 2).
        if ($AutoProceedOnHeaderMatch -and ($primaryRow2 -eq $secondaryRow2)) {
            Write-Host "Header row (row 2) MATCHES - auto-proceeding to file-info comparison." -ForegroundColor Green
            Show-Notification -Title "Header Row Matches" -Message (
                "The header row (row 2) matches.`n`nPrimary:      $primaryName`nSecondary:  $secondaryName`n`nProceeding to the file-info (row 1) comparison."
            )
            $row2Choice = 'Proceed'
        }
        else {
            $row2Choice = Show-HeaderComparison `
                -PrimaryHeader   $primaryRow2 `
                -SecondaryHeader $secondaryRow2 `
                -PrimaryName     $primaryName `
                -SecondaryName   $secondaryName `
                -RowNumber       2 `
                -ComparisonTitle "Step 1 of 2: Header Row Comparison" `
                -AlignOffer         $alignOffer `
                -AlignBlockedReason $alignBlocked
        }

        if ($row2Choice -eq 'ExitAll') {
            Write-Host "Exit All requested at header row comparison. Stopping." -ForegroundColor Yellow
            $aborted = $true
            break
        }
        if ($row2Choice -eq 'Align') { $aligning = $true }
        elseif ($row2Choice -ne 'Proceed') {
            Write-Host "Skipping $secondaryName (declined at header row comparison)" -ForegroundColor Yellow
            continue
        }
        elseif ($alignBlocked) {
            # Headers differ and alignment is unavailable. Proceeding would put
            # fields under the wrong names. Same outcome as Decline - the dialog
            # also disables Proceed in this case, so this is the backstop.
            Write-Host "Skipping $secondaryName (alignment unavailable: $alignBlocked)" -ForegroundColor Yellow
            $log.Add("  SKIPPED  $secondaryPath  -  alignment unavailable: $alignBlocked")
            continue
        }

        # STEP 2: Compare the file info row (row 1).
        $fileInfoChoice = Show-HeaderComparison `
            -PrimaryHeader   $originalHeader `
            -SecondaryHeader $header2 `
            -PrimaryName     $primaryName `
            -SecondaryName   $secondaryName `
            -RowNumber       1 `
            -ComparisonTitle "Step 2 of 2: File Info Comparison"

        if ($fileInfoChoice -eq 'ExitAll') {
            Write-Host "Exit All requested at file info comparison. Stopping." -ForegroundColor Yellow
            $aborted = $true
            break
        }
        if ($fileInfoChoice -ne 'Proceed') {
            Write-Host "Skipping $secondaryName (declined at file info comparison)" -ForegroundColor Yellow
            continue
        }

        Write-Host "Both comparisons approved; merging data." -ForegroundColor Green

        # STEP 3 (only when asked for): shift the secondary's columns into the
        # primary's order. Row 2 of the secondary said what each of its fields
        # means; from here on the rows carry the primary's column order and
        # nothing downstream - de-duplication, sorting, the written file - needs
        # to know this file ever had a different shape.
        $mergeRows = $data2
        $alignNote = $null
        if ($aligning) {
            $aligned = [System.Collections.Generic.List[string]]::new($data2.Count)
            foreach ($line in $data2) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $aligned.Add((ConvertTo-AlignedRow -Line $line -Map $align.Map))
            }
            $mergeRows = $aligned.ToArray()

            $bits = @()
            if ($align.Reordered) { $bits += "columns re-ordered" }
            if ($align.Filled.Count -gt 0) { $bits += "filled with NAN: $($align.Filled -join ', ')" }
            if ($align.Dropped.Count -gt 0) { $bits += "DROPPED (not merged): $($align.Dropped -join ', ')" }
            $alignNote = "aligned to primary columns - " + ($bits -join '; ')
            Write-Host "  $alignNote" -ForegroundColor Cyan
            if ($align.Dropped.Count -gt 0) {
                $msg = "'$secondaryName': column(s) $($align.Dropped -join ', ') exist in the secondary but not the primary and were NOT merged. The whole secondary is filed under Backup\RemovedColumns-NotMerged so those values are still recoverable."
                Write-Warning $msg
                $result.Warnings.Add($msg)
            }
        }

        # Merge data. The added rows are tracked individually so a re-order that
        # the statistics dialog then rejects can be taken back out exactly -
        # rows that were already in the primary must not be removed with them.
        $rowsBefore = $currentData.Count
        $beforeRows = if ($aligning -and $align.Reordered) { @($currentData) } else { $null }
        $addedRows = if ($aligning -and $align.Reordered) { [System.Collections.Generic.List[string]]::new() } else { $null }
        foreach ($line in $mergeRows) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($currentData.Add($line) -and $addedRows) { $addedRows.Add($line) }
        }
        Show-SlowHintIfNeeded -WatchPath "$PrimaryPath.combining.tmp"

        # STEP 4: a re-order moves every value in the file, and a wrong map is
        # silent - the rows still parse, they are just lies. Show what the
        # numbers did before anything is written, and let it be refused.
        if ($aligning -and $align.Reordered) {
            Write-Host "  Columns were re-ordered - building the before/after column statistics..." -ForegroundColor Cyan
            $statRows = Get-ColumnStatsTable `
                -ColumnNames   @(Split-CsvLine -Line $primaryRow2 | ForEach-Object { $_.Trim() }) `
                -PrimaryRows   $beforeRows `
                -AlignedRows   $mergeRows `
                -MergedRows    $currentData `
                -FilledColumns $align.Filled

            $statsChoice = Show-ColumnStatsComparison `
                -StatRows        $statRows `
                -PrimaryName     $primaryName `
                -SecondaryName   $secondaryName `
                -FilledColumns   $align.Filled `
                -DroppedColumns  $align.Dropped

            if ($statsChoice -ne 'Proceed') {
                foreach ($r in $addedRows) { [void]$currentData.Remove($r) }
                if ($statsChoice -eq 'ExitAll') {
                    Write-Host "Exit All requested at the column re-order check. Stopping." -ForegroundColor Yellow
                    $log.Add("  DECLINED $secondaryPath  -  column re-order check, then Exit All")
                    $aborted = $true
                    break
                }
                Write-Host "Skipping $secondaryName (declined at the column re-order check)" -ForegroundColor Yellow
                $log.Add("  DECLINED $secondaryPath  -  column re-order statistics rejected")
                continue
            }
            $log.Add("  REORDER  $secondaryPath  -  re-order confirmed against the column statistics below")
            $log.Add("           column | primary before | secondary aligned | merged after")
            foreach ($s in $statRows) {
                $log.Add("           $($s.Name)")
                $log.Add("             before : $($s.Before)")
                $log.Add("             second : $($s.Secondary)")
                $log.Add("             after  : $($s.After)")
            }
        }

        $rowsAdded = $currentData.Count - $rowsBefore
        $totalRowsAdded += $rowsAdded

        Write-Host "Added $rowsAdded new unique row(s). Total: $($currentData.Count)" -ForegroundColor Green

        # Write updated primary and move secondary to backup
        $tempPath = $null
        try {
            Show-SlowHintIfNeeded -WatchPath "$PrimaryPath.combining.tmp"
            Write-Host "Sorting $($currentData.Count) rows..." -ForegroundColor DarkGray
            $sortedData = Get-SortedDataRows -Rows $currentData

            # Written with an explicit .NET encoding rather than
            # Set-Content -Encoding, whose 'UTF8' means with-BOM on PowerShell
            # 5.1 and without-BOM on 7. A stray BOM stops LoggerNet recognising
            # the file and makes it abandon it -- see Resolve-OutputEncoding.
            $enc = Resolve-OutputEncoding -Name $Encoding -FilePath $PrimaryPath

            # Streamed into a temp file and moved into place, rather than written
            # straight over the primary. Two reasons:
            #   1. Killing the script mid-write can no longer truncate the
            #      primary. Previously one interrupted WriteAllLines destroyed it.
            #   2. The temp file visibly grows, so there is something to watch
            #      when a merge is slow. The primary changes only at the very end,
            #      in one atomic move.
            $tempPath = "$PrimaryPath.combining.tmp"
            $written = 0
            # 1 MB buffer, explicitly. These files live on a network share, and
            # StreamWriter's default buffer is a few KB - smaller than a single
            # 275-column SAA row, so every WriteLine would become its own SMB
            # round-trip. Batching into 1 MB writes turns ~38,000 round-trips into
            # ~50, which over a VPN link is the difference between minutes and
            # seconds.
            $writer = New-Object System.IO.StreamWriter($tempPath, $false, $enc, 1048576)
            try {
                $writer.WriteLine($originalHeader)
                foreach ($special in $originalSpecials) { $writer.WriteLine($special) }
                foreach ($row in $sortedData) {
                    $writer.WriteLine($row)
                    $written++
                    if (($written % 2000) -eq 0) {
                        # Flushed so the size on disk actually moves for anyone
                        # watching, and so Write-Progress has something to report.
                        $writer.Flush()
                        Show-SlowHintIfNeeded -WatchPath $tempPath
                        Write-Progress -Activity "Writing $primaryName" `
                            -Status "$written of $($sortedData.Count) rows" `
                            -PercentComplete (100 * $written / [Math]::Max($sortedData.Count, 1))
                    }
                }
            } finally {
                $writer.Dispose()
                Write-Progress -Activity "Writing $primaryName" -Completed
            }

            Move-Item -LiteralPath $tempPath -Destination $PrimaryPath -Force -ErrorAction Stop
            $tempPath = $null
            $lastSorted = $sortedData

            # A secondary that carried columns the primary does not have is filed
            # apart from the ordinary backups. Its rows merged, but some of its
            # COLUMNS did not, so it is the one backup nobody can afford to treat
            # as a redundant copy of what is now in the primary.
            $destFolder = $backupFolder
            if ($aligning -and $align.Dropped.Count -gt 0) {
                $destFolder = Join-Path $backupFolder 'RemovedColumns-NotMerged'
            }
            if (-not (Test-Path $destFolder)) {
                New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
            }

            $backupPath = Join-Path $destFolder $secondaryName
            if (Test-Path $backupPath) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($secondaryName)
                $extension = [System.IO.Path]::GetExtension($secondaryName)
                $backupPath = Join-Path $destFolder "${baseName}_${timestamp}${extension}"
            }

            Move-Item -Path $secondaryPath -Destination $backupPath -Force -ErrorAction Stop

            Write-Host "Successfully merged and backed up: $secondaryName" -ForegroundColor Green
            $log.Add("  MERGED   $secondaryPath  -  read $($data2.Count), new $rowsAdded, moved to $backupPath")
            if ($alignNote) { $log.Add("           $alignNote") }
            $filesProcessed++
        }
        catch {
            Write-Error "Failed to update files for $secondaryPath : $_"
            # The primary is only ever replaced by an atomic move, so a failure
            # here leaves it exactly as it was. Clear away the partial temp file.
            if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
            Write-Warning "Primary left unchanged. The secondary was not moved."
            $result.Warnings.Add("Write failed for '$secondaryName': $($_.Exception.Message). Primary left unchanged.")
            $log.Add("  FAILED   $secondaryPath  -  $($_.Exception.Message)")
            continue
        }
    }

    # Rows that share a timestamp but differ elsewhere. After the sort they are
    # adjacent, so one walk finds them all - no second index, no extra memory.
    # They are KEPT, not resolved: only the sources can say which is right.
    if ($filesProcessed -gt 0) {
        $finalSorted = if ($lastSorted) { $lastSorted } else { Get-SortedDataRows -Rows $currentData }
        $conflicts = [System.Collections.Generic.List[string]]::new()
        $prevTs = $null
        foreach ($row in $finalSorted) {
            $thisTs = Get-FirstFieldRaw -Line $row
            if ($null -ne $prevTs -and $thisTs -eq $prevTs) {
                $result.TsConflicts++
                if ($conflicts.Count -lt 20) { $conflicts.Add($thisTs) }
            }
            $prevTs = $thisTs
        }
        if ($result.TsConflicts -gt 0) {
            $msg = "$($result.TsConflicts) row(s) share a timestamp with another row but differ in content. ALL are kept. First few: $((($conflicts | Select-Object -Unique) -join ', '))"
            Write-Warning $msg
            $result.Warnings.Add($msg)
        }
    }

    $log.Add('')
    $log.Add("Totals:")
    $log.Add("  Files merged:          $filesProcessed of $($SecondaryPaths.Count)")
    $log.Add("  New rows added:        $totalRowsAdded")
    $log.Add("  Rows in primary:       $($currentData.Count)")
    $log.Add("  Timestamp conflicts:   $($result.TsConflicts)")
    if ($primaryBackupPath) { $log.Add("  Pre-merge backup:      $primaryBackupPath") }
    if ($aborted) { $log.Add("  STOPPED by 'Exit All' - remaining secondaries untouched.") }
    if ($result.Warnings.Count -gt 0) {
        $log.Add('')
        $log.Add("Warnings:")
        foreach ($w in $result.Warnings) { $log.Add("  - $w") }
    }

    # The log is the record of what went into the file once the console has
    # scrolled away. A dry run writes nothing, this included.
    if (-not $DryRun -and $filesProcessed -gt 0) {
        $logPath = "$PrimaryPath.merge-log.txt"
        try {
            [System.IO.File]::WriteAllLines($logPath, $log, (New-Object System.Text.UTF8Encoding($false)))
            $result.LogPath = $logPath
            Write-Host "Merge log: $logPath" -ForegroundColor DarkGray
        }
        catch {
            # A log that cannot be written must never fail a merge that succeeded.
            Write-Warning "Could not write the merge log to '$logPath': $($_.Exception.Message)"
        }
    }

    # If nothing was merged for this primary, remove the unused pre-merge backup.
    if ($filesProcessed -eq 0 -and -not $NoBackup -and $primaryBackupPath -and (Test-Path $primaryBackupPath)) {
        Remove-Item -Path $primaryBackupPath -Force -ErrorAction SilentlyContinue
        Write-Host "Removed unused pre-merge backup: $primaryBackupPath" -ForegroundColor DarkGray
        if ((Test-Path $backupFolder) -and -not (Get-ChildItem -Path $backupFolder -Force)) {
            Remove-Item -Path $backupFolder -Force -ErrorAction SilentlyContinue
        }
    }

    $result.FilesProcessed = $filesProcessed
    $result.RowsAdded = $totalRowsAdded
    $result.FinalRows = $currentData.Count
    $result.Aborted = $aborted
    return $result
}

#endregion

#region Main Script

try {
    # Determine whether a file OR a folder was supplied (parameter or right-click).
    $primaryFromArg = $null
    $folderFromArg = $null

    $candidate = $null
    if ($PrimaryFile -and (Test-Path $PrimaryFile)) {
        $candidate = $PrimaryFile
    }
    elseif ($args.Count -gt 0 -and (Test-Path $args[0])) {
        $candidate = $args[0]
    }

    if ($candidate) {
        if (Test-Path $candidate -PathType Container) {
            # A folder was supplied (e.g. right-click a folder) -> folder mode.
            $folderFromArg = $candidate
            Write-Host "Using supplied folder (folder mode): $folderFromArg" -ForegroundColor Cyan
        }
        else {
            # A file was supplied (e.g. right-click a file) -> direct primary mode.
            $primaryFromArg = $candidate
            Write-Host "Using supplied file as primary: $primaryFromArg" -ForegroundColor Cyan
        }
    }

    # Choose a mode. A supplied folder/file skips the prompt.
    $mode = 'manual'
    if ($folderFromArg) {
        $mode = 'folder'
    }
    elseif (-not $primaryFromArg) {
        $choice = [System.Windows.Forms.MessageBox]::Show(
            "How do you want to select files to combine?`n`n" +
            "Yes  =  Scan a FOLDER and auto-group duplicates" + [char]0x0A +
            "          (.bak / .backup / .1 ..., and files whose TOA5" + [char]0x0A +
            "          row 1 shows the same model, serial and table)`n`n" +
            "No   =  Manually pick a primary file and secondary files",
            "Combine DAT Files - Choose Mode",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
        $mode = if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) { 'folder' } else { 'manual' }
    }

    if ($mode -eq 'folder') {
        # ---------------- FOLDER MODE ----------------
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        if ($folderFromArg) {
            $folder = $folderFromArg
        }
        else {
            $folder = Select-FolderDialog -Description "Select the folder to scan for duplicate files" -InitialDir $scriptDir
        }
        if (-not $folder) {
            Write-Warning "No folder selected. Exiting."
            return
        }

        Write-Host "`nScanning folder for duplicates: $folder" -ForegroundColor Cyan
        Write-Host "(Top-level files only - subfolders are not scanned)" -ForegroundColor DarkGray
        if ($DryRun) {
            Write-Host "DRY RUN - reporting only. Nothing will be written, moved or backed up." -ForegroundColor Yellow
        }

        $groups = @(Get-DuplicateGroups -Folder $folder)

        if ($groups.Count -eq 0) {
            Show-Notification -Title "No Duplicates Found" -Icon Warning -Message (
                "No duplicate file groups were found in:`n$folder`n`n" +
                "A group needs a data file (.dat/.csv/.txt) plus at least one of:`n" +
                "  - a backup-style duplicate (.bak/.backup/.backup1/.1 ...), or`n" +
                "  - another data file of the same extension whose TOA5 row 1`n" +
                "    gives the same model, serial and table name, with`n" +
                "    a date stamp on the end of its name (_YYYY-MM-DD) marking`n" +
                "    it as the download rather than the collected file.`n`n" +
                "The console window lists any group that was found but skipped as`n" +
                "ambiguous - two files that could each be the collected file, or`n" +
                "dated downloads with no collected file to merge into."
            )
            Write-Host "No duplicate groups found." -ForegroundColor Yellow
            return
        }

        Write-Host "Found $($groups.Count) duplicate group(s)." -ForegroundColor Cyan

        $groupsMerged = 0
        $groupsVisited = 0
        $totalFiles = 0
        $totalRows = 0
        $totalConflicts = 0
        $userAborted = $false

        foreach ($g in $groups) {
            $groupName = [System.IO.Path]::GetFileName($g.Primary)
            Write-Host "`n########## GROUP: $groupName  ($($g.Secondaries.Count) duplicate(s)) ##########" -ForegroundColor Magenta
            $groupsVisited++

            # Isolate each group: a failure on one primary must not stop the loop.
            try {
                $res = Invoke-CombineForPrimary `
                    -PrimaryPath $g.Primary `
                    -SecondaryPaths $g.Secondaries `
                    -SpecialRowCount $SpecialRowCount `
                    -Encoding $Encoding `
                    -NoBackup:$NoBackup `
                    -AutoProceedOnHeaderMatch `
                    -DryRun:$DryRun

                $totalFiles += $res.FilesProcessed
                $totalRows += $res.RowsAdded
                $totalConflicts += $res.TsConflicts
                if ($res.FilesProcessed -gt 0) { $groupsMerged++ }

                if ($res.Aborted) {
                    $userAborted = $true
                    break
                }
            }
            catch {
                Write-Warning "Group '$groupName' failed: $_"
                Write-Warning "Continuing with the next group."
            }
        }

        $remaining = $groups.Count - $groupsVisited

        Write-Host "`n$('=' * 70)" -ForegroundColor Green
        Write-Host $(if ($userAborted) { "FOLDER SCAN STOPPED BY USER" } elseif ($DryRun) { "DRY RUN COMPLETE - NOTHING WAS WRITTEN" } else { "FOLDER SCAN COMPLETE" }) -ForegroundColor Green
        Write-Host "$('=' * 70)" -ForegroundColor Green
        Write-Host "Groups found:      $($groups.Count)"
        Write-Host "Groups processed:  $groupsVisited"
        Write-Host "$(if ($DryRun) { 'Groups that would merge:' } else { 'Groups merged:    ' }) $groupsMerged"
        Write-Host "$(if ($DryRun) { 'Files that would merge: ' } else { 'Files merged:     ' }) $totalFiles"
        Write-Host "$(if ($DryRun) { 'Rows that would be added:' } else { 'Rows added total: ' }) $totalRows"
        Write-Host "Timestamp conflicts: $totalConflicts"
        if ($userAborted) { Write-Host "Groups skipped:    $remaining (Exit All)" -ForegroundColor Yellow }
        Write-Host "$('=' * 70)" -ForegroundColor Green

        Show-Notification -Title $(if ($userAborted) { "Folder Scan Stopped" } elseif ($DryRun) { "Dry Run Complete" } else { "Folder Scan Complete" }) -Message (
            $(if ($userAborted) { "Folder scan stopped by 'Exit All'.`n`n" }
              elseif ($DryRun) { "Dry run complete - nothing was written, moved or backed up.`n`n" }
              else { "Folder scan complete.`n`n" }) +
            "Folder:                 $folder`n" +
            "Groups found:       $($groups.Count)`n" +
            "Groups processed: $groupsVisited`n" +
            "$(if ($DryRun) { 'Would merge:        ' } else { 'Groups merged:     ' }) $groupsMerged`n" +
            "$(if ($DryRun) { 'Files affected:      ' } else { 'Files merged:         ' }) $totalFiles`n" +
            "$(if ($DryRun) { 'Rows to add:         ' } else { 'Rows added:           ' }) $totalRows`n" +
            "Timestamp conflicts: $totalConflicts" +
            $(if ($userAborted) { "`nGroups skipped:     $remaining" } else { "" })
        )
        return
    }

    # ---------------- MANUAL MODE ----------------
    $primaryPath = $primaryFromArg
    if (-not $primaryPath) {
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
        $primaryFilter = "Text Files (*.txt;*.csv;*.dat)|*.txt;*.csv;*.dat|All Files|*.*"
        $primaryPath = Select-FileDialog -Title "Select the primary file to retain" -InitialDir $scriptDir -Filter $primaryFilter

        if (-not $primaryPath) {
            Write-Warning "No primary file selected. Exiting."
            return
        }
    }

    $secondaryFilter = "Text and Backup (*.txt;*.csv;*.dat;*.bak;*.backup)|*.txt;*.csv;*.dat;*.bak;*.backup|All Files|*.*"
    $secondaryFiles = Select-FileDialog -Title "Select one or more files to merge into primary" `
        -InitialDir (Split-Path -Parent $primaryPath) `
        -Filter $secondaryFilter `
        -MultiSelect $true

    if (-not $secondaryFiles -or $secondaryFiles.Count -eq 0) {
        Write-Host "No secondary files selected. Exiting." -ForegroundColor Yellow
        return
    }

    Write-Host "`nSelected $($secondaryFiles.Count) file(s) to merge`n" -ForegroundColor Cyan

    $res = Invoke-CombineForPrimary `
        -PrimaryPath $primaryPath `
        -SecondaryPaths $secondaryFiles `
        -SpecialRowCount $SpecialRowCount `
        -Encoding $Encoding `
        -NoBackup:$NoBackup `
        -DryRun:$DryRun

    if ($res.Aborted) {
        Write-Host "`nStopped by 'Exit All'. Remaining selected files were not processed." -ForegroundColor Yellow
    }

    if ($res.FilesProcessed -eq 0) {
        Write-Host "`n$('=' * 70)" -ForegroundColor Yellow
        Write-Host "MERGE ABORTED" -ForegroundColor Yellow
        Write-Host "$('=' * 70)" -ForegroundColor Yellow
        Write-Host "No files were merged. All files remain unchanged."
        Write-Host "Primary file: $primaryPath"
        Write-Host "$('=' * 70)" -ForegroundColor Yellow

        Show-Notification -Title "Merge Aborted" -Icon Warning -Message (
            "Merge aborted.`n`nNo files were merged and nothing was moved to Backup.`nAll files remain unchanged.`n`nPrimary file:`n$primaryPath"
        )
    }
    else {
        Write-Host "`n$('=' * 70)" -ForegroundColor Green
        Write-Host $(if ($DryRun) { "DRY RUN COMPLETE - NOTHING WAS WRITTEN" } else { "MERGE COMPLETE" }) -ForegroundColor Green
        Write-Host "$('=' * 70)" -ForegroundColor Green
        Write-Host "$(if ($DryRun) { 'Files that would merge' } else { 'Files processed' }): $($res.FilesProcessed)"
        Write-Host "$(if ($DryRun) { 'Rows that would be added' } else { 'Total new rows added' }): $($res.RowsAdded)"
        Write-Host "Final unique data rows: $($res.FinalRows)"
        Write-Host "Timestamp conflicts: $($res.TsConflicts)"
        Write-Host "$(if ($DryRun) { 'Unchanged file' } else { 'Updated file' }): $primaryPath"
        Write-Host "$('=' * 70)" -ForegroundColor Green

        Show-Notification -Title $(if ($DryRun) { "Dry Run Complete" } else { "Merge Complete" }) -Message (
            $(if ($DryRun) { "Dry run complete - nothing was written.`n`nFiles that would merge: $($res.FilesProcessed)`nRows the primary would hold: $($res.FinalRows)" }
              else { "Merging complete.`n`nFiles processed: $($res.FilesProcessed)`nTotal rows: $($res.FinalRows)" }) +
            "`nTimestamp conflicts: $($res.TsConflicts)`n`n" +
            $(if ($DryRun) { "Unchanged file:" } else { "Final file:" }) + "`n$primaryPath"
        )
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    $global:LASTEXITCODE = 1
}

#endregion
