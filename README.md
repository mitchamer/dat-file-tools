# dat-file-tools

PowerShell tools for the housekeeping that piles up around Campbell Scientific /
LoggerNet data files (`.dat` / `.csv` / `.txt`) — the same table arriving from
automatic collection, local manual downloads, remote manual collections and
backups all at once, records that grow past the
point of being useful to plot, and trees of daily Affinity downloads.

Windows PowerShell 5.1 or later (PowerShell 7 works). Windows only — the tools use
Windows Forms dialogs.

| Tool | Use it when | |
| --- | --- | --- |
| **[Combine DAT files](combine-dat-files/)** | One table is scattered across a live collected file (primary), `.bak` and `.backup` copies and timestamped manual downloads (local or remote). You want all available records in one continuous file. Normally you would do this manually, but you risk merging files with mismatched headers, mismatched column counts, and unsorted dates. This script handles those issues for you. | [docs](combine-dat-files/README.md) |
| **[Combine Affinity Files](combine-dat-files/)** | Hundreds of daily downloads scattered through dated subfolders, and you want one new file per dataset. Recursive, non-destructive, TOACI1 (and TOA5). Not a replacement for folder-mode Combine DAT files | [docs](combine-dat-files/README.md#combine-affinity-files) |
| **[Decimate](decimate/)** | A file has more rows than you need, and you want hourly, six-hourly or daily — keeping the full record recoverable | [docs](decimate/README.md) |
| **[Fix Timestamps](fix-timestamps/)** | The first column is `9/1/2026` or `2026/9/1` rather than `YYYY-MM-DD HH:MM:SS`. Every other tool here sorts rows as text, which that breaks silently. Decides each file's date format from the file's own contents and refuses the ones it cannot settle | [docs](fix-timestamps/README.md) |

## ⚠ Use at your own risk

**Combine DAT files and Decimate rewrite data files in place. Combine Affinity
Files writes a new file and leaves sources alone unless you pass `-MoveSources`.**
Run them on copies until you trust them, and keep independent backups of anything
you cannot regenerate.

Provided "as is" with **no warranty of any kind** — see sections 15–17 of
[LICENSE](LICENSE) (GPL-3.0). You are responsible for verifying output before
relying on it for analysis, reporting or any decision. The authors accept no
liability for lost, altered or corrupted data.

Combine DAT files and Decimate follow the same safety pattern:

- the original is copied into a `Backup` folder before anything is written
- you are shown what will change and must approve it — a header comparison for
  Combine, a rows-kept/rows-dropped count for Decimate
- on failure the original is left untouched and temporary files are removed
- `Proceed` / `Skip file` / `Exit all` mean the same thing in both

Affinity's undo is deleting the `Combined` output folder. `-MoveSources` is the
one destructive switch — off by default.

What each one can specifically get wrong is documented in its own README. Read
that section before a first run — it is short, and it is the part that matters.

## Quick start

Clone or download, then:

```powershell
# merge a folder's duplicates, approving each header comparison
.\combine-dat-files\'Combine DAT files.ps1'

# optional: add Explorer right-click entries for it (per-user, no admin)
.\combine-dat-files\Install-ContextMenu.ps1

# recursive combine of a download tree (writes Combined\, does not touch sources)
.\combine-dat-files\'Combine Affinity Files.ps1' 'C:\Data\affinity'

# check a folder's timestamp format without changing anything
.\fix-timestamps\Fix-Timestamps.ps1 'C:\Data\Site' -DryRun

# thin a file to hourly, previewing before it writes
.\decimate\Decimate.ps1

# see what decimating would do without writing anything
.\decimate\Decimate.ps1 -Mode Hourly -Path 'C:\Data\*.dat' -WhatIf
```

Run Combine DAT files or Decimate with no arguments and they will prompt for
everything they need. Combine Affinity Files with no arguments opens a folder
picker for the tree to scan.

## Layout

```
combine-dat-files/    Combine DAT files, Combine Affinity Files, context-menu installers, docs
decimate/             the thinning tool, its tests, and its docs
fix-timestamps/       the timestamp normaliser, its context-menu installer, tests and docs
```

Each folder is self-contained — copy just the one you need. `combine-dat-files`
and `fix-timestamps` each carry their own context-menu installer, and each
resolves the script beside it, so they keep working wherever the folder lives.

**Order of operations:** if a folder's timestamps are not already
`YYYY-MM-DD HH:MM:SS`, run **Fix Timestamps** before combining or decimating.
Both of those sort rows as text, which is only correct once the first column is
in that shape.

## Licence

GPL-3.0 — see [LICENSE](LICENSE). Licensed free of charge, with no warranty and
no liability for damages arising from use, including loss of data.
