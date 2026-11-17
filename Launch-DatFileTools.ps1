<#
    Launch-DatFileTools.ps1
    -----------------------
    One window for every tool: pick (or drop) a file or folder, click a tool.
    Each tool runs in its own PowerShell window, exactly as it does from the
    right-click menu, and asks for anything it still needs.

    On opening it checks GitHub for a newer version in the background and, if
    there is one, offers to update (Check-ForUpdates.ps1 does the work).

    Install-ContextMenu.ps1 adds a Start-menu shortcut, "DAT File Tools".

    Usage:
      PS> .\Launch-DatFileTools.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = $PSScriptRoot
$checkScript = Join-Path $root 'Check-ForUpdates.ps1'

# Path = the tool's script. NeedsPath = it cannot start without a file/folder.
$tools = @(
    @{ Name = 'Combine DAT files';      Path = 'combine-dat-files\Combine DAT files.ps1'
       Help = 'Merge .bak/.backup copies and dated downloads into the collected file. Pick a folder to find them all, or the collected file.' }
    @{ Name = 'Combine Affinity Files'; Path = 'combine-dat-files\Combine Affinity Files.ps1'
       Help = 'Combine a tree of daily Affinity downloads into one new file per dataset (writes Combined\, sources untouched).' }
    @{ Name = 'Fix Timestamps';         Path = 'fix-timestamps\Fix-Timestamps.ps1'
       Help = 'Rewrite the first column as YYYY-MM-DD HH:MM:SS. Run before combining or decimating if dates look like 9/1/2026.' }
    @{ Name = 'Decimate';               Path = 'decimate\Decimate.ps1'
       Help = 'Thin a file to hourly, six-hourly or daily, keeping the full record in Backup.' }
    @{ Name = 'Populate Missing Data';  Path = 'populate-missing-data\Populate-MissingData.ps1'
       Help = "Fill a file's NAN gaps from another file that logged the same measurements." }
    @{ Name = 'CSV to TOA5';            Path = 'csv-to-toa5\CSV-to-TOA5.ps1'; NeedsPath = $true
       Help = "Turn a logger's own CSV download (DT2485) into TOA5 beside it. Needs a file." }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DAT File Tools'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(680, 470)
$form.MinimumSize = New-Object System.Drawing.Size(560, 420)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.BackColor = [System.Drawing.Color]::White
$icon = Join-Path $root 'combine-dat-files\CombineDatFiles.ico'
if (Test-Path -LiteralPath $icon) { $form.Icon = New-Object System.Drawing.Icon($icon) }

# --- update banner (shown only when GitHub is ahead) ---
$banner = New-Object System.Windows.Forms.Panel
$banner.Dock = 'Top'; $banner.Height = 44; $banner.Visible = $false
$banner.BackColor = [System.Drawing.Color]::FromArgb(255, 244, 206)
$bannerText = New-Object System.Windows.Forms.Label
$bannerText.AutoSize = $false; $bannerText.Dock = 'Fill'; $bannerText.TextAlign = 'MiddleLeft'
$bannerText.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = 'Update now'; $updateButton.Dock = 'Right'; $updateButton.Width = 110
$banner.Controls.AddRange(@($bannerText, $updateButton))

# --- file / folder picker ---
$pick = New-Object System.Windows.Forms.TableLayoutPanel
$pick.Dock = 'Top'; $pick.Height = 72; $pick.ColumnCount = 3; $pick.RowCount = 2
$pick.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 0)
[void]$pick.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$pick.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
[void]$pick.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$pickLabel = New-Object System.Windows.Forms.Label
$pickLabel.Text = 'File or folder to work on (or drop one here). Leave empty and the tool will ask.'
$pickLabel.AutoSize = $true
$pick.Controls.Add($pickLabel, 0, 0); $pick.SetColumnSpan($pickLabel, 3)
$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Dock = 'Fill'
$fileButton = New-Object System.Windows.Forms.Button; $fileButton.Text = 'File...'; $fileButton.AutoSize = $true
$folderButton = New-Object System.Windows.Forms.Button; $folderButton.Text = 'Folder...'; $folderButton.AutoSize = $true
$pick.Controls.Add($pathBox, 0, 1); $pick.Controls.Add($fileButton, 1, 1); $pick.Controls.Add($folderButton, 2, 1)

# --- one row per tool ---
$list = New-Object System.Windows.Forms.TableLayoutPanel
$list.Dock = 'Fill'; $list.ColumnCount = 2; $list.AutoScroll = $true
$list.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
[void]$list.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 190)))
[void]$list.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$list.RowCount = $tools.Count
foreach ($t in $tools) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $t.Name; $b.Dock = 'Fill'; $b.Height = 44; $b.Tag = $t
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 4)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $t.Help; $l.Dock = 'Fill'; $l.TextAlign = 'MiddleLeft'
    $l.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $list.Controls.Add($b); $list.Controls.Add($l)
    [void]$list.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 54)))
    $b.Add_Click({
        $tool = $this.Tag
        $target = $pathBox.Text.Trim().Trim('"').TrimEnd('\')
        if ($target -and -not (Test-Path -LiteralPath $target)) {
            [void][System.Windows.Forms.MessageBox]::Show("Not found:`n$target", 'DAT File Tools', 'OK', 'Warning'); return
        }
        if ($tool.NeedsPath -and -not $target) {
            [void][System.Windows.Forms.MessageBox]::Show("$($tool.Name) needs a file. Pick one first.", 'DAT File Tools', 'OK', 'Information'); return
        }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $root $tool.Path)`"")
        if ($target) { $argList += "`"$target`"" }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WorkingDirectory $root
    })
}

# An empty last row takes the spare height, so the tool rows keep theirs.
$list.RowCount = $tools.Count + 1
[void]$list.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))

$status = New-Object System.Windows.Forms.StatusStrip
$statusText = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusText.Text = 'Checking for updates...'
[void]$status.Items.Add($statusText)

# Dock order: last added docks first, so Fill goes in first.
$form.Controls.AddRange(@($list, $pick, $banner, $status))

$fileButton.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Data files (*.dat;*.csv;*.txt)|*.dat;*.csv;*.txt|All files (*.*)|*.*'
    if ($pathBox.Text -and (Test-Path -LiteralPath $pathBox.Text)) { $d.InitialDirectory = Split-Path -LiteralPath $pathBox.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $pathBox.Text = $d.FileName }
})
$folderButton.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($pathBox.Text -and (Test-Path -LiteralPath $pathBox.Text -PathType Container)) { $d.SelectedPath = $pathBox.Text }
    if ($d.ShowDialog($form) -eq 'OK') { $pathBox.Text = $d.SelectedPath }
})
$form.AllowDrop = $true
$form.Add_DragEnter({ if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$form.Add_DragDrop({ $pathBox.Text = @($_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))[0] })

# --- update check: a background job, polled, so a slow network never blocks the window ---
$job = $null
if (Test-Path -LiteralPath $checkScript) {
    $job = Start-Job -ArgumentList $checkScript -ScriptBlock { param($s) & $s -CheckOnly 3>$null }
}
else { $statusText.Text = 'Update check not available (Check-ForUpdates.ps1 missing).' }

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if (-not $job -or $job.State -eq 'Running') { return }
    $timer.Stop()
    $r = @(Receive-Job $job -ErrorAction SilentlyContinue | Where-Object { $_.Status }) | Select-Object -Last 1
    Remove-Job $job -Force
    switch ($r.Status) {
        'UpToDate' { $statusText.Text = 'Up to date.' }
        'Behind' {
            $statusText.Text = "$($r.Behind) update(s) available."
            $bannerText.Text = "$($r.Behind) update(s) available: " + (@($r.Commits | Select-Object -First 3) -join '; ')
            $banner.Visible = $true
        }
        'Skipped' { $statusText.Text = "Update check skipped: $($r.Reason)." }
        default   { $statusText.Text = 'Update check failed.' }
    }
})
if ($job) { $timer.Start() }

$updateButton.Add_Click({
    $form.Cursor = 'WaitCursor'; $updateButton.Enabled = $false
    try { $r = & $checkScript -Update } finally { $form.Cursor = 'Default' }
    if ($r.Status -eq 'Updated') {
        [void][System.Windows.Forms.MessageBox]::Show("Updated. $($r.Reason)`n`nThe launcher will now reopen.", 'DAT File Tools', 'OK', 'Information')
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        $form.Close()
    }
    else {
        [void][System.Windows.Forms.MessageBox]::Show("Not updated: $($r.Reason)", 'DAT File Tools', 'OK', 'Warning')
        $updateButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
$timer.Dispose()
