# Fix Timestamps

Rewrites the first column of time-series data files into one canonical shape:

```
YYYY-MM-DD HH:MM:SS
```

It accepts the shapes these files arrive in, it decides each file's date format
from the file's own contents rather than from a guess, and **a file it cannot
decide is left exactly as it was** with a note beside it saying why.

Windows PowerShell 5.1+ (7 works). Windows only (the folder picker and summary
box use Windows Forms; `-Unattended` skips both).

## Why it exists

Every other tool in this repo sorts rows as **text**, which is correct only
while the first column is `YYYY-MM-DD HH:MM:SS` — fixed width, largest unit
first. A file written as `9/1/2026` sorts into nonsense, and the damage is
quiet: every row is still there, just in the wrong order. Run this first, then
merge or decimate.

## ⚠ Use at your own risk

**This rewrites data files in place.** Provided "as is" with no warranty — see
[LICENSE](../LICENSE) sections 15–17.

- the original is copied into `Backup\` first, unless `-NoBackup`
- only the **first field** of each data row is touched — the rest of the row,
  the header rows and the file's byte-order mark are preserved exactly
- a file that is already correct is **not rewritten, backed up or touched**, so
  running this twice is the same as running it once
- `-DryRun` reports every decision and writes nothing. Use it first — the
  right-click menu has an entry for exactly that.

## The month/day problem

`01/09/2026` is the 1st of September or the 9th of January, and the file alone
cannot always say. Rather than trusting a format string, the **field order is
decided once per file** from the file's own contents:

1. **Split** each first field into its numbers. Where the 4-digit year sits
   narrows the candidates immediately.
2. **Drop any reading that produces an impossible date** on any row — a `13` in
   the month slot settles it outright.
3. **Drop any reading whose dates do not ascend.** Ties are allowed; repeated
   timestamps are normal in this data. This is the test that separates `M/D`
   from `D/M` in a file where every number is 12 or less.
4. **One reading left** → convert. **None, or two that disagree** → the file is
   not touched and the reason is written out.

Two readings that survive and produce *identical* output (every date has the
same day and month, `2026-05-05`) are not a conflict — there is nothing to be
wrong about — so the conversion proceeds.

### Order of preference

Readings are tried in tiers, and the first tier that works wins:

| Tier | Reading | Example | |
|---|---|---|---|
| 1 | `YMD` | `2026-09-01` | the ISO ordering |
| 2 | `MDY` / `DMY` | `09/01/2026` / `01/09/2026` | tried **together** — both are real conventions |
| 3 | `YDM` | `2026-01-09` | last resort — no locale writes year-day-month |

Tier 2 is where the genuine doubt lives, and a file that fits both readings
differently is refused.

Tier 1 beating tier 3 is deliberate. As a flat contest, `YDM` would collide with
`YMD` on *every* year-first file whose days are all 12 or less — so an ordinary
`2026/9/1` file would be refused as "ambiguous" when nobody would ever read it
the other way. `YDM` is still reachable, but only once `YMD` has been ruled out.

## What it accepts

| Shape | Example |
|---|---|
| Year first | `2026/9/1 0:00:00`, `2026-9-1 00:00:00` |
| Year last | `9/1/2026 00:00:00`, `1/9/2026 00:00:00` |
| Two-digit years | `26-09-01`, `9/1/26` |
| ISO `T` separator | `2026-09-01T00:00:00`, trailing `Z` allowed |
| AM/PM | `2026/9/1 1:05:00 PM` → `13:05:00` |
| No seconds | `2026/9/1 00:00` → `00:00:00` |
| Date only | `2026/9/1` → `2026-09-01 00:00:00` |

Separators may be `-`, `/` or `.`, and may be mixed within a file.

**Two-digit years:** `00`–`69` → 2000–2069, `70`–`99` → 1970–1999. Stated
because it is a cut-off, not a fact. The ascending test still has to pass with
those values, so a wrong century that reorders the file is caught.

## What it refuses

All three leave the file **completely untouched**:

| Refused | Why |
|---|---|
| **Any unparseable row** — junk, `NAN`, a truncated line | One bad row stops the whole file. A part-converted file is worse than an untouched one |
| **Fractional seconds** (`00:00:00.5`) | The target format holds whole seconds, so converting would drop precision and could turn two distinct rows into apparent duplicates |
| **Dates that run backwards under every reading** | Usually means the file is already out of order rather than badly formatted. This tool never sorts — it only rewrites field 1 in place |

Blank lines are structural, not rows: they are preserved and are not counted
against the file. A file with no date-like first column at all (a notes file) is
skipped quietly, with no error note — that is not doubt, it is just not data.

## The error note

A refused file gets `<name>_DATEFORMATERROR.txt` beside it:

```
DATE FORMAT NOT CHANGED
=======================
File:      C:\Data\Site\ambiguous.dat
Checked:   2026-10-14 17:21:17
Header rows: 4
Data rows:   3

THE FILE WAS NOT MODIFIED. No backup was made, because nothing was written.

Why:
  - Ambiguous: MDY and DMY both give real dates in ascending order, and they
    disagree. Line 5 reads as MDY -> 2026-09-01 00:00:00, DMY -> 2026-01-09
    00:00:00. Nothing in this file settles which is right, so nothing was changed.
...
```

It lists what was tried, why each reading was dropped (with the line number that
killed it), and the first few rows as they stand, so the question can usually be
settled by eye. The note is **deleted automatically** once that file converts
cleanly, so a leftover note always means a live question.

## How to run it

### Right-click (the folder you are looking at, nothing deeper)

```powershell
.\Install-ContextMenu.ps1          # per-user, no admin
```

Two entries appear on a folder, and on the empty space inside one:

- **Fix Timestamp Format** — converts
- **Check Timestamp Format (no changes)** — the same scan with `-DryRun`

Both pass only the folder, so the scan is **that folder alone** — subfolders are
never entered from the menu. `.\Uninstall-ContextMenu.ps1` removes them.

There is deliberately no `.reg` file: it would have to hard-code the path, which
goes stale the moment the folder moves.

### Terminal (where `-Depth` lives)

```powershell
.\Fix-Timestamps.ps1 'C:\Data\Site'                 # this folder only
.\Fix-Timestamps.ps1 'C:\Data\Site' -DryRun         # report, write nothing
.\Fix-Timestamps.ps1 'C:\Data\Site' -Depth 2        # plus two levels of subfolder
.\Fix-Timestamps.ps1 'C:\Data\Site\One.dat'         # a single file
.\Fix-Timestamps.ps1                                # folder picker
```

## Options

| Option | Effect |
|---|---|
| `-Depth <int>` | Levels of subfolder to descend. **0 (default)** is the given folder only — what the right-click entries use |
| `-DryRun` | Report every decision, write nothing (the same idea as Decimate's `-WhatIf`) |
| `-NoBackup` | Skip the copy into `Backup\`. Removes the only automatic undo |
| `-Extensions <string[]>` | Defaults to `dat`, `csv`, `txt` |
| `-Encoding <Auto\|UTF8\|UTF8BOM\|ASCII\|Unicode>` | Default `Auto` — writes the file back with the byte-order mark it arrived with. A BOM in front of the TOA5 row leaves LoggerNet unable to recognise the file, so `Auto` matters |
| `-Unattended` | Never open a dialog — no folder picker, no summary box. For scheduled runs |

`Backup`, `Combined` and `Sources` folders are never scanned, and neither are
this tool's own `_DATEFORMATERROR.txt` notes or the combine tool's
`.merge-log.txt` files.

## Tests

```powershell
.\test_timestamps.ps1
```

63 checks: every accepted shape, the month/day cases decided by the ascending
test, each refusal leaving the file byte-for-byte unchanged, round-trip fidelity
(quoting, trailing fields, headers, BOM), `-DryRun` writing nothing, `-Depth`,
the skipped folders, and the two-digit-year window. It loads the script's
functions through the AST and opens no dialogs, so it runs unattended.
