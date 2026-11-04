<#
    Uninstall-ContextMenu.ps1
    -------------------------
    Removes the right-click entries for EVERY tool in this repo, by running
    each tool folder's own Uninstall-ContextMenu.ps1.

    Usage:
      PS> .\Uninstall-ContextMenu.ps1
      PS> .\Uninstall-ContextMenu.ps1 -AllUsers     # run as Administrator
#>
[CmdletBinding()]
param(
    [switch]$AllUsers
)

$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$uninstallers = Get-ChildItem -LiteralPath $root -Directory |
    ForEach-Object { Join-Path $_.FullName 'Uninstall-ContextMenu.ps1' } |
    Where-Object { Test-Path -LiteralPath $_ }

$failed = @()
foreach ($u in $uninstallers) {
    Write-Host "`n=== $(Split-Path -Leaf (Split-Path -Parent $u)) ===" -ForegroundColor Magenta
    try { & $u -AllUsers:$AllUsers }
    catch { Write-Warning "Failed: $u`n  $_"; $failed += $u }
}

if ($failed) { exit 1 }
Write-Host "`nRemoved context-menu entries for all $(@($uninstallers).Count) tools." -ForegroundColor Green
