# Changelog

This project has no tagged releases yet, so entries are grouped by date.

## 2026-11-06

### Added
- `scan-long` refuses more than 300 dpi on the ADS-1200 before it scans. The scanner rejects it for long paper.
- `scan-long` warns when a page is cut off at the scanner's maximum length.
- Arch package files that work with `makepkg`: `pkg/PKGBUILD` and `pkg/.SRCINFO`.
- The backend is registered by `/etc/sane.d/dll.d/brother5lp`, so **\[Long Paper\]** devices appear with no setup. `make install` writes the same file.
- `.gitignore` for build and `makepkg` output.

### Changed
- The hook now logs a warning when a scan area has no height to extend.
- `scan-long` now scans through the `brother5lp` backend instead of `LD_PRELOAD`.
- `scan-long` picks the source and length limit for each model, and asks for `--device` when more than one scanner is connected.
- `scan-long` refuses duplex arguments. Long paper is single-sided only.

### Removed
- `scan-long` no longer trims by content, which could cut real blank paper from the end of a document.
- The package install script that edited `/etc/sane.d/dll.conf`.

### Fixed
- The package could not build, because `makepkg`'s flags replaced the required `-fPIC` and `-shared`.
- `--as-needed` removed libusb from the libraries, so the hook could not find it at runtime. The link now keeps libusb.
- The misspelled repository URL.
- Simple Scan reported a jam on long-paper devices. It turns on Auto Document Size, which makes the driver send `AREA=ATDSKW`, and that has no height to extend. The backend now keeps the option off.
- `Black & White` and `Gray[Error Diffusion]` stopped at 14 inches with no error, whatever the paper length. The driver dropped every line past its page height. Both modes now scan the whole page.
- Long 1-bit scans on the DS-740D could cancel the whole scan, because the driver counted the scanner's "page too long" notice as a second page. The backend now skips that notice.
- The end of page log line undercounted rows.
- Simple Scan hung after a long page, receiving empty pages without end. The backend stopped reading at the start of the filler and left the driver mid-page. It now reads the filler to the end, so the driver reports an empty feeder.

### Documented
- The DS-740D should scan long paper with the Output Guide closed, so paper passes straight through. Brother rates the Output Guide for paper up to 297 mm long.

### Tested
Packaged `scan-long` on a Steam Deck with brscan5 1.7.0, one pass on each scanner with a three-sheet test scroll:

| Scanner | Length | Time |
|---|---|---|
| ADS-1200 | 33.12 in | 23 s |
| DS-740D | 33.17 in | 27 s |

Simple Scan 50.0 on the same Steam Deck, DS-740D, 300 dpi, All Pages From Feeder, one pass in each mode. Both finished without an error and every test scroll code read correctly:

| Mode | Driver mode | Saved image |
|---|---|---|
| Text | True Gray | 2550 x 9919, 4 grey levels |
| Photo | 24bit Color[Fast] | 2550 x 9935, full colour |

Mode tests on the same Steam Deck, one pass each, with the test scroll extended past the 33 inches above. Every test code on the scroll read correctly:

| Scanner | Mode | Resolution | Length |
|---|---|---|---|
| DS-740D | 24bit Color[Fast] | 300 dpi | 44.21 in |
| DS-740D | 24bit Color[Fast] | 600 dpi | 44.08 in |
| DS-740D | Black & White | 300 dpi | 44.10 in |
| DS-740D | Gray[Error Diffusion] | 300 dpi | 44.14 in |
| ADS-1200 | 24bit Color[Fast] | 300 dpi | 35.79 in |
| ADS-1200 | Black & White | 300 dpi | 35.72 in |
| ADS-1200 | Gray[Error Diffusion] | 300 dpi | 35.70 in |
| ADS-1200, through `scan-long` | Black & White | 300 dpi | 35.68 in |
| DS-740D, through `scan-long` | True Gray | 300 dpi | 35.84 in |
| DS-740D, through `scan-long` | Black & White | 300 dpi | 35.80 in |

The two 44 inch DS-740D 1-bit passes needed a gentle pull at the end. The 35.80 inch pass did not. The ADS-1200 refused 600 dpi colour before feeding, and stopped a longer scroll at exactly 36.00 inches. The `scan-long` passes used the final build. The 44 inch passes used an earlier build, which differs in log messages, the page too long check and `scan-long`.

## 2026-11-04

### Fixed
- Long scans now finish correctly on brscan5 1.7.0. The backend uses the height the scanner measured and stops at the filler rows sent after the page ends.
- A driver failure during a long scan now sends the scanner an abort, so the rollers do not keep feeding paper.

### Added
- `BR5LP_FORCE` and `BR5LP_DUMP` debug options. `BR5LP_DUMP` captures the scanned document, so do not use it on private material.

## 2026-05

### Fixed
- SANE can now load the backend, through exported `sane_brother5lp_*` aliases.
- The hook now takes effect, by loading in a fresh `dlmopen` namespace.

### Changed
- Removed the backend's main-namespace interposers. The hook mode is now seeded through the environment.

## 2026-04

### Added
- First long paper support for the Brother DS-740D and ADS-1200, using USB command patching.
- The `brother5lp` SANE backend, which needs no `LD_PRELOAD` or `patchelf`.
- First Arch package, and `README.md`.
