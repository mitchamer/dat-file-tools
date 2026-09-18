<#
    Combine Affinity Files - recursive, many-to-one
    -----------------------------------------------
    Combines structured, timestamp-based data files (.dat/.csv/.txt) found in a
    folder AND ALL OF ITS SUBFOLDERS into one combined file per dataset.

    Built for Fort Hills Affinity data: hundreds of daily download files
    scattered through dated subfolders, all holding the same table, with the
    same rows repeated in file after file.

    This is the sibling of Combine DAT files, not a replacement. That script
    merges a handful of duplicates into an existing primary file, in one folder,
    with a dialog per file.

    WHAT IS DIFFERENT FROM COMBINE DAT FILES
    =========================
      * RECURSIVE. Subfolders are scanned (v9 deliberately never entered them).
      * NON-DESTRUCTIVE BY DEFAULT. No source file is rewritten, renamed or
        moved. The result is written to a NEW file in an output folder
        (default '<SourceFolder>\Combined'). There is no primary to destroy, so
        the whole merge is undone by deleting the output folder.
      * NO PER-FILE DIALOG. With 278 files, 278 dialogs is not a workflow.
        Files are grouped by dataset, the header rows are compared in code, and
        matching files merge silently. A dialog appears only for a file whose
        headers do NOT match its group, which is the only case worth a human.
      * TWO HEADER ROWS. This data (TOACI1) carries row 1 = file info and
        row 2 = column names, then data. v9 assumed the TOA5 shape of 1 + 3.
        The count is auto-detected per dataset unless -HeaderRowCount is given,
        so both shapes work.
      * VALIDATION. Timestamp format, column count, and rows that share a
        timestamp but disagree on content are all checked and reported rather
        than silently baked into the output.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    Licensed under GPL-3.0 and provided "as is" with no warranty of any kind
    (see LICENSE sections 15-17). You are responsible for verifying the
    combined output before relying on it.

    Even though sources are left alone by default, read the summary before
    trusting the result. In particular:
      * de-duplication compares the WHOLE row, case-insensitively, so rows
        differing only in letter case (NAN vs NaN) collapse to one, and rows
        that share a timestamp but differ ANYWHERE else are BOTH kept. The
        count of such timestamps is reported - a non-zero count means the
        sources disagree with each other and the output has more than one row
        for some timestamps.
      * sorting is an ordinal TEXT sort of the whole row. Correct for
        YYYY-MM-DD HH:MM:SS (fixed width, leading field). WRONG for formats
        like M/D/YYYY, so the first data column is checked and a mismatch is
        reported.
      * -MoveSources is the one destructive option: merged source files are
        MOVED into '<OutputFolder>\Sources'. Off by default.

    HOW FILES ARE GROUPED
    =====================
    A "dataset" is a group of files that may be merged into one output file.
    Two files land in the same dataset only when BOTH of these agree:

      1. Canonical file name - the file name with any download timestamp
         stripped from either end, e.g.
             20251026020052_FH23-GT1247-MR1-SI_SN753940_raw_readings.csv
             20260814020101_FH23-GT1247-MR1-SI_SN753940_raw_readings.csv
         both reduce to
             FH23-GT1247-MR1-SI_SN753940_raw_readings.csv
         Stripped patterns: a leading 8-14 digit stamp, a trailing 8-14 digit
         stamp, and a trailing LoggerNet stamp (_YYYY-MM-DDTHH-MM[-SS]).

      2. Header signature - every header row, byte for byte.

    Requiring both is on purpose. Names alone would merge two sensors whose
    files were named to the same pattern; headers alone would merge two
    stations that happen to share a column layout. If the file names in a
    folder tree carry no common canonical form, pass -SingleGroup to force
    every file with a matching header signature into one output file.

    A file whose headers differ from the rest of its name group forms its own
    dataset and is reported, never quietly merged into a mismatched layout.

    INVOCATION
    ==========
      1) RIGHT-CLICK / DIRECT - pass the root folder
         PS> .\'Combine Affinity Files.ps1' 'C:\Raw Data\...\affinity'

      2) DIALOG - run with no arguments and pick the root folder
         PS> .\'Combine Affinity Files.ps1'

      3) DRY RUN - scan, group, validate and report; write nothing
         PS> .\'Combine Affinity Files.ps1' 'C:\Data\affinity' -DryRun

    PARAMETERS
    ==========
      -SourceFolder <path>     Root folder to scan (recursively). Position 0.
      -OutputFolder <path>     Where combined files are written.
                               Default '<SourceFolder>\Combined'.
      -HeaderRowCount <int>    Total header lines before the data (TOACI1 = 2,
                               TOA5 = 4). Omit to auto-detect per dataset.
      -SpecialRowCount <int>   v9 compatibility: HeaderRowCount = this + 1.
      -Extensions <string[]>   Extensions to scan. Default dat, csv, txt.
      -ExcludeFolders <s[]>    Folder NAMES to skip anywhere in the tree, in
                               addition to the always-skipped Backup, Combined
                               and Sources. Use this for staging folders that
                               hold copies of the same data - scanning them is
                               harmless (duplicates are dropped) but doubles
                               the read time.
      -SingleGroup             Ignore file names; group by header signature
                               alone, producing one output file per layout.
      -OutputName <name>       Name for the combined file. Only valid with
                               -SingleGroup (one output file to name).
      -MoveSources             Move merged sources into <OutputFolder>\Sources.
                               DESTRUCTIVE. Off by default.
      -Unattended              Never show a dialog. Mismatched files are
                               skipped and reported instead of prompting.
      -DryRun                  Report only; write nothing.
      -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                               Output encoding. Default Auto, which matches the
                               byte-order mark of the first source file so the
                               combined file opens the way the sources did. A
                               BOM ahead of the TOACI1/TOA5 row leaves
                               LoggerNet unable to recognise the file.

    OUTPUT
    ======
    For each dataset:
      <OutputFolder>\<canonical name>              the combined file
      <OutputFolder>\<canonical name>.merge-log.txt every source file, rows
                                                   read, rows contributed, and
                                                   every warning raised
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$SourceFolder,

    [Parameter()]
    [string]$OutputFolder,

    [Parameter()]
    [ValidateRange(1, 50)]
    [int]$HeaderRowCount = 2,

    # v9 spelled this as "rows after the header", i.e. one less than the total.
    [Parameter()]
    [ValidateRange(0, 49)]
    [int]$SpecialRowCount,

    [Parameter()]
    [string[]]$Extensions = @('dat', 'csv', 'txt'),

    # Folder names skipped anywhere in the tree. Backup / Combined / Sources are
    # always skipped on top of these, so the script never eats its own output.
    [Parameter()]
    [string[]]$ExcludeFolders = @(),

    [Parameter()]
    [switch]$SingleGroup,

    [Parameter()]
    [string]$OutputName,

    [Parameter()]
    [switch]$MoveSources,

    [Parameter()]
    [switch]$Unattended,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'ASCII', 'Unicode')]
    [string]$Encoding = 'Auto'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Header row count: explicit beats v9-style, and neither means auto-detect.
$script:HeaderRowsExplicit = $PSBoundParameters.ContainsKey('HeaderRowCount')
if ($PSBoundParameters.ContainsKey('SpecialRowCount')) {
    $HeaderRowCount = $SpecialRowCount + 1
    $script:HeaderRowsExplicit = $true
}
if ($PSBoundParameters.ContainsKey('OutputName') -and -not $SingleGroup) {
    throw "-OutputName names a single combined file, so it is only valid with -SingleGroup. Without -SingleGroup each dataset is named after its own canonical file name."
}

#region Helper Functions

# --- Encoding -------------------------------------------------------------
# Carried over from v9 unchanged. The reasoning is worth repeating: LoggerNet
# data files carry no BOM, and a BOM ahead of the TOACI1/TOA5 row leaves
# LoggerNet unable to recognise the file it is appending to. It responds by
# renaming the file to .backup and starting a fresh one, silently orphaning
# everything that was just written.

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

# --- Bulk data helpers ----------------------------------------------------

function Read-DataFileLines {
    param([string]$Path)
    # Markedly faster than Get-Content, which wraps every line in a PSObject and
    # attaches note properties. On 2,157-column rows that overhead is most of
    # the read time. UTF-8 with BOM detection, matching Read-DataFileHead - on
    # Windows PowerShell 5.1 Get-Content defaults to the ANSI code page, which
    # turns a UTF-8 BOM into ï»¿ and makes every header look like a mismatch.
    $lines = [System.IO.File]::ReadAllLines($Path)
    if ($lines.Length -gt 0 -and $lines[0]) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
    return $lines
}

function Read-DataFileHead {
    <#
        First $Count lines of a data file, same encoding as Read-DataFileLines
        (UTF-8, BOM-aware). Grouping 278 files must not read every row twice.
    #>
    param([string]$Path, [int]$Count)

    $list = New-Object System.Collections.Generic.List[string]
    $reader = New-Object System.IO.StreamReader($Path, [System.Text.Encoding]::UTF8, $true)
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            [void]$list.Add($line)
        }
    }
    finally {
        $reader.Dispose()
    }
    if ($list.Count -gt 0 -and $list[0]) { $list[0] = $list[0].TrimStart([char]0xFEFF) }
    return $list.ToArray()
}

function Get-SortedDataRows {
    param([System.Collections.Generic.HashSet[string]]$Rows)

    $values = New-Object 'string[]' $Rows.Count
    $Rows.CopyTo($values)

    # An ordinal sort of the whole row. The timestamp is the leading field and
    # is fixed width, so this orders by timestamp exactly - and breaks ties on
    # the rest of the row rather than leaving equal-timestamp rows in an
    # arbitrary order, so repeated runs produce byte-identical output.
    #
    # One .NET call, no per-row PowerShell work. The obvious
    #     $rows | Sort-Object { ($_ -split ',')[0] }
    # splits every row into all 2,157 fields to read the first one, and pays
    # pipeline overhead on every comparison. On this dataset that is the
    # difference between seconds and many minutes.
    [Array]::Sort($values, [System.StringComparer]::Ordinal)
    # Unary comma: a 1-element string[] must not unroll into a single string,
    # or the writer iterates characters and the output is garbage.
    return ,$values
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
        the rest. Called once per row during the conflict scan, where splitting
        2,157 fields to read field 1 would dominate the run.
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

# --- Progress / reassurance ----------------------------------------------
#
# A long merge looks indistinguishable from a hang, and someone killing it part
# way is how data gets lost. Say what is happening and name a file whose size
# actually moves.

$script:MergeStopwatch = $null
$script:SlowHintShown = $false

function Start-MergeTimer {
    $script:MergeStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:SlowHintShown = $false
}

function Show-SlowHintIfNeeded {
    # The threshold is a parameter default rather than a script-level variable
    # on purpose. As a loose variable it could fall out of scope, and then
    # `elapsed -lt $null` compares against 0, which is always false - so the
    # hint would fire on every merge instead of only slow ones.
    param(
        [string]$WatchPath,
        [double]$AfterSeconds = 15
    )

    if ($script:SlowHintShown -or -not $script:MergeStopwatch) { return }
    if ($script:MergeStopwatch.Elapsed.TotalSeconds -lt $AfterSeconds) { return }
    $script:SlowHintShown = $true

    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  Still working. Hundreds of files take a while - not stuck.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Nothing is written until every source has been read, so the' -ForegroundColor Yellow
    Write-Host '  output folder stays empty during the read phase. Once writing' -ForegroundColor Yellow
    Write-Host '  starts, this working file grows (Explorer, F5):' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "      $WatchPath" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Source files are not modified. Closing this window now leaves' -ForegroundColor Yellow
    Write-Host '  every source exactly as it is.' -ForegroundColor Yellow
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
}

# --- Dialogs -------------------------------------------------------------

function Select-FolderDialog {
    param(
        [string]$Description = "Select a folder",
        [string]$InitialDir
    )

    # The modern Explorer-style OpenFileDialog in "folder pick" mode rather than
    # the classic FolderBrowserDialog tree: it has an address bar, shows mapped
    # network drives, and accepts a typed or pasted path including UNC.
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "$Description  -  open any folder, then click 'Select Folder'"
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.Multiselect = $false
    $dlg.Filter = "Folders|*.__select_folder__"
    $dlg.FileName = "Select Folder"
    if ($InitialDir -and (Test-Path $InitialDir)) {
        $dlg.InitialDirectory = $InitialDir
    }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selected = [System.IO.Path]::GetDirectoryName($dlg.FileName)
        if ([string]::IsNullOrWhiteSpace($selected)) { $selected = $dlg.FileName }
        if ($selected -and (Test-Path $selected -PathType Container)) { return $selected }
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

function Show-HeaderComparison {
    <#
        Side-by-side, column-by-column comparison of two header lines. Returns
        'Proceed' (merge this file), 'Decline' (skip this file, continue) or
        'ExitAll' (stop everything).

        Shown only when a file's header does not match its dataset's - the
        mismatch cases, not every file.
    #>
    param(
        [string]$PrimaryHeader,
        [string]$SecondaryHeader,
        [string]$PrimaryName,
        [string]$SecondaryName,
        [int]$RowNumber,
        [string]$ComparisonTitle = "Header Comparison"
    )

    $primaryFields = Split-CsvLine -Line $PrimaryHeader
    $secondaryFields = Split-CsvLine -Line $SecondaryHeader
    $maxCols = [Math]::Max($primaryFields.Count, $secondaryFields.Count)

    $identical = ($PrimaryHeader -eq $SecondaryHeader)

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
    $form.Size = New-Object System.Drawing.Size(820, 600)
    $form.MinimumSize = New-Object System.Drawing.Size(600, 440)
    $form.TopMost = $true
    $form.BackColor = $clrBg
    $form.Font = $fontUI
    $form.Padding = New-Object System.Windows.Forms.Padding(0)

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
    $lblFiles.Text = "Dataset:  $PrimaryName`nThis file:  $SecondaryName"

    $banner.Controls.Add($lblFiles)
    $banner.Controls.Add($lblStatus)

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

    [void]$grid.Columns.Add("Col", "#")
    [void]$grid.Columns.Add("Primary", "Dataset")
    [void]$grid.Columns.Add("Secondary", "This file")
    [void]$grid.Columns.Add("Status", "Status")
    $grid.Columns["Col"].FillWeight = 12
    $grid.Columns["Col"].DefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.Columns["Col"].DefaultCellStyle.ForeColor = $clrSubtle
    $grid.Columns["Primary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Secondary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Status"].FillWeight = 26

    # Only differing columns are listed. On a 2,157-column header a full listing
    # is 2,157 rows of "Match" with the answer buried somewhere inside it.
    $shown = 0
    for ($i = 0; $i -lt $maxCols; $i++) {
        $p = if ($i -lt $primaryFields.Count) { $primaryFields[$i] }   else { $null }
        $s = if ($i -lt $secondaryFields.Count) { $secondaryFields[$i] } else { $null }

        if ($null -eq $p) { $status = "Missing in dataset" }
        elseif ($null -eq $s) { $status = "Missing in this file" }
        elseif ($p -eq $s) { $status = "Match" }
        else { $status = "Different" }

        if ($status -eq "Match" -and $maxCols -gt 60) { continue }

        $rowIndex = $grid.Rows.Add(($i + 1), $(if ($null -eq $p) { "(none)" }else { $p }), $(if ($null -eq $s) { "(none)" }else { $s }), $status)
        $row = $grid.Rows[$rowIndex]
        $shown++

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
    if ($maxCols -gt 60) {
        $lblStatus.Text += "  ($shown of $maxCols columns shown - matching columns hidden)"
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

    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = if ($identical) { "Include" } else { "Include Anyway" }
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
    $btnDecline.Text = "Skip This File"
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
    $panel.Controls.Add($btnProceed)
    $panel.Controls.Add($btnDecline)
    $panel.Controls.Add($btnExitAll)

    # Add the fill control first (lowest z-order) so docked panels are not overlapped.
    $form.Controls.Add($gridHost)
    $form.Controls.Add($panel)
    $form.Controls.Add($banner)
    $form.Controls.Add($titleBar)
    $form.AcceptButton = $btnProceed
    $form.CancelButton = $btnDecline

    $result = $form.ShowDialog()
    $form.Dispose()

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes) { return 'Proceed' }
        ([System.Windows.Forms.DialogResult]::Abort) { return 'ExitAll' }
        default { return 'Decline' }   # No / Esc / window closed = skip this file only
    }
}

# --- Grouping -------------------------------------------------------------

function Get-CanonicalDataName {
    <#
        Reduces a download file name to the name of the dataset it belongs to by
        stripping a collection timestamp from either end:

          20251026020052_FH23-GT1247-MR1-SI_SN753940_raw_readings.csv
            -> FH23-GT1247-MR1-SI_SN753940_raw_readings.csv
          TM_MCL-02_Status_2026-07-23T15-44.dat
            -> TM_MCL-02_Status.dat
          Site_Diagnostics_20260723.dat
            -> Site_Diagnostics.dat

        Only a stamp is removed, never a meaningful token: the leading pattern
        needs 8-14 digits followed by a separator, and the trailing patterns
        need a separator followed by 8-14 digits or a full LoggerNet stamp. A
        name that is nothing but a stamp is left alone rather than reduced to
        the extension.
    #>
    param([string]$FileName)

    $ext = [System.IO.Path]::GetExtension($FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    # Leading stamp: 20251026020052_Rest
    if ($base -match '^\d{8,14}[_\-](?<rest>.+)$') { $base = $Matches['rest'] }

    # Trailing LoggerNet stamp: Rest_2026-07-23T15-44[-30]
    if ($base -match '^(?<rest>.+)[_\-]\d{4}-\d{2}-\d{2}T\d{2}-\d{2}(?:-\d{2})?$') { $base = $Matches['rest'] }

    # Trailing plain stamp: Rest_20260723[020052]
    if ($base -match '^(?<rest>.+)[_\-]\d{8,14}$') { $base = $Matches['rest'] }

    return "$base$ext"
}

function Get-HeaderSignature {
    <#
        Reads the first $Count lines of a file and returns them plus a stable
        signature string. Returns $null when the file is unreadable or too short
        to hold headers plus at least one data row.
    #>
    param([string]$FilePath, [int]$Count)

    try {
        $lines = @(Read-DataFileHead -Path $FilePath -Count ($Count + 1))
    }
    catch {
        return $null
    }
    if ($lines.Count -lt $Count) { return $null }

    $headers = @($lines[0..($Count - 1)])
    return [pscustomobject]@{
        Headers   = $headers
        Signature = ($headers -join "`u{241E}")
        HasData   = ($lines.Count -gt $Count)
    }
}

function Get-DetectedHeaderRowCount {
    <#
        Number of header lines in a file, found by locating the first line whose
        leading field looks like a date. TOACI1 gives 2 (file info + column
        names); TOA5 gives 4 (file info + names + units + aggregation), so the
        same script handles both without being told which it is looking at.

        Returns 0 when no data-looking line is found in the first $MaxScan lines,
        which the caller reads as "could not detect".
    #>
    param([string]$FilePath, [int]$MaxScan = 12)

    try {
        $lines = @(Read-DataFileHead -Path $FilePath -Count $MaxScan)
    }
    catch {
        return 0
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $first = Get-FirstFieldRaw -Line $lines[$i]
        # A leading ISO date, or a slash/dot date, marks the first data row.
        if ($first -match '^\d{4}[-/]\d{1,2}[-/]\d{1,2}' -or $first -match '^\d{1,2}[/.]\d{1,2}[/.]\d{2,4}') {
            return $i
        }
    }
    return 0
}

function Get-RecursiveMergeGroups {
    <#
        Walks $Folder and every subfolder and returns one object per dataset:

          Name        canonical output file name
          Headers     the header lines every member shares
          HeaderRows  how many header lines that is
          Files       member files (FileInfo), oldest name first
          Signature   the shared header signature

        Members of a dataset agree on BOTH canonical name and header signature
        (see the comment block at the top of this script for why both). With
        -ForceSingleGroup the name is ignored and only the signature groups.

        Header row count is detected per file (TOACI1 = 2, TOA5 = 4) unless
        -HeaderRowsExplicit, so a mixed tree does not pin every dataset to
        whichever file Get-ChildItem returned first. Files that share a name
        but not a count become separate datasets, the same way differing
        header signatures already do.

        The output folder and any folder named Backup / Combined / Sources is
        skipped, so re-running the script never feeds its own output back in,
        plus any name passed in -ExcludeFolders.
    #>
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string[]]$Extensions,
        [Parameter(Mandatory)][int]$HeaderRows,
        [bool]$HeaderRowsExplicit = $false,
        [string]$ExcludeFolder,
        [string[]]$ExcludeNames = @(),
        [bool]$ForceSingleGroup = $false,
        [System.Collections.Generic.List[string]]$Problems
    )

    $extSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $Extensions) { [void]$extSet.Add('.' + $e.TrimStart('.')) }

    Write-Host "Enumerating files under: $Folder" -ForegroundColor DarkGray
    $all = @(Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction SilentlyContinue)

    $skipNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in @('Backup', 'Combined', 'Sources') + $ExcludeNames) {
        if ($n) { [void]$skipNames.Add($n.Trim('\', '/', ' ')) }
    }
    $excludeFull = if ($ExcludeFolder) { [System.IO.Path]::GetFullPath($ExcludeFolder).TrimEnd('\') } else { $null }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $excluded = 0
    foreach ($f in $all) {
        if (-not $extSet.Contains($f.Extension)) { continue }
        if ($f.Name -like '*.combining.tmp') { continue }

        $dir = $f.DirectoryName
        if ($excludeFull -and ($dir.TrimEnd('\') -eq $excludeFull -or $dir.StartsWith($excludeFull + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
            $excluded++
            continue
        }

        # Skip anything under a folder this tool writes to, or one the caller
        # named. Matched per path segment so 'Backup' skips the folder but not a
        # file called Backup_readings.csv.
        $rel = $dir.Substring([Math]::Min($Folder.Length, $dir.Length)).Trim('\')
        $inSkipped = $false
        if ($rel) {
            foreach ($s in $rel.Split('\')) { if ($skipNames.Contains($s)) { $inSkipped = $true; break } }
        }
        if ($inSkipped) { $excluded++; continue }

        $candidates.Add($f)
    }

    Write-Host "  $($all.Count) file(s) found, $($candidates.Count) to scan ($excluded excluded by folder name)." -ForegroundColor DarkGray
    if ($candidates.Count -eq 0) { return @() }

    $groups = [ordered]@{}
    $index = 0
    foreach ($f in $candidates) {
        $index++
        if (($index % 25) -eq 0 -or $index -eq $candidates.Count) {
            Write-Progress -Activity "Reading headers" -Status "$index of $($candidates.Count)" `
                -PercentComplete (100 * $index / [Math]::Max($candidates.Count, 1))
        }

        $fileRows = $HeaderRows
        if (-not $HeaderRowsExplicit) {
            $detected = Get-DetectedHeaderRowCount -FilePath $f.FullName
            if ($detected -le 0) {
                $msg = "Skipped '$($f.FullName)': could not detect how many header rows it has (no date-like value in the first field of the first 12 lines). Pass -HeaderRowCount if the timestamps are in an unusual format."
                Write-Warning $msg
                if ($null -ne $Problems) { $Problems.Add($msg) }
                continue
            }
            $fileRows = $detected
        }

        $sig = Get-HeaderSignature -FilePath $f.FullName -Count $fileRows
        if (-not $sig) {
            $msg = "Skipped '$($f.FullName)': unreadable, or fewer than $fileRows header line(s)."
            Write-Warning $msg
            if ($null -ne $Problems) { $Problems.Add($msg) }
            continue
        }
        if (-not $sig.HasData) {
            $msg = "Skipped '$($f.FullName)': headers only, no data rows."
            Write-Host "  $msg" -ForegroundColor DarkYellow
            if ($null -ne $Problems) { $Problems.Add($msg) }
            continue
        }

        $canonical = Get-CanonicalDataName -FileName $f.Name
        $sigHash = Get-ShortHash -Text $sig.Signature
        $key = if ($ForceSingleGroup) { "$fileRows|$sigHash" } else { $canonical.ToLowerInvariant() + '|' + $fileRows + '|' + $sigHash }

        if (-not $groups.Contains($key)) {
            $groups[$key] = [pscustomobject]@{
                Name       = $canonical
                Headers    = $sig.Headers
                HeaderRows = $fileRows
                Signature  = $sig.Signature
                SigHash    = $sigHash
                Files      = [System.Collections.Generic.List[object]]::new()
            }
        }
        $groups[$key].Files.Add($f)
    }
    Write-Progress -Activity "Reading headers" -Completed

    $result = @($groups.Values)

    if (-not $HeaderRowsExplicit -and $result.Count -gt 0) {
        $byRows = @($result | Group-Object -Property HeaderRows)
        foreach ($r in $byRows) {
            Write-Host "  $($r.Count) dataset(s) with $($r.Name) header row(s)." -ForegroundColor DarkGray
        }
    }

    # Two datasets can only share a canonical name when their headers differ,
    # which is exactly the case worth flagging rather than overwriting.
    $byName = $result | Group-Object -Property { $_.Name.ToLowerInvariant() }
    foreach ($n in $byName) {
        if ($n.Count -le 1) { continue }
        $msg = "'$($n.Group[0].Name)' has $($n.Count) different header layouts - each is combined into a separate output file (suffixed with its header hash)."
        Write-Warning $msg
        if ($null -ne $Problems) { $Problems.Add($msg) }
        foreach ($g in $n.Group) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($g.Name)
            $ext = [System.IO.Path]::GetExtension($g.Name)
            $g.Name = "$stem`_hdr-$($g.SigHash)$ext"
        }
    }

    # Oldest first, so the combined file is built in collection order and the
    # log reads chronologically.
    foreach ($g in $result) {
        $sorted = @($g.Files | Sort-Object -Property Name, FullName)
        $g.Files.Clear()
        foreach ($f in $sorted) { $g.Files.Add($f) }
    }

    return @($result | Sort-Object -Property Name)
}

function Get-ShortHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
    }
    finally {
        $sha.Dispose()
    }
    return -join ($bytes[0..3] | ForEach-Object { $_.ToString('x2') })
}

# --- Merge ---------------------------------------------------------------

function Invoke-CombineGroup {
    <#
        Reads every file in one dataset, de-duplicates and sorts the data rows,
        and writes a single combined file plus a log.

        Returns FilesRead, FilesSkipped, RowsRead, UniqueRows, DuplicateRows,
        OutputPath, LogPath, Aborted, Warnings.

        -MoveSources moves only files whose rows were actually merged. A skip
        or Exit All leaves those sources in place; Exit All writes nothing.
    #>
    param(
        [Parameter(Mandatory)][object]$Group,
        [Parameter(Mandatory)][string]$OutputFolder,
        [string]$Encoding = 'Auto',
        [switch]$Unattended,
        [switch]$DryRun,
        [switch]$MoveSources,
        [string]$OverrideName
    )

    $outName = if ($OverrideName) { $OverrideName } else { $Group.Name }
    $outPath = Join-Path $OutputFolder $outName
    $logPath = "$outPath.merge-log.txt"

    $result = [pscustomobject]@{
        FilesRead     = 0
        FilesSkipped  = 0
        RowsRead      = 0
        UniqueRows    = 0
        DuplicateRows = 0
        TsConflicts   = 0
        OutputPath    = $outPath
        LogPath       = $logPath
        Aborted       = $false
        Warnings      = [System.Collections.Generic.List[string]]::new()
    }

    $log = [System.Collections.Generic.List[string]]::new()
    $log.Add("Combine Affinity Files - merge log")
    $log.Add("Generated:      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $log.Add("Dataset:        $($Group.Name)")
    $log.Add("Output file:    $outPath")
    $log.Add("Header rows:    $($Group.HeaderRows)")
    $log.Add("Source files:   $($Group.Files.Count)")
    $log.Add("Dry run:        $([bool]$DryRun)")
    $log.Add('')

    # Ordinal-ignore-case, matching v9: rows differing only in letter case
    # (NAN vs NaN) are treated as the same row.
    $data = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $headerFieldCount = (Split-CsvLine -Line $Group.Headers[$Group.HeaderRows - 1]).Count
    $badTimestampFiles = 0
    $badColumnFiles = 0
    $fileIndex = 0
    $mergedFiles = [System.Collections.Generic.List[object]]::new()

    $log.Add("Per-file detail (rows read / new unique rows contributed):")

    foreach ($f in $Group.Files) {
        $fileIndex++
        Write-Progress -Activity "Reading $($Group.Name)" `
            -Status "$fileIndex of $($Group.Files.Count): $($f.Name)" `
            -PercentComplete (100 * $fileIndex / [Math]::Max($Group.Files.Count, 1))
        Show-SlowHintIfNeeded -WatchPath "$outPath.combining.tmp"

        $lines = $null
        try {
            $lines = Read-DataFileLines $f.FullName
        }
        catch {
            $msg = "Could not read '$($f.FullName)': $($_.Exception.Message)"
            Write-Warning $msg
            $result.Warnings.Add($msg)
            $log.Add("  SKIPPED  $($f.FullName)  -  $msg")
            $result.FilesSkipped++
            continue
        }

        if ($lines.Count -le $Group.HeaderRows) {
            $log.Add("  SKIPPED  $($f.FullName)  -  no data rows")
            $result.FilesSkipped++
            continue
        }

        # Headers are re-verified from the full read. Grouping used a signature
        # taken from a separate, earlier read; a file rewritten in between would
        # otherwise slip in unchecked.
        $mismatchRow = 0
        for ($h = 0; $h -lt $Group.HeaderRows; $h++) {
            $line = if ($h -eq 0) { $lines[0].TrimStart([char]0xFEFF) } else { $lines[$h] }
            if ($line -ne $Group.Headers[$h]) { $mismatchRow = $h + 1; break }
        }

        if ($mismatchRow -gt 0) {
            $msg = "Header row $mismatchRow of '$($f.FullName)' does not match the dataset."
            if ($Unattended) {
                Write-Warning "$msg Skipped (-Unattended)."
                $result.Warnings.Add("$msg Skipped.")
                $log.Add("  SKIPPED  $($f.FullName)  -  header row $mismatchRow differs")
                $result.FilesSkipped++
                continue
            }

            Write-Warning $msg
            $choice = Show-HeaderComparison `
                -PrimaryHeader   $Group.Headers[$mismatchRow - 1] `
                -SecondaryHeader $(if ($mismatchRow - 1 -lt $lines.Count) { $lines[$mismatchRow - 1] } else { '' }) `
                -PrimaryName     $Group.Name `
                -SecondaryName   $f.FullName `
                -RowNumber       $mismatchRow `
                -ComparisonTitle "Header mismatch - include this file?"

            if ($choice -eq 'ExitAll') {
                $log.Add("  ABORTED at $($f.FullName) (Exit All)")
                $result.Aborted = $true
                break
            }
            if ($choice -ne 'Proceed') {
                $result.Warnings.Add("$msg Skipped by user.")
                $log.Add("  SKIPPED  $($f.FullName)  -  header row $mismatchRow differs (declined)")
                $result.FilesSkipped++
                continue
            }
            $result.Warnings.Add("$msg Included by user.")
            $log.Add("  INCLUDED DESPITE MISMATCH  $($f.FullName)  -  header row $mismatchRow differs")
        }

        # Shape checks on this file's first data row only. Running them on every
        # row of 300,000 x 2,157 fields would cost more than the merge itself,
        # and a file that is malformed is malformed from its first row.
        $firstData = $lines[$Group.HeaderRows]
        $ts = Get-FirstFieldRaw -Line $firstData
        if ($ts -notmatch '^\d{4}-\d{2}-\d{2}') {
            $badTimestampFiles++
            $msg = "'$($f.Name)' first data timestamp is '$ts', not YYYY-MM-DD. The output sort orders rows as TEXT, so it will be wrong for this format."
            if ($badTimestampFiles -le 3) { Write-Warning $msg }
            $result.Warnings.Add($msg)
        }
        $fieldCount = (Split-CsvLine -Line $firstData).Count
        if ($fieldCount -ne $headerFieldCount) {
            $badColumnFiles++
            $msg = "'$($f.Name)' first data row has $fieldCount field(s) but the header has $headerFieldCount."
            if ($badColumnFiles -le 3) { Write-Warning $msg }
            $result.Warnings.Add($msg)
        }

        $before = $data.Count
        $rowsThisFile = 0
        for ($i = $Group.HeaderRows; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $rowsThisFile++
            [void]$data.Add($line)
        }

        $added = $data.Count - $before
        $result.RowsRead += $rowsThisFile
        $result.FilesRead++
        $mergedFiles.Add($f)
        $log.Add("  $($f.FullName)".PadRight(4) + "  read $rowsThisFile, new $added")

        # Release the file's line array before reading the next one. Without
        # this, PowerShell can hold the previous 2,157-column array alive while
        # the next is allocated.
        $lines = $null
    }
    Write-Progress -Activity "Reading $($Group.Name)" -Completed

    if ($result.Aborted) {
        $msg = "Stopped at Exit All before writing '$($Group.Name)'. No output written; source files left in place."
        Write-Warning $msg
        $result.Warnings.Add($msg)
        $log.Add('')
        $log.Add($msg)
        if (-not $DryRun) {
            if (-not (Test-Path -LiteralPath $OutputFolder)) {
                New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
            }
            [System.IO.File]::WriteAllLines($logPath, $log, (New-Object System.Text.UTF8Encoding($false)))
        }
        return $result
    }

    $result.UniqueRows = $data.Count
    $result.DuplicateRows = $result.RowsRead - $data.Count

    if ($data.Count -eq 0) {
        $msg = "No data rows collected for '$($Group.Name)'. Nothing written."
        Write-Warning $msg
        $result.Warnings.Add($msg)
        return $result
    }

    Write-Host "  Sorting $($data.Count) unique row(s)..." -ForegroundColor DarkGray
    Show-SlowHintIfNeeded -WatchPath "$outPath.combining.tmp"
    $sorted = Get-SortedDataRows -Rows $data

    # Rows that share a timestamp but differ elsewhere. After the sort these are
    # adjacent, so one walk finds them all - no second index, no extra memory.
    # They are kept, not resolved: only the sources can say which is right.
    $conflicts = [System.Collections.Generic.List[string]]::new()
    $prevTs = $null
    for ($i = 0; $i -lt $sorted.Length; $i++) {
        $thisTs = Get-FirstFieldRaw -Line $sorted[$i]
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

    $log.Add('')
    $log.Add("Totals:")
    $log.Add("  Files read:            $($result.FilesRead)")
    $log.Add("  Files skipped:         $($result.FilesSkipped)")
    $log.Add("  Data rows read:        $($result.RowsRead)")
    $log.Add("  Unique rows written:   $($result.UniqueRows)")
    $log.Add("  Duplicate rows dropped:$($result.DuplicateRows)")
    $log.Add("  Timestamp conflicts:   $($result.TsConflicts)")
    if ($result.Warnings.Count -gt 0) {
        $log.Add('')
        $log.Add("Warnings:")
        foreach ($w in $result.Warnings) { $log.Add("  - $w") }
    }

    if ($DryRun) {
        Write-Host "  DRY RUN - would write $($sorted.Length) row(s) to $outPath" -ForegroundColor Yellow
        return $result
    }

    if (-not (Test-Path -LiteralPath $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }

    # An existing output file is moved aside rather than overwritten, so a
    # re-run can never destroy the previous result.
    if (Test-Path -LiteralPath $outPath) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($outName)
        $ext = [System.IO.Path]::GetExtension($outName)
        $aside = Join-Path $OutputFolder "$stem`_superseded_$stamp$ext"
        Move-Item -LiteralPath $outPath -Destination $aside -Force -ErrorAction Stop
        Write-Host "  Previous output moved aside: $aside" -ForegroundColor DarkGray
        $log.Add("  Previous output moved aside to: $aside")
    }

    $enc = Resolve-OutputEncoding -Name $Encoding -FilePath $Group.Files[0].FullName
    $tempPath = "$outPath.combining.tmp"

    try {
        # Streamed into a temp file and moved into place. An interrupted write
        # leaves only the temp file behind, never a truncated output, and the
        # temp file visibly grows so a slow run has something to watch.
        #
        # 1 MB buffer, explicitly. These files often live on a network share and
        # StreamWriter's default buffer is a few KB - smaller than a single
        # 2,157-column row, so every WriteLine would become its own SMB
        # round-trip.
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $enc, 1048576)
        $written = 0
        try {
            foreach ($h in $Group.Headers) { $writer.WriteLine($h) }
            foreach ($row in $sorted) {
                $writer.WriteLine($row)
                $written++
                if (($written % 5000) -eq 0) {
                    $writer.Flush()
                    Show-SlowHintIfNeeded -WatchPath $tempPath
                    Write-Progress -Activity "Writing $outName" -Status "$written of $($sorted.Length) rows" `
                        -PercentComplete (100 * $written / [Math]::Max($sorted.Length, 1))
                }
            }
        }
        finally {
            $writer.Dispose()
            Write-Progress -Activity "Writing $outName" -Completed
        }

        Move-Item -LiteralPath $tempPath -Destination $outPath -Force -ErrorAction Stop
        $tempPath = $null
        Write-Host "  Wrote $($sorted.Length) row(s): $outPath" -ForegroundColor Green
    }
    catch {
        $msg = "Failed to write '$outPath': $($_.Exception.Message)"
        Write-Error $msg
        $result.Warnings.Add($msg)
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        $log.Add("  WRITE FAILED: $msg")
        [System.IO.File]::WriteAllLines($logPath, $log, (New-Object System.Text.UTF8Encoding($false)))
        return $result
    }

    # -MoveSources is the only destructive path in this script. It runs after a
    # successful write, and the folder tree is recreated under Sources so two
    # same-named files from different date folders cannot collide. Only files
    # whose rows actually went into the output are moved - a skipped member
    # stays where it is.
    if ($MoveSources) {
        $sourcesRoot = Join-Path $OutputFolder 'Sources'
        $moved = 0
        foreach ($f in $mergedFiles) {
            try {
                $rel = $f.DirectoryName
                if ($rel.StartsWith($script:SourceRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $rel = $rel.Substring($script:SourceRootFull.Length).Trim('\')
                }
                $destDir = if ($rel) { Join-Path $sourcesRoot $rel } else { $sourcesRoot }
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Move-Item -LiteralPath $f.FullName -Destination (Join-Path $destDir $f.Name) -Force -ErrorAction Stop
                $moved++
            }
            catch {
                $msg = "Could not move '$($f.FullName)' to Sources: $($_.Exception.Message)"
                Write-Warning $msg
                $result.Warnings.Add($msg)
            }
        }
        Write-Host "  Moved $moved merged source file(s) into $sourcesRoot" -ForegroundColor DarkGray
        $log.Add('')
        $log.Add("Moved $moved of $($mergedFiles.Count) merged source file(s) into: $sourcesRoot")
        if ($result.FilesSkipped -gt 0) {
            $log.Add("Left $($result.FilesSkipped) skipped source file(s) in place.")
        }
    }

    [System.IO.File]::WriteAllLines($logPath, $log, (New-Object System.Text.UTF8Encoding($false)))
    return $result
}

#endregion

#region Main Script

try {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

    # Root folder: parameter, first positional argument, or a picker.
    $root = $null
    if ($SourceFolder -and (Test-Path -LiteralPath $SourceFolder)) { $root = $SourceFolder }
    elseif ($args.Count -gt 0 -and (Test-Path -LiteralPath $args[0])) { $root = $args[0] }

    if ($root -and -not (Test-Path -LiteralPath $root -PathType Container)) {
        # A file was handed over (right-clicking a file rather than a folder):
        # use its folder, which is what was almost certainly meant.
        Write-Host "A file was supplied; scanning its folder instead: $(Split-Path -Parent $root)" -ForegroundColor Yellow
        $root = Split-Path -Parent $root
    }

    if (-not $root) {
        if ($Unattended) { throw "No source folder supplied and -Unattended forbids the folder picker." }
        $root = Select-FolderDialog -Description "Select the ROOT folder to combine (all subfolders are scanned)" -InitialDir $scriptDir
    }
    if (-not $root) {
        Write-Warning "No folder selected. Exiting."
        return
    }

    $script:SourceRootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
    $root = $script:SourceRootFull

    if (-not $OutputFolder) { $OutputFolder = Join-Path $root 'Combined' }
    $OutputFolder = [System.IO.Path]::GetFullPath($OutputFolder)

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "COMBINE AFFINITY FILES - recursive combine" -ForegroundColor Cyan
    Write-Host "$('=' * 70)" -ForegroundColor Cyan
    Write-Host "Source root:   $root"
    Write-Host "Output folder: $OutputFolder"
    Write-Host "Extensions:    $($Extensions -join ', ')"
    Write-Host "Skipped dirs:  $((@('Backup', 'Combined', 'Sources') + $ExcludeFolders | Where-Object { $_ }) -join ', ')"
    Write-Host "Header rows:   $(if ($script:HeaderRowsExplicit) { "$HeaderRowCount (explicit)" } else { "auto-detect (default $HeaderRowCount)" })"
    Write-Host "Sources:       $(if ($MoveSources) { 'MOVED into Combined\Sources after merge' } else { 'left untouched' })"
    if ($DryRun) { Write-Host "Mode:          DRY RUN - nothing will be written" -ForegroundColor Yellow }
    Write-Host "$('=' * 70)" -ForegroundColor Cyan

    $problems = [System.Collections.Generic.List[string]]::new()

    Start-MergeTimer
    $groups = @(Get-RecursiveMergeGroups `
            -Folder $root `
            -Extensions $Extensions `
            -HeaderRows $HeaderRowCount `
            -HeaderRowsExplicit $script:HeaderRowsExplicit `
            -ExcludeFolder $OutputFolder `
            -ExcludeNames $ExcludeFolders `
            -ForceSingleGroup:$SingleGroup `
            -Problems $problems)

    if ($groups.Count -eq 0) {
        $msg = "No combinable data files found under:`n$root`n`nLooked for *.$($Extensions -join ', *.') in every subfolder, each needing at least $HeaderRowCount header row(s) plus one data row."
        Write-Warning ($msg -replace "`n", ' ')
        if (-not $Unattended) { Show-Notification -Title "Nothing to Combine" -Icon Warning -Message $msg }
        return
    }

    Write-Host ''
    Write-Host "$($groups.Count) dataset(s) to combine:" -ForegroundColor Cyan
    $totalFiles = 0
    $totalBytes = 0
    foreach ($g in $groups) {
        $bytes = ($g.Files | Measure-Object -Property Length -Sum).Sum
        $totalFiles += $g.Files.Count
        $totalBytes += $bytes
        $folders = @($g.Files | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique).Count
        Write-Host ("  {0,-52} {1,5} file(s) in {2,4} folder(s), {3,8:N1} MB" -f $g.Name, $g.Files.Count, $folders, ($bytes / 1MB))
    }
    Write-Host ("  {0,-52} {1,5} file(s), {2,20:N1} MB" -f 'TOTAL', $totalFiles, ($totalBytes / 1MB)) -ForegroundColor DarkGray

    # One confirmation for the whole job, replacing v9's dialog-per-file.
    if (-not $Unattended -and -not $DryRun) {
        $preview = ($groups | Select-Object -First 12 | ForEach-Object { "  $($_.Name)  ($($_.Files.Count) files)" }) -join "`n"
        if ($groups.Count -gt 12) { $preview += "`n  ... and $($groups.Count - 12) more" }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            ("Combine $totalFiles file(s) ($([math]::Round($totalBytes / 1MB, 1)) MB) into $($groups.Count) file(s)?`n`n" +
            "Source root:`n$root`n`nOutput folder:`n$OutputFolder`n`n" +
            "Datasets:`n$preview`n`n" +
            $(if ($MoveSources) { "Source files WILL BE MOVED into Combined\Sources after merging.`n`n" } else { "Source files are NOT modified or moved.`n`n" }) +
                "Duplicate rows are dropped and rows are sorted by timestamp."),
            "Combine Affinity Files - Confirm",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host "Cancelled - nothing was written." -ForegroundColor Yellow
            return
        }
    }

    $summaries = [System.Collections.Generic.List[object]]::new()
    $aborted = $false
    $groupIndex = 0

    foreach ($g in $groups) {
        $groupIndex++
        Write-Host ''
        Write-Host "########## [$groupIndex/$($groups.Count)] $($g.Name)  ($($g.Files.Count) file(s)) ##########" -ForegroundColor Magenta

        # Isolated per dataset: one bad dataset must not stop the rest.
        try {
            $res = Invoke-CombineGroup `
                -Group $g `
                -OutputFolder $OutputFolder `
                -Encoding $Encoding `
                -Unattended:$Unattended `
                -DryRun:$DryRun `
                -MoveSources:$MoveSources `
                -OverrideName $(if ($SingleGroup -and $OutputName) { $OutputName } else { $null })

            $summaries.Add([pscustomobject]@{
                    Name        = $g.Name
                    FilesRead   = $res.FilesRead
                    Skipped     = $res.FilesSkipped
                    RowsRead    = $res.RowsRead
                    Unique      = $res.UniqueRows
                    Dropped     = $res.DuplicateRows
                    TsConflicts = $res.TsConflicts
                    Output      = $res.OutputPath
                })
            foreach ($w in $res.Warnings) { $problems.Add("[$($g.Name)] $w") }

            if ($res.Aborted) { $aborted = $true; break }
        }
        catch {
            $msg = "Dataset '$($g.Name)' failed: $($_.Exception.Message)"
            Write-Warning $msg
            Write-Warning "Continuing with the next dataset."
            $problems.Add($msg)
        }
    }

    $elapsed = if ($script:MergeStopwatch) { $script:MergeStopwatch.Elapsed } else { [TimeSpan]::Zero }

    Write-Host ''
    Write-Host "$('=' * 70)" -ForegroundColor Green
    Write-Host $(if ($aborted) { "COMBINE STOPPED BY USER" } elseif ($DryRun) { "DRY RUN COMPLETE - NOTHING WRITTEN" } else { "COMBINE COMPLETE" }) -ForegroundColor Green
    Write-Host "$('=' * 70)" -ForegroundColor Green
    if ($summaries.Count -gt 0) {
        $summaries | Format-Table -AutoSize Name, FilesRead, Skipped, RowsRead, Unique, Dropped, TsConflicts | Out-String | Write-Host
    }
    Write-Host ("Datasets:      {0} of {1}" -f $summaries.Count, $groups.Count)
    Write-Host ("Files read:    {0}" -f ($summaries | Measure-Object -Property FilesRead -Sum).Sum)
    Write-Host ("Files skipped: {0}" -f ($summaries | Measure-Object -Property Skipped -Sum).Sum)
    Write-Host ("Rows read:     {0}" -f ($summaries | Measure-Object -Property RowsRead -Sum).Sum)
    Write-Host ("Rows written:  {0}" -f ($summaries | Measure-Object -Property Unique -Sum).Sum)
    Write-Host ("Duplicates:    {0}" -f ($summaries | Measure-Object -Property Dropped -Sum).Sum)
    Write-Host ("Elapsed:       {0:hh\:mm\:ss}" -f $elapsed)
    Write-Host ("Output folder: {0}" -f $OutputFolder)
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Host "$($problems.Count) warning(s) - full detail is in each dataset's .merge-log.txt:" -ForegroundColor Yellow
        foreach ($p in ($problems | Select-Object -First 15)) { Write-Host "  - $p" -ForegroundColor Yellow }
        if ($problems.Count -gt 15) { Write-Host "  ... and $($problems.Count - 15) more" -ForegroundColor Yellow }
    }
    Write-Host "$('=' * 70)" -ForegroundColor Green

    if (-not $Unattended) {
        $icon = if ($problems.Count -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        Show-Notification -Icon $icon -Title $(if ($DryRun) { "Dry Run Complete" } elseif ($aborted) { "Combine Stopped" } else { "Combine Complete" }) -Message (
            $(if ($DryRun) { "Dry run complete - nothing was written.`n`n" } elseif ($aborted) { "Stopped by 'Exit All'.`n`n" } else { "Combine complete.`n`n" }) +
            "Datasets:      $($summaries.Count) of $($groups.Count)`n" +
            "Files read:    $(($summaries | Measure-Object -Property FilesRead -Sum).Sum)`n" +
            "Files skipped: $(($summaries | Measure-Object -Property Skipped -Sum).Sum)`n" +
            "Rows read:     $(($summaries | Measure-Object -Property RowsRead -Sum).Sum)`n" +
            "Rows written:  $(($summaries | Measure-Object -Property Unique -Sum).Sum)`n" +
            "Duplicates:    $(($summaries | Measure-Object -Property Dropped -Sum).Sum)`n" +
            "Warnings:      $($problems.Count)`n`n" +
            "Output folder:`n$OutputFolder"
        )
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    $global:LASTEXITCODE = 1
}

#endregion
