#Requires -Version 5.1
<#
    Decimate (v3)
    -------------
    Thins time-series CSV / DAT files by keeping only rows that land on a fixed
    interval - hourly, six-hourly, or daily. Header rows are detected and
    preserved, the original is copied to a Backup folder, and the thinned result
    replaces the original file under its original name.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    This script REPLACES DATA FILES IN PLACE. Licensed under GPL-3.0 and provided
    "as is" with no warranty of any kind (see LICENSE sections 15-17). You are
    responsible for verifying output before relying on it. Decimation is lossy by
    definition: discarded rows exist only in the backup copy.

    Read these before pointing it at anything you cannot regenerate:

      * ROWS MUST LAND ON THE INTERVAL. Hourly keeps rows at HH:00 (seconds are
        allowed to be 0 or absent). Data logged at :05 or :07 matches nothing, so
        every data row would be dropped. v3 refuses to write a file that would
        keep no data rows unless you pass -Force, and the confirmation dialog
        shows the before/after counts - but check your logging offset anyway.
      * NO BACKUP IS MADE IF THE INPUT IS ALREADY INSIDE A "Backup" FOLDER. v3
        refuses such files outright rather than overwriting them unprotected;
        pass -Force to override.
      * THE ORIGINAL FILENAME IS KEPT, so a thinned file is indistinguishable
        from a full one by name. The full copy is Backup\<name>_fulldataset<ext>.
      * DISCARDED ROWS ARE GONE from the working file. The backup is the only copy.

    On failure the original is left untouched and temporary files are cleaned up.
    Supports -WhatIf. Test on copies first, and confirm the row count and time
    range of the result.

    RUNNING IT
    ==========
    Interactive - a settings dialog, then a file picker, then a per-file
    confirmation showing rows in / rows kept:

        .\Decimate_v3.ps1

    Non-interactive - supplying -Mode suppresses all dialogs:

        .\Decimate_v3.ps1 -Mode Hourly -RetainFirst 5 `
                          -Path 'C:\Data\Station1.csv','C:\Data\Station2.dat'

        .\Decimate_v3.ps1 -Mode Daily -Path 'C:\Data\*.dat' -WhatIf

    The v2 parameter names (-ModeParam, -RetainParam, -FilesParam) still work as
    aliases, so existing scheduled calls keep running.

    TIMESTAMPS
    ==========
    The first column must be a timestamp in one of:
        yyyy-MM-dd HH:mm:ss.fff     yyyy-MM-dd HH:mm:ss
        yyyy-MM-dd HH:mm            yyyy-MM-ddTHH:mm:ss[.fff]
    v2 accepted only 'yyyy-MM-dd HH:mm:ss', which silently did nothing to TOA5
    files that carry fractional seconds.

    Emits one summary object per file (Path, RowsIn, RowsKept, RowsDropped,
    Unparseable, Action), so results can be captured or piped.
#>
# SupportsShouldProcess gives -WhatIf and -Confirm. ConfirmImpact is deliberately
# left at the default: setting it to High makes every run prompt, which throws
# outright under -NonInteractive and would break scheduled use. Safety here comes
# from the refuse-to-empty guard and the preview dialog, not a blanket prompt.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # Interval to thin to. Supplying this switches the script to
    # non-interactive: no dialogs are shown.
    [Parameter()]
    [ValidateSet('Hourly', 'SixHourly', 'Daily')]
    [Alias('ModeParam')]
    [string]$Mode,

    # Keep the first N rows that carry a valid timestamp regardless of interval.
    # Useful for SAA files whose initialisation rows matter. 0 disables.
    [Parameter()]
    [ValidateRange(0, [int]::MaxValue)]
    [Alias('RetainParam')]
    [int]$RetainFirst = 0,

    # Files to process. Wildcards are expanded. Omit to get a file picker.
    [Parameter(Position = 0)]
    [Alias('FilesParam')]
    [string[]]$Path,

    # Do not copy the original into Backup\ before replacing it. This removes
    # your only automatic undo.
    [Parameter()]
    [switch]$NoBackup,

    # Output encoding. 'Auto' (default) matches the input file's byte-order mark,
    # so the file is not silently re-encoded. v2 always wrote UTF8, which under
    # PowerShell 5.1 means UTF8 *with* a BOM.
    [Parameter()]
    [ValidateSet('Auto', 'UTF8', 'UTF8BOM', 'ASCII', 'Unicode')]
    [string]$Encoding = 'Auto',

    # Override the safety guards: allows writing a file that would keep zero data
    # rows, and allows processing a file that already sits inside a Backup folder.
    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Interactive = -not $PSBoundParameters.ContainsKey('Mode')

# ==========================================================================
# Timestamp handling
# ==========================================================================

# Ordered most specific first. TOA5 output commonly carries fractional seconds,
# which v2 could not parse at all.
$script:StampFormats = [string[]]@(
    'yyyy-MM-dd HH:mm:ss.fff',
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-ddTHH:mm:ss.fff',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm'
)
$script:StampCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Parse the first comma-separated field of a line as a timestamp.
# Returns $null when it is not a timestamp, so callers can treat "not data" and
# "bad data" the same way.
function Get-RowStamp {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    # Split on the first comma only, so commas inside later fields are irrelevant.
    $field = ($Line -split ',', 2)[0].Trim().Trim('"').Trim()
    if (-not $field) { return $null }

    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $field, $script:StampFormats, $script:StampCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$parsed)
    if ($ok) { return $parsed }
    return $null
}

function Test-StampOnInterval {
    param([datetime]$Stamp, [string]$IntervalMode)

    # Sub-minute components must be zero for every mode.
    if ($Stamp.Second -ne 0 -or $Stamp.Millisecond -ne 0) { return $false }
    if ($Stamp.Minute -ne 0) { return $false }

    switch ($IntervalMode) {
        'Hourly'    { return $true }
        'SixHourly' { return (($Stamp.Hour % 6) -eq 0) }
        'Daily'     { return ($Stamp.Hour -eq 0) }
    }
    return $false
}

# ==========================================================================
# Encoding
# ==========================================================================

# Sniff the byte-order mark so 'Auto' can write the file back the way it came in.
function Get-FileEncoding {
    param([string]$FilePath)

    $bytes = New-Object byte[] 4
    $read = 0
    $stream = [System.IO.File]::OpenRead($FilePath)
    try { $read = $stream.Read($bytes, 0, 4) } finally { $stream.Dispose() }

    if ($read -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))     # UTF8 with BOM
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return (New-Object System.Text.UnicodeEncoding($false, $true))
    }
    if ($read -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return (New-Object System.Text.UnicodeEncoding($true, $true))
    }
    return (New-Object System.Text.UTF8Encoding($false))        # UTF8, no BOM
}

function Resolve-OutputEncoding {
    param([string]$Name, [string]$FilePath)

    switch ($Name) {
        'Auto'    { return (Get-FileEncoding -FilePath $FilePath) }
        'UTF8'    { return (New-Object System.Text.UTF8Encoding($false)) }
        'UTF8BOM' { return (New-Object System.Text.UTF8Encoding($true)) }
        'ASCII'   { return ([System.Text.Encoding]::ASCII) }
        'Unicode' { return (New-Object System.Text.UnicodeEncoding($false, $true)) }
    }
    return (New-Object System.Text.UTF8Encoding($false))
}

# ==========================================================================
# UI
# ==========================================================================

$script:FormsLoaded = $false
function Initialize-Forms {
    if ($script:FormsLoaded) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $script:FormsLoaded = $true
}

# Settings dialog: replaces v2's two Read-Host prompts, which appeared in a
# console window that flashes past when the script is launched from Explorer.
function Show-SettingsDialog {
    Initialize-Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Decimate - settings'
    $form.Size = New-Object System.Drawing.Size(400, 300)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = 'Keep rows at'
    $group.Location = New-Object System.Drawing.Point(14, 12)
    $group.Size = New-Object System.Drawing.Size(360, 100)

    $radios = @{}
    $specs = @(
        @{ Key = 'Hourly';    Text = 'Every hour        (HH:00)';           Y = 22 },
        @{ Key = 'SixHourly'; Text = 'Every six hours   (00, 06, 12, 18)';  Y = 46 },
        @{ Key = 'Daily';     Text = 'Once a day        (00:00)';           Y = 70 }
    )
    foreach ($spec in $specs) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = $spec.Text
        $rb.Location = New-Object System.Drawing.Point(14, $spec.Y)
        $rb.Size = New-Object System.Drawing.Size(330, 20)
        $group.Controls.Add($rb)
        $radios[$spec.Key] = $rb
    }
    $radios['Hourly'].Checked = $true
    $form.Controls.Add($group)

    $lblRetain = New-Object System.Windows.Forms.Label
    $lblRetain.Text = 'Also keep the first N rows (0 = none). SAA files often need 5:'
    $lblRetain.Location = New-Object System.Drawing.Point(16, 124)
    $lblRetain.Size = New-Object System.Drawing.Size(360, 18)
    $form.Controls.Add($lblRetain)

    $numRetain = New-Object System.Windows.Forms.NumericUpDown
    $numRetain.Location = New-Object System.Drawing.Point(16, 146)
    $numRetain.Size = New-Object System.Drawing.Size(80, 22)
    $numRetain.Minimum = 0
    $numRetain.Maximum = 100000
    $numRetain.Value = 0
    $form.Controls.Add($numRetain)

    $chkBackup = New-Object System.Windows.Forms.CheckBox
    $chkBackup.Text = 'Copy the original into a Backup folder first (recommended)'
    $chkBackup.Location = New-Object System.Drawing.Point(16, 180)
    $chkBackup.Size = New-Object System.Drawing.Size(360, 20)
    $chkBackup.Checked = $true
    $form.Controls.Add($chkBackup)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Choose files...'
    $btnOk.Location = New-Object System.Drawing.Point(196, 218)
    $btnOk.Size = New-Object System.Drawing.Size(100, 28)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(302, 218)
    $btnCancel.Size = New-Object System.Drawing.Size(72, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.CancelButton = $btnCancel

    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        $chosen = 'Hourly'
        foreach ($key in $radios.Keys) { if ($radios[$key].Checked) { $chosen = $key } }
        return [pscustomobject]@{
            Mode        = $chosen
            RetainFirst = [int]$numRetain.Value
            Backup      = [bool]$chkBackup.Checked
        }
    } finally {
        $form.Dispose()
    }
}

function Select-DataFiles {
    Initialize-Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dlg.Title = 'Select CSV or DAT files to decimate'
        $dlg.Filter = 'CSV and DAT Files (*.csv;*.dat)|*.csv;*.dat|CSV Files (*.csv)|*.csv|DAT Files (*.dat)|*.dat|All Files (*.*)|*.*'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return @() }
        return @($dlg.FileNames)
    } finally {
        $dlg.Dispose()
    }
}

# Per-file confirmation showing what the merge would actually cost. This is the
# main safety addition in v3: v2 wrote first and reported afterwards, so a file
# whose timestamps were off the interval was emptied before you could react.
function Show-PreviewDialog {
    param([pscustomobject]$Preview)

    Initialize-Forms

    $keepsNothing = ($Preview.RowsKept -le 0)
    $pct = 0
    if ($Preview.RowsIn -gt 0) { $pct = [math]::Round(100 * $Preview.RowsKept / $Preview.RowsIn, 1) }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Decimate - confirm'
    $form.Size = New-Object System.Drawing.Size(560, 340)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $lblFile = New-Object System.Windows.Forms.Label
    $lblFile.Text = [System.IO.Path]::GetFileName($Preview.Path)
    $lblFile.Font = New-Object System.Drawing.Font($form.Font, [System.Drawing.FontStyle]::Bold)
    $lblFile.Location = New-Object System.Drawing.Point(14, 12)
    $lblFile.Size = New-Object System.Drawing.Size(520, 20)
    $form.Controls.Add($lblFile)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Vertical'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Location = New-Object System.Drawing.Point(14, 38)
    $box.Size = New-Object System.Drawing.Size(520, 180)

    $lines = @()
    $lines += "Mode              : $($Preview.Mode)"
    if ($Preview.RetainFirst -gt 0) { $lines += "Retain first      : $($Preview.RetainFirst) row(s)" }
    $lines += "Header rows       : $($Preview.HeaderRows) (preserved)"
    $lines += ''
    $lines += "Data rows in      : $($Preview.RowsIn)"
    $lines += "Data rows kept    : $($Preview.RowsKept)   ($pct%)"
    $lines += "Data rows dropped : $($Preview.RowsDropped)"
    if ($Preview.Unparseable -gt 0) {
        $lines += "Unparseable rows  : $($Preview.Unparseable) (kept as-is)"
    }
    $lines += ''
    if ($Preview.FirstKept -and $Preview.LastKept) {
        $lines += "Kept range        : $($Preview.FirstKept)  ..  $($Preview.LastKept)"
    }
    if ($Preview.BackupPath) {
        $lines += "Full copy saved to: $($Preview.BackupPath)"
    } else {
        $lines += 'Full copy         : NONE - no backup will be made'
    }
    if ($keepsNothing) {
        $lines += ''
        $lines += 'WARNING: this would leave NO data rows.'
        $lines += 'The timestamps in this file do not land on the chosen interval.'
        $lines += 'Check the logging interval and offset before proceeding.'
    }
    $box.Text = ($lines -join "`r`n")
    $form.Controls.Add($box)

    if ($keepsNothing) {
        $warn = New-Object System.Windows.Forms.Label
        $warn.Text = 'Keeping nothing - proceeding would empty this file.'
        $warn.ForeColor = [System.Drawing.Color]::Firebrick
        $warn.Font = New-Object System.Drawing.Font($form.Font, [System.Drawing.FontStyle]::Bold)
        $warn.Location = New-Object System.Drawing.Point(14, 224)
        $warn.Size = New-Object System.Drawing.Size(520, 20)
        $form.Controls.Add($warn)
    }

    # Same button vocabulary as the Combine tool, so the two feel like one set.
    $btnProceed = New-Object System.Windows.Forms.Button
    $btnProceed.Text = 'Proceed'
    $btnProceed.Location = New-Object System.Drawing.Point(232, 254)
    $btnProceed.Size = New-Object System.Drawing.Size(90, 30)
    $btnProceed.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $btnProceed.Enabled = (-not $keepsNothing) -or $Force
    $form.Controls.Add($btnProceed)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = 'Skip file'
    $btnSkip.Location = New-Object System.Drawing.Point(328, 254)
    $btnSkip.Size = New-Object System.Drawing.Size(90, 30)
    $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::No
    $form.Controls.Add($btnSkip)
    $form.CancelButton = $btnSkip

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = 'Exit all'
    $btnExit.Location = New-Object System.Drawing.Point(424, 254)
    $btnExit.Size = New-Object System.Drawing.Size(90, 30)
    $btnExit.DialogResult = [System.Windows.Forms.DialogResult]::Abort
    $form.Controls.Add($btnExit)

    if ($btnProceed.Enabled) { $form.AcceptButton = $btnProceed }

    try {
        $result = $form.ShowDialog()
    } finally {
        $form.Dispose()
    }

    switch ($result) {
        ([System.Windows.Forms.DialogResult]::Yes)   { return 'Proceed' }
        ([System.Windows.Forms.DialogResult]::Abort) { return 'ExitAll' }
        default                                     { return 'Skip' }
    }
}

# ==========================================================================
# Core
# ==========================================================================

# Streams the input, writing kept rows to a temp file and counting as it goes.
# Nothing touches the original here, so the caller can show the counts and then
# decide - which is what makes the preview possible without a second pass over
# what may be a very large file.
function Invoke-Decimation {
    param(
        [string]$FilePath,
        [string]$IntervalMode,
        [int]$Retain,
        [System.Text.Encoding]$OutputEncoding
    )

    $dir = [System.IO.Path]::GetDirectoryName($FilePath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $tempPath = Join-Path $dir ("{0}_decimating_{1}_{2}.tmp" -f $baseName, $IntervalMode, [guid]::NewGuid().ToString('N').Substring(0, 8))

    $headerRows = 0
    $rowsIn = 0
    $rowsKept = 0
    $unparseable = 0
    $retained = 0
    $sawAnyStamp = $false
    $firstKept = $null
    $lastKept = $null
    $badSamples = New-Object System.Collections.ArrayList
    $inHeader = $true

    $writer = New-Object System.IO.StreamWriter($tempPath, $false, $OutputEncoding)
    try {
        foreach ($line in [System.IO.File]::ReadLines($FilePath)) {
            $stamp = Get-RowStamp -Line $line

            # Leading rows without a timestamp are the header block. Once a
            # timestamp has been seen, the header is over - a later unparseable
            # row is bad data, not a header.
            if ($inHeader) {
                if ($null -eq $stamp) {
                    $headerRows++
                    $writer.WriteLine($line)
                    continue
                }
                $inHeader = $false
            }

            if ($null -eq $stamp) {
                # Kept rather than dropped: dropping a row we cannot understand
                # would be destroying data on a guess.
                $unparseable++
                if ($badSamples.Count -lt 3) { [void]$badSamples.Add($line) }
                $writer.WriteLine($line)
                continue
            }

            $sawAnyStamp = $true
            $rowsIn++

            $keep = $false
            if ($retained -lt $Retain) {
                $keep = $true
                $retained++
            } elseif (Test-StampOnInterval -Stamp $stamp -IntervalMode $IntervalMode) {
                $keep = $true
            }

            if ($keep) {
                $writer.WriteLine($line)
                $rowsKept++
                if ($null -eq $firstKept) { $firstKept = $stamp }
                $lastKept = $stamp
            }
        }
    } catch {
        $writer.Dispose()
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        throw
    }
    $writer.Dispose()

    # Formatted outside the literal: an `if` expression inside a hashtable is not
    # reliable across PowerShell 5.1 and 7.
    $fmt = 'yyyy-MM-dd HH:mm:ss'
    $firstKeptText = $null
    $lastKeptText = $null
    if ($null -ne $firstKept) { $firstKeptText = $firstKept.ToString($fmt) }
    if ($null -ne $lastKept) { $lastKeptText = $lastKept.ToString($fmt) }

    return [pscustomobject]@{
        Path        = $FilePath
        TempPath    = $tempPath
        Mode        = $IntervalMode
        RetainFirst = $Retain
        HeaderRows  = $headerRows
        RowsIn      = $rowsIn
        RowsKept    = $rowsKept
        RowsDropped = ($rowsIn - $rowsKept)
        Unparseable = $unparseable
        BadSamples  = $badSamples.ToArray()
        SawAnyStamp = $sawAnyStamp
        FirstKept   = $firstKeptText
        LastKept    = $lastKeptText
        BackupPath  = $null
    }
}

function Save-Decimation {
    param([pscustomobject]$Preview, [switch]$SkipBackup)

    $FilePath = $Preview.Path
    $dir = [System.IO.Path]::GetDirectoryName($FilePath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath)
    $backupPath = $null

    if (-not $SkipBackup) {
        $backupDir = Join-Path $dir 'Backup'
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $backupPath = Join-Path $backupDir ("{0}_fulldataset{1}" -f $baseName, $ext)
        if (Test-Path -LiteralPath $backupPath) {
            $stamp = Get-Date -Format 'yyyyMMddHHmmss'
            $backupPath = Join-Path $backupDir ("{0}_fulldataset_{1}{2}" -f $baseName, $stamp, $ext)
        }
        Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force
    }

    try {
        Move-Item -LiteralPath $Preview.TempPath -Destination $FilePath -Force
    } catch {
        # Roll the backup back so a failed run leaves no confusing artefacts.
        if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    return $backupPath
}

function Remove-TempFile {
    param([string]$TempPath)
    if ($TempPath -and (Test-Path -LiteralPath $TempPath)) {
        # -WhatIf:$false because -WhatIf propagates into called cmdlets: without
        # it, a -WhatIf run skips its own cleanup and leaves .tmp files behind.
        # This file is our scratch, never user data, so removing it is not
        # something anyone needs to preview.
        Remove-Item -LiteralPath $TempPath -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# ==========================================================================
# Main
# ==========================================================================

$settings = $null
if ($script:Interactive) {
    $settings = Show-SettingsDialog
    if ($null -eq $settings) { Write-Host 'Cancelled.'; return }
    $Mode = $settings.Mode
    $RetainFirst = $settings.RetainFirst
    if (-not $settings.Backup) { $NoBackup = [switch]::Present }
}

# Resolve the file list. Wildcards are expanded; missing paths are reported
# rather than silently skipped, which v2 did not check at all.
$targets = New-Object System.Collections.ArrayList
if ($Path -and $Path.Count -gt 0) {
    foreach ($p in $Path) {
        $resolved = @()
        try { $resolved = @(Resolve-Path -Path $p -ErrorAction Stop | ForEach-Object { $_.ProviderPath }) }
        catch { Write-Warning "Not found, skipping: $p"; continue }
        foreach ($r in $resolved) {
            if (Test-Path -LiteralPath $r -PathType Leaf) { [void]$targets.Add($r) }
        }
    }
} elseif ($script:Interactive) {
    foreach ($f in (Select-DataFiles)) { [void]$targets.Add($f) }
}

if ($targets.Count -eq 0) { Write-Host 'No files to process.'; return }

Write-Host ("Mode: {0}   RetainFirst: {1}   Files: {2}" -f $Mode, $RetainFirst, $targets.Count)

$fileNumber = 0
foreach ($file in $targets) {
    $fileNumber++
    Write-Progress -Activity 'Decimating' -Status ([System.IO.Path]::GetFileName($file)) `
                   -PercentComplete (100 * ($fileNumber - 1) / $targets.Count)

    $action = 'Skipped'
    $preview = $null
    try {
        # A file inside Backup\ is the full-dataset copy. v2 would overwrite it
        # and, by design, make no backup of it - destroying the only full copy.
        $parentName = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($file))
        if ($parentName -eq 'Backup' -and -not $Force) {
            Write-Warning ("Refusing '{0}': it is inside a Backup folder, where no backup would be made. Use -Force to override." -f $file)
            continue
        }

        $enc = Resolve-OutputEncoding -Name $Encoding -FilePath $file
        $preview = Invoke-Decimation -FilePath $file -IntervalMode $Mode -Retain $RetainFirst -OutputEncoding $enc

        if (-not $preview.SawAnyStamp) {
            Write-Warning ("Skipping '{0}': no row's first column parsed as a timestamp. Expected one of: {1}" -f $file, ($script:StampFormats -join ', '))
            if ($preview.BadSamples.Count -gt 0) {
                Write-Warning ("  first unrecognised row: {0}" -f $preview.BadSamples[0])
            }
            Remove-TempFile -TempPath $preview.TempPath
            continue
        }

        if ($preview.Unparseable -gt 0) {
            Write-Warning ("{0}: {1} row(s) had an unreadable timestamp and were KEPT as-is." -f ([System.IO.Path]::GetFileName($file)), $preview.Unparseable)
        }

        if ($preview.RowsKept -le 0 -and -not $Force) {
            Write-Warning ("Refusing '{0}': decimating to {1} would keep 0 of {2} data rows. The timestamps do not land on that interval. Use -Force to override." -f $file, $Mode, $preview.RowsIn)
            Remove-TempFile -TempPath $preview.TempPath
            continue
        }

        $decision = 'Proceed'
        if ($script:Interactive) {
            # Indicative only - Save-Decimation appends a timestamp if a backup
            # of that name already exists.
            if (-not $NoBackup) {
                $backupDirDisplay = Join-Path ([System.IO.Path]::GetDirectoryName($file)) 'Backup'
                $preview.BackupPath = Join-Path $backupDirDisplay ("{0}_fulldataset{1}" -f `
                    [System.IO.Path]::GetFileNameWithoutExtension($file), [System.IO.Path]::GetExtension($file))
            }
            $decision = Show-PreviewDialog -Preview $preview
        }

        if ($decision -eq 'ExitAll') {
            Remove-TempFile -TempPath $preview.TempPath
            Write-Host 'Exit all - remaining files untouched.'
            break
        }
        if ($decision -ne 'Proceed') {
            Remove-TempFile -TempPath $preview.TempPath
            Write-Host ("Skipped: {0}" -f $file)
            continue
        }

        $target = "{0} ({1} of {2} data rows kept)" -f $file, $preview.RowsKept, $preview.RowsIn
        if ($PSCmdlet.ShouldProcess($target, "Decimate to $Mode")) {
            $backupPath = Save-Decimation -Preview $preview -SkipBackup:$NoBackup
            $preview.BackupPath = $backupPath
            $action = 'Decimated'
            if ($backupPath) { Write-Host ("Backup: {0}" -f $backupPath) }
            Write-Host ("Done  : {0}  ({1} of {2} data rows kept)" -f $file, $preview.RowsKept, $preview.RowsIn) -ForegroundColor Green
        } else {
            Remove-TempFile -TempPath $preview.TempPath
            $action = 'WhatIf'
        }
    } catch {
        Write-Error ("Failed on '{0}': {1}" -f $file, $_.Exception.Message)
        if ($preview) { Remove-TempFile -TempPath $preview.TempPath }
        $action = 'Failed'
    }

    if ($preview) {
        [pscustomobject]@{
            Path        = $file
            Mode        = $Mode
            RowsIn      = $preview.RowsIn
            RowsKept    = $preview.RowsKept
            RowsDropped = $preview.RowsDropped
            Unparseable = $preview.Unparseable
            HeaderRows  = $preview.HeaderRows
            BackupPath  = $preview.BackupPath
            Action      = $action
        }
    }
}

Write-Progress -Activity 'Decimating' -Completed
