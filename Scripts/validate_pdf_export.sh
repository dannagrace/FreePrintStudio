#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.dannagrace.FreePrintStudio"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/freeprintstudio-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/FreePrintStudio.app"
SAMPLE_IMAGE="$ROOT_DIR/AppStore/Assets/sample-print-image.png"
SIMCTL_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SIMCTL_TIMEOUT_SECONDS:-30}"
TEMPORARY_SIMULATOR_BOOT_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_BOOT_TIMEOUT_SECONDS:-120}"
TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS:-120}"
XCODEBUILD_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_XCODEBUILD_TIMEOUT_SECONDS:-300}"
APP_LAUNCH_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_APP_LAUNCH_TIMEOUT_SECONDS:-30}"
TEMPORARY_SIMULATOR_APP_LAUNCH_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_APP_LAUNCH_TIMEOUT_SECONDS:-180}"
PDF_WAIT_ATTEMPTS="${FREEPRINTSTUDIO_PDF_WAIT_ATTEMPTS:-30}"
TEMPORARY_SIMULATOR_PDF_WAIT_ATTEMPTS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_PDF_WAIT_ATTEMPTS:-120}"
MAX_SIMULATOR_CANDIDATES="${FREEPRINTSTUDIO_MAX_SIMULATOR_CANDIDATES:-5}"
TEMPORARY_SIMULATOR_UDID=""
DEVICE=""
TEST_PAPER="${FREEPRINTSTUDIO_PAPER:-letter}"
TEST_ORIENTATION="${FREEPRINTSTUDIO_ORIENTATION:-portrait}"
TEST_UNIT="${FREEPRINTSTUDIO_UNIT:-inch}"
TEST_TARGET_WIDTH="${FREEPRINTSTUDIO_TARGET_WIDTH:-4}"
TEST_TARGET_HEIGHT="${FREEPRINTSTUDIO_TARGET_HEIGHT:-6}"
if [[ -n "${FREEPRINTSTUDIO_FIT_MODE:-}" ]]; then
  FIT_MODES=("$FREEPRINTSTUDIO_FIT_MODE")
else
  FIT_MODES=(fit fill stretch)
fi

case "$TEST_PAPER" in
  letter|a4|fourBySix|fiveBySeven)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_PAPER for PDF validation: %s\n' "$TEST_PAPER"
    exit 1
    ;;
esac

case "$TEST_ORIENTATION" in
  portrait|landscape)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_ORIENTATION for PDF validation: %s\n' "$TEST_ORIENTATION"
    exit 1
    ;;
esac

case "$TEST_UNIT" in
  inch|centimeter|millimeter)
    ;;
  *)
    printf 'Unsupported FREEPRINTSTUDIO_UNIT for PDF validation: %s\n' "$TEST_UNIT"
    exit 1
    ;;
esac

Scripts/generate_store_sample_image.py

cleanup_temporary_simulator() {
  if [[ -z "${TEMPORARY_SIMULATOR_UDID:-}" ]]; then
    return
  fi

  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl shutdown "$TEMPORARY_SIMULATOR_UDID" >/dev/null 2>&1 || true
  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl delete "$TEMPORARY_SIMULATOR_UDID" >/dev/null 2>&1 || true
  TEMPORARY_SIMULATOR_UDID=""
}

trap cleanup_temporary_simulator EXIT

candidate_simulators() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "$SIMULATOR_UDID"
    return
  fi

  local booted_devices
  local available_devices
  local device_pattern
  local fallback_device_name
  device_pattern="${FREEPRINTSTUDIO_IPHONE_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
  fallback_device_name="${FREEPRINTSTUDIO_DEVICE_FALLBACK_NAME:-iPhone}"

  booted_devices="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices booted || true)"
  available_devices="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices available || true)"

  printf '%s\n' "$booted_devices" \
    | grep -E "$device_pattern" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p' \
    || true
  printf '%s\n' "$available_devices" \
    | grep -E "$device_pattern" \
    | sed -nE 's/.*\(([A-F0-9-]{36})\).*/\1/p' \
    || true
  printf '%s\n' "$booted_devices" \
    | sed -nE "/$fallback_device_name/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p" \
    || true
  printf '%s\n' "$available_devices" \
    | sed -nE "/$fallback_device_name/s/.*\\(([A-F0-9-]{36})\\).*/\\1/p" \
    || true
}

unique_candidate_simulators() {
  candidate_simulators | awk 'NF && !seen[$0]++'
}

is_temporary_simulator() {
  local device="$1"
  [[ -n "${TEMPORARY_SIMULATOR_UDID:-}" && "$device" == "$TEMPORARY_SIMULATOR_UDID" ]]
}

boot_simulator() {
  local device="$1"
  local boot_command_output
  local bootstatus_timeout
  local bootstatus_output
  if [[ "$device" != "booted" ]]; then
    bootstatus_timeout="$SIMCTL_TIMEOUT_SECONDS"
    if is_temporary_simulator "$device"; then
      bootstatus_timeout="$TEMPORARY_SIMULATOR_BOOT_TIMEOUT_SECONDS"
    fi

    boot_command_output="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl boot "$device" 2>&1)" || {
      case "$boot_command_output" in
        *"Unable to boot device in current state: Booted"*|*"Unable to boot device in current state: Booting"*)
          ;;
        *)
          printf '%s\n' "$boot_command_output"
          return 1
          ;;
      esac
    }
    bootstatus_output="$(run_with_timeout "$bootstatus_timeout" xcrun simctl bootstatus "$device" -b 2>&1)" || {
      if run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devices booted | grep -q "$device"; then
        return 0
      fi
      printf '%s\n' "$bootstatus_output"
      return 1
    }
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout_text = sys.argv[1]
command = sys.argv[2:]
try:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=float(timeout_text),
    )
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        output = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else exc.stdout
        print(output, end="")
    print(f"{' '.join(command)} timed out after {timeout_text} seconds")
    sys.exit(124)

if result.stdout:
    print(result.stdout, end="")
sys.exit(result.returncode)
PY
}

preferred_simulator_device_type() {
  if [[ -n "${FREEPRINTSTUDIO_SIMULATOR_DEVICE_TYPE:-}" ]]; then
    printf '%s\n' "$FREEPRINTSTUDIO_SIMULATOR_DEVICE_TYPE"
    return
  fi

  local device_pattern
  local device_type
  local device_types
  device_pattern="${FREEPRINTSTUDIO_IPHONE_DEVICE_PATTERN:-iPhone 17 Pro Max|iPhone Air|iPhone 16 Pro Max|iPhone 16 Plus|iPhone 15 Pro Max|iPhone 15 Plus|iPhone 14 Pro Max}"
  device_types="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list devicetypes 2>&1)" || {
    printf '%s\n' "$device_types" >&2
    return 1
  }

  device_type="$(printf '%s\n' "$device_types" \
    | grep -E "$device_pattern" \
    | sed -nE 's/.*\((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]+)\).*/\1/p' \
    | head -n 1 \
    || true)"

  if [[ -z "$device_type" ]]; then
    device_type="$(printf '%s\n' "$device_types" \
      | sed -nE 's/^iPhone .*\((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]+)\).*/\1/p' \
      | head -n 1 \
      || true)"
  fi

  if [[ -z "$device_type" ]]; then
    printf 'No iPhone simulator device type found for temporary PDF validation simulator.\n' >&2
    return 1
  fi

  printf '%s\n' "$device_type"
}

preferred_simulator_runtime() {
  if [[ -n "${FREEPRINTSTUDIO_SIMULATOR_RUNTIME:-}" ]]; then
    printf '%s\n' "$FREEPRINTSTUDIO_SIMULATOR_RUNTIME"
    return
  fi

  local runtime
  local runtimes
  runtimes="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl list runtimes available 2>&1)" || {
    printf '%s\n' "$runtimes" >&2
    return 1
  }

  runtime="$(printf '%s\n' "$runtimes" \
    | sed -nE 's/.*- (com\.apple\.CoreSimulator\.SimRuntime\.iOS[-A-Za-z0-9.]*)$/\1/p' \
    | tail -n 1 \
    || true)"

  if [[ -z "$runtime" ]]; then
    printf 'No available iOS simulator runtime found for temporary PDF validation simulator.\n' >&2
    return 1
  fi

  printf '%s\n' "$runtime"
}

create_temporary_simulator() {
  local create_output
  local device_type
  local runtime
  local simulator_name

  device_type="$(preferred_simulator_device_type)" || return 1
  runtime="$(preferred_simulator_runtime)" || return 1
  simulator_name="FreePrintStudio PDF Validation ${GITHUB_RUN_ID:-$$}"

  printf 'Creating temporary simulator: %s (%s, %s)\n' "$simulator_name" "$device_type" "$runtime" >&2
  create_output="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl create "$simulator_name" "$device_type" "$runtime" 2>&1)" || {
    printf '%s\n' "$create_output" >&2
    return 1
  }

  TEMPORARY_SIMULATOR_UDID="$(printf '%s\n' "$create_output" | awk 'NF { value=$0 } END { print value }' | tr -d '\r')"
  if [[ -z "$TEMPORARY_SIMULATOR_UDID" ]]; then
    printf 'Temporary simulator creation did not return a UDID.\n' >&2
    return 1
  fi

  printf 'Created temporary simulator: %s\n' "$TEMPORARY_SIMULATOR_UDID" >&2
}

prepare_simulator_candidate() {
  local candidate="$1"
  local boot_output
  local install_timeout
  local install_output

  printf 'Trying simulator: %s\n' "$candidate" >&2
  boot_output=""
  if ! boot_output="$(boot_simulator "$candidate" 2>&1)"; then
    if [[ -n "$boot_output" ]]; then
      printf '%s\n' "$boot_output" >&2
    fi
    printf 'Skipping simulator after boot failure: %s\n' "$candidate" >&2
    return 1
  fi

  install_timeout="$SIMCTL_TIMEOUT_SECONDS"
  if is_temporary_simulator "$candidate"; then
    install_timeout="$TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS"
  fi

  install_output=""
  if install_output="$(run_with_timeout "$install_timeout" xcrun simctl install "$candidate" "$APP_PATH" 2>&1)"; then
    if [[ -n "$install_output" ]]; then
      printf '%s\n' "$install_output" >&2
    fi
    DEVICE="$candidate"
    return 0
  fi

  if [[ -n "$install_output" ]]; then
    printf '%s\n' "$install_output" >&2
  fi
  printf 'Skipping simulator after install failure: %s\n' "$candidate" >&2
  return 1
}

select_installed_simulator() {
  local candidate
  local candidates
  local attempted
  attempted=0
  candidates="$(unique_candidate_simulators)"
  if [[ -z "$candidates" ]]; then
    printf 'No installed iPhone simulator candidate found.\n' >&2
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    attempted=$((attempted + 1))
    if (( attempted > MAX_SIMULATOR_CANDIDATES )); then
      printf 'Reached simulator candidate attempt limit: %s\n' "$MAX_SIMULATOR_CANDIDATES" >&2
      break
    fi
    if prepare_simulator_candidate "$candidate"; then
      return
    fi
  done <<<"$candidates"

  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf 'No simulator accepted the validation app install.\n' >&2
    exit 1
  fi

  if ! create_temporary_simulator; then
    printf 'No simulator accepted the validation app install, and temporary simulator creation failed.\n' >&2
    exit 1
  fi
  candidate="$TEMPORARY_SIMULATOR_UDID"
  if prepare_simulator_candidate "$candidate"; then
    return
  fi

  printf 'No simulator accepted the validation app install.\n' >&2
  exit 1
}

if ! run_with_timeout "$XCODEBUILD_TIMEOUT_SECONDS" \
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme FreePrintStudio \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build >/tmp/freeprintstudio-pdf-validation-build.log 2>&1; then
  cat /tmp/freeprintstudio-pdf-validation-build.log
  exit 1
fi

select_installed_simulator
if [[ -z "$DEVICE" ]]; then
  printf 'No simulator selected for PDF validation.\n' >&2
  exit 1
fi
printf 'Using simulator: %s\n' "$DEVICE"

CONTAINER="$(run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)"
TEST_DIR="$CONTAINER/Documents/FreePrintStudioPDFValidation"
mkdir -p "$TEST_DIR"
cp "$SAMPLE_IMAGE" "$TEST_DIR/sample-print-image.png"

host_pdf_path_for_label() {
  local label="$1"
  local requested_path="${PDF_EXPORT_PATH:-}"

  if [[ -z "$requested_path" ]]; then
    printf '/tmp/freeprintstudio-export-validation-%s.pdf\n' "$label"
    return
  fi

  if (( ${#FIT_MODES[@]} == 1 )); then
    printf '%s\n' "$requested_path"
  elif [[ "$requested_path" == *.* ]]; then
    printf '%s-%s.%s\n' "${requested_path%.*}" "$label" "${requested_path##*.}"
  else
    printf '%s-%s.pdf\n' "$requested_path" "$label"
  fi
}

validate_pdf() {
  local label="$1"
  local mode="$2"
  local paper="$3"
  local orientation="$4"
  local unit="$5"
  local target_width="$6"
  local target_height="$7"
  local app_pdf_path="$TEST_DIR/export-validation-$label.pdf"
  local attempt
  local host_pdf_path
  local launch_output
  local launch_status
  local launch_timeout
  local pdf_wait_attempts
  local expected_width_points
  local expected_height_points
  local portrait_width_points
  local portrait_height_points
  host_pdf_path="$(host_pdf_path_for_label "$label")"

  case "$mode" in
    fit|fill|stretch)
      ;;
    *)
      printf 'Unsupported FREEPRINTSTUDIO_FIT_MODE for PDF validation: %s\n' "$mode"
      exit 1
      ;;
  esac

  case "$paper" in
    letter)
      portrait_width_points="612"
      portrait_height_points="792"
      ;;
    a4)
      portrait_width_points="595.2755905512"
      portrait_height_points="841.8897637795"
      ;;
    fourBySix)
      portrait_width_points="288"
      portrait_height_points="432"
      ;;
    fiveBySeven)
      portrait_width_points="360"
      portrait_height_points="504"
      ;;
    *)
      printf 'Unsupported paper for PDF validation: %s\n' "$paper"
      exit 1
      ;;
  esac

  case "$orientation" in
    portrait)
      expected_width_points="$portrait_width_points"
      expected_height_points="$portrait_height_points"
      ;;
    landscape)
      expected_width_points="$portrait_height_points"
      expected_height_points="$portrait_width_points"
      ;;
    *)
      printf 'Unsupported orientation for PDF validation: %s\n' "$orientation"
      exit 1
      ;;
  esac

  case "$unit" in
    inch|centimeter|millimeter)
      ;;
    *)
      printf 'Unsupported measurement unit for PDF validation: %s\n' "$unit"
      exit 1
      ;;
  esac

  rm -f "$app_pdf_path" "$host_pdf_path"

  run_with_timeout "$SIMCTL_TIMEOUT_SECONDS" xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  launch_timeout="$APP_LAUNCH_TIMEOUT_SECONDS"
  if is_temporary_simulator "$DEVICE"; then
    launch_timeout="$TEMPORARY_SIMULATOR_APP_LAUNCH_TIMEOUT_SECONDS"
  fi

  launch_output=""
  launch_status=0
  if launch_output="$(run_with_timeout "$launch_timeout" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" \
    -FreePrintStudioTestImagePath "$TEST_DIR/sample-print-image.png" \
    -FreePrintStudioPaper "$paper" \
    -FreePrintStudioOrientation "$orientation" \
    -FreePrintStudioUnit "$unit" \
    -FreePrintStudioFitMode "$mode" \
    -FreePrintStudioTargetWidth "$target_width" \
    -FreePrintStudioTargetHeight "$target_height" \
    -FreePrintStudioAutoExportPDFPath "$app_pdf_path" \
    2>&1)"; then
    launch_status=0
  else
    launch_status=$?
    if [[ "$launch_status" -ne 124 ]]; then
      printf '%s\n' "$launch_output"
      exit 1
    fi
  fi

  pdf_wait_attempts="$PDF_WAIT_ATTEMPTS"
  if is_temporary_simulator "$DEVICE"; then
    pdf_wait_attempts="$TEMPORARY_SIMULATOR_PDF_WAIT_ATTEMPTS"
  fi

  for ((attempt = 1; attempt <= pdf_wait_attempts; attempt += 1)); do
    if [[ -s "$app_pdf_path" ]]; then
      break
    fi
    sleep 0.5
  done

  if [[ ! -s "$app_pdf_path" ]]; then
    if [[ -n "$launch_output" ]]; then
      printf '%s\n' "$launch_output"
    fi
    printf 'Timed out waiting for exported PDF: %s\n' "$app_pdf_path"
    exit 1
  fi

  mkdir -p "$(dirname "$host_pdf_path")"
  cp "$app_pdf_path" "$host_pdf_path"

  python3 - "$host_pdf_path" "$expected_width_points" "$expected_height_points" "$mode" "$unit" "$target_width" "$target_height" <<'PY'
import re
import sys
import zlib

path = sys.argv[1]
expected_width = float(sys.argv[2])
expected_height = float(sys.argv[3])
mode = sys.argv[4]
unit = sys.argv[5]
target_width_text = sys.argv[6]
target_height_text = sys.argv[7]
data = open(path, "rb").read()

if not data.startswith(b"%PDF-"):
    raise SystemExit("Exported file is not a PDF")

match = re.search(
    rb"/MediaBox\s*\[\s*([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s*\]",
    data,
)
if not match:
    raise SystemExit("PDF MediaBox not found")

x0, y0, x1, y1 = (float(value) for value in match.groups())
width = x1 - x0
height = y1 - y0
tolerance = 0.02

print(f"PDF MediaBox: {width:.4f} x {height:.4f} pt")
if abs(width - expected_width) > tolerance or abs(height - expected_height) > tolerance:
    raise SystemExit(
        f"Unexpected PDF page size: {width:.4f} x {height:.4f}, "
        f"expected {expected_width:.4f} x {expected_height:.4f}"
    )

if b"/Subtype /Image" not in data:
    raise SystemExit("Exported PDF does not contain an embedded image")

if len(data) < 1000:
    raise SystemExit("Exported PDF is unexpectedly small")

def parse_measurement(value: str) -> float:
    value = value.strip()
    if value.count(",") == 1 and "." not in value:
        value = value.replace(",", ".")
    return float(value)

def target_points(value_text: str, unit_name: str) -> float:
    value = parse_measurement(value_text)
    if unit_name == "inch":
        return value * 72
    if unit_name == "centimeter":
        return value / 2.54 * 72
    if unit_name == "millimeter":
        return value / 25.4 * 72
    raise SystemExit(f"Unsupported measurement unit: {unit_name}")

expected_target_width = target_points(target_width_text, unit)
expected_target_height = target_points(target_height_text, unit)
decoded_streams = []
for stream in re.findall(rb"stream\r?\n(.*?)\r?\nendstream", data, re.S):
    try:
        decoded_streams.append(zlib.decompress(stream))
    except zlib.error:
        decoded_streams.append(stream)
content = b"\n".join(decoded_streams)
clip_match = re.search(
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+m\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+"
    rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+l\s+h\s+W\s+n",
    content,
)
if not clip_match:
    raise SystemExit("Image clip rectangle not found in PDF content stream")

clip_values = [float(value) for value in clip_match.groups()]
clip_x_values = clip_values[0::2]
clip_y_values = clip_values[1::2]
clip_width = max(clip_x_values) - min(clip_x_values)
clip_height = max(clip_y_values) - min(clip_y_values)
if abs(clip_width - expected_target_width) > tolerance or abs(clip_height - expected_target_height) > tolerance:
    raise SystemExit(
        f"Unexpected image clip rectangle size: {clip_width:.4f} x {clip_height:.4f}, "
        f"expected {expected_target_width:.4f} x {expected_target_height:.4f}"
    )
print(f"Image clip rectangle: {clip_width:.4f} x {clip_height:.4f} pt")

if mode == "stretch":
    expected_draw_width = expected_target_width
    expected_draw_height = expected_target_height
    matrix_match = re.search(
        rb"([-+]?[0-9]*\.?[0-9]+)\s+0\s+0\s+([-+]?[0-9]*\.?[0-9]+)\s+"
        rb"([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+cm\s+/Im\d+\s+Do",
        content,
    )
    if not matrix_match:
        raise SystemExit("Image draw matrix not found in stretch PDF content stream")

    draw_width = float(matrix_match.group(1))
    draw_height = float(matrix_match.group(2))
    if abs(draw_width - expected_draw_width) > tolerance or abs(draw_height - expected_draw_height) > tolerance:
        raise SystemExit(
            f"Unexpected stretch image draw size: {draw_width:.4f} x {draw_height:.4f}, "
            f"expected {expected_draw_width:.4f} x {expected_draw_height:.4f}"
        )
    print(f"Image draw matrix: {draw_width:.4f} x {draw_height:.4f} pt")

print(f"Validated {mode} exported PDF: {path}")
PY
}

for mode in "${FIT_MODES[@]}"; do
  validate_pdf "$mode" "$mode" "$TEST_PAPER" "$TEST_ORIENTATION" "$TEST_UNIT" "$TEST_TARGET_WIDTH" "$TEST_TARGET_HEIGHT"
done

if [[ -z "${FREEPRINTSTUDIO_TARGET_WIDTH:-}" && -z "${FREEPRINTSTUDIO_TARGET_HEIGHT:-}" && -z "${FREEPRINTSTUDIO_FIT_MODE:-}" && -z "${FREEPRINTSTUDIO_PAPER:-}" && -z "${FREEPRINTSTUDIO_ORIENTATION:-}" && -z "${FREEPRINTSTUDIO_UNIT:-}" ]]; then
  validate_pdf "localized-decimal-stretch" "stretch" "letter" "portrait" "inch" "4,5" "6,25"
  validate_pdf "landscape-letter-stretch" "stretch" "letter" "landscape" "inch" "4" "6"
  validate_pdf "centimeter-a4-stretch" "stretch" "a4" "portrait" "centimeter" "10" "15"
  validate_pdf "millimeter-a4-stretch" "stretch" "a4" "portrait" "millimeter" "100" "150"
fi
