<#
    Install-ContextMenu.ps1
    -----------------------
    Registers the right-click entries for Fix-Timestamps.ps1, which sits NEXT
    TO this installer. Because it works out its own location, the folder can
    live anywhere - move it and re-run this to repoint the entries.

    Entries created, on a FOLDER and on the empty space inside one:
      * "Fix Timestamp Format"                converts in place
      * "Check Timestamp Format (no changes)" the same scan with -DryRun

    Both pass only the folder, so the scan is that folder alone - subfolders
    are never entered from the right-click menu. Use -Depth from a terminal
    for that.

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
$target = Join-Path $scriptDir 'Fix-Timestamps.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    throw "Cannot find 'Fix-Timestamps.ps1' next to this installer ($scriptDir)."
}

if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "-AllUsers writes to HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

$exe = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
$cmdFixFolder = "$exe `"$target`" `"%1`""
$cmdFixHere = "$exe `"$target`" `"%V`""
$cmdCheckFolder = "$exe `"$target`" `"%1`" -DryRun"
$cmdCheckHere = "$exe `"$target`" `"%V`" -DryRun"

# Optional icon, if one is ever dropped beside the script. Absent is normal and
# not worth a warning - the entries work without decoration.
$iconPath = Join-Path $scriptDir 'FixTimestamps.ico'
$iconValue = if (Test-Path -LiteralPath $iconPath) { "`"$iconPath`"" } else { $null }

# The .NET registry API directly, rather than the PowerShell registry provider,
# which treats key names as wildcard patterns.
$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$base = 'Software\Classes'

function Set-ContextEntry {
    param(
        [Microsoft.Win32.RegistryKey]$RootKey,
        [string]$SubPath,
        [string]$Label,
        [string]$Command,
        [string]$Icon
    )
    $key = $RootKey.CreateSubKey($SubPath)
    try {
        $key.SetValue('', $Label)
        # 'Icon' belongs on the verb key itself, not on its command subkey.
        if ($Icon) { $key.SetValue('Icon', $Icon) }
        $cmd = $key.CreateSubKey('command')
        try { $cmd.SetValue('', $Command) } finally { $cmd.Dispose() }
    }
    finally { $key.Dispose() }
    Write-Host "  + $SubPath" -ForegroundColor DarkGray
}

$scope = if ($AllUsers) { 'HKLM (all users)' } else { 'HKCU (current user)' }
Write-Host "Installing context-menu entries under $scope ..." -ForegroundColor Cyan
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\shell\FixTimestamps"                 -Label "Fix Timestamp Format"                 -Command $cmdFixFolder   -Icon $iconValue
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\Background\shell\FixTimestamps"      -Label "Fix Timestamp Format (this folder)"  -Command $cmdFixHere     -Icon $iconValue
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\shell\FixTimestampsCheck"            -Label "Check Timestamp Format (no changes)" -Command $cmdCheckFolder -Icon $iconValue
Set-ContextEntry -RootKey $rootKey -SubPath "$base\Directory\Background\shell\FixTimestampsCheck" -Label "Check Timestamp Format (no changes)" -Command $cmdCheckHere   -Icon $iconValue

Write-Host "`nDone. Target script:" -ForegroundColor Green
Write-Host "  $target"
Write-Host "`nRight-click a folder (or inside one) to use it." -ForegroundColor Green
Write-Host "Run the CHECK entry first - it writes nothing." -ForegroundColor Green
Write-Host "To remove, run Uninstall-ContextMenu.ps1." -ForegroundColor Green
