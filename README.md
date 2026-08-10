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
| **Decimate** (`Decimate_v2.ps1`) | Thins a file to rows landing exactly on the hour, every six hours, or daily. Backs up the full dataset first | [`Decimate_v2_README.txt`](Decimate_v2_README.txt) |

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

- **Rows must land exactly on the interval.** Hourly keeps only rows where minute
  *and* second are `0`. Data logged at `:05`, `:07`, `:15` matches nothing, so
  **every data row is dropped** and you are left with the headers plus any
  `-RetainParam` rows. Check your logging interval and offset before running —
  this is the way to empty a file in one go.
- **Timestamps must be exactly `yyyy-MM-dd HH:mm:ss`, in the first column.** Rows
  that fail to parse are kept and reported, so a file in another format is not
  damaged — but nothing is thinned either, which is a silent no-op.
- **No backup is created if the input is already inside a `Backup` folder** — and
  the file is still overwritten. Do not re-run this on its own output.
- **The original filename is kept**, so a thinned file looks identical to a full
  one. The full copy lands at `Backup\<name>_fulldataset<ext>`.
- **Output is written as UTF-8** regardless of the input encoding.
- If the very first row happens to parse as a timestamp, header detection finds no
  headers and falls back to assuming 2 — so the first two data rows are treated as
  headers and always retained.

On failure the original is left untouched and temporary files are cleaned up.

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

Interactively, it asks for the mode and the retain count, then opens a file
picker (multi-select):

```powershell
.\Decimate_v2.ps1
```

At the prompts: `1` = hourly (default), `6` = six-hourly, `24` = daily. The
retain count keeps the first N valid data rows regardless of their timestamp —
useful for SAA files whose initialisation rows matter.

Non-interactively:

```powershell
.\Decimate_v2.ps1 -ModeParam Hourly -RetainParam 5 `
                  -FilesParam "C:\Data\Station1.csv","C:\Data\Station2.dat"
```

| Option | Effect |
|---|---|
| `-ModeParam` | `Hourly` \| `SixHourly` \| `Daily` |
| `-RetainParam <int>` | Keep the first N valid data rows regardless of interval (`0` disables) |
| `-FilesParam <paths>` | One or more files; skips the picker |

## What it keeps

| Mode | Rows kept |
|---|---|
| `Hourly` | `HH:00:00` |
| `SixHourly` | `00:00:00`, `06:00:00`, `12:00:00`, `18:00:00` |
| `Daily` | `00:00:00` |

Header rows are found by scanning down from the top until a first column parses
as `yyyy-MM-dd HH:mm:ss`, and everything above that is preserved as-is. The
original is copied to `Backup\<name>_fulldataset<ext>` before the thinned version
takes its place under the original name.

Full reference: [`Decimate_v2_README.txt`](Decimate_v2_README.txt).

## Licence and warranty

GPL-3.0 — see [LICENSE](LICENSE).

As stated there in sections 15–17, the program is licensed free of charge and
comes with **no warranty**: no implied warranty of merchantability or fitness for
a particular purpose, and no liability for damages arising from its use,
including loss of data. See [Use at your own risk](#-use-at-your-own-risk) above
for what that means in practice for this particular tool.
