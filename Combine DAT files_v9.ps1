<#
    Combine DAT Files (v9)
    ----------------------
    Combines structured, timestamp-based data files (TOA5 .dat/.csv/.txt) into a
    single primary file. Preserves the primary file's header + special rows,
    visually compares headers before merging, de-duplicates and sorts data, and
    moves merged secondaries into a Backup folder.

    THREE WAYS TO INVOKE
    ====================

    1) FOLDER MODE (auto-group duplicates)
       Run with NO primary file. A dialog appears - choose "Yes" to scan a folder.
       The script groups two kinds of duplicate, then for each group compares
       row 2 (header) then row 1 (file info):
         a) backup-style duplicates
            (.bak/.backup/.backup1/.1/.old/.orig/.copy), and
         b) LoggerNet/CardConvert timestamped downloads
            <serial>_<Table>_<YYYY-MM-DDTHH-MM[-SS]>.dat merged into the
            collected file holding the same table:
              13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat
                -> TM_MCL-02_SAA_DIAGNOSTICS.dat
            The table is read from TOA5 row 1 (last field), not from the file
            name, so renamed collected files still match. Extensions must be the
            same, and if more than one file could be the target the download is
            reported and skipped instead of being merged into a guess.
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
       -Encoding <UTF8|ASCII|Unicode>   Output encoding (default UTF8). ASCII also
                                enables non-ASCII character checks.
         PS> .\'Combine DAT files_v9.ps1' -SpecialRowCount 3 -Encoding UTF8
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PrimaryFile,

    [Parameter()]
    [int]$SpecialRowCount = 3,

    [Parameter()]
    [switch]$NoBackup,

    [Parameter()]
    [ValidateSet('UTF8', 'ASCII', 'Unicode')]
    [string]$Encoding = 'UTF8'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region Helper Functions

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
        builds merge groups from two naming conventions:

        1) BACKUP SUFFIXES - files sharing the same canonical data-file name plus
           an extra suffix such as .bak, .backup, .backup1, .1, .old, .orig, .copy.

        2) LOGGERNET TIMESTAMPED DOWNLOADS - files named
              <serial>_<Table>_<YYYY-MM-DDTHH-MM[-SS]>.<ext>
           (e.g. 13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat) are merged into the
           collected file for the same table in the same folder
              <Station>_<Table>.<ext>
           (e.g. TM_MCL-02_SAA_DIAGNOSTICS.dat).
           Matching is deliberately strict - see Add-LoggerNetDownloadGroups.

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

    # Second pass: LoggerNet / CardConvert timestamped downloads.
    Add-LoggerNetDownloadGroups -AllFiles $allFiles -Groups $groups -DataExt $dataExt

    # Only return groups that actually have a primary AND at least one duplicate.
    return $groups.Values | Where-Object { $_.Primary -and $_.Secondaries.Count -gt 0 }
}

function Add-LoggerNetDownloadGroups {
    <#
        Adds LoggerNet / CardConvert timestamped downloads to the merge groups.

        A SECONDARY must look exactly like:
            <serial>_<Table>_<YYYY-MM-DDTHH-MM[-SS]>.<dat|csv|txt>
            13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat
        i.e. a digits-only leading serial, underscore-separated table name, then an
        ISO-style date, a literal 'T', and a hyphen-separated time - and NOTHING
        after the stamp except the data extension.

        Its PRIMARY is the collected file for the SAME TABLE in the same folder,
        e.g. TM_MCL-02_SAA_DIAGNOSTICS.dat.

        The table is taken from TOA5 row 1 (field 8), not from the file name:
            "TOA5","TM_MCL-02","CR6","13910","CR6.Std.14.01","prog.cr6","31248","Status"
             0      1 station    2     3 serial 4              5          6       7 table
        The name in row 1 is what the datalogger actually wrote, so it survives
        renamed / re-collected files. The file name is only used to recognise a
        download in the first place, and as a fallback for files that have no
        TOA5 row 1 at all.

        Strictness rules (mis-matching is worse than not matching):
          * the download name must match the pattern above exactly - digits-only
            serial, an ISO date + 'T' + hyphenated time, nothing after the stamp;
          * row-1 table names must be equal (case-insensitive);
          * extensions must be the same;
          * the primary must not itself be a timestamped download or a backup file;
          * exactly ONE primary candidate must remain, otherwise the download is
            skipped and reported - never guessed at. Ties are broken only by hard
            evidence: the row-1 serial number, then the file name's table suffix.

        $Groups is mutated in place (hashtable keyed by lowercase primary name).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllFiles,
        [Parameter(Mandatory)][hashtable]$Groups,
        [Parameter(Mandatory)][string]$DataExt
    )

    $tableToken = '[A-Za-z0-9][A-Za-z0-9-]*'
    $stamp = '\d{4}-\d{2}-\d{2}T\d{2}-\d{2}(?:-\d{2})?'
    $loggerPattern = "^(?<serial>\d{3,10})_(?<table>$tableToken(?:_$tableToken)*)_(?<stamp>$stamp)\.(?<ext>$DataExt)$"

    # Oldest download first so merges happen in chronological order.
    $downloads = @(
        $AllFiles |
            Where-Object { $_.Name -match $loggerPattern } |
            Sort-Object -Property @{ Expression = { if ($_.Name -match $loggerPattern) { $Matches['stamp'] } else { '' } } }, Name
    )
    if ($downloads.Count -eq 0) { return }

    # Row 1 is read once per file - these folders often live on a slow share.
    $toa5Cache = @{}
    $getFields = {
        param([string]$Path)
        if (-not $toa5Cache.ContainsKey($Path)) {
            $toa5Cache[$Path] = Get-Toa5EnvironmentFields -FilePath $Path
        }
        return $toa5Cache[$Path]
    }

    # Candidate primaries: data files that are neither timestamped downloads nor
    # backup files (a trailing .bak/.1/... means the data extension is not last,
    # so those simply fail this pattern).
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $AllFiles) {
        if ($f.Name -match $loggerPattern) { continue }
        if ($f.Name -notmatch "^(?<base>.+)\.(?<ext>$DataExt)$") { continue }
        # Read $Matches before anything else can overwrite it.
        $base = $Matches['base']
        $fileExt = $Matches['ext']
        $fields = & $getFields $f.FullName
        $candidates.Add([pscustomobject]@{
            File   = $f
            Base   = $base
            Ext    = $fileExt
            Table  = if ($fields) { $fields[7].Trim() } else { $null }
            Serial = if ($fields) { $fields[3].Trim() } else { $null }
        })
    }

    foreach ($d in $downloads) {
        [void]($d.Name -match $loggerPattern)
        $nameTable = $Matches['table']
        $ext = $Matches['ext']

        $dFields = & $getFields $d.FullName
        # Row 1 is the authority; the file name only fills in for non-TOA5 files.
        $table = if ($dFields) { $dFields[7].Trim() } else { $nameTable }
        $dSerial = if ($dFields) { $dFields[3].Trim() } else { $null }
        $tableSource = if ($dFields) { 'row 1' } else { 'file name' }

        $pool = @($candidates | Where-Object { $_.Ext -eq $ext })

        # 1) Table name from row 1 - the normal path.
        $targets = @($pool | Where-Object { $_.Table -and $_.Table -eq $table })

        # 2) Only files with no TOA5 row 1 fall back to the name's table suffix.
        #    A file that HAS row 1 and disagrees is never matched by name.
        if ($targets.Count -eq 0) {
            $tail = "_$table"
            $targets = @(
                $pool | Where-Object {
                    -not $_.Table -and
                    $_.Base.Length -gt $tail.Length -and
                    $_.Base.EndsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)
                }
            )
        }

        # 3) Two collected files for the same table (two stations in one folder):
        #    break the tie on the row-1 serial number, then on the name suffix.
        if ($targets.Count -gt 1 -and $dSerial) {
            $narrowed = @($targets | Where-Object { $_.Serial -and $_.Serial -eq $dSerial })
            if ($narrowed.Count -gt 0) { $targets = $narrowed }
        }
        if ($targets.Count -gt 1) {
            $tail = "_$nameTable"
            $narrowed = @(
                $targets | Where-Object {
                    $_.Base.Length -gt $tail.Length -and
                    $_.Base.EndsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)
                }
            )
            if ($narrowed.Count -gt 0) { $targets = $narrowed }
        }

        if ($targets.Count -eq 0) {
            Write-Host ("  Skipped '$($d.Name)': no .$ext file in this folder holds table " +
                "'$table' (from $tableSource).") -ForegroundColor DarkYellow
            continue
        }
        if ($targets.Count -gt 1) {
            $names = ($targets | ForEach-Object { $_.File.Name }) -join ', '
            Write-Warning "Skipped '$($d.Name)': table '$table' is ambiguous ($names). Merge it manually."
            continue
        }

        $primaryFile = $targets[0].File
        $keyLower = $primaryFile.Name.ToLowerInvariant()
        if (-not $Groups.ContainsKey($keyLower)) {
            $Groups[$keyLower] = [pscustomobject]@{
                Key         = $primaryFile.Name
                Primary     = $primaryFile.FullName
                Secondaries = [System.Collections.Generic.List[string]]::new()
            }
        }
        if (-not $Groups[$keyLower].Primary) { $Groups[$keyLower].Primary = $primaryFile.FullName }
        if (-not $Groups[$keyLower].Secondaries.Contains($d.FullName)) {
            $Groups[$keyLower].Secondaries.Add($d.FullName)
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
        [string]$Encoding = 'UTF8',
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

    $linesPrimary = Get-Content $PrimaryPath
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
    if ($linesPrimary.Count -gt $dataStartIndex) {
        foreach ($line in $linesPrimary[$dataStartIndex..($linesPrimary.Count - 1)]) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$currentData.Add($line) }
        }
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
        $secondaryLines = Get-Content $secondaryPath

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
        $rowsAdded = $currentData.Count - $rowsBefore
        $totalRowsAdded += $rowsAdded

        Write-Host "Added $rowsAdded new unique row(s). Total: $($currentData.Count)" -ForegroundColor Green

        # Write updated primary and move secondary to backup
        try {
            $sortedData = $currentData | Sort-Object {
                $fields = $_ -split ','
                if ($fields.Count -gt 0) { $fields[0] } else { $_ }
            }

            $outputLines = @($originalHeader) + $originalSpecials + $sortedData
            $outputLines | Set-Content -Path $PrimaryPath -Encoding $Encoding -ErrorAction Stop

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
            Write-Warning "Primary file may be partially updated. Check backup if needed."
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
            "          (matches .bak / .backup / .backup1 / .1 ...)`n`n" +
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
                "  - a LoggerNet download named`n" +
                "    <serial>_<Table>_<YYYY-MM-DDTHH-MM>.dat whose TOA5 table`n" +
                "    name matches a collected file in the same folder."
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
