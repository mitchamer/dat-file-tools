<#
    Install-ContextMenu.ps1
    -----------------------
    The one installer for every tool's right-click entries. It:

      1. removes every entry the tools have ever registered in this scope -
         including ones pointing at an old copy of this folder elsewhere on
         the machine, and the legacy locations earlier versions used - by
         running each tool folder's Uninstall-ContextMenu.ps1, then
      2. registers them all again from THIS folder, by running each tool
         folder's Install-ContextMenu.ps1.

    So re-running it after moving or updating the folder always leaves exactly
    one current set of entries. Tool folders are discovered, so a missing one is
    skipped and a new tool that ships its own installer is picked up.

    Scope:
      Default = current user only (HKCU) - NO admin required.
      -AllUsers = all users (HKLM)       - requires an elevated PowerShell.

    Machine-wide entries (from -AllUsers, or the old .reg files) also show up
    for the current user and cannot be removed without admin. A per-user run
    lists any it finds; remove them with an elevated
    `.\Uninstall-ContextMenu.ps1 -AllUsers`.

    Usage:
      PS> .\Install-ContextMenu.ps1
      PS> .\Install-ContextMenu.ps1 -AllUsers      # run as Administrator
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Invoke-ToolScripts([string]$Name) {
    $scripts = @(Get-ChildItem -LiteralPath $root -Directory |
        ForEach-Object { Join-Path $_.FullName $Name } |
        Where-Object { Test-Path -LiteralPath $_ })
    if (-not $scripts) { throw "No tool $Name found under $root." }
    $failed = 0
    foreach ($s in $scripts) {
        Write-Host "`n=== $(Split-Path -Leaf (Split-Path -Parent $s)) ===" -ForegroundColor Magenta
        # One tool failing (e.g. its script was removed) should not stop the rest.
        try { & $s -AllUsers:$AllUsers }
        catch { Write-Warning "Failed: $s`n  $_"; $failed++ }
    }
    [pscustomobject]@{ Count = $scripts.Count; Failed = $failed }
}

Write-Host '##### Removing existing entries #####' -ForegroundColor Cyan
$null = Invoke-ToolScripts 'Uninstall-ContextMenu.ps1'

Write-Host "`n##### Installing from $root #####" -ForegroundColor Cyan
$r = Invoke-ToolScripts 'Install-ContextMenu.ps1'

# Machine-wide leftovers still appear in this user's menu, as duplicates.
if (-not $AllUsers) {
    $verbs = '^(CombineDATFiles|CsvToToa5|FixTimestamps|PopulateMissingData)'
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $left = foreach ($shell in '*\shell', 'Directory\shell', 'Directory\Background\shell',
                                'SystemFileAssociations\.dat\shell', 'SystemFileAssociations\.csv\shell') {
        $k = $hklm.OpenSubKey("Software\Classes\$shell")
        if ($k) {
            try { $k.GetSubKeyNames() | Where-Object { $_ -match $verbs } | ForEach-Object { "HKLM\Software\Classes\$shell\$_" } }
            finally { $k.Dispose() }
        }
    }
    if ($left) {
        Write-Warning ("Machine-wide entries are also installed and will show as duplicates:`n  " +
            ($left -join "`n  ") +
            "`nRemove them from an elevated PowerShell with: .\Uninstall-ContextMenu.ps1 -AllUsers")
    }
}

Write-Host ''
if ($r.Failed) {
    Write-Host "Installed $($r.Count - $r.Failed) of $($r.Count) tools; see warnings above." -ForegroundColor Yellow
    exit 1
}
Write-Host "Installed context-menu entries for all $($r.Count) tools." -ForegroundColor Green
