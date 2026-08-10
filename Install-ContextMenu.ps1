<#
    Install-ContextMenu.ps1
    -----------------------
    Registers the "Combine Time Series Files" right-click (context menu) entries
    for the Combine DAT files script that sits NEXT TO this installer.

    Because it registers based on its own location, the whole package folder can
    live anywhere (e.g. C:\tools\loggernet-monitor\CombineTimeSeriesFiles).

    Entries created:
      * Right-click a FILE               -> use as PRIMARY (direct mode)
      * Right-click a FOLDER             -> scan that folder (folder mode)
      * Right-click a FOLDER background  -> scan the current folder (folder mode)

    Scope:
      Default = current user only (HKCU) - NO admin required.
      -AllUsers = all users (HKLM)       - requires an elevated PowerShell.

    Usage:
      PS> .\Install-ContextMenu.ps1
      PS> .\Install-ContextMenu.ps1 -AllUsers      # run as Administrator
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$target = Join-Path $scriptDir 'Combine DAT files_v9.ps1'

if (-not (Test-Path $target)) {
    throw "Cannot find 'Combine DAT files_v9.ps1' next to this installer ($scriptDir)."
}

if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "-AllUsers writes to HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

$menuLabel = 'Combine Time Series Files'
$cmdFile = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target`" `"%1`""
$cmdBg = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$target`" `"%V`""

# Use the .NET registry API directly so the literal "*" class key is not treated
# as a wildcard (which the PowerShell registry provider would try to expand).
$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$base = 'Software\Classes'

function Set-ContextEntry {
    param(
        [Microsoft.Win32.RegistryKey]$RootKey,
        [string]$SubPath,   # e.g. '*\shell\CombineDATFiles'
        [string]$Label,
        [string]$Command
    )
    $key = $RootKey.CreateSubKey($SubPath)
    try {
        $key.SetValue('', $Label)
        $cmd = $key.CreateSubKey('command')
        try { $cmd.SetValue('', $Command) } finally { $cmd.Dispose() }
    }
    finally { $key.Dispose() }
    Write-Host "  + $SubPath" -ForegroundColor DarkGray
}

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Installing context-menu entries under $scope ..." -ForegroundColor Cyan
Set-ContextEntry -RootKey $rootKey -SubPath "$base\*\shell\CombineDATFiles"                    -Label $menuLabel                      -Command $cmdFile
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\shell\CombineDATFiles"           -Label "$menuLabel (scan folder)"      -Command $cmdFile
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\Background\shell\CombineDATFiles" -Label "$menuLabel (scan this folder)" -Command $cmdBg

Write-Host "`nDone. Target script:" -ForegroundColor Green
Write-Host "  $target"
Write-Host "`nRight-click a file or folder to use it. To remove, run Uninstall-ContextMenu.ps1." -ForegroundColor Green
