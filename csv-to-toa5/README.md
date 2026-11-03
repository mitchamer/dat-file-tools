# CSV to TOA5

Converts a logger's own CSV download into a Campbell Scientific **TOA5** file,
so the other tools here can read it. It was built for **DT2485 IPI logger**
downloads, which carry a 26-row header of metadata, sensor settings and units
and are not TOA5.

The source is **never changed**. The result is written beside it as
`<name>_TOA5.dat`.

Windows PowerShell 5.1+ (7 works).

## ⚠ Use at your own risk

Provided "as is" with no warranty — see [LICENSE](../LICENSE) sections 15–17.
Check the summary it shows, especially any renamed columns, before relying on
the output.

## What it does

| Part | Result |
|---|---|
| **Header** | The 4 TOA5 rows. Row 1 is `"TOA5", station, model, serial, firmware, "", "", table`, taken from the download's `Name`, `Model`, `Serial Number` and `Firmware Version` rows. The table is the last word of the station name. Without those rows, the file name is used |
| **Names** | From the download's name row. The first column is always `TIMESTAMP` |
| **Units** | From the `UNITS->` row. `TS` for the timestamp, `RN` for `RECORD` |
| **Processing** | `""` for `TIMESTAMP` and `RECORD`, `Smp` for the rest |
| **Timestamps** | `"YYYY-MM-DD HH:MM:SS"`. Single-digit months and days, missing seconds and AM/PM are all normalised |
| **Values** | Copied exactly. Numbers stay bare; `NAN` and text are quoted. A leading-zero code such as the DT2485 `STATUS 0x` value `012` stays `"012"`, not `12` |
| **Rows** | Every one, in the order the logger wrote it. Nothing is sorted, dropped or de-duplicated. If the logger's clock stepped back, the output steps back too |

## Columns

- **Separator columns** — no name, and empty in every row — are dropped, as is
  the DT2485 `Serial (MB Addr)` label column. The summary lists them.
- **The DT2485 full-precision block.** A DT2485 repeats every sensor reading at
  full precision in a second block whose columns are all named after the
  sensor's serial (`"83199 (1)"` three times). These become
  `<reading> SN<serial>`, e.g. `Axis A 1 SN83199`, `Axis B 1 SN83199`,
  `Temp 1 SN83199`. The download's `Serial` row says which reading is which.
- **Mislabelled sensors.** Some DT2485 downloads give one sensor another
  sensor's number. For example, a DH19-02 download labels the sensors at
  Modbus addresses 7 and 8 as `39` and `40`, while the real sensors 39 and 40
  carry the same names. When a name is **repeated** and its number disagrees
  with the `MB Addr` row, it is renamed from the address (`Axis A 39` →
  `Axis A 7`). Every rename is listed in the summary.
- **Any other repeated name** gets `_2`, `_3`, … so every TOA5 name is unique.

## What it refuses

Nothing is written when:

| Refused | Why |
|---|---|
| **Year-last dates** (`10/08/2021`) | Month-first or day-first, and the file has to say which. Run [Fix Timestamps](../fix-timestamps/) on it first |
| **Any row whose first field is not a real date and time** | One bad row refuses the file. A part-converted file is worse than none |
| **A row with a different number of fields from the name row** | Its values would land under the wrong names |
| **No column-name row** | Needs a row whose first field is `TIMESTAMP`, `Date/Time`, `DateTime`, `Date` or `Time`, above the data |
| **A file that is already TOA5** | Nothing to do |

An existing `<name>_TOA5.dat` is not overwritten unless you answer **Yes** to the
prompt, or pass `-Force` from the terminal.

## How to run it

### Right-click

```powershell
.\Install-ContextMenu.ps1          # per-user, no admin
```

**Convert to TOA5** appears on `.csv`, `.dat` and `.txt` files. On Windows 11
it is under **Show more options**. `.\Uninstall-ContextMenu.ps1` removes it.

### Terminal

```powershell
.\CSV-to-TOA5.ps1 'C:\Data\DT2485_DT50583_20261008_103345_DH11-29.csv'
.\CSV-to-TOA5.ps1 'C:\Data\download.csv' -OutputPath 'C:\Data\Site.dat'
```

| Option | Effect |
|---|---|
| `-OutputPath <file>` | Where to write. Default `<name>_TOA5.dat` beside the source |
| `-Force` | Overwrite an existing output file |
| `-Unattended` | No dialogs. An existing output is left alone unless `-Force` |

## Then what

A converted DT2485 download is the **source** for
[Populate Missing Data](../populate-missing-data/): right-click the CR6 file with
the gaps, and pick the `_TOA5.dat` to fill from.

## Tests

```powershell
.\test_csv_to_toa5.ps1
```

34 checks:

- a DT2485-style download: the header, the dropped separators, the mislabelled
  sensor renamed from its address, the second-block names, units, values,
  `NAN`, status codes
- a plain CSV
- every refusal
- the script end to end: output name, no BOM, CRLF, source untouched, no
  overwrite without `-Force`

On the real DH11-29 download, the output is byte-identical to a conversion
checked field by field against the source.
