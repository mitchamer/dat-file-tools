# Decimate

Thins a time-series file to rows landing on a fixed interval — hourly, six-hourly
or daily — copying the full dataset into `Backup` first and showing what the
thinning will cost before it writes.

A 15-minute logger produces ~35,000 rows a year; a trend plot or a report usually
wants hourly or daily. This keeps the rows on a clean interval and sets the
complete record aside, so the working file stays under its original name.

Windows PowerShell 5.1+ (7 works). Windows only.

## ⚠ Use at your own risk

**This replaces data files in place, and decimation is lossy by definition —
discarded rows exist only in the backup copy.** Provided "as is" with no
warranty — see [LICENSE](../LICENSE) sections 15–17.

- **Rows must land on the interval.** Hourly keeps rows at `HH:00` with seconds
  zero. Data logged at `:05` or `:07` matches nothing, so thinning would leave no
  data. **It refuses to write in that case** and names the cause; `-Force`
  overrides. Still worth knowing your logging offset before you start.
- **The original filename is kept**, so a thinned file looks identical to a full
  one. The full copy is `Backup\<name>_fulldataset<ext>`.
- **`-NoBackup` removes your only automatic undo.**
- **Files already inside a `Backup` folder are refused** — that is the full-dataset
  copy, and no backup-of-a-backup would be made. `-Force` overrides.

Rows whose timestamp cannot be read are **kept and counted**, never dropped —
discarding a row the tool cannot interpret would be destroying data on a guess. If
*no* row in the file parses, the file is skipped and the expected formats reported,
rather than being rewritten unchanged.

Use `-WhatIf` to see what would happen without writing anything.

## Running it

Interactively — a settings dialog, then a multi-select file picker, then one
confirmation per file:

```powershell
.\Decimate.ps1
```

The confirmation is the point: rows in, rows kept, rows dropped, and the retained
time range, **before** anything is written. Buttons are `Proceed` / `Skip file` /
`Exit all`, matching the combine tool.

Non-interactively — supplying `-Mode` suppresses all dialogs:

```powershell
.\Decimate.ps1 -Mode Hourly -RetainFirst 5 `
                  -Path 'C:\Data\Station1.csv','C:\Data\Station2.dat'

.\Decimate.ps1 -Mode Daily -Path 'C:\Data\*.dat' -WhatIf
```

One summary object is emitted per file, so runs can be captured:

```powershell
$r = .\Decimate.ps1 -Mode Hourly -Path 'C:\Data\*.dat'
$r | Where-Object RowsKept -eq 0
```

Fields: `Path`, `Mode`, `RowsIn`, `RowsKept`, `RowsDropped`, `Unparseable`,
`HeaderRows`, `BackupPath`, `Action`.

## Options

| Option | Effect |
|---|---|
| `-Mode <Hourly\|SixHourly\|Daily>` | Interval. Supplying it means no dialogs |
| `-RetainFirst <int>` | Also keep the first N valid rows regardless of interval (`0` disables). SAA files often need `5` for initialisation rows |
| `-Path <string[]>` | Files; wildcards allowed. Omit for a picker |
| `-NoBackup` | Skip the backup copy |
| `-Encoding <Auto\|UTF8\|UTF8BOM\|ASCII\|Unicode>` | Output encoding. `Auto` (default) matches the input's byte-order mark |
| `-Force` | Allow emptying a file, and allow files inside `Backup\` |
| `-WhatIf` / `-Confirm` | Standard PowerShell |

`-ModeParam`, `-RetainParam` and `-FilesParam` are accepted as aliases, so older
scheduled calls keep running.

## What it keeps

| Mode | Rows kept |
|---|---|
| `Hourly` | `HH:00` |
| `SixHourly` | `00:00`, `06:00`, `12:00`, `18:00` |
| `Daily` | `00:00` |

Seconds and milliseconds must be zero. Accepted timestamp formats, in the first
comma-separated column:

```
yyyy-MM-dd HH:mm:ss.fff      yyyy-MM-dd HH:mm:ss
yyyy-MM-dd HH:mm             yyyy-MM-ddTHH:mm:ss[.fff]
yyyy-MM-ddTHH:mm
```

Header rows are the leading rows whose first column is not a timestamp — however
many that is, including none. Once a timestamp has been seen the header is over, so
a later unreadable row counts as bad data rather than a header.

## Backups

- a `Backup` folder is created beside the input file
- the original is copied to `Backup\<name>_fulldataset<ext>`
- if that name exists, a timestamp is appended
- if the copy succeeds but the replace then fails, the backup is removed again, so
  a failed run leaves no confusing leftovers

## Tests

```powershell
.\test_decimate.ps1
```

12 cases, 34 assertions: aligned data, fractional-second timestamps,
off-interval data being refused, `-Force` overriding that, files with no
timestamps, `RetainFirst`, `-WhatIf` leaving nothing behind, files inside
`Backup`, BOM preservation both ways, wildcards, the parameter aliases, and
unreadable rows surviving.
