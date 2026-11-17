<#
    Install-DatFileTools.ps1
    ------------------------
    First-time install for someone without the folder yet. No git, no admin.
    Paste into PowerShell:

      irm https://raw.githubusercontent.com/mitchamer/dat-file-tools/main/Install-DatFileTools.ps1 | iex

    It puts the latest version in %LOCALAPPDATA%\Programs\dat-file-tools (set
    DAT_FILE_TOOLS_DIR first to choose another folder), adds the right-click
    entries and the "DAT File Tools" Start-menu shortcut, and opens the
    launcher. Running it again updates that copy.

    It does this by fetching Check-ForUpdates.ps1 alone and running its
    update: a folder with no .version is always offered the latest, so the
    first install is just an update into an empty folder.

    Runs under `iex`, so it never calls `exit` (that would close the window).
#>
& {
    # Inside the block, so nothing leaks into the pasting user's session.
    $ErrorActionPreference = 'Stop'
    $dir = if ($env:DAT_FILE_TOOLS_DIR) { $env:DAT_FILE_TOOLS_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\dat-file-tools' }
    $raw = 'https://raw.githubusercontent.com/mitchamer/dat-file-tools/main'

    if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
        Write-Host "$dir is a git clone - update it with git pull, or open its launcher." -ForegroundColor Yellow
        return
    }

    Write-Host "Installing DAT File Tools into $dir ..." -ForegroundColor Cyan
    $null = New-Item -ItemType Directory -Force -Path $dir
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $checker = Join-Path $dir 'Check-ForUpdates.ps1'
    Invoke-WebRequest -Uri "$raw/Check-ForUpdates.ps1" -OutFile $checker -UseBasicParsing

    # A child process with Bypass: the default execution policy on a Windows
    # desktop refuses to run a .ps1 file at all.
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $status = @(& $ps -NoProfile -ExecutionPolicy Bypass -Command "`$r = & '$checker' -Update; `$r.Status; `$r.Reason")
    if ($status[0] -ne 'Updated') {
        Write-Host "Install failed: $($status -join ' ')" -ForegroundColor Red
        return
    }
    Write-Host "Installed. $($status[1])" -ForegroundColor Green
    Write-Host "Open it any time from the Start menu: DAT File Tools." -ForegroundColor Green
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $dir 'Launch-DatFileTools.ps1')`"")
}
