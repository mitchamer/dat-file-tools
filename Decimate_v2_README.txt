DECIMATE_V2.PS1 – README
PURPOSE

This PowerShell script decimates time-series CSV or DAT files by keeping only
rows at fixed time intervals (hourly, 6-hourly, or daily). It is designed to
reduce dataset size while preserving regularly spaced timestamped records.
Original files are safely backed up before being overwritten.

WHAT THE SCRIPT DOES

• Accepts one or more .csv or .dat files
• Automatically detects and preserves header rows
• Filters data rows based on timestamps in the FIRST column
• Supports three decimation modes:
- Hourly : keeps rows at HH:00:00
- SixHourly : keeps rows at 00, 06, 12, and 18 hours
- Daily : keeps rows at 00:00:00
• Optionally retains the first N valid data rows
(useful for SAA initialization data)
• Creates a backup of the original file before replacing it
• Retains the original filename for the decimated output

INPUT FILE REQUIREMENTS

• File type: .csv or .dat
• Timestamp MUST be in the first column
• Timestamp format MUST be exactly:

yyyy-MM-dd HH:mm:ss

Example:
2024-03-15 06:00:00

• Files may contain multiple header rows
(these are detected automatically and preserved)

BACKUP BEHAVIOR

• A folder named "Backup" is created in the same directory as the input file
• The original file is copied to:

Backup<original_name>_fulldataset.csv

• If a backup already exists, a timestamp is appended
• If the input file is already inside a "Backup" folder, no new backup
is created

HOW TO RUN – INTERACTIVE MODE

Run the script:
• Right-click Decimate_v2.ps1 → "Run with PowerShell"
OR
• From PowerShell:
.\Decimate_v2.ps1

When prompted:
• Select decimation mode:
1 = Hourly (default)
6 = Six-hourly
24 = Daily
• Enter how many initial data rows to retain
(enter 0 to disable)

A file selection window will open:
• Select one or more CSV/DAT files
• Click "Open" to process them

HOW TO RUN – NON-INTERACTIVE / COMMAND LINE

Parameters:
• -ModeParam : Hourly | SixHourly | Daily
• -RetainParam : Integer (number of initial data rows to retain)
• -FilesParam : One or more full file paths

Example:

.\Decimate_v2.ps1 ^
-ModeParam Hourly ^
-RetainParam 5 ^
-FilesParam "C:\Data\Station1.csv","C:\Data\Station2.dat"

OUTPUT

• Original file is replaced with the decimated version
• Headers and retained rows are preserved
• Filename remains unchanged
• Console output confirms:
- Backup creation
- Processing status

ERROR HANDLING

• Files with fewer than 3 rows are skipped
• Rows with unparseable timestamps are kept and reported
• If processing fails:
- Original file is NOT overwritten
- Temporary files are cleaned up

NOTES

• Recommended PowerShell version: 5.1 or later
• Windows only (uses Windows file selection dialog)
• Files are modified in place — verify backups before bulk processing

END OF README