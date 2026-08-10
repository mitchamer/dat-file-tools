DECIMATE_V3.PS1 - README
========================

PURPOSE

Thins time-series CSV or DAT files by keeping only rows that land on a fixed
interval (hourly, six-hourly, or daily). Header rows are detected and preserved,
the original is copied into a Backup folder, and the thinned result replaces the
original file under its original name.

Intended for Campbell Scientific / LoggerNet TOA5 output, where a 15-minute
logger produces ~35,000 rows a year and a trend plot or report only needs hourly
or daily.


USE AT YOUR OWN RISK - NO WARRANTY

This script REPLACES DATA FILES IN PLACE. Licensed under GPL-3.0 and provided
"as is" with no warranty of any kind (see LICENSE sections 15-17). You are
responsible for verifying output before relying on it. Decimation is lossy by
definition: discarded rows exist only in the backup copy.

Test on copies first. Use -WhatIf to see what would happen without writing.


WHAT CHANGED IN v3

v3 is a reviewed rewrite of v2. Behaviour that was silent is now explicit, and
the two ways v2 could destroy data without warning are now blocked by default.

Correctness

  * TIMESTAMP FORMATS. v2 accepted only 'yyyy-MM-dd HH:mm:ss'. TOA5 files
    routinely carry fractional seconds ('2026-07-27 14:02:49.557'), and v2 could
    not parse those at all - it treated every row as unreadable, kept them all,
    and reported success having changed nothing. v3 accepts fractional seconds,
    minute-precision, and the ISO 'T' separator.

  * REFUSES TO EMPTY A FILE. If the chosen interval matches no rows - data logged
    at :07 against Hourly, say - v2 wrote the file out with its headers and no
    data. v3 detects this before writing and refuses, naming the cause. Pass
    -Force to override deliberately.

  * REFUSES FILES INSIDE A Backup FOLDER. v2 skipped backup creation for these
    (correctly, to avoid nesting) but still overwrote them - destroying the only
    full copy. v3 refuses outright; -Force overrides.

  * NO SILENT NO-OP. If no row anywhere in the file parses as a timestamp, v3
    skips the file and reports the formats it expected. v2 fell back to assuming
    two header rows and rewrote the file unchanged.

  * HEADER DETECTION. v2 forced a minimum of two header rows, so a headerless
    CSV lost its first two data rows into the header block. v3 counts the actual
    leading non-timestamp rows, which may be zero. Once a timestamp has been
    seen the header is over, so a later unreadable row is treated as bad data
    rather than a header.

  * ENCODING. v2 always wrote 'UTF8', which under PowerShell 5.1 means UTF8
    *with* a byte-order mark - so a file without one silently gained one, and
    behaviour differed between PowerShell 5.1 and 7. v3 defaults to -Encoding
    Auto, which detects the input's BOM and writes it back the same way.

  * MEMORY. v2 read the whole file with Get-Content before processing. Since the
    reason to decimate is that a file is large, v3 streams the input and writes
    as it goes.

  * WARNING FLOOD. v2 emitted one warning per unreadable row, which on a
    wrong-format file meant thousands. v3 reports a count with a sample.

Interface

  * PREVIEW BEFORE WRITING. The biggest change. v2 wrote first and reported
    afterwards, so by the time you saw "0 rows kept" it had already happened.
    v3 writes to a temporary file, then shows rows in / rows kept / dropped /
    the retained time range, and only commits if you approve.

  * A SETTINGS DIALOG replaces v2's two Read-Host prompts, which appeared in a
    console window that flashes past when launched from Explorer. Mode is now
    radio buttons, retain count a spinner, backup a checkbox.

  * Proceed / Skip file / Exit all - the same button vocabulary as the Combine
    tool, so the two behave alike.

  * -WhatIf and -Confirm are supported.

  * WILDCARDS in -Path, and missing paths are reported rather than ignored.

  * A SUMMARY OBJECT per file is emitted (Path, Mode, RowsIn, RowsKept,
    RowsDropped, Unparseable, HeaderRows, BackupPath, Action), so runs can be
    captured or piped.

  * Write-Progress across multiple files.

  * ASCII console output. v2 used emoji, which render as garbage on a legacy
    console.

Compatibility

  * Parameters were renamed to -Mode / -RetainFirst / -Path, with the v2 names
    (-ModeParam, -RetainParam, -FilesParam) kept as ALIASES. Existing scheduled
    calls keep working.

  * ConfirmImpact is deliberately NOT set to High. Setting it made every run
    prompt, which throws outright under -NonInteractive and would have broken
    scheduled use.


INPUT REQUIREMENTS

  * File type: any text file; .csv and .dat are what the picker offers
  * The timestamp must be the FIRST comma-separated field
  * Accepted formats:
        yyyy-MM-dd HH:mm:ss.fff      yyyy-MM-dd HH:mm:ss
        yyyy-MM-dd HH:mm             yyyy-MM-ddTHH:mm:ss[.fff]
        yyyy-MM-ddTHH:mm
  * Any number of leading header rows, detected automatically


WHAT IS KEPT

    Hourly       rows at HH:00
    SixHourly    rows at 00:00, 06:00, 12:00, 18:00
    Daily        rows at 00:00

Seconds and milliseconds must be zero. Rows whose timestamp cannot be read are
KEPT and counted, never dropped - discarding a row we cannot interpret would be
destroying data on a guess.

-RetainFirst N additionally keeps the first N rows that carry a valid timestamp,
regardless of interval. SAA files often need 5 for their initialisation rows.


BACKUP BEHAVIOUR

  * A 'Backup' folder is created beside the input file
  * The original is copied to Backup\<name>_fulldataset<ext>
  * If that name exists, a timestamp is appended
  * -NoBackup skips it, which removes your only automatic undo
  * If the copy succeeds but the replace then fails, the backup is removed again
    so a failed run leaves no confusing leftovers


RUNNING IT - INTERACTIVE

    .\Decimate_v3.ps1

A settings dialog appears, then a multi-select file picker, then one confirmation
per file showing what the thinning would cost.


RUNNING IT - NON-INTERACTIVE

Supplying -Mode suppresses all dialogs.

    .\Decimate_v3.ps1 -Mode Hourly -RetainFirst 5 `
                      -Path 'C:\Data\Station1.csv','C:\Data\Station2.dat'

    .\Decimate_v3.ps1 -Mode Daily -Path 'C:\Data\*.dat' -WhatIf

    # capture results
    $r = .\Decimate_v3.ps1 -Mode Hourly -Path 'C:\Data\*.dat'
    $r | Where-Object RowsKept -eq 0

PARAMETERS

    -Mode <Hourly|SixHourly|Daily>   Interval. Supplying it means no dialogs.
    -RetainFirst <int>               Keep the first N valid rows too (0 = none).
    -Path <string[]>                 Files; wildcards allowed. Omit for a picker.
    -NoBackup                        Do not copy the original first.
    -Encoding <Auto|UTF8|UTF8BOM|ASCII|Unicode>
                                     Output encoding. Auto (default) matches the
                                     input's BOM.
    -Force                           Allow writing a file that would keep zero
                                     data rows, and allow files inside Backup\.
    -WhatIf / -Confirm               Standard PowerShell.


ERROR HANDLING

  * Files with no readable timestamp anywhere are skipped and reported
  * Rows with unreadable timestamps are kept and counted
  * On any failure the original is left untouched and temporaries are removed
  * Temporary file cleanup runs even under -WhatIf


TESTS

test_decimate_v3.ps1 covers the cases this review turned on: aligned data,
fractional seconds, off-interval data being refused, -Force overriding that,
files with no timestamps, RetainFirst, -WhatIf leaving nothing behind, files
inside Backup, BOM preservation both ways, wildcards, the v2 aliases, and
unreadable rows surviving. Run it from anywhere:

    .\test_decimate_v3.ps1


REQUIREMENTS

  * Windows PowerShell 5.1 or later (PowerShell 7 works)
  * Windows only - uses Windows Forms dialogs

END OF README
