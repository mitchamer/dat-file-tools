<#
    Combine DAT Files (v9)
    ----------------------
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
            (.bak/.backup/.backup1/.1/.old/.orig/.copy), and
         b) data files that TOA5 row 1 says came from the SAME LOGGER SERIAL and
            the SAME TABLE - matched on those two fields alone, so the file name
            plays no part in the match:
              18421_SAA_SAA1_DATA_2026-09-08.dat -> 18421_SAA1_DATA.dat
            Row 1 is what the logger itself wrote, so renamed, re-collected and
            card-converted files all match. Extensions must be the same. Within
            a group the primary is the one file whose name does NOT end in a date
            stamp (the file the logger software keeps appending to); if that
            leaves two candidates, or none, the group is reported and skipped
            rather than merged into a guess.
       Only files sitting directly in the chosen folder are scanned - subfolders
       are NOT entered.
         PS> .\'Combine DAT files_v9.ps1'
         (then click "Yes" and pick a folder)

    2) MANUAL MODE (pick files yourself)
       Run with NO primary file and choose "No" at the mode prompt (or select a
       primary via the dialog). You pick the primary file, then one or more
       secondary files to merge into it.
         PS> .\'Combine DAT files_v9.ps1'
         (then click "No", pick a primary, then pick secondaries)

    3) DIRECT / RIGHT-CLICK MODE (file or folder supplied up front)
       Pass a FILE as the first argument (or via -PrimaryFile) and the mode
       prompt is skipped - you go straight to picking secondary files.
       Pass a FOLDER as the first argument and the script runs FOLDER MODE on
       that folder directly (no prompt, no folder picker). This is what the
       right-click context-menu entries use.
         PS> .\'Combine DAT files_v9.ps1' 'C:\Data\TM_Site_Diagnostics.dat'
         PS> .\'Combine DAT files_v9.ps1' -PrimaryFile 'C:\Data\TM_Site_Diagnostics.dat'
         PS> .\'Combine DAT files_v9.ps1' 'C:\Data\SiteFolder'   (folder mode)

    COMPARISON DIALOG BUTTONS
       Proceed              Merge this secondary into the primary.
       Decline (Skip File)  Skip this secondary only; the scan continues with the
                            next duplicate / next group. Esc or closing the window
                            does the same.
       Exit All             Stop immediately - no further files or groups are
                            processed. Already-merged files stay merged.

    OPTIONAL PARAMETERS (all modes)
       -SpecialRowCount <int>   Number of special/metadata rows after the header
                                (default 3 -> rows 2-4 are preserved as-is).
       -NoBackup                Do not create a pre-merge backup of the primary.
       -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                                Output encoding. Default Auto, which matches the
                                primary's existing byte-order mark so merging does
                                not change the file's encoding. ASCII also enables
                                non-ASCII character checks.
         PS> .\'Combine DAT files_v9.ps1' -SpecialRowCount 3 -Encoding Auto

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
    return $values
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

function Show-HeaderComparison {
    <#
        Displays a side-by-side, column-by-column comparison of two lines.
        Returns one of:
          'Proceed' - merge this file
          'Decline' - skip this file and continue with the next one
          'ExitAll' - stop processing everything (remaining files and groups)
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
    $form.Size = New-Object System.Drawing.Size(820, 600)
    $form.MinimumSize = New-Object System.Drawing.Size(600, 440)
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

    $banner.Controls.Add($lblFiles)
    $banner.Controls.Add($lblStatus)

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

    [void]$grid.Columns.Add("Col", "#")
    [void]$grid.Columns.Add("Primary", "Primary")
    [void]$grid.Columns.Add("Secondary", "Secondary")
    [void]$grid.Columns.Add("Status", "Status")
    $grid.Columns["Col"].FillWeight = 12
    $grid.Columns["Col"].DefaultCellStyle.Alignment = 'MiddleCenter'
    $grid.Columns["Col"].DefaultCellStyle.ForeColor = $clrSubtle
    $grid.Columns["Primary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Secondary"].DefaultCellStyle.Font = $fontMono
    $grid.Columns["Status"].FillWeight = 26

    for ($i = 0; $i -lt $maxCols; $i++) {
        $p = if ($i -lt $primaryFields.Count) { $primaryFields[$i] }   else { $null }
        $s = if ($i -lt $secondaryFields.Count) { $secondaryFields[$i] } else { $null }

        if ($null -eq $p) { $status = "Missing in Primary" }
        elseif ($null -eq $s) { $status = "Missing in Secondary" }
        elseif ($p -eq $s) { $status = "Match" }
        else { $status = "Different" }

        $rowIndex = $grid.Rows.Add(($i + 1), $(if ($null -eq $p) { "(none)" }else { $p }), $(if ($null -eq $s) { "(none)" }else { $s }), $status)
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

function Test-NonAsciiCharacters {
    param([string]$FilePath)

    $lines = Get-Content $FilePath
    $nonAsciiLines = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '[^\x00-\x7F]') {
            $nonAsciiLines += ($i + 1)
        }
    }

    if ($nonAsciiLines.Count -gt 0) {
        Write-Warning "Non-ASCII characters found in '$FilePath' on lines: $($nonAsciiLines -join ', ')"
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
           the same SERIAL and the same TABLE are one group, whatever they are
           named:
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
    # A suffix appended after the data extension that marks a backup/version.
    $suffixPattern = '^\.(bak|backup\d*|\d+|old|orig|copy)$'

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

    # Second pass: same serial + same table per TOA5 row 1.
    Add-Toa5SerialTableGroups -AllFiles $allFiles -Groups $groups -DataExt $dataExt

    # Only return groups that actually have a primary AND at least one duplicate.
    return $groups.Values | Where-Object { $_.Primary -and $_.Secondaries.Count -gt 0 }
}

function Add-Toa5SerialTableGroups {
    <#
        Adds re-collected / re-downloaded copies of a logger table to the merge
        groups, matched ONLY on the two pieces of hard evidence the datalogger
        itself wrote into TOA5 row 1:

            "TOA5","TM_MCL-02","CR6","13910","CR6.Std.14.01","prog.cr6","31248","Status"
             0      1 station    2     3 SERIAL 4             5          6       7 TABLE

        Two files belong to the same group when row 1 gives them the SAME SERIAL
        and the SAME TABLE (case-insensitive) - and they share an extension, so a
        merge never changes what kind of file the folder holds. The file NAME is
        not consulted for matching at all, so every naming convention works:

            18421_SAA_SAA1_DATA_2026-09-08.dat  ->  18421_SAA1_DATA.dat
            13910_Status_2026-07-23T15-44.dat   ->  TM_MCL-02_Status.dat
            SAA1_DATA (1).dat                   ->  18421_SAA1_DATA.dat

        WHICH FILE IS THE PRIMARY
        The primary must be the file the logger software keeps appending to -
        merging the other way round leaves the newly merged rows in a file
        nothing collects into. Serial and table cannot tell those apart (they are
        identical by definition here), so exactly one name-shaped rule decides
        the ROLE, never the match: a file whose name ends in a download date
        stamp (_YYYY-MM-DD, optionally with a time) is a download, and anything
        else is a collected file.

          * exactly one collected file in the group -> it is the primary and
            every dated download merges into it, oldest stamp first;
          * two or more collected files (two archives of one table in one
            folder) -> reported and skipped, never merged into a guess;
          * dated downloads only, no collected file -> reported and skipped;
            which download should become the archive is the user's call.

        Files with no readable TOA5 row 1 carry neither serial nor table, so they
        take no part in this pass (backup-suffix matching still covers them).

        $Groups is mutated in place (hashtable keyed by lowercase primary name).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllFiles,
        [Parameter(Mandatory)][hashtable]$Groups,
        [Parameter(Mandatory)][string]$DataExt
    )

    # A trailing download stamp: _2026-09-08, _2026-09-08T15-44, _2026-09-08T15-44-30,
    # and the underscore / dotted-time variants LoggerNet and CardConvert produce.
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
        $serial = $fields[3].Trim()
        $table = $fields[7].Trim()
        if ([string]::IsNullOrWhiteSpace($serial) -or [string]::IsNullOrWhiteSpace($table)) { continue }

        $stamp = if ($base -match $stampSuffix) { $Matches['stamp'] } else { $null }

        $members.Add([pscustomobject]@{
            File   = $f
            Serial = $serial
            Table  = $table
            Ext    = $ext
            Stamp  = $stamp
        })
    }
    if ($members.Count -lt 2) { return }

    # Group on serial + table + extension, and nothing else.
    $sets = @{}
    foreach ($m in $members) {
        $key = '{0}|{1}|{2}' -f $m.Serial.ToLowerInvariant(), $m.Table.ToLowerInvariant(), $m.Ext
        if (-not $sets.ContainsKey($key)) {
            $sets[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $sets[$key].Add($m)
    }

    foreach ($key in @($sets.Keys | Sort-Object)) {
        $set = @($sets[$key])
        if ($set.Count -lt 2) { continue }

        $label = "serial $($set[0].Serial), table '$($set[0].Table)' (.$($set[0].Ext))"
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

        Returns an object with FilesProcessed, RowsAdded, FinalRows, PrimaryPath,
        Aborted. Aborted is $true when the user pressed "Exit All", meaning the
        caller should stop processing any remaining primaries/groups too.
    #>
    param(
        [Parameter(Mandatory)][string]$PrimaryPath,
        [Parameter(Mandatory)][string[]]$SecondaryPaths,
        [int]$SpecialRowCount = 3,
        [string]$Encoding = 'Auto',
        [switch]$NoBackup,
        [switch]$AutoProceedOnHeaderMatch
    )

    $result = [pscustomobject]@{
        FilesProcessed = 0
        RowsAdded      = 0
        FinalRows      = 0
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
    $originalSpecials = if ($specialCountPrimary -gt 0) { $linesPrimary[1..$specialCountPrimary] } else { @() }
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

    $backupFolder = Join-Path (Split-Path -Parent $PrimaryPath) "Backup"
    $primaryBackupPath = $null
    if (-not $NoBackup) {
        $primaryBackupPath = Backup-File -FilePath $PrimaryPath -BackupFolder $backupFolder
    }

    $filesProcessed = 0
    $totalRowsAdded = 0
    $aborted = $false

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

        if ($Encoding -eq 'ASCII' -and -not (Test-NonAsciiCharacters -FilePath $secondaryPath)) {
            Write-Host "Skipping (non-ASCII declined): $secondaryName" -ForegroundColor Yellow
            continue
        }

        $header2 = $secondaryLines[0]
        $specialCount2 = [Math]::Min($SpecialRowCount, $secondaryLines.Count - 1)
        $specials2 = if ($specialCount2 -gt 0) { $secondaryLines[1..$specialCount2] } else { @() }
        $dataStart2 = $specialCount2 + 1
        $data2 = if ($secondaryLines.Count -gt $dataStart2) { $secondaryLines[$dataStart2..($secondaryLines.Count - 1)] } else { @() }

        $primaryRow2 = if ($originalSpecials.Count -ge 1) { $originalSpecials[0] } else { $originalHeader }
        $secondaryRow2 = if ($specials2.Count -ge 1) { $specials2[0] } else { $header2 }

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
                -ComparisonTitle "Step 1 of 2: Header Row Comparison"
        }

        if ($row2Choice -eq 'ExitAll') {
            Write-Host "Exit All requested at header row comparison. Stopping." -ForegroundColor Yellow
            $aborted = $true
            break
        }
        if ($row2Choice -ne 'Proceed') {
            Write-Host "Skipping $secondaryName (declined at header row comparison)" -ForegroundColor Yellow
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

        # Merge data
        $rowsBefore = $currentData.Count
        foreach ($line in $data2) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$currentData.Add($line) }
        }
        Show-SlowHintIfNeeded -WatchPath "$PrimaryPath.combining.tmp"
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

            $backupPath = Join-Path $backupFolder $secondaryName
            if (Test-Path $backupPath) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($secondaryName)
                $extension = [System.IO.Path]::GetExtension($secondaryName)
                $backupPath = Join-Path $backupFolder "${baseName}_${timestamp}${extension}"
            }

            Move-Item -Path $secondaryPath -Destination $backupPath -Force -ErrorAction Stop

            Write-Host "Successfully merged and backed up: $secondaryName" -ForegroundColor Green
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
            continue
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
            "          row 1 shows the same logger serial and table)`n`n" +
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

        $groups = @(Get-DuplicateGroups -Folder $folder)

        if ($groups.Count -eq 0) {
            Show-Notification -Title "No Duplicates Found" -Icon Warning -Message (
                "No duplicate file groups were found in:`n$folder`n`n" +
                "A group needs a data file (.dat/.csv/.txt) plus at least one of:`n" +
                "  - a backup-style duplicate (.bak/.backup/.backup1/.1 ...), or`n" +
                "  - another data file of the same extension whose TOA5 row 1`n" +
                "    gives the same logger serial and the same table name, with`n" +
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
                    -AutoProceedOnHeaderMatch

                $totalFiles += $res.FilesProcessed
                $totalRows += $res.RowsAdded
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
        Write-Host $(if ($userAborted) { "FOLDER SCAN STOPPED BY USER" } else { "FOLDER SCAN COMPLETE" }) -ForegroundColor Green
        Write-Host "$('=' * 70)" -ForegroundColor Green
        Write-Host "Groups found:      $($groups.Count)"
        Write-Host "Groups processed:  $groupsVisited"
        Write-Host "Groups merged:     $groupsMerged"
        Write-Host "Files merged:      $totalFiles"
        Write-Host "Rows added total:  $totalRows"
        if ($userAborted) { Write-Host "Groups skipped:    $remaining (Exit All)" -ForegroundColor Yellow }
        Write-Host "$('=' * 70)" -ForegroundColor Green

        Show-Notification -Title $(if ($userAborted) { "Folder Scan Stopped" } else { "Folder Scan Complete" }) -Message (
            $(if ($userAborted) { "Folder scan stopped by 'Exit All'.`n`n" } else { "Folder scan complete.`n`n" }) +
            "Folder:                 $folder`n" +
            "Groups found:       $($groups.Count)`n" +
            "Groups processed: $groupsVisited`n" +
            "Groups merged:     $groupsMerged`n" +
            "Files merged:         $totalFiles`n" +
            "Rows added:           $totalRows" +
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
        -NoBackup:$NoBackup

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
        Write-Host "MERGE COMPLETE" -ForegroundColor Green
        Write-Host "$('=' * 70)" -ForegroundColor Green
        Write-Host "Files processed: $($res.FilesProcessed)"
        Write-Host "Total new rows added: $($res.RowsAdded)"
        Write-Host "Final unique data rows: $($res.FinalRows)"
        Write-Host "Updated file: $primaryPath"
        Write-Host "$('=' * 70)" -ForegroundColor Green

        Show-Notification -Title "Merge Complete" -Message (
            "Merging complete.`n`nFiles processed: $($res.FilesProcessed)`nTotal rows: $($res.FinalRows)`n`nFinal file:`n$primaryPath"
        )
    }
}
catch {
    Write-Error "Fatal error: $_"
    Write-Error $_.ScriptStackTrace
    $global:LASTEXITCODE = 1
}

#endregion
