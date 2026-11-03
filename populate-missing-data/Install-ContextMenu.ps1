<#
    Install-ContextMenu.ps1
    -----------------------
    Registers the right-click entries for Populate-MissingData.ps1, which sits
    NEXT TO this installer. Because it works out its own location, the folder
    can live anywhere - move it and re-run this to repoint the entries.

    Entries created, on .dat and .csv FILES (right-click the file to fill):
      * "Populate Missing Data"                 asks for the source file, shows
                                                the column mapping, fills on approval
      * "Check Populate Missing Data (no changes)"  the same with -DryRun

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
$target = Join-Path $scriptDir 'Populate-MissingData.ps1'

if (-not (Test-Path -LiteralPath $target)) {
    throw "Cannot find 'Populate-MissingData.ps1' next to this installer ($scriptDir)."
}

if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "-AllUsers writes to HKLM and must be run from an elevated (Administrator) PowerShell."
    }
}

$exe = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File'
$cmdFill = "$exe `"$target`" `"%1`""
$cmdCheck = "$exe `"$target`" `"%1`" -DryRun"

# Optional icon, if one is ever dropped beside the script. Absent is normal and
# not worth a warning - the entries work without decoration.
$iconPath = Join-Path $scriptDir 'PopulateMissingData.ico'
$iconValue = if (Test-Path -LiteralPath $iconPath) { "`"$iconPath`"" } else { $null }

# The .NET registry API directly, rather than the PowerShell registry provider,
# which treats key names as wildcard patterns.
$rootKey = if ($AllUsers) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
$base = 'Software\Classes'

# SystemFileAssociations attaches the verbs to the extension whatever program
# the user has .dat or .csv opening in, without touching that association.
$extensions = @('.dat', '.csv')

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
foreach ($ext in $extensions) {
    Set-ContextEntry -RootKey $rootKey -SubPath "$base\SystemFileAssociations\$ext\shell\PopulateMissingData"      -Label "Populate Missing Data"                    -Command $cmdFill  -Icon $iconValue
    Set-ContextEntry -RootKey $rootKey -SubPath "$base\SystemFileAssociations\$ext\shell\PopulateMissingDataCheck" -Label "Check Populate Missing Data (no changes)" -Command $cmdCheck -Icon $iconValue
}

Write-Host "`nDone. Target script:" -ForegroundColor Green
Write-Host "  $target"
Write-Host "`nRight-click the .dat/.csv file that HAS the gaps, then pick the file to fill it from." -ForegroundColor Green
Write-Host "Run the CHECK entry first - it writes nothing." -ForegroundColor Green
Write-Host "On Windows 11 the entries are under 'Show more options'." -ForegroundColor Green
Write-Host "To remove, run Uninstall-ContextMenu.ps1." -ForegroundColor Green
