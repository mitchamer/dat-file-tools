# dat-file-tools — Combine Time Series Files

Combines LoggerNet / TOA5-style time-series data files (`.dat` / `.csv` / `.txt`)
and their backups into a single file, with a visual header comparison before each
merge. Built for Campbell Scientific datalogger output, where the same table ends
up split across collected files, `.bak`/`.backup` duplicates, and timestamped
CardConvert downloads.

Windows PowerShell 5.1 or later (PowerShell 7 works). Uses Windows Forms dialogs,
so it is Windows-only.

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

## Licence

GPL-3.0. See [LICENSE](LICENSE).
