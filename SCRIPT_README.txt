COMBINE_DAT_FILES.PS1 (v9) – README
====================================

PURPOSE

This PowerShell script combines multiple time-series data files (DAT, CSV, TXT,
and their backups) into a single primary file. It preserves the primary file's
header and special rows, provides a side-by-side VISUAL comparison of headers
before combining, and safely backs up merged files after successful processing.

The script is intended for consolidating structured, timestamp-based datasets
that share a common TOA5-style layout.

WHAT'S NEW IN v9

• FOLDER MODE: point the script at a folder and it automatically finds data
  files that have backup-style duplicates or LoggerNet timestamped downloads
  and groups them for you.
• VISUAL HEADER COMPARISON: differences are shown in a clean, color-coded
  side-by-side window (not just terminal text).
• TWO-STEP APPROVAL per file:
    Step 1 – Header row (row 2) comparison   (Proceed / Decline)
    Step 2 – File info row (row 1) comparison (Proceed / Decline)
  Step 2 is only shown if Step 1 is approved.
• AUTO-PROCEED ON MATCH (folder mode): if the row 2 header matches exactly, the
  script notifies you and jumps straight to the Step 2 (row 1) comparison.
• MERGE ABORTED handling: if nothing is merged, files are left exactly as they
  were and the unused pre-merge backup is removed.

FILE STRUCTURE ASSUMPTIONS

Each file is assumed to have the following structure:

  Row 1              : File info / metadata line (e.g. "TOA5", station, ...)
  Rows 2–4 (default) : Special / header rows
                         Row 2 = column names  (the key row that must match)
                         Row 3 = units
                         Row 4 = aggregation type
  Remaining rows     : Time-series data

Notes:
• The number of special rows can be changed with -SpecialRowCount (default 3)
• Data rows are expected to be comma-separated
• Sorting and uniqueness are based on the FIRST column (typically TIMESTAMP)

SUPPORTED / RECOGNIZED FILE TYPES

Data files (become the PRIMARY in a group):
  .dat  .csv  .txt

Backup-style duplicates (become SECONDARIES in folder mode):
  .bak    .backup    .backup1 (backupN)    .1 (any number)
  .old    .orig      .copy
  e.g.  Foo.dat.backup   Foo.dat.1   Foo.dat.backup1

LoggerNet / CardConvert downloads (also become SECONDARIES in folder mode):
  <serial>_<Table>_<YYYY-MM-DDTHH-MM[-SS]>.dat / .csv / .txt
  e.g.  13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat
  These merge into the collected file holding the SAME TABLE in the same folder:
  e.g.  13910_SAA_DIAGNOSTICS_2026-07-23T15-44.dat
          -> TM_MCL-02_SAA_DIAGNOSTICS.dat

  The table name is taken from TOA5 ROW 1, not from the file name. Row 1 is:
     "TOA5","TM_MCL-02","CR6","13910","CR6.Std.14.01","prog.cr6","31248","Status"
      1      2 station    3     4        5              6         7       8 TABLE
  Row 1 is what the datalogger itself wrote, so renamed or re-collected files
  still match correctly.

  Matching is strict, so nothing is merged into the wrong file:
   • the download's serial must be digits only, and the stamp must be exactly
     YYYY-MM-DDTHH-MM (optionally -SS) with nothing after it
   • the row-1 table names must be equal (case-insensitive)
   • the extension must be the same
   • a file that HAS a row 1 whose table disagrees is never matched by its name
   • files with no TOA5 row 1 fall back to matching on the "_<Table>" ending
     of the file name
   • if two or more files could still be the target, the tie is broken only on
     hard evidence - the row-1 serial number, then the file-name table suffix.
     If it is still not down to exactly one file, the download is reported and
     SKIPPED - it is never merged into a guess.

THREE WAYS TO RUN

1) FOLDER MODE  (auto-group duplicates)
   • Run the script with no primary file.
   • At the "Choose Mode" prompt, click YES.
   • Pick a folder. The script scans it and groups each data file with its
     backup-style duplicates and its LoggerNet timestamped downloads.
   • For each group it runs the two-step comparison, then merges.

     From PowerShell:
         .\"Combine DAT files_v9.ps1"
         (click "Yes", then choose a folder)

   Folders that are IGNORED during the scan:
         backup, bak, scd, superseded  (and common misspellings such as
         superceded / superseeded)

2) MANUAL MODE  (pick files yourself)
   • Run the script with no primary file.
   • At the "Choose Mode" prompt, click NO.
   • Select the PRIMARY file to retain.
   • Select one or more SECONDARY files to merge into it.

     From PowerShell:
         .\"Combine DAT files_v9.ps1"
         (click "No", pick a primary, then pick secondaries)

3) DIRECT / RIGHT-CLICK MODE  (primary supplied up front)
   • Provide a primary file as the first argument or via -PrimaryFile.
   • The mode prompt is skipped; you go straight to picking secondary files.
   • This is what the right-click "Run with PowerShell" context entry uses; the
     right-clicked file becomes the PRIMARY.

     From PowerShell:
         .\"Combine DAT files_v9.ps1" "C:\Data\TM_Site_Diagnostics.dat"
         .\"Combine DAT files_v9.ps1" -PrimaryFile "C:\Data\TM_Site_Diagnostics.dat"

OPTIONAL PARAMETERS (all modes)

  -SpecialRowCount <int>
      Number of special/metadata rows after the header row.
      Default 3 (rows 2–4 are preserved from the primary).

  -NoBackup
      Do not create a pre-merge backup of the primary file.

  -Encoding <UTF8 | ASCII | Unicode>
      Output encoding for the updated primary file. Default UTF8.
      ASCII additionally enables non-ASCII character checks on the files.

  Example:
      .\"Combine DAT files_v9.ps1" -SpecialRowCount 3 -Encoding UTF8

THE VISUAL COMPARISON WINDOW

Each comparison opens a window titled either:
  "Step 1 of 2: Header Row Comparison" (Row 2), or
  "Step 2 of 2: File Info Comparison"  (Row 1)

It shows a column-by-column, side-by-side table:

  #  |  Primary  |  Secondary  |  Status

Status values:
  Match                 – columns are identical (green)
  Different             – values differ (primary rose / secondary amber)
  Missing in Primary    – secondary has an extra column
  Missing in Secondary  – primary has an extra column

Buttons:
  Proceed / Proceed Anyway  – accept and continue
  Decline (Skip File)       – skip this file (no merge, no move)

The status banner at the top is green when the values are identical and red when
they differ.

COMBINING LOGIC

• Data rows from an approved secondary are appended to the primary dataset
• Combined data is de-duplicated (unique rows only) and sorted by the first
  column (typically TIMESTAMP)
• The updated dataset overwrites the primary file, preserving the primary's
  row 1 and special rows

BACKUP BEHAVIOR

• A folder named "Backup" is created next to the primary file
• Before merging, the primary is copied into Backup (unless -NoBackup)
• After a successful merge, each merged secondary is MOVED into Backup
• If a name already exists in Backup, a timestamp is appended
• If NOTHING is merged for a primary, the unused pre-merge backup is removed and
  the (now empty) Backup folder is cleaned up

NON-ASCII CHARACTER CHECK  (ASCII encoding only)

• When -Encoding ASCII is used, the primary and each secondary are scanned for
  non-ASCII characters
• If detected, the affected line numbers are reported and you are prompted to
  continue or skip that file

OUTPUT & SUMMARIES

Manual / direct mode:
  • "MERGE COMPLETE" – files processed, rows added, final row count, file path
  • "MERGE ABORTED"  – nothing merged; all files left unchanged

Folder mode:
  • "FOLDER SCAN COMPLETE" – groups found, groups merged, files merged, and
    total rows added, shown in the console and a summary message box

ERROR HANDLING

• Files with fewer than 2 lines are skipped
• If writing the primary file fails, the corresponding secondary is NOT moved
• Errors are reported clearly in the console

NOTES

• Recommended PowerShell version: 5.1 or later
• Windows only (uses Windows Forms dialogs)
• Files are modified in place — backups are strongly recommended
• Designed for structured, timestamp-based (TOA5-style) datasets

END OF README