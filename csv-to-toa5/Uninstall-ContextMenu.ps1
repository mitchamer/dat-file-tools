<#
    Uninstall-ContextMenu.ps1
    -------------------------
    Removes the right-click entry created by Install-ContextMenu.ps1.
    Removing the verb key also removes its \command subkey.

    Usage:
      PS> .\Uninstall-ContextMenu.ps1
      PS> .\Uninstall-ContextMenu.ps1 -AllUsers     # run as Administrator
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "-AllUsers writes to HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$p = 'Software\Classes\*\shell\CsvToToa5'

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Removing context-menu entry from $scope ..." -ForegroundColor Cyan
try {
    $rootKey.DeleteSubKeyTree($p, $false)
    Write-Host "  - $p" -ForegroundColor DarkGray
}
catch {
    Write-Host "  (not present) $p" -ForegroundColor DarkGray
}
Write-Host "`nDone." -ForegroundColor Green
