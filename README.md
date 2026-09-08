# dat-file-tools

PowerShell tools for the housekeeping that piles up around Campbell Scientific /
LoggerNet TOA5 data files (`.dat` / `.csv` / `.txt`) — the same table arriving from
collection, card downloads and backups all at once, and records that grow past the
point of being useful to plot.

Windows PowerShell 5.1 or later (PowerShell 7 works). Windows only — both tools use
Windows Forms dialogs.

| Tool | Use it when | |
|---|---|---|
| **[Combine DAT files](combine-dat-files/)** | One table is scattered across a collected file, `.bak` copies and timestamped card downloads, and you want one file — without silently stitching together mismatched headers | [docs](combine-dat-files/README.md) |
| **[Decimate](decimate/)** | A file has more rows than you need, and you want hourly, six-hourly or daily — keeping the full record recoverable | [docs](decimate/README.md) |

## ⚠ Use at your own risk

**Both tools rewrite data files in place. Run them on copies until you trust them,
and keep independent backups of anything you cannot regenerate.**

Provided "as is" with **no warranty of any kind** — see sections 15–17 of
[LICENSE](LICENSE) (GPL-3.0). You are responsible for verifying output before
relying on it for analysis, reporting or any decision. The authors accept no
liability for lost, altered or corrupted data.

Both tools follow the same safety pattern:

- the original is copied into a `Backup` folder before anything is written
- you are shown what will change and must approve it — a header comparison for
  Combine, a rows-kept/rows-dropped count for Decimate
- on failure the original is left untouched and temporary files are removed
- `Proceed` / `Skip file` / `Exit all` mean the same thing in both

What each one can specifically get wrong is documented in its own README. Read
that section before a first run — it is short, and it is the part that matters.

## Quick start

Clone or download, then:

```powershell
# merge a folder's duplicates, approving each header comparison
.\combine-dat-files\'Combine DAT files.ps1'

# optional: add Explorer right-click entries for it (per-user, no admin)
.\combine-dat-files\Install-ContextMenu.ps1

# thin a file to hourly, previewing before it writes
.\decimate\Decimate.ps1

# see what decimating would do without writing anything
.\decimate\Decimate.ps1 -Mode Hourly -Path 'C:\Data\*.dat' -WhatIf
```

Run either script with no arguments and it will prompt for everything it needs.

## Layout

```
combine-dat-files/    the merge tool, its context-menu installers, and its docs
decimate/            the thinning tool, its tests, and its docs
```

Each folder is self-contained — copy just the one you need. The context-menu
installer resolves the script beside it, so it keeps working wherever the folder
lives.

## Licence

GPL-3.0 — see [LICENSE](LICENSE). Licensed free of charge, with no warranty and
no liability for damages arising from use, including loss of data.
