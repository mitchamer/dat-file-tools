Combine Time Series Files - Package
===================================

A small, self-contained tool for combining LoggerNet / TOA5-style time-series
data files (.dat / .csv / .txt) and their backups into a single file, with a
visual header comparison before each merge.

This package is portable: put the whole folder anywhere (for example
C:\tools\loggernet-monitor\CombineTimeSeriesFiles) and run the installer.


CONTENTS
--------
  Combine DAT files_v9.ps1     The main script (all the logic).
  Install-ContextMenu.ps1      Adds right-click menu entries (per-user, no admin).
  Uninstall-ContextMenu.ps1    Removes those right-click menu entries.
  SCRIPT_README.txt            Full documentation of the script and its modes.
  Add_CombineDAT_Context.reg   Static installer (edit the path first; needs admin).
  Remove_CombineDAT_Context.reg Static uninstaller (needs admin).
  README.txt                   This file.


QUICK START (recommended - no admin required)
---------------------------------------------
1. Copy this whole folder to wherever you want it to live.
2. Right-click Install-ContextMenu.ps1 -> "Run with PowerShell"
     (or from PowerShell:  .\Install-ContextMenu.ps1 )
   This registers the menu for the CURRENT USER only, based on this folder's
   location - no administrator rights needed.
3. You now have these right-click options in File Explorer:
     * On a FILE               -> use it as the PRIMARY file (direct mode)
     * On a FOLDER             -> scan that folder for duplicates (folder mode)
     * On a FOLDER background   -> scan the current folder (folder mode)
4. To remove later:
     Right-click Uninstall-ContextMenu.ps1 -> "Run with PowerShell"
     (or:  .\Uninstall-ContextMenu.ps1 )

Install for ALL users instead of just you (optional):
     Open an elevated PowerShell (Run as Administrator), then:
        .\Install-ContextMenu.ps1 -AllUsers
     Remove with:
        .\Uninstall-ContextMenu.ps1 -AllUsers


ALTERNATIVE: STATIC .REG FILES (needs admin, fixed path)
--------------------------------------------------------
The .reg files register the menu under HKEY_CLASSES_ROOT and therefore need
administrator rights. They also contain a HARD-CODED path to the script, so if
you use them you must first edit Add_CombineDAT_Context.reg and replace
   C:\Script\Combine DAT files_v9.ps1
with the actual full path to the script in this package.

  Install:   double-click Add_CombineDAT_Context.reg   (accept the UAC prompt)
  Uninstall: double-click Remove_CombineDAT_Context.reg (accept the UAC prompt)

The PowerShell installer above is preferred because it needs no admin and no
manual path editing.


RUNNING WITHOUT THE CONTEXT MENU
--------------------------------
You can always run the script directly:

  Folder mode (auto-group duplicates):
     .\"Combine DAT files_v9.ps1"           (click "Yes", pick a folder)
     .\"Combine DAT files_v9.ps1" "C:\Data\SiteFolder"    (folder passed in)

  Manual mode (pick files yourself):
     .\"Combine DAT files_v9.ps1"           (click "No")

  Direct mode (file becomes the primary):
     .\"Combine DAT files_v9.ps1" "C:\Data\TM_Site_Diagnostics.dat"

See SCRIPT_README.txt for full details on modes, comparison windows, backups,
and optional parameters (-SpecialRowCount, -NoBackup, -Encoding).


REQUIREMENTS
------------
  * Windows (uses Windows Forms dialogs).
  * Windows PowerShell 5.1 or later (PowerShell 7 also works).

END OF README
