<#
    Uninstall-ContextMenu.ps1
    -------------------------
    Removes the "Combine Time Series Files" right-click (context menu) entries
    created by Install-ContextMenu.ps1.

    Scope:
      Default = current user only (HKCU) - NO admin required.
      -AllUsers = all users (HKLM)       - requires an elevated PowerShell.

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
        throw "-AllUsers removes from HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

# Use the .NET registry API directly so the literal "*" class key is not treated
# as a wildcard (which the PowerShell registry provider would try to expand).
$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$base = 'Software\Classes'

$subs = @(
    "$base\*\shell\CombineDATFiles",
    "$base\Directory\shell\CombineDATFiles",
    "$base\Directory\Background\shell\CombineDATFiles"
)

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Removing context-menu entries under $scope ..." -ForegroundColor Cyan

$removed = 0
foreach ($sub in $subs) {
    try {
        # $false = do not throw if the subkey is missing.
        $rootKey.DeleteSubKeyTree($sub, $false)
        Write-Host "  - $sub" -ForegroundColor DarkGray
        $removed++
    }
    catch {
        Write-Warning "Could not remove '$sub': $_"
    }
}

if ($removed -gt 0) {
    Write-Host "`nRemoved $removed entry group(s)." -ForegroundColor Green
}
else {
    Write-Host "`nNothing to remove (no entries found)." -ForegroundColor Yellow
}
