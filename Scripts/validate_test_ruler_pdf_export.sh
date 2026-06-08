#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FREEPRINTSTUDIO_PDF_CONTENT=testRuler \
FREEPRINTSTUDIO_PAPER=letter \
FREEPRINTSTUDIO_ORIENTATION=portrait \
FREEPRINTSTUDIO_UNIT=inch \
FREEPRINTSTUDIO_FIT_MODE=stretch \
FREEPRINTSTUDIO_TARGET_WIDTH=6 \
FREEPRINTSTUDIO_TARGET_HEIGHT=1 \
PDF_EXPORT_PATH="${PDF_EXPORT_PATH:-/tmp/freeprintstudio-test-ruler-validation.pdf}" \
Scripts/validate_pdf_export.sh
