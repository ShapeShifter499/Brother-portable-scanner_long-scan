# Brother ADS/DS Scanner Protocol Notes

Reverse-engineered from `brscan5-1.5.1-0` package libraries.

## USB Identification

| Field      | Value                          |
|------------|-------------------------------|
| Vendor ID  | `0x04f9` (Brother Industries) |
| Interface  | Class `0xFF`, SubClass `0xFF`, Protocol `0xFF` (vendor-specific) |
| Transfer   | USB bulk (`libusb_bulk_transfer`) |

### Known Product IDs (from `brscan5ext_*.ini`)

| Model      | PID    | Capability type |
|------------|--------|-----------------|
| ADS-1200   | 0x0459 | 315             |
| ADS-1250W  | 0x045a | 315             |
| ADS-1700W  | 0x045b | 315             |
| ADS-2400N  | 0x03b7 | 315             |
| ADS-2800W  | 0x03b9 | 315             |
| ADS-3000N  | 0x03b8 | 319             |
| ADS-3600W  | 0x03ba | 319             |
| DS-740D    | 0x0469 | ??? (in encrypted ini) |

The DS-740D is shipped in the same `brscan5-1.5.1-0` package as the ADS-1200
(same download IDs `dlf104033_000` / `dlf104034_000`), but its entry is in one
of the XOR-obfuscated `brscan5ext_*.ini` files (files 3–26 are obfuscated).

The XOR key for those files has not been fully recovered. The user must run
`lsusb | grep 04f9` with the DS-740D connected to determine its PID.

## brscan5 File Layout (after `dpkg -x brscan5-*.deb /opt/...`)

```
/opt/brother/scanner/brscan5/
├── brsaneconfig5               # CLI scanner registration tool
├── brscan5.ini                 # Main config
├── models/brscan5ext_*.ini     # Model capability tables
│   0,1,2: plaintext (ADS models)
│   3–26:  XOR-obfuscated
├── libsane-brother5.so.1.0.7   # SANE backend (loads core API)
├── libLxBsScanCoreApi.so.3.2.1 # Core scanning API
├── libLxBsUsbDevAccs.so.1.0.0  # USB device access layer
├── libLxBsNetDevAccs.so.1.0.0  # Network device access layer
└── libLxBsDeviceAccs.so.1.0.0  # Generic device access
```

## Scan Command Protocol (QDI text format)

Commands are sent as plain-text key=value pairs over USB bulk transfers.
Multiple commands types exist (CKD, ABT, XSC, SSP).

### Command Keys (extracted from `libLxBsScanCoreApi.so.3.2.1`)

**Group 1 — scan setup (CKD command)**
| Key    | Known values                                          | Notes                     |
|--------|-------------------------------------------------------|---------------------------|
| OS=    | `LNX`, `WIN`, `MAC`, `IOS`, `ADR`, `WPH`             | Operating system          |
| PSRC=  | (paper source values)                                 | Paper source / ADF type   |
| CLR=   | `C24BIT`, (others)                                    | Color mode                |
| AREA=  | `NORMAL`, `FULL`, `OVER`, `ATDSKW`                    | Area detection mode       |
| DPLX=  | `OFF`, (duplex values)                                 | Duplex mode               |
| COMP=  | `JSF`, `422`, `411`, `420`, `400`, `444`              | Compression               |
| IPRC=  | `COPY`, `TXTGR`                                       | Image processing          |
| PTYPE= | `THIN`, `THOCK`, `PCARD`, **`LONGPAPER_WIDE`**, **`LONGPAPER_NARROW`**, `DEVICEMAX`, `CUSTOMSIZE` | Paper type |
| LONG=  | **`ON`** (assumed; function takes bool)               | Long paper enable flag    |
| CARR=  |                                                       | Carrier sheet mode        |
| DSKW=  |                                                       | Deskew                    |
| LSMD=  |                                                       | Long scan mode detect     |

**Group 2 — resolution and processing (ABT/XSC command)**
| Key    | Notes                  |
|--------|------------------------|
| RESO=  | Resolution (DPI)       |
| GMMA=  | Gamma                  |
| RMBP=  | Remove blank pages     |
| DTDF=  | Double-feed detection  |
| RMGC=  | Remove gray channel    |
| PAGE=  | Page count             |
| BRIT=  | Brightness             |
| MRGN=  | Margin                 |

### Long Paper Values (from `libLxBsScanCoreApi.so` string table)

```
PTYPE=LONGPAPER_WIDE    # Wide long paper (A4/letter width ≈ 210–216mm)
PTYPE=LONGPAPER_NARROW  # Narrow long paper (receipt/ticket width)
LONG=ON                  # Enable long paper scan flag
```

The `LONGPAPER_WIDE` / `LONGPAPER_NARROW` identifiers come directly from the
internal `PAPERTYPEENUM` string table in the core library. The full enum is:

```
..., MEXICANLEGAL, INDIALEGAL, LONGPAPER_NARROW, LONGPAPER_WIDE,
DEVICEMAX, CUSTOMSIZE, PAPERTYPENUM
```

### Long Paper Functions in `libLxBsScanCoreApi.so`

```cpp
CAdjustScanSetting::ConvertUserSetting_LongPaper(
    const BS_SCANNER_PARAMETERS&, const BS_SCANNER_CAPABILITY&)

CCmdString_v2::MakeLongPaperModeString(bool)   // generates LONG= token
ScanCapability::GetLongPaperSupport(...)
ScanCapability::GetLongPaperMaxLength(...)
CReadPreparation_base::ChangeLongPaperIfNeededERNS(...)
CDeviceCapsForPreparation::GetLongPaperLengthMax()
CScanArea::GetLongPaperSizePixel(...)
```

## SANE Backend Constraints

`libsane-brother5.so` reads max ADF height from scanner capabilities in
0.01mm units and exposes it via the `br-y` SANE option range.
For ADS-1200 the reported max is approximately 291–355mm (non-long-paper mode).

The `libsane-brother5.so` exposes these scan-related SANE options:
- `mode` — color mode (Color, Grayscale, etc.)
- `resolution` — DPI
- `source` — paper source: `"Automatic Document Feeder(center aligned)"`, etc.
- `brightness`, `contrast`
- `tl-x`, `tl-y`, `br-x`, `br-y` — scan area
- `AutoDocumentSize` / `Auto Document Size`
- `Paper size detection`

There is **no** native SANE option for long paper mode in the current backend.

## What the Hook Does

`libbr5longpaper.so` intercepts two points:

1. **`sane_get_option_descriptor()`** — when `br-y` is queried, returns an
   extended range with `max = 5000mm` instead of the backend's default.

2. **`libusb_bulk_transfer()`** — when an outgoing bulk transfer contains scan
   parameters (`RESO=`, `CLR=`, `PTYPE=`), replaces/inserts:
   ```
   PTYPE=LONGPAPER_WIDE   (or LONGPAPER_NARROW)
   LONG=ON
   ```

## DS-740D PID Discovery

Run with the DS-740D connected:
```bash
lsusb | grep "04f9"
```
Example output:
```
Bus 001 Device 005: ID 04f9:04ab Brother Industries, Ltd DS-740D
```
PID here is `0x04ab`. Register it:
```bash
sudo brsaneconfig5 -a name=DS-740D model=DS-740D usb=0x04f9:0x04AB
```

## Open Questions (need hardware testing)

1. Does `LONG=` really take `ON`/`OFF`?  
   (`MakeLongPaperModeString(bool)` implies yes, but the exact string isn't
   stored as a literal in the binary — it's built at runtime.)

2. Does setting `br-y` above the reported max (before our hook extends it)
   already trigger `ChangeLongPaperIfNeeded` internally in brscan5?
   If yes, only the range extension in step 1 of the hook is needed.

3. What is the DS-740D's USB PID?

4. Does `AREA=FULL` need to accompany long paper, or is `AREA=NORMAL` + 
   `PTYPE=LONGPAPER_WIDE` sufficient?

5. What are the capability-type differences between `315` (ADS-1200) and
   `319` (ADS-3600W)?  Type `319` has extra ini fields `130,2`.

## Testing Procedure

```bash
# 1. Build the hook
make

# 2. Confirm scanner is detected (without hook)
scanimage -L

# 3. Check the br-y range reported without hook
scanimage --device 'brother5:...' --help 2>&1 | grep 'br-y'

# 4. Check br-y range with hook applied (should show 5000mm max)
BROTHER_LONG_MODE=WIDE LD_PRELOAD=./libbr5longpaper.so \
    scanimage --device 'brother5:...' --help 2>&1 | grep 'br-y'

# 5. Attempt a long scan (feed a long document through the ADF)
./scan_long.sh --length 1000 --output long_test.tiff

# 6. Verify output dimensions
identify long_test.tiff | grep 'x[0-9]'
```

## Hardware results (2026-11-04, brscan5 1.7.0)

Tested with a 33 inch taped, two-sided test scroll carrying QR markers.

| Scanner | One-sided long | Reported long max | Feed path |
|---|---|---|---|
| DS-740D | 33.5 in, clean; sheet swing up to about 2.7 degrees on one side | 1828.8 mm | Straight with the Output Guide closed, U-bend with it open |
| ADS-1200 | 33.0 to 33.1 in, clean, 9 s per side | 914.4 mm, then values 300,300 | Mostly straight |

The stock driver stops the same page with "Document feeder jammed".

### Capability reply (QDI)

Binary tag, length, value records, 0.1 mm units. Tag `0x0306` holds the long-paper
maximum as a 32-bit value. On the ADS-1200 two 16-bit values of 300 follow it, probably
a long-paper resolution cap. The DS-740D has zeros there. This is inferred from
reading the bytes, not documented.

### Page height

Short pages: `DeviceImageJpeg::SetHeight` gets the scanner's measured height.
Long pages: it gets the driver's cap (4200 at 300 dpi), and the driver pads the
output with rows of exactly 128 up to a fixed line count. The backend reports the
measured height when it has one, and otherwise stops at the first filler row.

The "Corrupt JPEG data" warning comes from the scanner's padded height in the JPEG
header (16959 rows) with the stream ending early. Images are complete.

### Duplex

`LONGPAPER_WIDE` with `DPLX=ON` is rejected at SSP, with an 8-byte reply starting
0x83, before any paper moves.

`BR5LP_FORCE=area` leaves SSP untouched and only raises the XSC area. The scanner
then scans both sides in one pass, but the driver hangs decoding, so the data has to
be captured with `BR5LP_DUMP`. The stream is 14-byte block headers (byte 2 is the side,
bytes 6-9 the block size) followed by one JPEG per side.

**Do not use this on real documents.** All of side 1 arrives before side 2, so the
scanner has to hold side 2 in its own memory. On the ADS-1200 the bottom of side 2 came
back corrupted even though every declared byte arrived and the scan reported success.
A memory overflow is the likely cause, but that is unproven. Scan each side in its
own pass.

### Feeding

Long paper needs a clear exit and support on both sides. The DS-740D takes a U-bend
when its Output Guide is open, and the exiting end can then meet the entering end
and fold the page. Keep the Output Guide closed so paper passes straight through.

Brother's Online User's Guide for the DS-640, DS-740D and DS-940DW gives these limits
for the DS-740D:

| Mode | Maximum document length |
|---|---|
| Single-sided | 1828.8 mm |
| 2-sided | 406.48 mm |
| Output Guide open | 297 mm |

The guide also says 2-sided scanning is not available for Long Paper. It lists both
the Long Paper setting and an open Output Guide as causes of skewed images.

## Capabilities reported by QDI

The QDI reply is a list of entries: a 16-bit tag, a 16-bit length, then the value,
all little-endian. The labels below come from the log strings in
`libLxBsScanCoreApi.so.3.2.6`.

Tag `0x0306` describes long paper. Lengths are in units of 0.1 mm:

| Field | DS-740D | ADS-1200 |
|---|---|---|
| `longPaperSizeSimplexMax` | 18288 | 9144 |
| `longPaperSizeDuplexMax` | 0 | 0 |
| `longPaperSimplexLengthSpecificationMethod` | 2 | 2 |
| `longPaperDuplexLengthSpecificationMethod` | 0 | 0 |
| `longPaperMaxResolutionX`, `Y` | 0, 0 | 300, 300 |

A 0 limit on the DS-740D did not stop a 600 dpi colour scan. The ADS-1200 refused
600 dpi at SSP with result code 0x83, before feeding.

Tag `0x050a` is `autoDocumentSize` and tag `0x050b` is `deskew`. Each holds a
capability byte, an interlocking byte and an X and Y resolution limit. Both scanners
report a 300 x 300 limit for each.

## Auto Document Size and deskew

`AutoDocumentSize` makes the driver send `AREA=ATDSKW` in place of a numeric area, so
the hook has no height to extend. Where the correction happens is not proven. The
scanners report it as a capability, the driver has a status message for a deskew
failure, and the DS-740D lists `deskewByDevice` in its carrier sheet exclusions. It
reports corner detection as unsupported, although `libLxBsScanCoreApi` contains
rotation and paper corner code. Long scans send `AREA=NORMAL`, `DSKW=OFF` and
`ATCRP=OFF`.

## End of a long page

brscan5 pads a long page with filler rows up to its full height. A frontend that scans
a whole feeder calls `sane_start` again after each page. If the page was not read to
the driver's EOF, that call succeeds without any USB traffic and returns filler as a
new page. Once the page is read to EOF, `sane_start` still succeeds, then `sane_read`
returns `SANE_STATUS_NO_DOCS`. Simple Scan accepts that as the end of the document.

The last rows of a page can be mixed with filler by JPEG compression, so they are not
exactly 128 and are not detected as filler. They appear as up to about 1.4 mm of grey.

## JPEG and line data

Colour and True Gray use JPEG. `Black & White` and `Gray[Error Diffusion]` arrive as
lines, and the SSP command has no `COMP=JPEG`.

A JPEG's height is in its own header: 22200 at 300 dpi and 44400 at 600 dpi on the
DS-740D. The last block header holds the height the scanner measured, such as 26436
for the 44 inch scroll at 600 dpi.

For line data, `CReadThread_v2::WriteDataBlockToImageDataArray` drops each line past
the page height when the paper type is fixed and `IsNormalAreaType()` is true. The
hook answers false for line data. That also makes the driver call
`DecodeParameter::SetSelectedArea` with the same height, and `ScanDecoder` keeps only
the rows inside that area, so the hook skips that call. A receipt-width crop is not
applied to line data as a result.

## Hook lookups

brscan5 loads after the hook library, outside the scope `RTLD_NEXT` searches, so
`dlsym(RTLD_NEXT, ...)` returns NULL for functions in `libLxBsScanCoreApi`. The calls
to the real `SetHeight` functions are therefore skipped, and the 65536 in the log is
not applied. Those hooks work by keeping the driver's cap out. Use `core_symbol()` for
a function that must really be called.

## Page too long

The scanner reports status `0x23`, `00 23 NN 00`, in two situations:

| Scanner | Seen after | Meaning |
|---|---|---|
| DS-740D, 1-bit modes, 44 inch page | `00 21 NN 00`, page end | The page is complete. The driver counts this as a second page and cancels the scan, so the hook skips it. The feed stops just before the paper clears the rollers. |
| ADS-1200, page over 36 inches | Line data, with no page end | The scanner stopped at its limit. The end of the page is missing, and the driver reports a normal finish. The hook logs a warning. |

The DS-740D did not send it for colour at 44 inches, or for `Black & White` at 35.8
inches, so in 1-bit modes it starts somewhere between 35.8 and 44 inches.

## Driver debug log

`libLxBsScanCoreApi` writes text logs when `$HOME/BrOutLog/BrSetupLog.txt` exists.
Each line is `Key=Value`, for example `LogLevel=5`. Do not enable the `Dump` keys on
private material, because they save image data.

Both scanners listed under the same SANE name when they shared a USB bus. On
separate buses the names differ.
