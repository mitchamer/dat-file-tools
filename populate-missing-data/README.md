# Populate Missing Data

Fills the gaps in one TOA5 file (the **target**) with readings from another
TOA5 file (the **source**) that logged the same measurements at the same times.

The usual case: a CR6 table polls a DT2485/DT85 over Modbus, the Modbus reads
drop out, and the table fills with `NAN` — while the DT2485's own download has
the readings. Right-click the CR6 file, pick the DT2485 file, approve the column
mapping, done.

Windows PowerShell 5.1+ (7 works). Windows only (the file picker and approval
window use Windows Forms; `-Unattended` skips them).

## ⚠ Use at your own risk

**This rewrites the target file in place.** Provided "as is" with no warranty —
see [LICENSE](../LICENSE) sections 15–17.

- the original is copied into `Backup\` first, unless `-NoBackup`
- **only missing fields change** — `NAN` (any case, quoted or not) or empty.
  Header rows, row order, every existing value, quoting, line endings and the
  byte-order mark are preserved
- **rows are never added, removed or sorted.** A source timestamp the target
  does not have is counted in the report, not inserted
- the source file is only read
- you see the column mapping and the counts and must click **Fill gaps** before
  anything is written. `-DryRun` shows the same and writes nothing
- every real run writes `Backup\<name>_<time>.populate-log.txt` with the mapping
  and the counts

## How columns are matched

The two files rarely share column names (`DT85-1_Ch-1` in one, `Axis A 1` in
the other), so a name alone is not trusted and is not required. Every mapping
has to be backed up by the rows **both** files already have readings for:

| Rule | When it applies |
|---|---|
| **Name** | A source column with the same name (case-insensitive) — unless the shared rows show its values disagree, which refuses the column |
| **Values** | Each target column is compared with every source column on the shared timestamps. A source column qualifies when at least 95% (`-MinAgreement`) of at least 20 (`-MinOverlap`) shared readings agree. The best qualifier wins |
| **Between** | A column whose values barely change (a temperature reading `5.5` for five years) proves nothing by its values — `0` matches every other `0`. It is mapped only when it sits **between two proven columns** that keep the same column spacing in the source, and the column that spacing points to agrees on the shared rows |
| **Edge** | The same for a constant column at the very **end** of the table — typically the last sensor's temperature — or the start, which has proven columns on one side only. The **two columns immediately next to it** must both be proven and keep their spacing in the source, and the column one further along must agree on the shared rows. It reaches exactly one column past them (an edge column is not itself proof), so it never walks on into the logger's own columns such as `RESET` or `USB` |

Two readings **agree** when `|target − source| ≤ 0.00001 + 0.2% of |target|`.
That absorbs rounding between loggers (`5.4375` vs `5.435`); two different
inclinometer axes still differ by orders of magnitude more.

**Choosing between qualifiers.** Higher agreement wins. Rates within half a
percent are a tie, and a tie goes to the column with the smaller average
difference, so a full-precision copy of a reading (`5.435000`) beats a rounded
one (`5.43`). If a runner-up nearly as good **disagrees** with the winner, the
column is **ambiguous** and left alone. Qualifiers that agree with each other
are the same reading logged twice. That is not a conflict: the others are kept
as fall-backs and are used, in order, wherever the chosen column has no usable
value.

`RECORD` and the timestamp are never filled — a record number belongs to the
logger that wrote it. Any target column none of the rules settles is listed in
the report with the reason, and its gaps stay as they are.

## Values never copied

| Not copied | Why |
|---|---|
| `NAN` or empty in the source | there is nothing to copy |
| `0.999998`, `-0.999998` (`-SkipSourceValues`) | the DT2485 sensor-error reading. It looks like a number, so it has to be named |
| any magnitude of 1e9 or more | the `2147483647` / `2.147484E+09` family of "no reading" codes |
| a value far outside the **target** column's own readings | matching proves two columns are the same measurement, not that every source value is a reading. Loggers write `163` for a temperature that never leaves 5–6, `0` for a failed axis read, or `-7.2E+08` when a Modbus read fails — all below the 1e9 cut-off. The limit is the column's 1st–99th percentile widened by that spread again on each side (at least 10% of the value), so seasonal swings and slow drift pass and the few error codes already in a column cannot stretch it |
| a timestamp the source holds twice with **different** values in that column | there is no telling which is right (the same value twice is fine) |

## Before you run it

- **Both files must be TOA5**, with timestamps as `YYYY-MM-DD HH:MM:SS`. Run
  [Fix Timestamps](../fix-timestamps/) first if they are not. A file with no
  timestamps in common with the other is refused and nothing is written.
- A DT2485's own download is not TOA5 — it has a 26-row DT2485 header. Convert
  it first with [CSV to TOA5](../csv-to-toa5/) (right-click → **Convert to TOA5**).

## How to run it

### Right-click

Run `Install-ContextMenu.ps1` at the top of the repo (every tool, per-user, no
admin), or this folder's own `Install-ContextMenu.ps1` for just this tool.

Two entries appear on `.dat` and `.csv` files. On Windows 11 they are under
**Show more options**.

- **Populate Missing Data** — asks for the source file, shows the mapping,
  fills on approval
- **Check Populate Missing Data (no changes)** — the same with `-DryRun`

Right-click the file **with the gaps**. `.\Uninstall-ContextMenu.ps1` removes the
entries.

### Terminal

```powershell
.\Populate-MissingData.ps1 'C:\Data\Site.dat' 'C:\Data\DT2485_TOA5.dat' -DryRun
.\Populate-MissingData.ps1 'C:\Data\Site.dat' 'C:\Data\DT2485_TOA5.dat'
.\Populate-MissingData.ps1 'C:\Data\Site.dat'          # file picker for the source
```

## Options

| Option | Effect |
|---|---|
| `-Source <file>` | The file to fill from (position 1). A picker opens if it is not given |
| `-DryRun` | Report the mapping and counts, write nothing |
| `-NoBackup` | Skip the copy into `Backup\`. Removes the only automatic undo |
| `-Encoding <Auto\|UTF8\|UTF8BOM\|ASCII\|Unicode>` | Default `Auto` — writes the file back with the byte-order mark it arrived with |
| `-MinAgreement <0.5–1>` | Share of shared readings that must agree for a column to match. Default `0.95` |
| `-MinOverlap <int>` | Shared readings needed before values can prove a match. Default `20` |
| `-SkipSourceValues <string[]>` | Source values never copied. Default `0.999998`, `-0.999998` |
| `-Unattended` | No picker, no approval, no summary box. Requires `-Source`. For scripted runs |

## Tests

```powershell
.\test_populate.ps1
```

42 checks: matching by values with different names and order, by name, the
Between rule and its limit, the Edge rule at the end and start of a table and
its one-column reach, constant columns not taken as proof, ambiguity,
full precision preferred and the fall-back copy used, every value that is never
copied (including out-of-range readings), repeated source timestamps, refusals, round-trip fidelity (BOM, LF,
quoting), and the script end to end (`-DryRun` writes nothing; a real run backs
up, logs and fills). It loads the script's functions through the AST and opens
no dialogs, so it runs unattended.
