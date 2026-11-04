<#
    Install-ContextMenu.ps1
    -----------------------
    Installs the right-click entries for EVERY tool in this repo in one go, by
    running each tool folder's own Install-ContextMenu.ps1. Tool folders that
    are missing (someone copied only some) are simply not found, so nothing
    breaks; a new tool that ships its own installer is picked up automatically.

    Scope:
      Default = current user only (HKCU) - NO admin required.
      -AllUsers = all users (HKLM)       - requires an elevated PowerShell.

    Usage:
      PS> .\Install-ContextMenu.ps1
      PS> .\Install-ContextMenu.ps1 -AllUsers      # run as Administrator

    To remove them all, run Uninstall-ContextMenu.ps1 beside this file.
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$installers = Get-ChildItem -LiteralPath $root -Directory |
    ForEach-Object { Join-Path $_.FullName 'Install-ContextMenu.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ }

if (-not $installers) { throw "No tool installers found under $root." }

# One tool failing (e.g. its script was removed) should not stop the rest.
$failed = @()
foreach ($i in $installers) {
    Write-Host "`n=== $(Split-Path -Leaf (Split-Path -Parent $i)) ===" -ForegroundColor Magenta
    try { & $i -AllUsers:$AllUsers }
    catch { Write-Warning "Failed: $i`n  $_"; $failed += $i }
}

Write-Host ''
if ($failed) {
    Write-Host "Installed $($installers.Count - $failed.Count) of $($installers.Count) tools; see warnings above." -ForegroundColor Yellow
    exit 1
}
Write-Host "Installed context-menu entries for all $($installers.Count) tools." -ForegroundColor Green
