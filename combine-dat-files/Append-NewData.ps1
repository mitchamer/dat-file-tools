<#
    Appends newly downloaded tables (e.g. CR6_SAA_SAA1_DATA.dat) into the
    long-lived files downstream software reads (e.g. 18421_SAA1_DATA.dat), keeping
    the long-lived names.

    Each .dat in -Folder that does NOT start with -Prefix is paired by name with
    the '<Prefix><X>.dat' whose <X> is the longest ending of its name:

        CR6_SAA_SAA1_DATA.dat        ->  18421_SAA1_DATA.dat
        CR6_SAA_SAA_DIAGNOSTICS.dat  ->  18421_SAA_DIAGNOSTICS.dat

    Each pair is merged by 'Combine DAT files.ps1 -Unattended': no dialogs, the
    newer download is expected, row 2 and the TOA5 table name must match or that
    file is skipped. Merged downloads are moved to Backup as usual.

    Pairs that pass are merged even when others fail. Exit code 0 only when there
    was at least one download and every one merged; otherwise 1.

    .\Append-NewData.ps1 -Folder 'C:\Data\LLD SAA1' -Prefix '18421_'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Folder,
    [Parameter(Mandatory)][string]$Prefix
)

$combine = Join-Path $PSScriptRoot 'Combine DAT files.ps1'
# Extension checked explicitly: -Filter '*.dat' also matches '.data' etc.
$dats = @(Get-ChildItem -LiteralPath $Folder -File -Filter '*.dat' | Where-Object { $_.Extension -eq '.dat' })
$targets = @($dats | Where-Object { $_.Name.StartsWith($Prefix, 'OrdinalIgnoreCase') })
$incoming = @($dats | Where-Object { -not $_.Name.StartsWith($Prefix, 'OrdinalIgnoreCase') })

if ($incoming.Count -eq 0) {
    Write-Host "No new .dat files (not starting '$Prefix') in $Folder - nothing to append." -ForegroundColor Yellow
    exit 1
}

$failed = 0
foreach ($in in $incoming) {
    $target = $targets |
        Where-Object { $in.Name.EndsWith('_' + $_.Name.Substring($Prefix.Length), 'OrdinalIgnoreCase') } |
        Sort-Object { $_.Name.Length } -Descending |
        Select-Object -First 1

    if (-not $target) {
        Write-Host "NO MATCH: $($in.Name) - no '$Prefix*.dat' whose name it ends with. Not merged." -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "`n>>> $($in.Name)  ->  $($target.Name)" -ForegroundColor Magenta
    & $combine -PrimaryFile $target.FullName -SecondaryFile $in.FullName -Unattended
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

Write-Host ''
if ($failed) {
    Write-Host "$failed of $($incoming.Count) file(s) NOT merged - see above." -ForegroundColor Red
    exit 1
}
Write-Host "All $($incoming.Count) file(s) appended." -ForegroundColor Green
exit 0
