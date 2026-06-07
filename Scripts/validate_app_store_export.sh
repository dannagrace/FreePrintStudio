#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source Scripts/load_release_env.sh

SCHEME="FreePrintStudio"
CONFIGURATION="Release"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/FreePrintStudio.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/AppStoreExport}"

setting_value() {
  local key="$1"
  xcodebuild \
    -project FreePrintStudio.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -showBuildSettings 2>/dev/null \
    | awk -F'= ' -v key="$key" '{
        lhs = $1
        gsub(/^[ \t]+|[ \t]+$/, "", lhs)
        if (lhs == key) {
          gsub(/^[ \t]+|[ \t]+$/, "", $2)
          print $2
          exit
        }
      }'
}

find_exported_ipa() {
  local explicit_path="${IPA_PATH:-}"
  local ipa_count=0
  local found_path=""
  local candidate

  if [[ -n "$explicit_path" ]]; then
    printf '%s\n' "$explicit_path"
    return
  fi

  if [[ -d "$EXPORT_PATH" ]]; then
    while IFS= read -r -d '' candidate; do
      ipa_count=$((ipa_count + 1))
      found_path="$candidate"
    done < <(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.ipa' -print0)
  fi

  if (( ipa_count == 1 )); then
    printf '%s\n' "$found_path"
  elif (( ipa_count > 1 )); then
    printf 'ERROR: Multiple IPA files found under %s; set IPA_PATH explicitly.\n' "$EXPORT_PATH" >&2
    return 1
  else
    printf '%s\n' "$EXPORT_PATH/FreePrintStudio.ipa"
  fi
}

expected_bundle_id="$(setting_value PRODUCT_BUNDLE_IDENTIFIER)"
expected_version="$(setting_value MARKETING_VERSION)"
expected_build="$(setting_value CURRENT_PROJECT_VERSION)"
expected_executable="$(setting_value EXECUTABLE_NAME)"
expected_wrapper="$(setting_value WRAPPER_NAME)"
expected_display_name="$(plutil -extract CFBundleDisplayName raw -o - FreePrintStudio/Resources/Info.plist 2>/dev/null || true)"
ipa_path="$(find_exported_ipa)"

python3 - "$ARCHIVE_PATH" "$ipa_path" "$expected_bundle_id" "$expected_version" "$expected_build" "$expected_executable" "$expected_wrapper" "$expected_display_name" <<'PY'
import plistlib
import sys
import zipfile
from pathlib import Path

archive_path = Path(sys.argv[1])
ipa_path = Path(sys.argv[2])
expected_bundle_id = sys.argv[3]
expected_version = sys.argv[4]
expected_build = sys.argv[5]
expected_executable = sys.argv[6]
expected_wrapper = sys.argv[7]
expected_display_name = sys.argv[8]

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def ok(message: str) -> None:
    print(f"OK: {message}")


def require_file(path: Path, label: str) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"{label} missing or empty: {path}")


def read_plist(path: Path, label: str) -> dict:
    if not path.is_file():
        fail(f"{label} missing: {path}")
        return {}
    try:
        with path.open("rb") as plist_file:
            value = plistlib.load(plist_file)
    except Exception as exc:
        fail(f"{label} is not a readable plist: {exc}")
        return {}
    if not isinstance(value, dict):
        fail(f"{label} is not a dictionary plist")
        return {}
    return value


def check_equal(label: str, actual: object, expected: str) -> None:
    value = "" if actual is None else str(actual)
    if value != expected:
        fail(f"{label} is {value or 'missing'}, expected {expected}")


def validate_app_info(info: dict, label: str) -> None:
    check_equal(f"{label} CFBundleIdentifier", info.get("CFBundleIdentifier"), expected_bundle_id)
    check_equal(f"{label} CFBundleShortVersionString", info.get("CFBundleShortVersionString"), expected_version)
    check_equal(f"{label} CFBundleVersion", info.get("CFBundleVersion"), expected_build)
    check_equal(f"{label} CFBundleExecutable", info.get("CFBundleExecutable"), expected_executable)
    check_equal(f"{label} CFBundleDisplayName", info.get("CFBundleDisplayName"), expected_display_name)


def validate_archive() -> None:
    if not archive_path.is_dir():
        fail(f"Archive directory missing: {archive_path}")
        return

    archive_info = read_plist(archive_path / "Info.plist", "Archive Info.plist")
    properties = archive_info.get("ApplicationProperties", {})
    if not isinstance(properties, dict):
        fail("Archive Info.plist is missing ApplicationProperties")
        properties = {}

    check_equal("Archive ApplicationProperties.CFBundleIdentifier", properties.get("CFBundleIdentifier"), expected_bundle_id)
    check_equal(
        "Archive ApplicationProperties.CFBundleShortVersionString",
        properties.get("CFBundleShortVersionString"),
        expected_version,
    )
    check_equal("Archive ApplicationProperties.CFBundleVersion", properties.get("CFBundleVersion"), expected_build)

    signing_identity = str(properties.get("SigningIdentity", ""))
    if not signing_identity.startswith("Apple Distribution"):
        fail(
            "Archive signing identity must be Apple Distribution, "
            f"found {signing_identity or 'missing'}"
        )

    archive_app = archive_path / "Products" / "Applications" / expected_wrapper
    app_info = read_plist(archive_app / "Info.plist", "Archive app Info.plist")
    validate_app_info(app_info, "Archive app")
    require_file(archive_app / "_CodeSignature" / "CodeResources", "Archive app code signature")
    require_file(
        archive_path / "dSYMs" / f"{expected_wrapper}.dSYM" / "Contents" / "Resources" / "DWARF" / expected_executable,
        "Archive dSYM DWARF file",
    )
    ok(f"Archive structure validated: {archive_path}")


def validate_ipa() -> None:
    if not ipa_path.is_file():
        fail(f"IPA missing: {ipa_path}")
        return

    if ipa_path.stat().st_size < 100_000:
        fail(f"IPA is suspiciously small: {ipa_path} ({ipa_path.stat().st_size} bytes)")

    try:
        with zipfile.ZipFile(ipa_path) as ipa:
            names = ipa.namelist()
            app_roots = sorted({
                name.split("/", 2)[1]
                for name in names
                if name.startswith("Payload/") and name.count("/") >= 2 and name.split("/", 2)[1].endswith(".app")
            })

            if app_roots != [expected_wrapper]:
                fail(f"IPA Payload app bundle is {app_roots or 'missing'}, expected [{expected_wrapper}]")
                return

            info_name = f"Payload/{expected_wrapper}/Info.plist"
            signature_name = f"Payload/{expected_wrapper}/_CodeSignature/CodeResources"
            if info_name not in names:
                fail(f"IPA app Info.plist missing: {info_name}")
                return

            try:
                app_info = plistlib.loads(ipa.read(info_name))
            except Exception as exc:
                fail(f"IPA app Info.plist is not readable: {exc}")
                return

            validate_app_info(app_info, "IPA app")

            if signature_name not in names or not ipa.read(signature_name):
                fail(f"IPA app code signature missing or empty: {signature_name}")

            nested_payloads = [
                name for name in names
                if name.startswith("Payload/") and "/Payload/" in name
            ]
            if nested_payloads:
                fail("IPA contains a nested Payload directory")
    except zipfile.BadZipFile as exc:
        fail(f"IPA is not a valid zip archive: {exc}")
        return

    ok(f"IPA payload validated: {ipa_path}")


validate_archive()
validate_ipa()

if failures:
    for failure in failures:
        print(f"BLOCKED: {failure}")
    sys.exit(1)

print("App Store export validation passed.")
PY
