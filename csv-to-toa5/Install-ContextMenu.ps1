<#
    Install-ContextMenu.ps1
    -----------------------
    Registers the "Convert to TOA5" right-click entry for CSV-to-TOA5.ps1,
    which sits NEXT TO this installer. Because it works out its own location,
    the folder can live anywhere - move it and re-run this to repoint the entry.

    Entry created, on .csv, .dat and .txt FILES:
      * "Convert to TOA5"   writes '<name>_TOA5.dat' beside the file; the file
                            itself is never changed

    Scope:
      Default = current user only (HKCU) - NO admin required.
      -AllUsers = all users (HKLM)       - requires an elevated PowerShell.

    Usage:
      PS> .\Install-ContextMenu.ps1
      PS> .\Install-ContextMenu.ps1 -AllUsers      # run as Administrator

    There is deliberately no .reg equivalent: a .reg file has to hard-code the
    path, which goes stale the moment the folder moves.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$target = Join-Path $scriptDir 'CSV-to-TOA5.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    throw "Cannot find 'CSV-to-TOA5.ps1' next to this installer ($scriptDir)."
}

if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "-AllUsers writes to HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target`" `"%1`""

# Optional icon, if one is ever dropped beside the script. Absent is normal and
# not worth a warning - the entry works without decoration.
$iconPath = Join-Path $scriptDir 'CsvToToa5.ico'
$iconValue = if (Test-Path -LiteralPath $iconPath) { "`"$iconPath`"" } else { $null }

# The .NET registry API directly, rather than the PowerShell registry provider,
# which treats key names as wildcard patterns ('*' here would match every key).
$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$base = 'Software\Classes'

# Registered on every file ('*') and narrowed with AppliesTo. Registering under
# SystemFileAssociations\.dat instead is skipped by Explorer when .dat is set
# to open with an app such as Notepad++, so the entry would never appear.
$appliesTo = 'System.FileExtension:=.csv OR System.FileExtension:=.dat OR System.FileExtension:=.txt'

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Installing context-menu entry under $scope ..." -ForegroundColor Cyan
$subPath = "$base\*\shell\CsvToToa5"
$key = $rootKey.CreateSubKey($subPath)
try {
    $key.SetValue('', 'Convert to TOA5')
    # 'Icon' and 'AppliesTo' belong on the verb key itself, not on its
    # command subkey.
    if ($iconValue) { $key.SetValue('Icon', $iconValue) }
    $key.SetValue('AppliesTo', $appliesTo)
    $c = $key.CreateSubKey('command')
    try { $c.SetValue('', $cmd) } finally { $c.Dispose() }
}
finally { $key.Dispose() }
Write-Host "  + $subPath" -ForegroundColor DarkGray

Write-Host "`nDone. Target script:" -ForegroundColor Green
Write-Host "  $target"
Write-Host "`nRight-click a logger's .csv/.dat download -> Convert to TOA5." -ForegroundColor Green
Write-Host "On Windows 11 the entry is under 'Show more options'." -ForegroundColor Green
Write-Host "To remove, run Uninstall-ContextMenu.ps1." -ForegroundColor Green
