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
  data. **v3 refuses to write in that case** and names the cause; `-Force`
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

The v2 names `-ModeParam`, `-RetainParam` and `-FilesParam` still work as aliases,
so existing scheduled calls keep running.

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

12 cases, 34 assertions, covering what the review turned on: aligned data,
fractional-second timestamps, off-interval data being refused, `-Force` overriding
that, files with no timestamps, `RetainFirst`, `-WhatIf` leaving nothing behind,
files inside `Backup`, BOM preservation both ways, wildcards, the v2 aliases, and
unreadable rows surviving.

## What changed in v3

v3 is a reviewed rewrite. Two ways v2 could destroy data without warning are now
blocked by default, and behaviour that was silent is now reported.

### Correctness

| | |
|---|---|
| **Timestamps** | v2 parsed only `yyyy-MM-dd HH:mm:ss`. TOA5 output routinely carries fractional seconds, which v2 could not parse **at all** — it treated every row as unreadable, kept them, and reported success having changed nothing. v3 accepts fractional seconds, minute precision and the ISO `T` separator |
| **Refuses to empty a file** | Data at `:07` against `Hourly` matches nothing; v2 wrote out headers with no data. v3 detects this before writing and refuses |
| **Refuses files inside `Backup\`** | v2 correctly skipped making a backup for these, but still overwrote them — destroying the only full copy |
| **No silent no-op** | If nothing parses as a timestamp, v3 skips and reports the expected formats. v2 assumed two header rows and rewrote the file unchanged |
| **Header detection** | v2 forced a minimum of two header rows, so a headerless CSV lost its first two data rows into the header block. v3 counts the actual leading non-timestamp rows, which may be zero |
| **Encoding** | v2 always wrote `UTF8`, which under PowerShell 5.1 means UTF8 **with** a BOM — files silently gained one, and behaviour differed between 5.1 and 7. v3 defaults to `Auto` and preserves what came in |
| **Memory** | v2 read the whole file with `Get-Content`. Since the reason to decimate is that a file is large, v3 streams input and writes as it goes |
| **Warning flood** | v2 emitted one warning per unreadable row — thousands on a wrong-format file. v3 reports a count with a sample |

### Interface

- **Preview before writing**, the main change. v2 wrote first and reported after,
  so "0 rows kept" arrived too late to act on.
- **A settings dialog** replaces two `Read-Host` prompts, which appeared in a
  console window that flashes past when launched from Explorer.
- `Proceed` / `Skip file` / `Exit all`, matching the combine tool.
- `-WhatIf` and `-Confirm`; wildcard `-Path` with missing paths reported;
  `Write-Progress` across files; a summary object per file; ASCII console output
  instead of emoji.

### Two bugs the tests caught that review had not

- `ConfirmImpact='High'` made every run prompt, which **throws** under
  `-NonInteractive` — it would have broken scheduled use outright.
- `-WhatIf` propagates into called cmdlets, so the temp-file cleanup skipped
  itself and left `.tmp` files behind.
