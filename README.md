# brscan5-longpaper

Long paper scanning for Brother DS-740D and ADS-1200 scanners on Linux.

> **Warning:** Experimental / vibe-coded. There may be bugs.
> Test with low-value documents first.

## Background

On Windows, the Brother driver supports long paper scanning — receipts, shipping labels, and other documents longer than US Letter / A4. On Linux, the `brscan5` SANE driver never sends the required protocol commands, so feeding anything longer than ~14 inches causes a false paper-jam error and aborts the scan.

This project reverse-engineers the Windows long paper USB protocol and implements it for Linux via a native SANE backend.

## Status

| Hardware | Status |
|---|---|
| Brother DS-740D | ✅ 33 in scan tested with the Arch package on brscan5 1.7.0; keep the Output Guide closed for long paper |
| Brother ADS-1200 | ✅ 33 in scan tested with the Arch package on brscan5 1.7.0; reports a 36 in maximum |

> **Long paper is single-sided only.** The scanners reject long paper with duplex, and Brother's DS-740D guide says 2-sided scanning is not available for Long Paper.
> For a two-sided document, scan it once, turn it over, and scan it again.

These results come from `scan-long`. Simple Scan 50.0 has also been tested on the DS-740D in Text and Photo modes. Other GUI apps, and any GUI app on the ADS-1200, have not been tested on brscan5 1.7.0. See the [changelog](CHANGELOG.md) for recent changes.

**Platform:** Arch Linux (and derivatives). Should work on any distro with `brscan5` and `sane` installed; only an Arch package is provided for now.

## How it works

A SANE backend (`brother5lp`) registers alongside the normal `brother5` backend. Scanning apps see the scanner as an additional device:

```
Brother DS-740D            ← original brscan5 (normal scans)
Brother DS-740D [Long Paper]  ← this project
```

Select the **\[Long Paper\]** device and the backend handles everything internally:

- Injects `PTYPE=LONGPAPER_WIDE`, `LONG=ON`, `LSMD=ON` into the USB scan commands
- Extends the scan area beyond the driver's built-in ADF cap
- Stops automatically when the paper exits the ADF — same behaviour as Windows
- Drops the filler rows the scanner sends after the page ends; blank paper in the document is kept
- Exposes up to 5000 mm br-y range to the frontend; set page height in your scanning app to control the maximum scan length

No `LD_PRELOAD`, no patching of system files, no configuration beyond selecting the device.

## Installation

### Arch Linux

Install [`brscan5`](https://aur.archlinux.org/packages/brscan5) from the AUR first, then build this package:

```bash
git clone https://github.com/ShapeShifter499/Brother-portable-scanner_long-scan
cd Brother-portable-scanner_long-scan/pkg
makepkg -si
```

The package adds `/etc/sane.d/dll.d/brother5lp`, so the **\[Long Paper\]** devices appear with no further setup. It is not on the AUR yet.

If you used `sudo make install` before, remove those files first. A `scan-long` left in `/usr/local/bin` runs instead of the packaged one.

### Manual (other distros)

```bash
git clone https://github.com/ShapeShifter499/Brother-portable-scanner_long-scan
cd Brother-portable-scanner_long-scan
make
sudo make install
```

Requires: `gcc`, `libsane-dev` (or `sane`), `libusb-1.0-dev`.

## Usage

### GUI (Simple Scan, XSane, gscan2pdf, GIMP)

1. Open your scanning app
2. Select **Brother DS-740D \[Long Paper\]** (or equivalent) as the device
3. Set page height to the maximum you want to scan (e.g. 1000 mm for a long receipt)
4. Feed the document. Scanning stops automatically when the paper exits
5. Support long paper on both sides, and keep it clear of the scanner's entry

On the DS-740D, keep the **Output Guide** closed so paper passes straight through. Opening it sends paper around a U-bend and out of the top. Brother rates that route for paper up to 297 mm long, and lists an open Output Guide as a cause of skewed scans and jams.

Choose a single-sided source. The duplex sources do not work with long paper.

Long-paper devices keep Brother's Auto Document Size option off, because it cannot work with a page of unknown length. Your scanning app may turn it on, and the backend turns it back off.

In Simple Scan, Text mode saves only 4 shades of grey. Use Photo mode to keep full detail.

Long scans can end with up to about 1.4 mm of grey at the bottom, where the driver's filler begins. It is left in place, so that real content is never trimmed.

### CLI

```bash
scan-long --output receipt.png
```

Single-sided only. Options:

```
--output FILE       Output file (default: scan_YYYYMMDD_HHMMSS.png)
--resolution DPI    Scan resolution (default: 300)
--length MM         Maximum length (default: the scanner's reported maximum)
--device DEVICE     Needed when more than one scanner is connected
```

## Building from source

```bash
make          # builds libbr5longpaper.so and libsane-brother5lp.so.1
sudo make install  # installs under /usr/local and registers the backend in /etc/sane.d/dll.d
```

## Troubleshooting

Run with `BROTHER_SCAN_DEBUG=1` to see USB command logs on stderr. Key lines to look for:

```
[brother5lp] promoted to RTLD_GLOBAL          ← hooks active
[brother5lp] loaded brscan5 via dlopen        ← brscan5 wrapped
[brother5lp] USB patch SSP: LONGPAPER_WIDE    ← protocol patched
[brother5lp] DeviceImageJpeg::SetHeight ...   ← height cap bypassed
[brother5lp] BitmapImage::AppendWhiteLines suppressed  ← no blank rows
```

If `promoted to RTLD_GLOBAL` is missing, the USB and C++ hooks will not fire.

## Contributing

Testing reports are very welcome, especially from GUI apps. Open an issue with the debug log output and a description of what did or didn't work.

## License

GPLv2. See [LICENSE](LICENSE).
