# dat-file-tools

PowerShell tools for managing Campbell Scientific / LoggerNet TOA5 time-series
files (`.dat` / `.csv` / `.txt`) — the kind of housekeeping that piles up when the
same logger table arrives from collection, card downloads, and backups all at
once.

Windows PowerShell 5.1 or later (PowerShell 7 works). Both tools use Windows
Forms dialogs, so they are Windows-only.

| Tool | Does | Docs |
|---|---|---|
| **Combine DAT files** (`Combine DAT files_v9.ps1`) | Merges a table's duplicates — `.bak`/`.backup` copies and timestamped CardConvert downloads — into one file, with a header comparison you approve before anything is written | [`SCRIPT_README.txt`](SCRIPT_README.txt) |
| **Decimate** (`Decimate_v3.ps1`) | Thins a file to rows landing on the hour, every six hours, or daily. Previews the row count before writing, and backs up the full dataset first | [`Decimate_v3_README.txt`](Decimate_v3_README.txt) |

## ⚠ Use at your own risk

**Both tools rewrite your data files in place. Run them on copies until you trust
them, and keep independent backups of anything you cannot regenerate.**

They are provided "as is", with **no warranty of any kind** — see sections 15 and
16 of [LICENSE](LICENSE) (GPL-3.0) for the formal terms. You are responsible for
verifying output before relying on it for analysis, reporting, or any decision.
The authors accept no liability for lost, altered, or corrupted data.

### Combine DAT files

A merge is **destructive**, and these are the behaviours to understand before
pointing it at anything you care about:

- **The primary file is rewritten in place.** Header and special rows are
  preserved, but the data section is replaced with the merged, de-duplicated,
  re-sorted result. Original row order is not retained.
- **Secondary files are moved, not copied.** After a successful merge they are
  relocated into a `Backup` subfolder beside the primary.
- **De-duplication compares the entire row, case-insensitively.** Two rows with
  the same timestamp but different values are both kept, as they should be — but
  two rows differing *only* in letter case (for example `NAN` vs `NaN`) are
  treated as the same row and one is silently dropped.
- **Sorting is a text sort on the first column.** That is chronologically correct
  for `YYYY-MM-DD HH:MM:SS` timestamps. If your first column uses another format
  — `M/D/YYYY`, for instance — the output will be ordered wrongly.
- **A pre-merge backup of the primary is created unless you pass `-NoBackup`.**
  Passing it removes your only automatic undo.
- **The file is rewritten with the encoding given by `-Encoding`.** If that does
  not match the original, characters can change.

The header-comparison dialogs exist precisely because these operations cannot be
undone automatically. Read them rather than clicking through — declining a single
file is cheap, and un-merging one is not.

### Decimate

Decimation is **lossy by definition** — discarded rows survive only in the backup
copy. The failure modes are different from the combine tool's:

- **Rows must land on the interval.** Hourly keeps rows at `HH:00`, with seconds
  zero. Data logged at `:05` or `:07` matches nothing, so thinning it would leave
  no data at all. v3 **refuses to write** in that case and names the cause; the
  confirmation dialog shows the before/after counts either way. `-Force`
  overrides. Still worth knowing your logging offset before you start.
- **The original filename is kept**, so a thinned file looks identical to a full
  one. The full copy lands at `Backup\<name>_fulldataset<ext>`.
- **`-NoBackup` removes your only automatic undo.**
- **Discarded rows are gone from the working file.** The backup is the only copy.
- **Files already inside a `Backup` folder are refused** — that is the full-dataset
  copy, and no backup-of-the-backup would be made. `-Force` overrides.

Rows whose timestamp cannot be read are **kept and counted**, never dropped —
discarding a row the tool cannot interpret would be destroying data on a guess.
If *no* row in the file parses, the file is skipped and the expected formats are
reported rather than rewriting it unchanged.

On failure the original is left untouched and temporary files are cleaned up.
`-WhatIf` shows what would happen without writing anything.

### Before you run either on real data

1. Copy a representative folder somewhere scratch and run it there first.
2. Confirm the row count and time range of the result are what you expect.
3. Check the `Backup` folder contains what you think it should.
4. Only then run against live data — and leave `-NoBackup` alone.

---

# Combine DAT files

## Why

A logger table accumulates duplicates from several directions at once:

- collection writes `Station_Table.dat`, and prior versions pile up as
  `.bak`, `.backup`, `.backup1`, `.1`, `.old`, `.orig`, `.copy`
- a card pulled in the field gives
  `13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat`

All of it is the same table, and merging it by hand risks silently stitching
together files whose headers do not actually match — different program, different
column set, different units. This tool makes the header comparison explicit and
requires approval before anything is written.

## Three ways to run it

| Mode | How | What it does |
|---|---|---|
| **Folder** | run with no arguments, choose "Yes", pick a folder | Finds backup-style duplicates and timestamped downloads, groups them, and walks you through each group |
| **Manual** | run with no arguments, choose "No" | You pick the primary file, then the secondaries to merge into it |
| **Direct** | pass a file or folder as the first argument | A file becomes the primary; a folder runs folder mode on it. This is what the right-click menu uses |

```powershell
.\'Combine DAT files_v9.ps1'                                     # folder or manual
.\'Combine DAT files_v9.ps1' 'C:\Data\TM_Site_Diagnostics.dat'    # direct
.\'Combine DAT files_v9.ps1' 'C:\Data\SiteFolder'                 # folder mode
```

Folder mode only looks at files sitting directly in the chosen folder —
subfolders are not entered.

## Install the right-click menu

No administrator rights needed:

```powershell
.\Install-ContextMenu.ps1
```

That registers the entries for the current user, based on wherever this folder
lives. Remove them with `.\Uninstall-ContextMenu.ps1`. Add `-AllUsers` to either
one (from an elevated prompt) to apply machine-wide.

The `.reg` files do the same thing under `HKEY_CLASSES_ROOT`, but they need admin
**and** contain a hard-coded path you must edit first. The PowerShell installer
is preferred.

## How a merge is decided

Files are assumed to be TOA5-shaped:

| Row | Content |
|---|---|
| 1 | file info / metadata (`"TOA5"`, station, model, serial, OS version, …) |
| 2 | column names — **the row that must match** |
| 3 | units |
| 4 | aggregation type |
| 5+ | time-series data |

Approval is two steps, and step 2 only appears if step 1 is approved:

1. row 2 (column names) compared side by side
2. row 1 (file info) compared side by side

In folder mode, an exact row-2 match skips straight to step 2. Data rows are
de-duplicated and sorted on the first column (normally `TIMESTAMP`). The primary
file's header and special rows are preserved as-is; merged secondaries are moved
into a `Backup` folder.

For timestamped downloads the table name is read from **row 1**, not the file
name, so a renamed collected file still matches. If more than one file could be
the merge target, the download is reported and skipped rather than merged into a
guess.

## Options

| Option | Effect |
|---|---|
| `-SpecialRowCount <int>` | Number of special rows after row 1 (default 3, so rows 2–4 are preserved) |
| `-NoBackup` | Skip the pre-merge backup of the primary file |
| `-Encoding` | Override the file encoding |

If a merge is aborted, files are left exactly as they were and the unused
pre-merge backup is removed.

## Documentation

- `README.txt` — packaging and install detail
- `SCRIPT_README.txt` — full reference: modes, comparison windows, backups, parameters

A screen-recorded walkthrough ships with the internal copy of this package but is
not in the repository — it is far past GitHub's file size limit.

---

# Decimate

## Why

Long records get unwieldy: a 15-minute logger produces ~35,000 rows a year, and
for a trend plot or a report you often want hourly or daily. Decimate keeps the
rows that sit on a clean interval and sets the full dataset aside, so the file
stays under its original name while the complete record remains recoverable.

## Running it

Interactively — a settings dialog, then a multi-select file picker, then one
confirmation per file:

```powershell
.\Decimate_v3.ps1
```

The confirmation is the point. It shows rows in, rows kept, rows dropped and the
retained time range **before** anything is written, so a file whose timestamps
don't line up is caught rather than emptied. Buttons are Proceed / Skip file /
Exit all, the same as the combine tool.

Non-interactively — supplying `-Mode` suppresses all dialogs:

```powershell
.\Decimate_v3.ps1 -Mode Hourly -RetainFirst 5 `
                  -Path 'C:\Data\Station1.csv','C:\Data\Station2.dat'

.\Decimate_v3.ps1 -Mode Daily -Path 'C:\Data\*.dat' -WhatIf
```

| Option | Effect |
|---|---|
| `-Mode` | `Hourly` \| `SixHourly` \| `Daily`. Supplying it means no dialogs |
| `-RetainFirst <int>` | Also keep the first N valid rows regardless of interval (`0` disables). SAA files often need `5` |
| `-Path <string[]>` | Files; wildcards allowed. Omit for a picker |
| `-NoBackup` | Skip the backup copy — removes your only automatic undo |
| `-Encoding` | `Auto` (default, matches the input's BOM), `UTF8`, `UTF8BOM`, `ASCII`, `Unicode` |
| `-Force` | Allow emptying a file, and allow files inside `Backup\` |
| `-WhatIf` / `-Confirm` | Standard PowerShell |

The v2 names `-ModeParam`, `-RetainParam` and `-FilesParam` still work as
aliases, so existing scheduled calls keep running.

One summary object per file is emitted, so results can be captured:

```powershell
$r = .\Decimate_v3.ps1 -Mode Hourly -Path 'C:\Data\*.dat'
$r | Where-Object RowsKept -eq 0
```

## What it keeps

| Mode | Rows kept |
|---|---|
| `Hourly` | `HH:00` |
| `SixHourly` | `00:00`, `06:00`, `12:00`, `18:00` |
| `Daily` | `00:00` |

Seconds and milliseconds must be zero. Accepted timestamp formats in the first
column:

```
yyyy-MM-dd HH:mm:ss.fff      yyyy-MM-dd HH:mm:ss
yyyy-MM-dd HH:mm             yyyy-MM-ddTHH:mm:ss[.fff]
```

Header rows are the leading rows whose first column is not a timestamp — however
many that is, including none. Once a timestamp has been seen the header is over,
so a later unreadable row counts as bad data rather than a header.

The original is copied to `Backup\<name>_fulldataset<ext>` before the thinned
version takes its place under the original name.

## Tests

`test_decimate_v3.ps1` covers the cases the review turned on — off-interval data
being refused, fractional-second timestamps, BOM preservation, `-WhatIf` leaving
nothing behind, the v2 aliases, and more:

```powershell
.\test_decimate_v3.ps1
```

Full reference and the v2 → v3 changelog:
[`Decimate_v3_README.txt`](Decimate_v3_README.txt).

## Licence and warranty

GPL-3.0 — see [LICENSE](LICENSE).

As stated there in sections 15–17, the program is licensed free of charge and
comes with **no warranty**: no implied warranty of merchantability or fitness for
a particular purpose, and no liability for damages arising from its use,
including loss of data. See [Use at your own risk](#-use-at-your-own-risk) above
for what that means in practice for this particular tool.
