<#
    Check-ForUpdates.ps1
    --------------------
    Is this copy of dat-file-tools behind GitHub, and if so, update it.

    This folder is a git clone, and the right-click entries run the scripts in
    it directly, so a clone nobody pulls keeps running old code without saying
    so. Every tool calls this at start-up (at most once a day, see -Daily), and
    the launcher calls it every time it opens.

    It never overwrites anything: the update is `git pull --ff-only`, and it is
    refused - with the reason - when the folder has local edits or is not on
    main. With no git, no clone, or no network (fetch is given a few seconds),
    it says nothing and the tool runs as it is.

    When an update changes a context-menu installer, the entries are
    reinstalled so they match.

    Returns one object: Status = UpToDate | Behind | Updated | Skipped | Failed,
    plus Behind (count), Commits (one line each) and Reason.

    Usage:
      PS> .\Check-ForUpdates.ps1                # check, ask, update
      PS> .\Check-ForUpdates.ps1 -CheckOnly     # check, ask nothing
      PS> .\Check-ForUpdates.ps1 -Update        # update without asking
#>
[CmdletBinding()]
param(
    # Skip when the last check was less than a day ago. Keeps a slow share or
    # network from adding a fetch to every right-click.
    [switch]$Daily,
    # Report only; no dialog, no update. The launcher and unattended runs.
    [switch]$CheckOnly,
    # Update without asking (the launcher's "Update now" button).
    [switch]$Update,
    [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$branch = 'main'

function New-Result([string]$Status, [string]$Reason = '', [int]$Behind = 0, [string[]]$Commits = @()) {
    [pscustomobject]@{ Status = $Status; Reason = $Reason; Behind = $Behind; Commits = $Commits }
}

function Invoke-Git([string[]]$GitArgs, [int]$Timeout = $TimeoutSeconds) {
    # A process, not `& git`, so a hung fetch (VPN down, credential prompt) can
    # be killed instead of freezing the tool.
    $psi = [System.Diagnostics.ProcessStartInfo]::new('git')
    $psi.Arguments = (@('-C', "`"$root`"") + $GitArgs) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Closed below: inherited, a background job's stdin is its remoting pipe,
    # and fetch waits on it forever.
    $psi.RedirectStandardInput = $true
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Timeout * 1000)) {
        # The whole tree: git-remote-https outlives a plain Kill() of git.
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        throw "git $($GitArgs[0]) took longer than $Timeout s"
    }
    if ($p.ExitCode -ne 0) { throw "git $($GitArgs[0]) failed: $($err.Result.Trim())" }
    $out.Result.Trim()
}

function Get-UpdateStatus {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return New-Result Skipped 'git is not installed' }
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { return New-Result Skipped "$root is not a git clone" }
    try { $null = Invoke-Git @('fetch', '--quiet', 'origin', $branch) }
    catch { return New-Result Skipped "could not reach GitHub ($($_.Exception.Message))" }

    $count = [int](Invoke-Git @('rev-list', '--count', "HEAD..origin/$branch"))
    if ($count -eq 0) { return New-Result UpToDate }
    $log = @((Invoke-Git @('log', '--format=%s', "HEAD..origin/$branch")) -split "`r?`n")
    New-Result Behind '' $count $log
}

function Invoke-Update {
    $current = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($current -ne $branch) {
        return New-Result Failed "$root is on branch '$current', not '$branch'. Switch it to $branch to update."
    }
    if (Invoke-Git @('status', '--porcelain', '--untracked-files=no')) {
        return New-Result Failed "$root has local edits, so it was not updated. Commit or discard them first."
    }
    $before = Invoke-Git @('rev-parse', 'HEAD')
    try { $null = Invoke-Git @('pull', '--ff-only', '--quiet', 'origin', $branch) 30 }
    catch { return New-Result Failed $_.Exception.Message }
    $changed = @((Invoke-Git @('diff', '--name-only', $before, 'HEAD')) -split "`r?`n")

    $reason = ''
    if ($changed -match '(^|/)(Un)?[Ii]nstall-ContextMenu\.ps1$') {
        try {
            $null = & (Join-Path $root 'Install-ContextMenu.ps1') *>&1
            $reason = 'Right-click entries reinstalled.'
        }
        catch { $reason = "Reinstalling the right-click entries failed: $($_.Exception.Message). Run Install-ContextMenu.ps1." }
    }
    New-Result Updated $reason
}

# --- once a day ---
$stampFile = Join-Path $env:LOCALAPPDATA 'dat-file-tools\last-update-check.txt'
if ($Daily -and -not $Update) {
    try {
        $last = [datetime]::Parse((Get-Content -LiteralPath $stampFile -Raw -ErrorAction Stop).Trim(), [Globalization.CultureInfo]::InvariantCulture)
        if (((Get-Date) - $last).TotalHours -lt 24) { return New-Result Skipped 'checked within the last day' }
    }
    catch { }   # no stamp yet, or unreadable: check now
}

if ($Update) { return Invoke-Update }

$status = Get-UpdateStatus
if ($status.Status -ne 'Skipped') {
    try {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $stampFile)
        Set-Content -LiteralPath $stampFile -Value (Get-Date).ToString('o') -Encoding ascii
    }
    catch { }
}
if ($status.Status -ne 'Behind') { return $status }
if ($CheckOnly) {
    Write-Warning "dat-file-tools is $($status.Behind) update(s) behind GitHub. Open the launcher, or run Check-ForUpdates.ps1, to update."
    return $status
}

# --- behind: ask ---
Add-Type -AssemblyName System.Windows.Forms
$shown = @($status.Commits | Select-Object -First 10 | ForEach-Object { "  - $_" })
if ($status.Commits.Count -gt 10) { $shown += "  ... and $($status.Commits.Count - 10) more" }
$answer = [System.Windows.Forms.MessageBox]::Show(
    "dat-file-tools is $($status.Behind) update(s) behind GitHub:`n`n$($shown -join "`n")`n`nUpdate now? The tool then runs the new version.",
    'dat-file-tools - update available',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Information)
if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return $status }

$result = Invoke-Update
if ($result.Status -eq 'Failed') {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Not updated: $($result.Reason)`n`nThe tool will run the version you have.",
        'dat-file-tools - update failed',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
}
elseif ($result.Reason) { Write-Host $result.Reason -ForegroundColor DarkGray }
$result
