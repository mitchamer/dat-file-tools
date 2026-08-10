# Combine DAT files (v9)

Merges a table's scattered copies — the collected file, its `.bak`/`.backup`
duplicates, and timestamped card downloads — into one file, showing a side-by-side
header comparison that you must approve before anything is written.

Built for TOA5-style output, where the same logger table ends up in several files
and merging by hand risks stitching together data from different programs, column
sets or units.

Windows PowerShell 5.1+ (7 works). Windows only.

> Merged from the former `README.txt` and `SCRIPT_README.txt`, which overlapped.

## ⚠ Use at your own risk

**A merge is destructive and cannot be undone automatically.** Provided "as is"
with no warranty — see [LICENSE](../LICENSE) sections 15–17.

Behaviours to understand before pointing it at anything you care about:

- **The primary file is rewritten in place.** Row 1 and the special rows are
  preserved, but the data section is replaced by the merged, de-duplicated,
  re-sorted result. Original row order is not retained.
- **Secondary files are moved, not copied**, into `Backup` after a successful merge.
- **De-duplication compares the entire row, case-insensitively.** Two rows sharing
  a timestamp but differing in values are both kept, as they should be — but two
  rows differing *only* in letter case (`NAN` vs `NaN`) collapse to one. This is
  the one genuine silent-loss case.
- **Sorting is a text sort on the first column.** Correct for
  `YYYY-MM-DD HH:MM:SS`; wrong for formats like `M/D/YYYY`.
- **`-NoBackup` removes your only automatic undo.**
- **The file is rewritten with the encoding from `-Encoding`.** If that does not
  match the original, characters can change.

The comparison dialogs exist because these operations cannot be reversed. Read
them rather than clicking through — declining one file is cheap, un-merging one is
not.

**Before a first run on real data:** copy a representative folder somewhere
scratch, run it there, confirm the row count and time range, check `Backup`
contains what you expect. Then run it live, and leave `-NoBackup` alone.

## Three ways to run it

### 1. Folder mode — auto-group duplicates

Run with no arguments and click **Yes** at the mode prompt, then pick a folder. It
groups each data file with its backup-style duplicates and timestamped downloads,
then runs the two-step comparison per group.

```powershell
.\'Combine DAT files_v9.ps1'
```

Only files sitting **directly** in the chosen folder are scanned — subfolders are
not entered. These folder names are skipped: `backup`, `bak`, `scd`, `superseded`
(and the common misspellings `superceded` / `superseeded`).

### 2. Manual mode — pick files yourself

Run with no arguments and click **No**. Choose the primary file to keep, then one
or more secondaries to merge into it.

### 3. Direct mode — primary supplied up front

Pass a file and the mode prompt is skipped; pass a folder and it runs folder mode
directly. This is what the right-click entries use.

```powershell
.\'Combine DAT files_v9.ps1' 'C:\Data\TM_Site_Diagnostics.dat'
.\'Combine DAT files_v9.ps1' -PrimaryFile 'C:\Data\TM_Site_Diagnostics.dat'
.\'Combine DAT files_v9.ps1' 'C:\Data\SiteFolder'
```

## Right-click menu

No administrator rights needed — registers for the current user, based on wherever
this folder lives:

```powershell
.\Install-ContextMenu.ps1          # add
.\Uninstall-ContextMenu.ps1        # remove
```

Add `-AllUsers` to either, from an elevated prompt, to apply machine-wide.

You get three entries: on a **file** (becomes the primary), on a **folder** (scans
it), and on a **folder background** (scans the current folder).

> If you move this folder, re-run `Install-ContextMenu.ps1` — the registered
> command records the path it was installed from.

The `.reg` files do the same under `HKEY_CLASSES_ROOT`, but need admin **and**
contain a hard-coded path you must edit first. The PowerShell installer is
preferred.

## What it expects

| Row | Content |
|---|---|
| 1 | file info / metadata (`"TOA5"`, station, model, serial, OS version, program, signature, table) |
| 2 | column names — **the row that must match** |
| 3 | units |
| 4 | aggregation type |
| 5+ | comma-separated time-series data |

`-SpecialRowCount` changes how many rows after row 1 are treated as special
(default 3, so rows 2–4). Sorting and uniqueness use the first column.

### Files it recognises

**Primaries:** `.dat` `.csv` `.txt`

**Backup-style secondaries:** `.bak` `.backup` `.backupN` `.1` (any number)
`.old` `.orig` `.copy` — e.g. `Foo.dat.backup`, `Foo.dat.1`

**LoggerNet / CardConvert downloads:**
`<serial>_<Table>_<YYYY-MM-DDTHH-MM[-SS]>.dat` — e.g.
`13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat`, merging into the collected file
holding the same table.

The table name comes from **row 1**, not the filename:

```
"TOA5","TM_MCL-02","CR6","13910","CR6.Std.14.01","prog.cr6","31248","Status"
 1      2 station    3     4       5              6          7       8 TABLE
```

Row 1 is what the logger itself wrote, so renamed or re-collected files still
match. Matching is strict so nothing lands in the wrong file:

- the serial must be digits only, and the stamp exactly `YYYY-MM-DDTHH-MM`
  (optionally `-SS`) with nothing after it
- row-1 table names must be equal (case-insensitive)
- extensions must match
- a file whose row 1 names a *different* table is never matched by its filename
- files with no TOA5 row 1 fall back to matching the `_<Table>` filename ending
- if two or more files could still be the target, the tie breaks only on hard
  evidence — row-1 serial, then filename table suffix. If that still leaves more
  than one, the download is **reported and skipped**, never merged into a guess

## The comparison window

Titled either *Step 1 of 2: Header Row Comparison* (row 2) or *Step 2 of 2: File
Info Comparison* (row 1). Step 2 only appears if step 1 is approved. In folder
mode, an exact row-2 match skips straight to step 2.

Columns: `# | Primary | Secondary | Status`

| Status | Meaning |
|---|---|
| Match | identical (green) |
| Different | values differ (primary rose / secondary amber) |
| Missing in Primary | secondary has an extra column |
| Missing in Secondary | primary has an extra column |

The banner is green when values are identical, red when they differ.

| Button | Effect |
|---|---|
| Proceed / Proceed Anyway | accept and continue |
| Decline (Skip File) | skip this secondary only; the scan continues. Esc or closing does the same |
| Exit All | stop immediately. Already-merged files stay merged |

## Options

| Option | Effect |
|---|---|
| `-SpecialRowCount <int>` | Special rows after row 1 (default 3) |
| `-NoBackup` | Skip the pre-merge backup of the primary |
| `-Encoding <Auto\|UTF8\|UTF8BOM\|ASCII\|Unicode>` | Output encoding. **Default `Auto`** — matches the primary's existing byte-order mark. `ASCII` also enables non-ASCII character checks |

```powershell
.\'Combine DAT files_v9.ps1' -SpecialRowCount 3 -Encoding Auto
```

### Fixed: merging used to make LoggerNet abandon the file

Earlier versions defaulted to `-Encoding UTF8` via `Set-Content`, which **under
PowerShell 5.1 writes a byte-order mark** (PowerShell 7 does not). A BOM sits
ahead of the TOA5 row, so LoggerNet could no longer recognise the data file it was
appending to — it renamed the file to `.dat.backup` and started a fresh one.

The result was quietly bad: the merge itself succeeded, but LoggerNet stopped
using the merged file, collection restarted from zero, and the merged history was
left orphaned in a `.backup` nobody was looking at.

`Auto` fixes this by writing the file back the way it was found. LoggerNet data
files have no BOM, so none is added. `test_encoding.ps1` covers it:

```powershell
.\test_encoding.ps1
```

**If this already happened to you**, the symptom is a large `.dat.backup` beside a
small, recently-started `.dat`, and the `.backup` begins with the bytes
`EF BB BF`. To check and recover:

```powershell
# does the backup carry a BOM?
$f = 'X_DATA.dat.backup'
$b = New-Object byte[] 3
$s = [IO.File]::OpenRead($f); $null = $s.Read($b,0,3); $s.Dispose()
'{0:X2} {1:X2} {2:X2}' -f $b[0],$b[1],$b[2]     # EF BB BF means yes

# strip it, then merge the backup into the live .dat with this fixed version
$lines = [string[]](Get-Content -LiteralPath $f)
[IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding($false)))
```

Then run the combine tool with the **live `.dat` as the primary** and the
`.backup` as the secondary, so the result stays in the file LoggerNet is
collecting into. Do it between collections, or with LoggerNet's collection for
that station paused.

With `-Encoding ASCII`, the primary and each secondary are scanned for non-ASCII
characters; if any are found the line numbers are reported and you choose whether
to continue or skip that file.

## Backups

- a `Backup` folder is created next to the primary
- the primary is copied there before merging (unless `-NoBackup`)
- each merged secondary is **moved** there afterwards
- if a name already exists there, a timestamp is appended
- if nothing was merged, the unused pre-merge backup is removed and an empty
  `Backup` folder is cleaned up

## Output

Manual / direct mode ends with **MERGE COMPLETE** (files processed, rows added,
final row count, path) or **MERGE ABORTED** (nothing merged, everything unchanged).

Folder mode ends with **FOLDER SCAN COMPLETE** — groups found, groups merged,
files merged, total rows added — in the console and a summary box.

## Errors

- files with fewer than 2 lines are skipped
- if writing the primary fails, the corresponding secondary is **not** moved
- errors are reported in the console

## Notes

A screen-recorded walkthrough ships with the internal copy of this package but is
not in the repository — it is far past GitHub's file size limit.
