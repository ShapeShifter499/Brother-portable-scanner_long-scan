#!/usr/bin/env bash
# scan-long: scan a long page through the [Long Paper] SANE backend.
#
# SINGLE-SIDED ONLY. The scanners reject long paper with duplex. To scan a
# two-sided document, scan it once, turn it over, and scan it again.
#
# Usage:
#   scan-long [--resolution DPI] [--mode MODE] [--length MM]
#             [--device DEVICE] [--output FILE]
#
# Examples:
#   scan-long                                # 300 dpi, scanner found automatically
#   scan-long --resolution 200 --output receipt.png
#   scan-long --device 'brother5lp:bus1;dev4'
#
# The scan ends when the paper leaves the feeder. --length is only a ceiling.
#
# Reported limits for long paper:
#   DS-740D:  72 inches (1829 mm), tested at up to 600 dpi
#   ADS-1200: 36 inches (914 mm), up to 300 dpi
#
# A page longer than the limit is cut off at the limit. scan-long warns when this
# happens.
#
# On the DS-740D, "Black & White" and "Gray[Error Diffusion]" can stop feeding just
# before a long page clears the rollers. Nothing is lost. Pull the page out gently.
#
# Support long paper on both sides as it feeds, and keep it clear of the
# scanner's entry. Press the scanner's button to stop a feed.
#
# Requirements: brscan5, scanimage, and 'brother5lp' enabled in SANE.

set -euo pipefail

# ── Check prerequisites ──────────────────────────────────────────
command -v scanimage >/dev/null 2>&1 || {
    echo "ERROR: 'scanimage' not found. Install sane-utils or sane-backends." >&2
    exit 1
}

# ── Defaults ─────────────────────────────────────────────────────
RESOLUTION="300"
COLOR_MODE="24bit Color[Fast]"
LENGTH_MM=""               # ceiling only: the scan stops when the paper exits
DEVICE=""                  # auto-detect if empty
OUTPUT_FILE="scan_$(date +%Y%m%d_%H%M%S).png"
EXTRA_ARGS=()

# ── Parse arguments ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resolution|-r) RESOLUTION="$2"; shift 2 ;;
        --mode|-m)       COLOR_MODE="$2"; shift 2 ;;
        --length|-l)     LENGTH_MM="$2"; shift 2 ;;
        --device|-d)     DEVICE="$2"; shift 2 ;;
        --output|-o)     OUTPUT_FILE="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,31p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *)
            EXTRA_ARGS+=("$1"); shift ;;
    esac
done

if [[ "${EXTRA_ARGS[*]:-}" == *[Dd]uplex* ]]; then
    echo "ERROR: long paper is single-sided. Scan each side in its own pass." >&2
    exit 1
fi

# ── Determine the scanner device string ──────────────────────────
# Only [Long Paper] devices count, so a plain brother5 device is never used.
LISTING=$(scanimage -L 2>/dev/null | grep 'brother5lp:' || true)
if [[ -z "${DEVICE}" ]]; then
    COUNT=$(printf '%s' "${LISTING}" | grep -c . || true)
    if [[ "${COUNT}" -eq 0 ]]; then
        echo "ERROR: no [Long Paper] scanner found." >&2
        echo "  Is the scanner plugged in and awake?" >&2
        echo "  Is the backend enabled? It needs /etc/sane.d/dll.d/brother5lp" >&2
        exit 1
    fi
    if [[ "${COUNT}" -gt 1 ]]; then
        echo "ERROR: more than one scanner found. Choose one with --device:" >&2
        printf '%s\n' "${LISTING}" >&2
        exit 1
    fi
    DEVICE=$(printf '%s' "${LISTING}" | grep -oE "brother5lp:[^']+")
fi
MODEL_LINE=$(printf '%s\n' "${LISTING}" | grep -F "${DEVICE}" || true)

# The ADS-1200 feeds centred and the DS-740D feeds to the left.
if [[ "${MODEL_LINE}" == *ADS-* ]]; then
    SOURCE="Automatic Document Feeder(center aligned)"
    MAX_MM=914
    if (( RESOLUTION > 300 )); then
        echo "ERROR: the ADS-1200 scans long paper at up to 300 dpi." >&2
        exit 1
    fi
else
    SOURCE="Automatic Document Feeder(left aligned)"
    MAX_MM=1829
fi
[[ -n "${LENGTH_MM}" ]] || LENGTH_MM="${MAX_MM}"

# ── Build scanimage arguments ─────────────────────────────────────
# Long pages have an unknown height until the paper exits, which PNG output
# cannot handle, so scan to a temporary PNM and convert afterwards.
PNM_TMP="${OUTPUT_FILE%.*}_tmp$$.pnm"

SCAN_ARGS=(
    --device  "${DEVICE}"
    --resolution "${RESOLUTION}"
    --mode    "${COLOR_MODE}"
    --format  pnm
    -o        "${PNM_TMP}"
)
SCAN_ARGS+=(--source "${SOURCE}" -l 0 -t 0 -x 215.88 -y "${LENGTH_MM}")

[[ ${#EXTRA_ARGS[@]} -gt 0 ]] && SCAN_ARGS+=("${EXTRA_ARGS[@]}")

# ── Run ──────────────────────────────────────────────────────────
echo ""
echo "Scanning in LONG PAPER mode (single-sided)"
echo "  Device:     ${DEVICE}"
echo "  Resolution: ${RESOLUTION} DPI"
echo "  Mode:       ${COLOR_MODE}"
echo "  Max length: ${LENGTH_MM} mm (scan auto-stops when paper exits ADF)"
echo "  Output:     ${OUTPUT_FILE}"
echo ""

SCAN_LOG=$(mktemp)
trap 'rm -f "${SCAN_LOG}"' EXIT
scanimage "${SCAN_ARGS[@]}" 2>&1 | tee "${SCAN_LOG}"

if [[ ! -f "${PNM_TMP}" ]]; then
    echo "ERROR: scan produced no output file." >&2
    exit 1
fi

# ── Convert PNM → requested format ───────────────────────────────
# Nothing is trimmed here. The backend stops at the end of the page, and trimming
# by content would cut real blank paper from the bottom of a document.
do_convert() {
    if command -v magick >/dev/null 2>&1; then
        magick "$1" "$2"
    else
        convert "$1" "$2"
    fi
}

if [[ "${OUTPUT_FILE}" == *.pnm || "${OUTPUT_FILE}" == *.ppm ]]; then
    mv "${PNM_TMP}" "${OUTPUT_FILE}"
elif command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    echo "Converting to ${OUTPUT_FILE}..."
    do_convert "${PNM_TMP}" "${OUTPUT_FILE}"
    rm -f "${PNM_TMP}"
else
    # No converter available — keep the PNM
    PNM_FINAL="${OUTPUT_FILE%.*}.pnm"
    mv "${PNM_TMP}" "${PNM_FINAL}"
    echo "NOTE: ImageMagick not found; output kept as ${PNM_FINAL}" >&2
    echo "      Install ImageMagick to auto-convert:  sudo pacman -S imagemagick" >&2
    OUTPUT_FILE="${PNM_FINAL}"
fi

echo ""
echo "Scan complete: ${OUTPUT_FILE}"
if grep -q "reached its maximum length" "${SCAN_LOG}"; then
    echo "WARNING: the page is longer than this scanner's limit. Its end is missing." >&2
fi

# Report actual scanned dimensions
if command -v identify >/dev/null 2>&1; then
    PX_H=$(identify -ping -format "%h" "${OUTPUT_FILE}" 2>/dev/null)
    PX_W=$(identify -ping -format "%w" "${OUTPUT_FILE}" 2>/dev/null)
    if [[ -n "${PX_H}" && -n "${PX_W}" ]]; then
        MM_H=$(awk -v h="${PX_H}" -v r="${RESOLUTION}" 'BEGIN { printf "%.1f", h / r * 25.4 }')
        IN_H=$(awk -v h="${PX_H}" -v r="${RESOLUTION}" 'BEGIN { printf "%.2f", h / r }')
        echo "Image dimensions: ${PX_W}×${PX_H} px"
        echo "Scanned length:  ${MM_H} mm (${IN_H} inches) at ${RESOLUTION} DPI"
    fi
fi
