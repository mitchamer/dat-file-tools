<#
    Decimate (v2)
    -------------
    Thins time-series CSV / DAT files by keeping only rows that land exactly on a
    fixed interval - hourly (HH:00:00), six-hourly (00/06/12/18:00:00), or daily
    (00:00:00). Header rows are detected and preserved, the original is copied to
    a Backup folder, and the thinned result replaces the original file under its
    original name.

    USE AT YOUR OWN RISK - NO WARRANTY
    ==================================
    This script REPLACES DATA FILES IN PLACE. Licensed under GPL-3.0 and provided
    "as is" with no warranty of any kind (see LICENSE sections 15-17). You are
    responsible for verifying output before relying on it. Decimation is lossy by
    definition: discarded rows exist only in the backup copy.

    Read these before pointing it at anything you cannot regenerate:

      * ROWS MUST LAND EXACTLY ON THE INTERVAL. Hourly keeps only rows where
        minute AND second are 0. Data logged at :05, :07, :15 and so on matches
        nothing, so EVERY data row is dropped and you are left with the headers
        (plus any -RetainParam rows). Check your logging interval and offset
        first - this is the way to lose a whole file's data in one run.
      * TIMESTAMPS MUST BE EXACTLY yyyy-MM-dd HH:mm:ss in the FIRST column. Rows
        that do not parse are kept and reported, so a file in another format is
        simply not thinned rather than damaged - but it is a silent no-op.
      * NO BACKUP IS MADE IF THE INPUT IS ALREADY INSIDE A "Backup" FOLDER, and
        the file is still overwritten. Do not re-run this on its own output.
      * THE ORIGINAL FILENAME IS KEPT, so a thinned file is indistinguishable
        from a full one by name. The full copy is Backup\<name>_fulldataset<ext>.
      * OUTPUT IS WRITTEN AS UTF8 regardless of the input encoding.
      * If the very first row parses as a timestamp, header detection finds no
        headers and falls back to assuming 2, so the first two data rows are
        treated as headers and always retained.

    On failure the original is left untouched and temporary files are cleaned up.
    Test on copies first, and confirm the row count and time range of the result.
#>
param (
    [ValidateSet('Hourly', 'SixHourly', 'Daily')]
    [string]$ModeParam = $null,
    [int]$RetainParam = $null,
    [string[]]$FilesParam = $null
)

Add-Type -AssemblyName System.Windows.Forms

function Select-CSVFiles {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select CSV or DAT files to filter"
    $dlg.Filter = "CSV and DAT Files (*.csv;*.dat)|*.csv;*.dat|CSV Files (*.csv)|*.csv|DAT Files (*.dat)|*.dat|All Files (*.*)|*.*"
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "No files selected."
        return $null
    }
    return $dlg.FileNames
}

function Filter-ToHourOnly {
    param (
        [string]$CsvPath,
        [ValidateSet('Hourly', 'SixHourly', 'Daily')]
        [string]$Mode = 'Hourly',
        [int]$RetainFirst = 0
    )

    $modeSuffix = switch ($Mode) {
        'Hourly' { 'hourly' }
        'SixHourly' { '6hr' }
        'Daily' { 'daily' }
    }

    # We'll write the decimated output to a temporary file first so we can
    # create the backup and replace the original only if decimation succeeds.
    $dir = [System.IO.Path]::GetDirectoryName($CsvPath)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $ext = [System.IO.Path]::GetExtension($CsvPath)
    $backupDir = Join-Path $dir 'Backup'

    $lines = Get-Content $CsvPath
    if ($lines.Count -lt 3) {
        Write-Warning "Skipping $CsvPath — file must have at least 3 rows."
        return
    }

    # Detect header rows: consecutive top rows whose first column is NOT a parseable datetime
    $headerCount = 0
    for ($h = 0; $h -lt $lines.Count; $h++) {
        $firstField = ($lines[$h] -split ',', 2)[0].Trim().Trim('"')
        try {
            [DateTime]::ParseExact($firstField, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) | Out-Null
            break
        }
        catch {
            $headerCount++
            continue
        }
    }

    if ($headerCount -lt 1) { $headerCount = 2 } # fallback to previous behavior if detection failed

    $filteredLines = @()
    for ($i = 0; $i -lt $headerCount; $i++) { $filteredLines += $lines[$i] }

    # Optionally retain the first N *time* rows (useful for SAAs). This counts only rows
    # whose first column is a parseable datetime, and keeps them in order.
    $startIndex = $headerCount
    if ($RetainFirst -gt 0) {
        $keptData = 0
        for ($i = $headerCount; $i -lt $lines.Count; $i++) {
            $dateField = ($lines[$i] -split ',', 2)[0]
            $dateStr = $dateField.Trim().Trim('"').Trim()
            try {
                $dt_tmp = [DateTime]::ParseExact($dateStr, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                $filteredLines += $lines[$i]
                $keptData++
                $lastKeptIdx = $i
                if ($keptData -ge $RetainFirst) { $startIndex = $i + 1; break }
            }
            catch {
                # keep non-parseable rows encountered before we've reached the requested number
                $filteredLines += $lines[$i]
            }
        }
        if ($keptData -lt $RetainFirst) { $startIndex = $lines.Count }
    }

    for ($i = $startIndex; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Extract only the first field (date) so commas in other fields don't break parsing
        $dateField = ($line -split ',', 2)[0]
        $dateStr = $dateField.Trim().Trim('"').Trim()

        try {
            $dt = [DateTime]::ParseExact($dateStr, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            Write-Warning "Row $($i+1) in ${CsvPath}: Could not parse date '$dateStr'. Keeping line."
            $filteredLines += $line
            continue
        }

        switch ($Mode) {
            'Hourly' {
                if ($dt.Minute -eq 0 -and $dt.Second -eq 0) { $filteredLines += $line }
            }
            'SixHourly' {
                if (($dt.Hour % 6) -eq 0 -and $dt.Minute -eq 0 -and $dt.Second -eq 0) { $filteredLines += $line }
            }
            'Daily' {
                if ($dt.Hour -eq 0 -and $dt.Minute -eq 0 -and $dt.Second -eq 0) { $filteredLines += $line }
            }
        }
    }

    # Write to a temp file first
    $tempPath = $null
    $backupPath = $null
    try {
        $tempName = "${baseName}_decimating_${modeSuffix}_$(Get-Date -Format 'yyyyMMddHHmmss')_$(Get-Random).tmp"
        $tempPath = Join-Path $dir $tempName
        $filteredLines | Set-Content $tempPath -Encoding UTF8 -Force -ErrorAction Stop

        # Backup original only after successful decimation write
        $dirName = [System.IO.Path]::GetFileName($dir)
        if ($dirName -eq 'Backup') {
            Write-Host "Input file is inside 'Backup' folder; skipping backup creation."
            $backupPath = $null
        }
        else {
            if (-not (Test-Path $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force -ErrorAction Stop | Out-Null
            }
            $backupName = "${baseName}_fulldataset${ext}"
            $backupPath = Join-Path $backupDir $backupName
            if (Test-Path $backupPath) {
                $ts = Get-Date -Format 'yyyyMMddHHmmss'
                $backupName = "${baseName}_fulldataset_$ts${ext}"
                $backupPath = Join-Path $backupDir $backupName
            }
            Copy-Item -Path $CsvPath -Destination $backupPath -Force -ErrorAction Stop
        }
        # Replace the original file with the decimated file (retain original name)
        Move-Item -Path $tempPath -Destination $CsvPath -Force -ErrorAction Stop

        Write-Host "Backup created: $backupPath"
        Write-Host "Filtered ($Mode): $CsvPath (original filename retained)"
    }
    catch {
        Write-Error "Processing failed for ${CsvPath}: $($_.Exception.Message)"
        # cleanup temp and any partially created backup if the run didn't complete
        if ($tempPath -and (Test-Path $tempPath)) { Remove-Item $tempPath -ErrorAction SilentlyContinue }
        if ($backupPath -and (Test-Path $backupPath)) { Remove-Item $backupPath -ErrorAction SilentlyContinue }
        return
    }
}

# ---- Main ----
# Decide mode & retain settings (allow script params when provided for non-interactive runs)
if ($ModeParam) {
    $modeRaw = $ModeParam.ToString().Trim()
}
else {
    $modeRaw = (Read-Host "Decimation mode - enter 1 (Hourly, default), 6 (6-hour), or 24 (Daily)").Trim()
}
if (-not $modeRaw) {
    $mode = 'Hourly'
}
else {
    switch ($modeRaw.ToLower()) {
        '1' { $mode = 'Hourly' }
        '6' { $mode = 'SixHourly' }
        '24' { $mode = 'Daily' }
        'sixhourly' { $mode = 'SixHourly' }
        '6hourly' { $mode = 'SixHourly' }
        '6hr' { $mode = 'SixHourly' }
        'daily' { $mode = 'Daily' }
        'd' { $mode = 'Daily' }
        'hourly' { $mode = 'Hourly' }
        'h' { $mode = 'Hourly' }
        default { $mode = 'Hourly' }
    }
}

if ($PSBoundParameters.ContainsKey('RetainParam')) {
    $retain = [int]$RetainParam
}
else {
    $retainRaw = (Read-Host "Retain first N data rows? (0 to disable). Note: retaining the first 5 rows may be required for SAAs. Default 0").Trim()
    if ($retainRaw -match '^[0-9]+$') { $retain = [int]$retainRaw } else { $retain = 0 }
}

Write-Host "🔧 Mode: $mode (1=Hourly, 6=SixHourly, 24=Daily); RetainFirst: $retain"

if ($FilesParam -and $FilesParam.Count -gt 0) { $files = $FilesParam } else {
    $files = Select-CSVFiles
}
if (-not $files) { Write-Host 'No files selected. Exiting.'; return }

foreach ($file in $files) {
    Filter-ToHourOnly -CsvPath $file -Mode $mode -RetainFirst $retain
}

Write-Host "`n🎉 Done. Files processed with mode: $mode; retained first $retain data rows (if >0)."
