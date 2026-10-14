<#
    Uninstall-ContextMenu.ps1
    -------------------------
    Removes the right-click entries created by Install-ContextMenu.ps1.
    Removing each verb key also removes its \command subkey.

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
$base = 'Software\Classes'
$paths = @(
    "$base\Directory\shell\FixTimestamps",
    "$base\Directory\Background\shell\FixTimestamps",
    "$base\Directory\shell\FixTimestampsCheck",
    "$base\Directory\Background\shell\FixTimestampsCheck"
)

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Removing context-menu entries from $scope ..." -ForegroundColor Cyan
foreach ($p in $paths) {
    try {
        $rootKey.DeleteSubKeyTree($p, $false)
        Write-Host "  - $p" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "  (not present) $p" -ForegroundColor DarkGray
    }
}
Write-Host "`nDone." -ForegroundColor Green
