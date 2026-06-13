#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
umask 077

failures=0

check_file() {
  local path="$1"
  local message="$2"
  if [[ ! -s "$path" ]]; then
    printf 'FAIL: %s (%s)\n' "$message" "$path"
    failures=$((failures + 1))
  fi
}

check_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$path" ]]; then
    printf 'FAIL: %s (%s missing)\n' "$message" "$path"
    failures=$((failures + 1))
    return
  fi
  if ! grep -q -- "$pattern" "$path"; then
    printf 'FAIL: %s (%s missing %s)\n' "$message" "$path" "$pattern"
    failures=$((failures + 1))
  fi
}

check_not_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$path" ]]; then
    printf 'FAIL: %s (%s missing)\n' "$message" "$path"
    failures=$((failures + 1))
    return
  fi
  if grep -q -- "$pattern" "$path"; then
    printf 'FAIL: %s (%s still contains %s)\n' "$message" "$path" "$pattern"
    failures=$((failures + 1))
  fi
}

check_occurrences_at_least() {
  local path="$1"
  local pattern="$2"
  local minimum="$3"
  local message="$4"
  local count
  if [[ ! -f "$path" ]]; then
    printf 'FAIL: %s (%s missing)\n' "$message" "$path"
    failures=$((failures + 1))
    return
  fi
  count="$(grep -c -- "$pattern" "$path" || true)"
  if (( count < minimum )); then
    printf 'FAIL: %s (%s has %s occurrence(s) of %s, expected at least %s)\n' \
      "$message" "$path" "$count" "$pattern" "$minimum"
    failures=$((failures + 1))
  fi
}

check_sips_property() {
  local path="$1"
  local property="$2"
  local expected="$3"
  local message="$4"
  local actual
  actual="$(sips -g "$property" "$path" 2>/dev/null | awk -F': ' -v key="$property" '$1 ~ key { print $2 }')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (%s %s is %s, expected %s)\n' "$message" "$path" "$property" "${actual:-missing}" "$expected"
    failures=$((failures + 1))
  fi
}

check_plist_raw_value() {
  local path="$1"
  local key="$2"
  local expected="$3"
  local message="$4"
  local actual
  actual="$(plutil -extract "$key" raw -o - "$path" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (%s %s is %s, expected %s)\n' "$message" "$path" "$key" "${actual:-missing}" "$expected"
    failures=$((failures + 1))
  fi
}

check_workflow_step_timeout() {
  local step_name="$1"
  local expected_timeout="$2"
  local message="$3"

  if ! python3 - ".github/workflows/release.yml" "$step_name" "$expected_timeout" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
step_name = sys.argv[2]
expected_timeout = sys.argv[3]
lines = path.read_text().splitlines()
start = None

for index, line in enumerate(lines):
    if line.strip() == f"- name: {step_name}":
        start = index
        break

if start is None:
    raise SystemExit(1)

for line in lines[start + 1:]:
    stripped = line.strip()
    if stripped.startswith("- name: "):
        break
    if stripped == f"timeout-minutes: {expected_timeout}":
        raise SystemExit(0)

raise SystemExit(1)
PY
  then
    printf 'FAIL: %s (.github/workflows/release.yml step "%s" missing timeout-minutes: %s)\n' \
      "$message" "$step_name" "$expected_timeout"
    failures=$((failures + 1))
  fi
}

check_icon_artwork() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return
  fi

  python3 - "$path" <<'PY'
import struct
import sys
import zlib

path = sys.argv[1]
data = open(path, "rb").read()
if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("FAIL: App icon artwork must be a PNG")

pos = 8
width = height = bit_depth = color_type = None
compressed = bytearray()

while pos < len(data):
    length = struct.unpack(">I", data[pos:pos + 4])[0]
    chunk_type = data[pos + 4:pos + 8]
    payload = data[pos + 8:pos + 8 + length]
    pos += 12 + length

    if chunk_type == b"IHDR":
        width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
    elif chunk_type == b"IDAT":
        compressed.extend(payload)
    elif chunk_type == b"IEND":
        break

if bit_depth != 8 or color_type not in (2, 6):
    raise SystemExit(f"FAIL: Unsupported app icon PNG format: bit_depth={bit_depth}, color_type={color_type}")

channels = 4 if color_type == 6 else 3
stride = width * channels
raw = zlib.decompress(bytes(compressed))
previous = [0] * stride
offset = 0
sample_step = max(1, width // 96)
total_luminance = 0
sample_count = 0
interesting = 0
colors = set()

for y in range(height):
    filter_type = raw[offset]
    offset += 1
    scanline = list(raw[offset:offset + stride])
    offset += stride

    for i, value in enumerate(scanline):
        left = scanline[i - channels] if i >= channels else 0
        up = previous[i]
        up_left = previous[i - channels] if i >= channels else 0
        if filter_type == 1:
            scanline[i] = (value + left) & 0xFF
        elif filter_type == 2:
            scanline[i] = (value + up) & 0xFF
        elif filter_type == 3:
            scanline[i] = (value + ((left + up) // 2)) & 0xFF
        elif filter_type == 4:
            p = left + up - up_left
            pa = abs(p - left)
            pb = abs(p - up)
            pc = abs(p - up_left)
            predictor = left if pa <= pb and pa <= pc else up if pb <= pc else up_left
            scanline[i] = (value + predictor) & 0xFF
        elif filter_type != 0:
            raise SystemExit(f"FAIL: Unsupported app icon PNG filter: {filter_type}")

    if y % sample_step == 0:
        for x in range(0, width, sample_step):
            i = x * channels
            red, green, blue = scanline[i], scanline[i + 1], scanline[i + 2]
            luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            total_luminance += luminance
            sample_count += 1
            if luminance > 24:
                interesting += 1
            colors.add((red // 24, green // 24, blue // 24))
    previous = scanline

average_luminance = total_luminance / max(1, sample_count)
interesting_ratio = interesting / max(1, sample_count)
if average_luminance < 30 or interesting_ratio < 0.35 or len(colors) < 8:
    raise SystemExit(
        "FAIL: App icon artwork looks blank or placeholder-like "
        f"(average_luminance={average_luminance:.1f}, interesting_ratio={interesting_ratio:.2f}, color_buckets={len(colors)})"
    )
PY
  local result=$?
  if [[ "$result" -ne 0 ]]; then
    failures=$((failures + 1))
  fi
}

check_file "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "App Store icon PNG is required"
check_contains "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" "AppIcon.png" "AppIcon asset catalog must reference AppIcon.png"
check_sips_property "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "pixelWidth" "1024" "App Store icon must be 1024px wide"
check_sips_property "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "pixelHeight" "1024" "App Store icon must be 1024px tall"
check_sips_property "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "hasAlpha" "no" "App Store icon must not contain an alpha channel"
check_icon_artwork "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
check_file "Scripts/validate_app_icon_set.sh" "App icon set validation script is required"
if [[ -x "Scripts/validate_app_icon_set.sh" ]]; then
  Scripts/validate_app_icon_set.sh || failures=$((failures + 1))
else
  printf 'FAIL: App icon set validation script must be executable (Scripts/validate_app_icon_set.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_icon_set.sh" "ios-marketing" "App icon set validation must check the marketing icon"
check_contains "Scripts/validate_app_icon_set.sh" "hasAlpha" "App icon set validation must reject alpha channels"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_icon_set.sh" "Readiness audit must validate the app icon catalog"
check_file "FreePrintStudio/Resources/PrivacyInfo.xcprivacy" "Privacy manifest is required for release documentation"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "PrivacyInfo.xcprivacy" "Privacy manifest must be included in the Xcode project"
check_contains "FreePrintStudio/ContentView.swift" "About FreePrint Studio" "App must expose an About screen"
check_contains "FreePrintStudio/ContentView.swift" "Privacy Policy" "App must expose privacy policy text"
check_contains "FreePrintStudio/ContentView.swift" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "About screen must link to the public privacy policy"
check_contains "FreePrintStudio/ContentView.swift" "https://dannagrace.github.io/FreePrintStudio/support.html" "About screen must link to the public support page"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityIdentifier(\"about-summary\")" "About screen summary must have a stable UI test identifier"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityIdentifier(\"privacy-policy-link\")" "About privacy link must have a stable UI test identifier"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityIdentifier(\"support-link\")" "About support link must have a stable UI test identifier"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityIdentifier(\"app-version-value\")" "About version value must have a stable UI test identifier"
check_contains "FreePrintStudio/ContentView.swift" "selectedImage == nil ? \"Choose Image\" : \"Change Image\"" "Image picker control must expose the current action as its VoiceOver label"
check_contains "FreePrintStudio/ContentView.swift" "Test Ruler" "App must expose a built-in exact-size test ruler"
check_contains "FreePrintStudio/ContentView.swift" "makeCalibrationGuideImage" "App must generate an on-device calibration guide image"
check_contains "FreePrintStudio/ContentView.swift" "PrintSizing.calibrationGuideTargetSize" "Calibration guide must use the shared print sizing target"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityLabel(\"Print preview\")" "Print preview must have an explicit VoiceOver label"
check_contains "FreePrintStudio/ContentView.swift" "Enter the target print width" "Width field must have a VoiceOver hint"
check_contains "FreePrintStudio/ContentView.swift" "Enter the target print height" "Height field must have a VoiceOver hint"
check_contains "Sources/FreePrintStudioCore/PrintSizing.swift" "parseMeasurement" "Sizing core must expose localized measurement parsing"
check_contains "Sources/FreePrintStudioCore/PrintSizing.swift" "calibrationGuideTargetSize" "Sizing core must expose the standard calibration guide target size"
check_contains "Sources/FreePrintStudioCoreChecks/main.swift" "6,25" "Core checks must cover decimal comma measurement input"
check_contains "Sources/FreePrintStudioCoreChecks/main.swift" "calibrationGuideTargetSize" "Core checks must cover calibration guide target sizing"
check_contains "FreePrintStudio/ContentView.swift" "PrintSizing.parseMeasurement(widthText)" "Width input must use localized measurement parsing"
check_contains "FreePrintStudio/ContentView.swift" "PrintSizing.parseMeasurement(heightText)" "Height input must use localized measurement parsing"
check_contains "FreePrintStudio/ContentView.swift" "selectedImage != nil && isTargetSizeValid" "Export and print actions must require both a selected image and a valid target size"
check_contains "FreePrintStudio/ContentView.swift" ".disabled(!isOutputReady)" "Export and print buttons must be disabled until output is ready"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "testTestRulerLoadsCalibrationGuide" "UI tests must cover the built-in Test Ruler workflow"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "testAboutScreenShowsReviewAndSupportInformation" "UI tests must cover About, privacy, support, and version review information"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "privacy-policy-link" "UI tests must verify the About privacy link"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "support-link" "UI tests must verify the About support link"
check_contains "FreePrintStudio/Resources/Info.plist" "NSPhotoLibraryUsageDescription" "Info.plist must explain photo library access"
check_contains "FreePrintStudio/Resources/Info.plist" "selected image locally" "Photo library usage description must explain local image processing"
check_file "Scripts/validate_app_identity.sh" "App identity validation script is required"
if [[ ! -x "Scripts/validate_app_identity.sh" ]]; then
  printf 'FAIL: App identity validation script must be executable (Scripts/validate_app_identity.sh)\n'
  failures=$((failures + 1))
fi
if [[ -x "Scripts/validate_app_identity.sh" ]]; then
  Scripts/validate_app_identity.sh || failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_identity.sh" "PRODUCT_BUNDLE_IDENTIFIER" "App identity validation must check the Xcode bundle identifier"
check_contains "Scripts/validate_app_identity.sh" "CFBundleDisplayName" "App identity validation must check the display name"
check_contains "Scripts/validate_app_identity.sh" "TARGETED_DEVICE_FAMILY" "App identity validation must check supported device families"
check_contains "Scripts/validate_app_identity.sh" "fastlane/Fastfile" "App identity validation must check Fastlane constants"
check_contains "Scripts/validate_app_identity.sh" "fastlane/Deliverfile" "App identity validation must check Deliverfile constants"
check_file "AppStore/metadata.md" "App Store metadata draft is required"
check_file "Scripts/validate_app_store_metadata.sh" "App Store metadata limit validation script is required"
if [[ -x "Scripts/validate_app_store_metadata.sh" ]]; then
  Scripts/validate_app_store_metadata.sh || failures=$((failures + 1))
else
  printf 'FAIL: App Store metadata limit validation script must be executable (Scripts/validate_app_store_metadata.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_store_metadata.sh" "name.txt" "Metadata validation must check the Fastlane app name"
check_contains "Scripts/validate_app_store_metadata.sh" "subtitle.txt" "Metadata validation must check the Fastlane subtitle"
check_contains "Scripts/validate_app_store_metadata.sh" "promotional_text.txt" "Metadata validation must check the Fastlane promotional text"
check_contains "Scripts/validate_app_store_metadata.sh" "description.txt" "Metadata validation must check the Fastlane description"
check_contains "Scripts/validate_app_store_metadata.sh" "privacy_url.txt" "Metadata validation must check the Fastlane privacy URL"
check_contains "Scripts/validate_app_store_metadata.sh" "support_url.txt" "Metadata validation must check the Fastlane support URL"
check_contains "Scripts/validate_app_store_metadata.sh" "check_review_notes_requirements" "Metadata validation must enforce App Review notes content requirements"
check_contains "Scripts/validate_app_store_metadata.sh" "does not require an account" "Metadata validation must require App Review notes to explain no account is needed"
check_contains "Scripts/validate_app_store_metadata.sh" "locally on device" "Metadata validation must require App Review notes to explain local image processing"
check_contains "Scripts/validate_app_store_metadata.sh" "Test Ruler" "Metadata validation must require App Review notes to describe the Test Ruler path"
check_contains "Scripts/validate_app_store_metadata.sh" "AirPrint" "Metadata validation must require App Review notes to describe print workflow testing"
check_contains "AppStore/metadata.md" "Privacy Policy" "Metadata must include privacy policy copy"
check_contains "AppStore/metadata.md" "Privacy Policy URL" "Metadata must include a privacy policy URL field"
check_contains "AppStore/metadata.md" "Support URL" "Metadata must include a support URL field"
check_contains "AppStore/metadata.md" "Copyright" "Metadata must include copyright copy"
check_contains "AppStore/metadata.md" "Version Release Notes" "Metadata must include version release notes"
check_contains "AppStore/metadata.md" "Test Ruler" "Metadata must mention the built-in exact-size test ruler"
check_contains "AppStore/metadata.md" "iphone-main.jpg" "Metadata must name the iPhone screenshot asset"
check_contains "AppStore/metadata.md" "iphone-test-ruler.jpg" "Metadata must name the iPhone Test Ruler screenshot asset"
check_contains "AppStore/metadata.md" "iphone-fit.jpg" "Metadata must name the iPhone Fit screenshot asset"
check_contains "AppStore/metadata.md" "iphone-fill.jpg" "Metadata must name the iPhone Fill screenshot asset"
check_contains "AppStore/metadata.md" "iphone-stretch.jpg" "Metadata must name the iPhone Stretch screenshot asset"
check_contains "AppStore/metadata.md" "iphone-metric-landscape.jpg" "Metadata must name the iPhone metric landscape screenshot asset"
check_contains "AppStore/metadata.md" "ipad-main.jpg" "Metadata must name the iPad screenshot asset"
check_file "AppStore/app-privacy.md" "App privacy questionnaire answers are required"
check_contains "AppStore/app-privacy.md" "No, we do not collect data from this app" "Privacy answers must state no data collection"
check_contains "AppStore/app-privacy.md" "Tracking: No" "Privacy answers must state no tracking"
check_file "AppStore/app_privacy_details.json" "Fastlane App Privacy Details JSON is required"
check_contains "AppStore/app_privacy_details.json" "DATA_NOT_COLLECTED" "App Privacy Details JSON must state no data collection"
check_file "Scripts/validate_app_privacy_details.sh" "App Privacy Details validation script is required"
if [[ -x "Scripts/validate_app_privacy_details.sh" ]]; then
  Scripts/validate_app_privacy_details.sh || failures=$((failures + 1))
else
  printf 'FAIL: App Privacy Details validation script must be executable (Scripts/validate_app_privacy_details.sh)\n'
  failures=$((failures + 1))
fi
check_file "Scripts/validate_privacy_surface.sh" "Privacy surface validation script is required"
if [[ -x "Scripts/validate_privacy_surface.sh" ]]; then
  Scripts/validate_privacy_surface.sh || failures=$((failures + 1))
else
  printf 'FAIL: Privacy surface validation script must be executable (Scripts/validate_privacy_surface.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_privacy_surface.sh" "analytics" "Privacy surface validation must scan for analytics SDK references"
check_contains "Scripts/validate_privacy_surface.sh" "URLSession" "Privacy surface validation must scan for direct network API usage"
privacy_surface_no_rg_test_dir="$(mktemp -d)"
privacy_surface_no_rg_bin="$privacy_surface_no_rg_test_dir/bin"
privacy_surface_no_rg_log="$privacy_surface_no_rg_test_dir/privacy-surface.log"
mkdir -p "$privacy_surface_no_rg_bin"
ln -s /bin/bash "$privacy_surface_no_rg_bin/bash"
ln -s /usr/bin/dirname "$privacy_surface_no_rg_bin/dirname"
ln -s /usr/bin/python3 "$privacy_surface_no_rg_bin/python3"
ln -s /usr/bin/plutil "$privacy_surface_no_rg_bin/plutil"
ln -s /usr/bin/sed "$privacy_surface_no_rg_bin/sed"
if ! PATH="$privacy_surface_no_rg_bin" bash Scripts/validate_privacy_surface.sh >"$privacy_surface_no_rg_log" 2>&1; then
  printf 'FAIL: Privacy surface validation must pass without requiring ripgrep in PATH\n'
  failures=$((failures + 1))
  sed 's/^/  /' "$privacy_surface_no_rg_log"
elif grep -q 'command not found' "$privacy_surface_no_rg_log"; then
  printf 'FAIL: Privacy surface validation must not print command-not-found noise when ripgrep is unavailable\n'
  failures=$((failures + 1))
  sed 's/^/  /' "$privacy_surface_no_rg_log"
fi
rm -rf "$privacy_surface_no_rg_test_dir"
check_contains "Scripts/verify_release.sh" "validate_privacy_surface.sh" "Release verification must run privacy surface validation"
check_file "AppStore/age-rating.md" "Age rating questionnaire answers are required"
check_contains "AppStore/age-rating.md" "Expected global age rating: 4+" "Age rating answers must record the expected 4+ rating"
check_contains "AppStore/age-rating.md" "User-generated content: None" "Age rating answers must record no user-generated content"
check_file "AppStore/accessibility-labels.md" "Accessibility Nutrition Label answers are required"
check_contains "AppStore/accessibility-labels.md" "VoiceOver: Supported" "Accessibility answers must record VoiceOver support"
check_contains "AppStore/accessibility-labels.md" "Larger Text: Supported" "Accessibility answers must record Larger Text support"
check_file "AppStore/export-compliance.md" "Export compliance questionnaire answers are required"
check_contains "AppStore/export-compliance.md" "Uses non-exempt encryption: No" "Export compliance answers must state no non-exempt encryption"
check_contains "AppStore/export-compliance.md" "ITSAppUsesNonExemptEncryption" "Export compliance answers must reference the Info.plist declaration"
check_file "Scripts/validate_app_store_questionnaires.sh" "App Store questionnaire consistency validation script is required"
if [[ -x "Scripts/validate_app_store_questionnaires.sh" ]]; then
  Scripts/validate_app_store_questionnaires.sh || failures=$((failures + 1))
else
  printf 'FAIL: App Store questionnaire consistency validation script must be executable (Scripts/validate_app_store_questionnaires.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_store_questionnaires.sh" "AppStore/age-rating.md" "Questionnaire validation must check age rating answers"
check_contains "Scripts/validate_app_store_questionnaires.sh" "AppStore/export-compliance.md" "Questionnaire validation must check export compliance answers"
check_contains "Scripts/validate_app_store_questionnaires.sh" "ITSAppUsesNonExemptEncryption" "Questionnaire validation must compare export compliance against Info.plist encryption declaration"
check_contains "Scripts/validate_app_store_questionnaires.sh" "AppStore/app-privacy.md" "Questionnaire validation must check App Privacy answers"
check_contains "Scripts/verify_release.sh" "validate_app_store_questionnaires.sh" "Release verification must run questionnaire consistency validation"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_store_questionnaires.sh" "Readiness audit must run questionnaire consistency validation"
check_file "docs/privacy-policy.html" "Publishable privacy policy page is required"
check_contains "docs/privacy-policy.html" "FreePrint Studio Privacy Policy" "Privacy page must identify the app and policy"
check_contains "docs/privacy-policy.html" "does not collect" "Privacy page must state no data collection"
check_file "docs/support.html" "Publishable support page is required"
check_contains "docs/support.html" "FreePrint Studio Support" "Support page must identify the app support page"
check_contains "docs/support.html" "Test Ruler" "Support page must explain the built-in test ruler"
check_contains "docs/support.html" "Actual Size (100%)" "Support page must explain exact-size printer scaling"
check_contains "docs/support.html" "Fit to Page" "Support page must warn about automatic print scaling"
check_contains "docs/support.html" "selected paper size" "Support page must explain matching printer paper size"
check_contains "docs/support.html" "Limited Photos Access" "Support page must explain Photos permission troubleshooting"
check_contains "docs/support.html" "0-6 inch marks" "Support page must include a practical size verification step"
check_contains "docs/support.html" "GitHub Issues" "Support page must label the public support contact channel"
check_file "Scripts/generate_public_pages_readiness_report.sh" "Public pages readiness report generator is required"
if [[ -f "Scripts/generate_public_pages_readiness_report.sh" && ! -x "Scripts/generate_public_pages_readiness_report.sh" ]]; then
  printf 'FAIL: Public pages readiness report generator must be executable (Scripts/generate_public_pages_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_public_pages_readiness_report.sh" "privacy-policy.html" "Public pages report must check the public privacy policy URL"
check_contains "Scripts/generate_public_pages_readiness_report.sh" "support.html" "Public pages report must check the public support URL"
check_contains "Scripts/generate_public_pages_readiness_report.sh" "curl" "Public pages report must verify deployed page reachability"
check_contains "Scripts/generate_public_pages_readiness_report.sh" "FreePrint Studio Privacy Policy" "Public pages report must verify privacy policy body text"
check_contains "Scripts/generate_public_pages_readiness_report.sh" "FreePrint Studio Support" "Public pages report must verify support page body text"
check_file "Scripts/validate_public_pages.sh" "Public pages strict validator is required"
if [[ -f "Scripts/validate_public_pages.sh" && ! -x "Scripts/validate_public_pages.sh" ]]; then
  printf 'FAIL: Public pages strict validator must be executable (Scripts/validate_public_pages.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_public_pages.sh" "privacy-policy.html" "Public pages validator must check the public privacy policy URL"
check_contains "Scripts/validate_public_pages.sh" "support.html" "Public pages validator must check the public support URL"
check_contains "Scripts/validate_public_pages.sh" "FreePrint Studio Privacy Policy" "Public pages validator must verify privacy policy body text"
check_contains "Scripts/validate_public_pages.sh" "FreePrint Studio Support" "Public pages validator must verify support page body text"
check_contains "Scripts/validate_public_pages.sh" "Public pages validation failed" "Public pages validator must fail when public pages are not ready"
check_file "Scripts/check_github_pages_source.sh" "GitHub Pages publishing source validator is required"
if [[ -f "Scripts/check_github_pages_source.sh" && ! -x "Scripts/check_github_pages_source.sh" ]]; then
  printf 'FAIL: GitHub Pages publishing source validator must be executable (Scripts/check_github_pages_source.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/check_github_pages_source.sh" "\"build_type\"" "GitHub Pages source validator must inspect the Pages build_type"
check_contains "Scripts/check_github_pages_source.sh" "\"workflow\"" "GitHub Pages source validator must require custom workflow publishing"
check_contains "Scripts/check_app_store_readiness.sh" "check_github_pages_source.sh" "Readiness audit must verify GitHub Pages uses custom workflow publishing"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "GitHub Pages Source" "Submission packet must classify GitHub Pages source external actions"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "GitHub Pages build_type" "Submission packet must track GitHub Pages source affected field"
check_contains "Scripts/validate_app_store_submission_packet.sh" "check_github_pages_source.sh" "Submission packet validator must track GitHub Pages source validation actions"
check_contains "Scripts/verify_release.sh" "generate_public_pages_readiness_report.sh" "Release verification must expose public pages readiness report generation"
check_contains "Scripts/verify_release.sh" "public-pages-report" "Release verification must provide a public-pages-report command"
check_contains "Scripts/verify_release.sh" "validate_public_pages.sh" "Release verification must expose strict public pages validation"
check_contains "Scripts/verify_release.sh" "public-pages)" "Release verification must provide a public-pages validation command"
check_file "AppStore/commercial-configuration.md" "App Store commercial configuration draft is required"
check_contains "AppStore/commercial-configuration.md" "Price: Free" "Commercial configuration must state the MVP price"
check_contains "AppStore/commercial-configuration.md" "Availability: All App Store countries or regions" "Commercial configuration must state availability scope"
check_contains "AppStore/commercial-configuration.md" "In-App Purchases: None" "Commercial configuration must state no in-app purchases"
check_contains "AppStore/commercial-configuration.md" "Subscriptions: None" "Commercial configuration must state no subscriptions"
check_contains "AppStore/commercial-configuration.md" "Advertising: None" "Commercial configuration must state no advertising"
check_contains "AppStore/commercial-configuration.md" "Manual App Store Connect fields" "Commercial configuration must identify manual App Store Connect fields"
check_file "AppStore/review-guideline-audit.md" "App Review guideline self-audit is required"
check_contains "AppStore/review-guideline-audit.md" "https://developer.apple.com/app-store/review/guidelines/" "Review audit must link the official App Review Guidelines"
check_contains "AppStore/review-guideline-audit.md" "https://developer.apple.com/app-store/app-privacy-details/" "Review audit must link the official App Privacy Details reference"
check_contains "AppStore/review-guideline-audit.md" "https://developer.apple.com/app-store/submitting/" "Review audit must link the official App Store submission reference"
check_contains "AppStore/review-guideline-audit.md" "2.1 App Completeness" "Review audit must cover App Completeness"
check_contains "AppStore/review-guideline-audit.md" "5.1 Privacy" "Review audit must cover privacy"
check_contains "AppStore/review-guideline-audit.md" "3.1 Payments" "Review audit must cover payments and in-app purchases"
check_contains "AppStore/review-guideline-audit.md" "4.2 Minimum Functionality" "Review audit must cover minimum functionality"
check_contains "AppStore/review-guideline-audit.md" "Scripts/verify_release.sh store-ready" "Review audit must cite the local store-ready evidence"
check_contains "AppStore/review-guideline-audit.md" "Scripts/check_app_store_readiness.sh" "Review audit must cite readiness audit evidence"
check_contains "AppStore/review-guideline-audit.md" "Config/manual-release-verification.env" "Review audit must identify real-device evidence"
check_contains "AppStore/review-guideline-audit.md" "AppStore/commercial-configuration.md" "Review audit must cite commercial configuration evidence"
check_contains "AppStore/review-guideline-audit.md" "PrivacyInfo.xcprivacy" "Review audit must cite privacy manifest evidence"
check_contains "AppStore/review-guideline-audit.md" "Xcode 26" "Review audit must cover current SDK submission readiness"
check_not_contains "AppStore/review-guideline-audit.md" "DEVELOPMENT_TEAM_ID=\\.\\.\\." "Review audit archive commands must use shell-safe Team ID placeholders"
check_contains "AppStore/review-guideline-audit.md" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Review audit must show a shell-safe archive command placeholder"
check_file "Config/ExportOptions-AppStore.plist" "App Store export options plist is required"
check_contains "Config/ExportOptions-AppStore.plist" "app-store-connect" "Export options must use the current App Store Connect export method"
check_file "Config/release.env.example" "Release environment template is required"
check_contains "Config/release.env.example" "DEVELOPMENT_TEAM_ID" "Release environment template must document the Apple Developer Team ID"
check_contains "Config/release.env.example" "# DEVELOPMENT_TEAM_ID=" "Release environment template must keep placeholder Team ID commented out"
check_contains "Config/release.env.example" "# DEVELOPMENT_TEAM_ID=YOURTEAMID" "Release environment template must use the validated Team ID placeholder"
check_contains "Config/release.env.example" "ASC_KEY_ID" "Release environment template must document App Store Connect API key variables"
check_contains "Config/release.env.example" "APP_REVIEW_CONTACT_EMAIL" "Release environment template must document App Review contact variables"
check_contains "Config/release.env.example" "CONFIRM_UPLOAD_APP_PRIVACY" "Release environment template must document the App Privacy Details upload guard"
check_contains "Config/release.env.example" "CONFIRM_SUBMIT_FOR_REVIEW" "Release environment template must document the final App Review submission guard"
check_contains ".gitignore" "Config/release.env" "Filled release environment files must stay untracked"
check_contains ".gitignore" "Config/manual-release-verification.env" "Manual release verification evidence must stay untracked"
check_contains ".gitignore" "*.p8" "App Store Connect private keys must stay untracked"
check_contains ".gitignore" "fastlane-api-key.json" "App Store Connect API JSON secrets must stay untracked"
check_contains ".gitignore" "*.ipa" "Exported App Store IPA files must stay untracked"
check_contains ".gitignore" "*.xcarchive" "Xcode archive bundles must stay untracked"
check_contains ".gitignore" "*.mobileprovision" "Provisioning profiles must stay untracked"
check_contains ".gitignore" "*.p12" "Signing certificate bundles must stay untracked"
check_file "Config/manual-release-verification.env.example" "Manual release verification evidence template is required"
check_contains "Config/manual-release-verification.env.example" "MANUAL_REAL_IPHONE_PHOTOS_IMPORT" "Manual verification template must include real iPhone Photos import evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_AIRPRINT_EXACT_SIZE" "Manual verification template must include AirPrint exact-size evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_AIRPRINT_RULER_TARGET_INCHES" "Manual verification template must include AirPrint target ruler length evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Manual verification template must include AirPrint measured ruler length evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_TESTFLIGHT_INSTALL" "Manual verification template must include TestFlight install evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_IPAD_TESTFLIGHT_DEVICE" "Manual verification template must include iPad TestFlight device evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_IPAD_TESTFLIGHT_LAYOUT" "Manual verification template must include iPad TestFlight layout evidence"
check_contains "Config/manual-release-verification.env.example" "MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW" "Manual verification template must include iPad TestFlight print workflow evidence"
check_file "AppStore/release-inputs-worksheet.md" "Release input worksheet is required for private App Store handoff values"
check_contains "AppStore/release-inputs-worksheet.md" "DEVELOPMENT_TEAM_ID" "Release input worksheet must cover Apple Developer Team ID"
check_contains "AppStore/release-inputs-worksheet.md" "APP_REVIEW_CONTACT_EMAIL" "Release input worksheet must cover App Review contact values"
check_contains "AppStore/release-inputs-worksheet.md" "ASC_KEY_ID" "Release input worksheet must cover App Store Connect API credentials"
check_contains "AppStore/release-inputs-worksheet.md" "Apple Distribution" "Release input worksheet must cover distribution signing assets"
check_contains "AppStore/release-inputs-worksheet.md" "MANUAL_AIRPRINT_EXACT_SIZE" "Release input worksheet must cover AirPrint exact-size evidence"
check_contains "AppStore/release-inputs-worksheet.md" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Release input worksheet must cover AirPrint measured ruler evidence"
check_contains "AppStore/release-inputs-worksheet.md" "MANUAL_IPAD_TESTFLIGHT_LAYOUT" "Release input worksheet must cover iPad TestFlight layout evidence"
check_contains "AppStore/release-inputs-worksheet.md" "same APP_STORE_BUILD_NUMBER" "Release input worksheet must require evidence for the selected App Store build"
check_not_contains "AppStore/release-inputs-worksheet.md" "APP_STORE_BUILD_NUMBER=1" "Release input worksheet must not hard-code a selected App Store build number"
check_not_contains "AppStore/release-inputs-worksheet.md" "APP_STORE_BUILD_NUMBER=<" "Release input worksheet must use shell-safe selected build placeholders"
check_contains "AppStore/release-inputs-worksheet.md" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" "Release input worksheet must validate manual evidence against the selected App Store build"
check_contains "AppStore/release-inputs-worksheet.md" "Scripts/preflight_metadata_upload.sh" "Release input worksheet must include the metadata upload preflight command"
check_contains "AppStore/release-inputs-worksheet.md" "Scripts/run_fastlane.sh ios metadata" "Release input worksheet must include the metadata upload command"
check_contains "AppStore/release-inputs-worksheet.md" "Scripts/preflight_app_privacy_upload.sh" "Release input worksheet must include the App Privacy Details upload preflight command"
check_contains "AppStore/release-inputs-worksheet.md" "Scripts/run_fastlane.sh ios privacy_details" "Release input worksheet must include the App Privacy Details upload command"
check_contains "AppStore/release-inputs-worksheet.md" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh" "Release input worksheet must include the App Privacy Details App Store Connect confirmation command"
check_contains "AppStore/release-inputs-worksheet.md" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "Release input worksheet must submit the selected App Store build"
check_file "Scripts/validate_manual_release_verification.sh" "Manual release verification evidence validation script is required"
if [[ ! -x "Scripts/validate_manual_release_verification.sh" ]]; then
  printf 'FAIL: Manual release verification script must be executable (Scripts/validate_manual_release_verification.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_manual_release_verification.sh" "Config/manual-release-verification.env" "Manual verification script must load the untracked evidence file"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_REAL_IPHONE_PHOTOS_IMPORT" "Manual verification script must require real iPhone Photos import evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_AIRPRINT_EXACT_SIZE" "Manual verification script must require AirPrint exact-size evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "DEFAULT_AIRPRINT_RULER_TARGET_INCHES" "Manual verification script must default the built-in AirPrint target ruler length"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Manual verification script must require AirPrint measured ruler evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_TESTFLIGHT_INSTALL" "Manual verification script must require TestFlight install evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_TESTFLIGHT_BUILD_NUMBER" "Manual verification script must require the tested TestFlight build number"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_IPAD_TESTFLIGHT_DEVICE" "Manual verification script must require iPad TestFlight device evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_IPAD_TESTFLIGHT_LAYOUT" "Manual verification script must require iPad TestFlight layout evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW" "Manual verification script must require iPad TestFlight print workflow evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "APP_STORE_BUILD_NUMBER" "Manual verification script must compare tested TestFlight build with the selected App Store build"
check_contains "Scripts/validate_manual_release_verification.sh" "source Scripts/load_release_env.sh" "Manual verification script must load release.env before comparing the selected App Store build"
check_contains "Scripts/validate_manual_release_verification.sh" "PROCESSED_BUILD_NUMBER" "Manual verification script must reject selected-build placeholder values"
check_contains "Scripts/validate_manual_release_verification.sh" "Selected App Store build still looks like a placeholder" "Manual verification script must validate the selected App Store build before comparing evidence"
check_contains "Scripts/validate_manual_release_verification.sh" "permissions are too broad" "Manual verification must reject overly broad manual evidence file permissions before sourcing private values"
check_contains "Scripts/validate_manual_release_verification.sh" "chmod 600" "Manual verification must explain how to fix broad manual evidence file permissions"
manual_release_missing_evidence_test_dir="$(mktemp -d)"
manual_release_missing_evidence_log="$manual_release_missing_evidence_test_dir/manual-release-verification-missing.log"
if MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_missing_evidence_test_dir/missing.env" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_missing_evidence_log" 2>&1; then
  printf 'FAIL: Manual verification must reject a missing evidence file\n'
  failures=$((failures + 1))
elif ! grep -q 'MANUAL_REAL_IPHONE_PHOTOS_IMPORT' "$manual_release_missing_evidence_log" \
  || ! grep -q 'MANUAL_TESTFLIGHT_PRINT_WORKFLOW' "$manual_release_missing_evidence_log" \
  || ! grep -q 'MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW' "$manual_release_missing_evidence_log"; then
  printf 'FAIL: Manual verification missing-file output must list required manual evidence fields\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_missing_evidence_test_dir"
manual_release_airprint_measurement_test_dir="$(mktemp -d)"
manual_release_airprint_measurement_evidence="$manual_release_airprint_measurement_test_dir/manual-release-verification.env"
manual_release_airprint_measurement_log="$manual_release_airprint_measurement_test_dir/manual-release-verification-airprint-measurement.log"
today="$(date +%F)"
cat >"$manual_release_airprint_measurement_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_airprint_measurement_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_airprint_measurement_log" 2>&1; then
  printf 'FAIL: Manual verification must require AirPrint measured ruler evidence, not only a pass flag\n'
  failures=$((failures + 1))
elif grep -q 'AirPrint ruler target length is missing (MANUAL_AIRPRINT_RULER_TARGET_INCHES)' "$manual_release_airprint_measurement_log" \
  || ! grep -q 'AirPrint ruler measured length is missing (MANUAL_AIRPRINT_RULER_MEASURED_INCHES)' "$manual_release_airprint_measurement_log"; then
  printf 'FAIL: Manual verification missing AirPrint measurement failure should require measured length but default the built-in target length\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_airprint_measurement_test_dir"
manual_release_airprint_default_target_test_dir="$(mktemp -d)"
manual_release_airprint_default_target_evidence="$manual_release_airprint_default_target_test_dir/manual-release-verification.env"
manual_release_airprint_default_target_log="$manual_release_airprint_default_target_test_dir/manual-release-verification-airprint-default-target.log"
cat >"$manual_release_airprint_default_target_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if ! APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_airprint_default_target_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_airprint_default_target_log" 2>&1; then
  printf 'FAIL: Manual verification should default the built-in AirPrint target ruler length when measured evidence is present\n'
  failures=$((failures + 1))
elif ! grep -q 'AirPrint ruler target length defaulted to 6 inch' "$manual_release_airprint_default_target_log"; then
  printf 'FAIL: Manual verification should report the defaulted built-in AirPrint target ruler length\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_airprint_default_target_test_dir"
manual_release_missing_ipad_test_dir="$(mktemp -d)"
manual_release_missing_ipad_evidence="$manual_release_missing_ipad_test_dir/manual-release-verification.env"
manual_release_missing_ipad_log="$manual_release_missing_ipad_test_dir/manual-release-verification-missing-ipad.log"
cat >"$manual_release_missing_ipad_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_missing_ipad_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_missing_ipad_log" 2>&1; then
  printf 'FAIL: Manual verification must require iPad TestFlight evidence when the app supports iPad\n'
  failures=$((failures + 1))
elif ! grep -q 'iPad TestFlight device is missing (MANUAL_IPAD_TESTFLIGHT_DEVICE)' "$manual_release_missing_ipad_log" \
  || ! grep -q 'iPad TestFlight layout result is missing (MANUAL_IPAD_TESTFLIGHT_LAYOUT=pass)' "$manual_release_missing_ipad_log" \
  || ! grep -q 'iPad TestFlight print workflow result is missing (MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW=pass)' "$manual_release_missing_ipad_log"; then
  printf 'FAIL: Manual verification missing-iPad failure should identify the required iPad TestFlight evidence fields\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_missing_ipad_test_dir"
manual_release_wrong_ipad_device_test_dir="$(mktemp -d)"
manual_release_wrong_ipad_device_evidence="$manual_release_wrong_ipad_device_test_dir/manual-release-verification.env"
manual_release_wrong_ipad_device_log="$manual_release_wrong_ipad_device_test_dir/manual-release-verification-wrong-ipad-device.log"
cat >"$manual_release_wrong_ipad_device_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_wrong_ipad_device_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_wrong_ipad_device_log" 2>&1; then
  printf 'FAIL: Manual verification must reject non-iPad evidence in the iPad TestFlight device field\n'
  failures=$((failures + 1))
elif ! grep -q 'iPad TestFlight device must be a physical iPad device' "$manual_release_wrong_ipad_device_log"; then
  printf 'FAIL: Manual verification wrong-iPad-device failure should identify the iPad device field\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_wrong_ipad_device_test_dir"
manual_release_ios_version_test_dir="$(mktemp -d)"
manual_release_ios_version_evidence="$manual_release_ios_version_test_dir/manual-release-verification.env"
manual_release_ios_version_log="$manual_release_ios_version_test_dir/manual-release-verification-ios-version.log"
cat >"$manual_release_ios_version_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="latest-iOS"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_ios_version_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_ios_version_log" 2>&1; then
  printf 'FAIL: Manual verification must reject non-numeric real iPhone iOS version evidence\n'
  failures=$((failures + 1))
elif ! grep -q 'Real iPhone iOS version must be a numeric iOS version' "$manual_release_ios_version_log"; then
  printf 'FAIL: Manual verification iOS-version failure should identify the malformed iOS version field\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_ios_version_test_dir"
manual_release_airprint_tolerance_test_dir="$(mktemp -d)"
manual_release_airprint_tolerance_evidence="$manual_release_airprint_tolerance_test_dir/manual-release-verification.env"
manual_release_airprint_tolerance_log="$manual_release_airprint_tolerance_test_dir/manual-release-verification-airprint-tolerance.log"
cat >"$manual_release_airprint_tolerance_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Office AirPrint Printer"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="5.75"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_airprint_tolerance_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_airprint_tolerance_log" 2>&1; then
  printf 'FAIL: Manual verification must reject AirPrint measured ruler evidence outside tolerance\n'
  failures=$((failures + 1))
elif ! grep -q 'AirPrint measured ruler length differs from target' "$manual_release_airprint_tolerance_log"; then
  printf 'FAIL: Manual verification AirPrint tolerance failure should identify the measured ruler length mismatch\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_airprint_tolerance_test_dir"
manual_release_selected_build_test_dir="$(mktemp -d)"
manual_release_selected_build_env="$manual_release_selected_build_test_dir/release.env"
manual_release_selected_build_evidence="$manual_release_selected_build_test_dir/manual-release-verification.env"
manual_release_selected_build_log="$manual_release_selected_build_test_dir/manual-release-verification.log"
today="$(date +%F)"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=42' >"$manual_release_selected_build_env"
cat >"$manual_release_selected_build_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="41"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if env -u APP_STORE_BUILD_NUMBER \
  RELEASE_ENV_PATH="$manual_release_selected_build_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_selected_build_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_selected_build_log" 2>&1; then
  printf 'FAIL: Manual verification must compare TestFlight evidence with APP_STORE_BUILD_NUMBER loaded from release.env\n'
  failures=$((failures + 1))
elif ! grep -q 'does not match selected APP_STORE_BUILD_NUMBER 42' "$manual_release_selected_build_log"; then
  printf 'FAIL: Manual verification mismatch should name the selected APP_STORE_BUILD_NUMBER loaded from release.env\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_selected_build_test_dir"
manual_release_placeholder_build_test_dir="$(mktemp -d)"
manual_release_placeholder_build_evidence="$manual_release_placeholder_build_test_dir/manual-release-verification.env"
manual_release_placeholder_build_log="$manual_release_placeholder_build_test_dir/manual-release-verification-placeholder.log"
today="$(date +%F)"
cat >"$manual_release_placeholder_build_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="PROCESSED_BUILD_NUMBER"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_placeholder_build_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_placeholder_build_log" 2>&1; then
  printf 'FAIL: Manual verification must reject PROCESSED_BUILD_NUMBER placeholders in selected and tested build numbers\n'
  failures=$((failures + 1))
elif ! grep -q 'PROCESSED_BUILD_NUMBER' "$manual_release_placeholder_build_log"; then
  printf 'FAIL: Manual verification placeholder-build failure should name PROCESSED_BUILD_NUMBER\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_placeholder_build_test_dir"
manual_release_lowercase_placeholder_test_dir="$(mktemp -d)"
manual_release_lowercase_placeholder_evidence="$manual_release_lowercase_placeholder_test_dir/manual-release-verification.env"
manual_release_lowercase_placeholder_log="$manual_release_lowercase_placeholder_test_dir/manual-release-verification-lowercase-placeholder.log"
cat >"$manual_release_lowercase_placeholder_evidence" <<EOF
MANUAL_VERIFIER_NAME="todo"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_lowercase_placeholder_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_lowercase_placeholder_log" 2>&1; then
  printf 'FAIL: Manual verification must reject lowercase placeholder evidence values\n'
  failures=$((failures + 1))
elif ! grep -q 'Manual verifier still looks like a placeholder' "$manual_release_lowercase_placeholder_log"; then
  printf 'FAIL: Manual verification lowercase placeholder failure should identify the placeholder field\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_lowercase_placeholder_test_dir"
manual_release_simulator_device_test_dir="$(mktemp -d)"
manual_release_simulator_device_evidence="$manual_release_simulator_device_test_dir/manual-release-verification.env"
manual_release_simulator_device_log="$manual_release_simulator_device_test_dir/manual-release-verification-simulator-device.log"
cat >"$manual_release_simulator_device_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15 Simulator"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15 Simulator"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
if APP_STORE_BUILD_NUMBER=42 \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_simulator_device_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_simulator_device_log" 2>&1; then
  printf 'FAIL: Manual verification must reject simulator device evidence for real iPhone and TestFlight checks\n'
  failures=$((failures + 1))
elif ! grep -q 'Real iPhone model must be a physical device, not a simulator' "$manual_release_simulator_device_log" \
  || ! grep -q 'TestFlight device must be a physical device, not a simulator' "$manual_release_simulator_device_log"; then
  printf 'FAIL: Manual verification simulator-device failure should identify the real-device fields\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_simulator_device_test_dir"
manual_release_loose_evidence_test_dir="$(mktemp -d)"
manual_release_loose_evidence="$manual_release_loose_evidence_test_dir/manual-release-verification.env"
manual_release_loose_evidence_log="$manual_release_loose_evidence_test_dir/manual-release-verification-loose.log"
cat >"$manual_release_loose_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
chmod 644 "$manual_release_loose_evidence"
if APP_STORE_BUILD_NUMBER=42 \
  RELEASE_ENV_PATH="$manual_release_loose_evidence_test_dir/missing-release.env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_loose_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_loose_evidence_log" 2>&1; then
  printf 'FAIL: Manual verification must reject overly broad manual evidence file permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'Manual release verification evidence permissions are too broad' "$manual_release_loose_evidence_log"; then
  printf 'FAIL: Manual verification should identify broad manual evidence file permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'chmod 600' "$manual_release_loose_evidence_log"; then
  printf 'FAIL: Manual verification broad-permission output should include chmod 600 guidance\n'
  failures=$((failures + 1))
elif grep -Fq "$manual_release_loose_evidence" "$manual_release_loose_evidence_log"; then
  printf 'FAIL: Manual verification must not print the full loose manual evidence path\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_loose_evidence_test_dir"
manual_release_invalid_evidence_test_dir="$(mktemp -d)"
manual_release_invalid_evidence="$manual_release_invalid_evidence_test_dir/manual-release-verification.env"
manual_release_invalid_evidence_log="$manual_release_invalid_evidence_test_dir/manual-release-verification-invalid.log"
printf '%s\n' 'MANUAL_VERIFIER_NAME="Release Tester' >"$manual_release_invalid_evidence"
chmod 600 "$manual_release_invalid_evidence"
if APP_STORE_BUILD_NUMBER=42 \
  RELEASE_ENV_PATH="$manual_release_invalid_evidence_test_dir/missing-release.env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$manual_release_invalid_evidence" \
  Scripts/validate_manual_release_verification.sh >"$manual_release_invalid_evidence_log" 2>&1; then
  printf 'FAIL: Manual verification must reject invalid manual evidence shell syntax\n'
  failures=$((failures + 1))
elif ! grep -q 'Manual release verification evidence is not a valid shell env file' "$manual_release_invalid_evidence_log"; then
  printf 'FAIL: Manual verification invalid-syntax output should identify the manual evidence env file\n'
  failures=$((failures + 1))
elif ! grep -q 'Quote values that contain spaces' "$manual_release_invalid_evidence_log"; then
  printf 'FAIL: Manual verification invalid-syntax output should include quoting guidance\n'
  failures=$((failures + 1))
elif grep -Fq "$manual_release_invalid_evidence" "$manual_release_invalid_evidence_log"; then
  printf 'FAIL: Manual verification must not print the full invalid manual evidence path\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_release_invalid_evidence_test_dir"
check_contains "Scripts/check_app_store_readiness.sh" "validate_manual_release_verification.sh" "Readiness audit must validate manual release evidence"
check_contains "Scripts/verify_release.sh" "manual-verification" "Release verification must expose manual release evidence validation"
check_file "Scripts/load_release_env.sh" "Release environment loader script is required"
check_contains "Scripts/load_release_env.sh" "Config/release.env" "Release environment loader must read the untracked release.env file"
check_contains "Scripts/load_release_env.sh" "not a valid shell env file" "Release environment loader must explain invalid release.env syntax"
check_contains "Scripts/load_release_env.sh" "Quote values containing spaces" "Release environment loader must explain how to fix values containing spaces"
check_contains "Scripts/load_release_env.sh" "permissions are too broad" "Release environment loader must reject overly broad release.env permissions before sourcing private values"
check_contains "Scripts/load_release_env.sh" "chmod 600" "Release environment loader must explain how to fix broad release.env permissions"
release_env_loader_test_dir="$(mktemp -d)"
release_env_loader_test_file="$release_env_loader_test_dir/release.env"
printf '%s\n' \
  'APP_STORE_BUILD_NUMBER=' \
  'ASC_KEY_ID=file-key-id' \
  >"$release_env_loader_test_file"
if ! RELEASE_ENV_PATH="$release_env_loader_test_file" APP_STORE_BUILD_NUMBER=42 bash -c '
  set -euo pipefail
  cd "$1"
  source Scripts/load_release_env.sh
  if [[ "${APP_STORE_BUILD_NUMBER:-}" != "42" ]]; then
    exit 1
  fi
  if [[ "${ASC_KEY_ID:-}" != "file-key-id" ]]; then
    exit 1
  fi
' _ "$ROOT_DIR"; then
  printf 'FAIL: Release environment loader must preserve non-empty inline values while loading missing values from release.env\n'
  failures=$((failures + 1))
fi
release_env_loader_loose_file="$release_env_loader_test_dir/loose-release.env"
printf 'ASC_KEY_ID=file-key-id\n' >"$release_env_loader_loose_file"
chmod 644 "$release_env_loader_loose_file"
if RELEASE_ENV_PATH="$release_env_loader_loose_file" bash -c '
  set -euo pipefail
  cd "$1"
  source Scripts/load_release_env.sh
' _ "$ROOT_DIR" >"$release_env_loader_test_dir/loose-release-env.log" 2>&1; then
  printf 'FAIL: Release environment loader must reject overly broad release.env file permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'Release environment permissions are too broad' "$release_env_loader_test_dir/loose-release-env.log"; then
  printf 'FAIL: Release environment loader should identify broad release.env permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'chmod 600' "$release_env_loader_test_dir/loose-release-env.log"; then
  printf 'FAIL: Release environment loader broad-permission output should include chmod 600 guidance\n'
  failures=$((failures + 1))
elif grep -Fq "$release_env_loader_loose_file" "$release_env_loader_test_dir/loose-release-env.log"; then
  printf 'FAIL: Release environment loader must not print the full loose release.env path\n'
  failures=$((failures + 1))
fi
release_env_loader_invalid_file="$release_env_loader_test_dir/invalid-release.env"
release_env_loader_invalid_log="$release_env_loader_test_dir/invalid-release-env.log"
printf '%s\n' 'APP_REVIEW_CONTACT_FIRST_NAME="Grace' >"$release_env_loader_invalid_file"
chmod 600 "$release_env_loader_invalid_file"
if RELEASE_ENV_PATH="$release_env_loader_invalid_file" bash -c '
  set -euo pipefail
  cd "$1"
  source Scripts/load_release_env.sh
' _ "$ROOT_DIR" >"$release_env_loader_invalid_log" 2>&1; then
  printf 'FAIL: Release environment loader must reject invalid release.env shell syntax\n'
  failures=$((failures + 1))
elif ! grep -q 'Release environment is not a valid shell env file' "$release_env_loader_invalid_log"; then
  printf 'FAIL: Release environment loader invalid-syntax output should identify release.env syntax errors\n'
  failures=$((failures + 1))
elif ! grep -q 'Quote values containing spaces' "$release_env_loader_invalid_log"; then
  printf 'FAIL: Release environment loader invalid-syntax output should include quoting guidance\n'
  failures=$((failures + 1))
elif grep -Fq "$release_env_loader_invalid_file" "$release_env_loader_invalid_log"; then
  printf 'FAIL: Release environment loader must not print the full invalid release.env path\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_loader_test_dir"
check_file "Scripts/bootstrap_release_env.sh" "Release environment bootstrap script is required"
if [[ ! -x "Scripts/bootstrap_release_env.sh" ]]; then
  printf 'FAIL: Release environment bootstrap script must be executable (Scripts/bootstrap_release_env.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/bootstrap_release_env.sh" "Config/release.env" "Release environment bootstrap must target the untracked release.env file"
check_contains "Scripts/bootstrap_release_env.sh" "git check-ignore" "Release environment bootstrap must verify release.env stays ignored"
check_contains "Scripts/bootstrap_release_env.sh" "chmod 600" "Release environment bootstrap must protect private release.env permissions"
check_file "Scripts/bootstrap_release_inputs.sh" "Combined private release input bootstrap script is required"
if [[ ! -x "Scripts/bootstrap_release_inputs.sh" ]]; then
  printf 'FAIL: Combined private release input bootstrap script must be executable (Scripts/bootstrap_release_inputs.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/bootstrap_release_env.sh" "Combined private release input bootstrap must reuse the release.env bootstrap"
check_contains "Scripts/bootstrap_release_inputs.sh" "Config/manual-release-verification.env" "Combined private release input bootstrap must create the manual verification evidence file"
check_contains "Scripts/bootstrap_release_inputs.sh" "git check-ignore" "Combined private release input bootstrap must verify private files stay ignored"
check_contains "Scripts/bootstrap_release_inputs.sh" "chmod 600" "Combined private release input bootstrap must protect private release input files"
check_not_contains "Scripts/bootstrap_release_inputs.sh" "APP_STORE_BUILD_NUMBER=<" "Combined private release input bootstrap must use shell-safe selected build placeholders"
check_contains "Scripts/bootstrap_release_inputs.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" "Combined private release input bootstrap must validate manual evidence against the selected App Store build"
check_file "Scripts/print_release_input_status.sh" "Redacted release input status script is required"
if [[ ! -x "Scripts/print_release_input_status.sh" ]]; then
  printf 'FAIL: Redacted release input status script must be executable (Scripts/print_release_input_status.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/print_release_input_status.sh" "APP_REVIEW_CONTACT_EMAIL" "Release input status must summarize App Review contact configuration"
check_contains "Scripts/print_release_input_status.sh" "DEVELOPMENT_TEAM_ID" "Release input status must summarize Apple Developer Team configuration"
check_contains "Scripts/print_release_input_status.sh" "ASC_KEY_ID" "Release input status must summarize App Store Connect API credentials"
check_contains "Scripts/print_release_input_status.sh" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Release input status must summarize AirPrint measured ruler evidence"
check_contains "Scripts/print_release_input_status.sh" "DEFAULT_AIRPRINT_RULER_TARGET_INCHES" "Release input status must default the built-in AirPrint target ruler length"
check_contains "Scripts/print_release_input_status.sh" "MANUAL_TESTFLIGHT_BUILD_NUMBER" "Release input status must summarize tested TestFlight build evidence"
check_contains "Scripts/print_release_input_status.sh" "Final Submission Guards" "Release input status must summarize final App Review submission guards"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER is configured" "Release input status must show whether the selected App Store build is configured"
check_contains "Scripts/print_release_input_status.sh" "CONFIRM_SUBMIT_FOR_REVIEW" "Release input status must show whether explicit App Review submission confirmation is configured"
check_contains "Scripts/print_release_input_status.sh" "git check-ignore" "Release input status must confirm private files stay ignored"
check_contains "Scripts/print_release_input_status.sh" "--strict" "Release input status must offer a strict mode for handoff gating"
check_contains "Scripts/print_release_input_status.sh" "does not print private values" "Release input status must explicitly avoid printing private values"
check_contains "Scripts/print_release_input_status.sh" "Scripts/check_app_store_connect_credentials.sh" "Release input status must run strict App Store Connect credential validation"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER=%s Scripts/validate_manual_release_verification.sh" "Release input status next commands must validate manual evidence against the selected App Store build"
check_contains "Scripts/print_release_input_status.sh" "Scripts/preflight_metadata_upload.sh" "Release input status next commands must include the metadata upload preflight"
check_contains "Scripts/print_release_input_status.sh" "Scripts/run_fastlane.sh ios metadata" "Release input status next commands must include metadata upload"
check_contains "Scripts/print_release_input_status.sh" "Scripts/preflight_app_privacy_upload.sh" "Release input status next commands must include the App Privacy Details upload preflight"
check_contains "Scripts/print_release_input_status.sh" "Scripts/run_fastlane.sh ios privacy_details" "Release input status next commands must include App Privacy Details upload"
check_contains "Scripts/print_release_input_status.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh" "Release input status next commands must include App Privacy Details App Store Connect confirmation"
check_contains "Scripts/print_release_input_status.sh" "Scripts/verify_release.sh testflight-dependencies-preflight" "Release input status next commands must include the TestFlight upload dependency preflight"
check_contains "Scripts/print_release_input_status.sh" "Scripts/preflight_app_store_archive.sh" "Release input status next commands must include the App Store archive preflight"
check_contains "Scripts/print_release_input_status.sh" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Release input status next commands must include the guarded archive command"
check_contains "Scripts/print_release_input_status.sh" "Scripts/preflight_testflight_upload.sh" "Release input status next commands must include the TestFlight upload preflight"
check_contains "Scripts/print_release_input_status.sh" "Scripts/run_fastlane.sh ios upload_testflight" "Release input status next commands must include TestFlight upload"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER=%s Scripts/run_fastlane.sh ios app_store_connect_state" "Release input status next commands must verify the selected App Store Connect build"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER=%s Scripts/preflight_app_review_submission.sh" "Release input status next commands must include the final App Review preflight"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "Release input status next commands must include the guarded final App Review submission"
check_contains "Scripts/print_release_input_status.sh" "Missing Release Input Fields" "Release input status must print a field-level missing input checklist"
check_contains "Scripts/print_release_input_status.sh" "MISSING_FIELD:" "Release input status must label individual missing input fields without private values"
check_contains "Scripts/print_release_input_status.sh" "APP_REVIEW_CONTACT_FIRST_NAME" "Release input status missing field checklist must include App Review contact fields"
check_contains "Scripts/print_release_input_status.sh" "MANUAL_REAL_IPHONE_PHOTOS_IMPORT" "Release input status missing field checklist must include manual result fields"
check_contains "Scripts/print_release_input_status.sh" "Apple Distribution certificate" "Release input status missing field checklist must include signing certificate status"
check_contains "Scripts/print_release_input_status.sh" "APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH" "Release input status missing field checklist must include App Store Connect credential alternatives"
check_not_contains "Scripts/print_release_input_status.sh" "APP_STORE_BUILD_NUMBER:-<" "Release input status must use a shell-safe selected-build placeholder when APP_STORE_BUILD_NUMBER is missing"
check_contains "Scripts/print_release_input_status.sh" "PROCESSED_BUILD_NUMBER" "Release input status must show a selected-build placeholder when APP_STORE_BUILD_NUMBER is missing"
release_input_placeholder_build_test_dir="$(mktemp -d)"
release_input_placeholder_build_env="$release_input_placeholder_build_test_dir/release.env"
release_input_placeholder_build_manual="$release_input_placeholder_build_test_dir/manual-release-verification.env"
release_input_placeholder_build_log="$release_input_placeholder_build_test_dir/release-input-status.log"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER' >"$release_input_placeholder_build_env"
printf '%s\n' '# intentionally blank manual evidence for release input status test' >"$release_input_placeholder_build_manual"
if ! RELEASE_ENV_PATH="$release_input_placeholder_build_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_placeholder_build_manual" \
  Scripts/print_release_input_status.sh >"$release_input_placeholder_build_log" 2>&1; then
  printf 'FAIL: Release input status should print redacted placeholder-build status without crashing\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder value' "$release_input_placeholder_build_log"; then
  printf 'FAIL: Release input status must flag PROCESSED_BUILD_NUMBER as a selected-build placeholder\n'
  failures=$((failures + 1))
elif grep -q 'OK: APP_STORE_BUILD_NUMBER is configured for final App Review submission' "$release_input_placeholder_build_log"; then
  printf 'FAIL: Release input status must not mark a selected-build placeholder as configured\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_placeholder_build_test_dir"
release_input_todo_build_test_dir="$(mktemp -d)"
release_input_todo_build_env="$release_input_todo_build_test_dir/release.env"
release_input_todo_build_manual="$release_input_todo_build_test_dir/manual-release-verification.env"
release_input_todo_build_log="$release_input_todo_build_test_dir/release-input-status.log"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=TODO' >"$release_input_todo_build_env"
printf '%s\n' '# intentionally blank manual evidence for release input status test' >"$release_input_todo_build_manual"
if ! RELEASE_ENV_PATH="$release_input_todo_build_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_todo_build_manual" \
  Scripts/print_release_input_status.sh >"$release_input_todo_build_log" 2>&1; then
  printf 'FAIL: Release input status should print redacted TODO-build status without crashing\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder value' "$release_input_todo_build_log"; then
  printf 'FAIL: Release input status must flag TODO as a selected-build placeholder\n'
  failures=$((failures + 1))
elif grep -q 'OK: APP_STORE_BUILD_NUMBER is configured for final App Review submission' "$release_input_todo_build_log"; then
  printf 'FAIL: Release input status must not mark a TODO selected build as configured\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_todo_build_test_dir"
release_input_lowercase_todo_build_test_dir="$(mktemp -d)"
release_input_lowercase_todo_build_env="$release_input_lowercase_todo_build_test_dir/release.env"
release_input_lowercase_todo_build_manual="$release_input_lowercase_todo_build_test_dir/manual-release-verification.env"
release_input_lowercase_todo_build_log="$release_input_lowercase_todo_build_test_dir/release-input-status.log"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=todo' >"$release_input_lowercase_todo_build_env"
printf '%s\n' '# intentionally blank manual evidence for release input status test' >"$release_input_lowercase_todo_build_manual"
if ! RELEASE_ENV_PATH="$release_input_lowercase_todo_build_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_lowercase_todo_build_manual" \
  Scripts/print_release_input_status.sh >"$release_input_lowercase_todo_build_log" 2>&1; then
  printf 'FAIL: Release input status should print redacted lowercase todo-build status without crashing\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder value' "$release_input_lowercase_todo_build_log"; then
  printf 'FAIL: Release input status must flag lowercase todo as a selected-build placeholder\n'
  failures=$((failures + 1))
elif grep -q 'OK: APP_STORE_BUILD_NUMBER is configured for final App Review submission' "$release_input_lowercase_todo_build_log"; then
  printf 'FAIL: Release input status must not mark a lowercase todo selected build as configured\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_lowercase_todo_build_test_dir"
for selected_build_handoff_path in \
  README.md \
  AppStore/release-inputs-worksheet.md \
  Scripts/bootstrap_release_inputs.sh \
  Scripts/print_release_input_status.sh \
  Scripts/generate_app_store_connect_readiness_report.sh \
  Scripts/generate_manual_release_readiness_report.sh \
  Scripts/prepare_app_store_submission_packet.sh \
  Scripts/generate_app_review_submission_readiness_report.sh \
  Scripts/generate_manual_release_evidence_form.sh \
  Scripts/generate_app_review_contact_readiness_report.sh
do
  check_not_contains "$selected_build_handoff_path" "APP_STORE_BUILD_NUMBER=<" "Release handoff commands must use shell-safe selected build placeholders"
done
release_input_status_external_dir="$(mktemp -d)"
release_input_status_external_env="$release_input_status_external_dir/release.env"
release_input_status_external_manual="$release_input_status_external_dir/manual-release-verification.env"
release_input_status_external_log="$release_input_status_external_dir/status.log"
: >"$release_input_status_external_env"
: >"$release_input_status_external_manual"
if RELEASE_ENV_PATH="$release_input_status_external_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_external_manual" \
  APP_STORE_BUILD_NUMBER=42 \
  CONFIRM_SUBMIT_FOR_REVIEW=1 \
  Scripts/print_release_input_status.sh >"$release_input_status_external_log" 2>&1; then
  if grep -Eq 'fatal:|outside repository' "$release_input_status_external_log"; then
    printf 'FAIL: Release input status must not print git fatal noise for private files outside the repository\n'
    failures=$((failures + 1))
  fi
else
  printf 'FAIL: Release input status must tolerate private release input file paths outside the repository\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_external_dir"
release_input_status_missing_fields_dir="$(mktemp -d)"
release_input_status_missing_fields_env="$release_input_status_missing_fields_dir/release.env"
release_input_status_missing_fields_manual="$release_input_status_missing_fields_dir/manual-release-verification.env"
release_input_status_missing_fields_log="$release_input_status_missing_fields_dir/status.log"
: >"$release_input_status_missing_fields_env"
: >"$release_input_status_missing_fields_manual"
RELEASE_ENV_PATH="$release_input_status_missing_fields_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_missing_fields_manual" \
  Scripts/print_release_input_status.sh >"$release_input_status_missing_fields_log" 2>&1 || true
for expected_missing_field in \
  "== Missing Release Input Fields ==" \
  "MISSING_FIELD: APP_REVIEW_CONTACT_FIRST_NAME" \
  "MISSING_FIELD: MANUAL_REAL_IPHONE_PHOTOS_IMPORT" \
  "MISSING_FIELD: Apple Distribution certificate" \
  "MISSING_FIELD: APP_STORE_CONNECT_API_KEY_JSON or ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH"
do
  if ! grep -q "$expected_missing_field" "$release_input_status_missing_fields_log"; then
    printf 'FAIL: Release input status missing field checklist must include %s\n' "$expected_missing_field"
    failures=$((failures + 1))
  fi
done
if grep -q "$release_input_status_missing_fields_dir" "$release_input_status_missing_fields_log"; then
  printf 'FAIL: Release input status missing field checklist must not print private release input paths\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_missing_fields_dir"
release_input_status_manual_validation_dir="$(mktemp -d)"
release_input_status_manual_validation_env="$release_input_status_manual_validation_dir/release.env"
release_input_status_manual_validation_evidence="$release_input_status_manual_validation_dir/manual-release-verification.env"
release_input_status_manual_validation_log="$release_input_status_manual_validation_dir/status.log"
today="$(date +%F)"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=42' >"$release_input_status_manual_validation_env"
cat >"$release_input_status_manual_validation_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="latest-iOS"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
RELEASE_ENV_PATH="$release_input_status_manual_validation_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_manual_validation_evidence" \
  Scripts/print_release_input_status.sh >"$release_input_status_manual_validation_log" 2>&1 || true
if ! grep -q 'Manual release evidence validation fails' "$release_input_status_manual_validation_log"; then
  printf 'FAIL: Release input status must surface strict manual evidence validation failures\n'
  failures=$((failures + 1))
fi
if grep -q 'OK: Manual real-device, AirPrint, iPad, and TestFlight evidence ready: 22/22' "$release_input_status_manual_validation_log"; then
  printf 'FAIL: Release input status must not mark manual evidence ready when strict validation fails\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_manual_validation_dir"
release_input_status_loose_manual_dir="$(mktemp -d)"
release_input_status_loose_manual_env="$release_input_status_loose_manual_dir/release.env"
release_input_status_loose_manual_evidence="$release_input_status_loose_manual_dir/manual-release-verification.env"
release_input_status_loose_manual_log="$release_input_status_loose_manual_dir/status.log"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=42' >"$release_input_status_loose_manual_env"
cat >"$release_input_status_loose_manual_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
chmod 644 "$release_input_status_loose_manual_evidence"
RELEASE_ENV_PATH="$release_input_status_loose_manual_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_loose_manual_evidence" \
  Scripts/print_release_input_status.sh >"$release_input_status_loose_manual_log" 2>&1 || true
if ! grep -q 'Manual release verification evidence permissions are too broad' "$release_input_status_loose_manual_log"; then
  printf 'FAIL: Release input status must reject broad manual evidence permissions before sourcing private values\n'
  failures=$((failures + 1))
elif ! grep -q 'chmod 600' "$release_input_status_loose_manual_log"; then
  printf 'FAIL: Release input status broad manual evidence output should include chmod 600 guidance\n'
  failures=$((failures + 1))
elif grep -Fq "$release_input_status_loose_manual_evidence" "$release_input_status_loose_manual_log"; then
  printf 'FAIL: Release input status must not print the full loose manual evidence path\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_loose_manual_dir"
release_input_status_default_target_dir="$(mktemp -d)"
release_input_status_default_target_env="$release_input_status_default_target_dir/release.env"
release_input_status_default_target_evidence="$release_input_status_default_target_dir/manual-release-verification.env"
release_input_status_default_target_log="$release_input_status_default_target_dir/status.log"
printf '%s\n' 'APP_STORE_BUILD_NUMBER=42' >"$release_input_status_default_target_env"
cat >"$release_input_status_default_target_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
RELEASE_ENV_PATH="$release_input_status_default_target_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_default_target_evidence" \
  Scripts/print_release_input_status.sh >"$release_input_status_default_target_log" 2>&1 || true
if ! grep -q 'OK: Manual real-device, AirPrint, iPad, and TestFlight evidence ready: 22/22' "$release_input_status_default_target_log"; then
  printf 'FAIL: Release input status should count the default built-in AirPrint target ruler length as ready\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_default_target_dir"
release_input_status_invalid_asc_dir="$(mktemp -d)"
release_input_status_invalid_asc_env="$release_input_status_invalid_asc_dir/release.env"
release_input_status_invalid_asc_manual="$release_input_status_invalid_asc_dir/manual-release-verification.env"
release_input_status_invalid_asc_json="$release_input_status_invalid_asc_dir/fastlane-api-key.json"
release_input_status_invalid_asc_log="$release_input_status_invalid_asc_dir/status.log"
cat >"$release_input_status_invalid_asc_json" <<EOF
{
  "key_id": "KEYID12345",
  "issuer_id": "00000000-0000-0000-0000-000000000001",
  "key_filepath": "$release_input_status_invalid_asc_dir/missing/AuthKey_KEYID12345.p8"
}
EOF
printf 'APP_STORE_CONNECT_API_KEY_JSON=%q\n' "$release_input_status_invalid_asc_json" >"$release_input_status_invalid_asc_env"
: >"$release_input_status_invalid_asc_manual"
RELEASE_ENV_PATH="$release_input_status_invalid_asc_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_invalid_asc_manual" \
  Scripts/print_release_input_status.sh >"$release_input_status_invalid_asc_log" 2>&1 || true
if ! grep -q 'App Store Connect API credential validation fails' "$release_input_status_invalid_asc_log"; then
  printf 'FAIL: Release input status must surface invalid App Store Connect API JSON key files\n'
  failures=$((failures + 1))
fi
if grep -q "$release_input_status_invalid_asc_dir" "$release_input_status_invalid_asc_log"; then
  printf 'FAIL: Release input status must not print private App Store Connect credential paths\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_invalid_asc_dir"
release_input_status_invalid_format_dir="$(mktemp -d)"
release_input_status_invalid_format_env="$release_input_status_invalid_format_dir/release.env"
release_input_status_invalid_format_manual="$release_input_status_invalid_format_dir/manual-release-verification.env"
release_input_status_invalid_format_log="$release_input_status_invalid_format_dir/status.log"
cat >"$release_input_status_invalid_format_env" <<'EOF'
DEVELOPMENT_TEAM_ID=too-short
ASC_KEY_ID=short
ASC_ISSUER_ID=not-a-uuid
FASTLANE_ITC_TEAM_ID=team-name
EOF
: >"$release_input_status_invalid_format_manual"
RELEASE_ENV_PATH="$release_input_status_invalid_format_env" \
  MANUAL_RELEASE_VERIFICATION_PATH="$release_input_status_invalid_format_manual" \
  Scripts/print_release_input_status.sh >"$release_input_status_invalid_format_log" 2>&1 || true
if ! grep -q 'Release environment validation fails' "$release_input_status_invalid_format_log"; then
  printf 'FAIL: Release input status must surface malformed release environment account identifiers\n'
  failures=$((failures + 1))
fi
if grep -q 'OK: DEVELOPMENT_TEAM_ID or Xcode DEVELOPMENT_TEAM configured: 1/1' "$release_input_status_invalid_format_log"; then
  printf 'FAIL: Release input status must not mark malformed DEVELOPMENT_TEAM_ID as configured\n'
  failures=$((failures + 1))
fi
rm -rf "$release_input_status_invalid_format_dir"
check_file "Scripts/validate_release_env.sh" "Release environment placeholder validation script is required"
if [[ -x "Scripts/validate_release_env.sh" ]]; then
  Scripts/validate_release_env.sh || failures=$((failures + 1))
else
  printf 'FAIL: Release environment placeholder validation script must be executable (Scripts/validate_release_env.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_release_env.sh" "PLACEHOLDER_VALUES" "Release environment validation must detect known placeholder values"
check_contains "Scripts/validate_release_env.sh" "APP_REVIEW_CONTACT_EMAIL" "Release environment validation must check App Review contact placeholders"
check_contains "Scripts/validate_release_env.sh" "FASTLANE_USER" "Release environment validation must check Fastlane Apple ID placeholders"
check_contains "Scripts/validate_release_env.sh" "PROCESSED_BUILD_NUMBER" "Release environment validation must reject the selected-build placeholder"
release_env_placeholder_test_dir="$(mktemp -d)"
release_env_placeholder_test_file="$release_env_placeholder_test_dir/release.env"
printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER\n' >"$release_env_placeholder_test_file"
if RELEASE_ENV_PATH="$release_env_placeholder_test_file" Scripts/validate_release_env.sh >/tmp/freeprintstudio-placeholder-release-env.log 2>&1; then
  printf 'FAIL: Release environment validation must reject PROCESSED_BUILD_NUMBER placeholder values\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder value' /tmp/freeprintstudio-placeholder-release-env.log; then
  printf 'FAIL: Release environment placeholder validation must identify APP_STORE_BUILD_NUMBER placeholder values\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_placeholder_test_dir"
release_env_generic_placeholder_test_dir="$(mktemp -d)"
release_env_generic_placeholder_test_file="$release_env_generic_placeholder_test_dir/release.env"
printf 'APP_REVIEW_CONTACT_FIRST_NAME=TODO\n' >"$release_env_generic_placeholder_test_file"
if RELEASE_ENV_PATH="$release_env_generic_placeholder_test_file" Scripts/validate_release_env.sh >/tmp/freeprintstudio-generic-placeholder-release-env.log 2>&1; then
  printf 'FAIL: Release environment validation must reject generic TODO placeholder values\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_REVIEW_CONTACT_FIRST_NAME still uses a placeholder value' /tmp/freeprintstudio-generic-placeholder-release-env.log; then
  printf 'FAIL: Release environment placeholder validation must identify generic TODO placeholder values\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_generic_placeholder_test_dir"
release_env_lowercase_placeholder_test_dir="$(mktemp -d)"
release_env_lowercase_placeholder_test_file="$release_env_lowercase_placeholder_test_dir/release.env"
printf 'APP_REVIEW_CONTACT_FIRST_NAME=todo\n' >"$release_env_lowercase_placeholder_test_file"
if RELEASE_ENV_PATH="$release_env_lowercase_placeholder_test_file" Scripts/validate_release_env.sh >/tmp/freeprintstudio-lowercase-placeholder-release-env.log 2>&1; then
  printf 'FAIL: Release environment validation must reject lowercase todo placeholder values\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_REVIEW_CONTACT_FIRST_NAME still uses a placeholder value' /tmp/freeprintstudio-lowercase-placeholder-release-env.log; then
  printf 'FAIL: Release environment placeholder validation must identify lowercase todo placeholder values\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_lowercase_placeholder_test_dir"
release_env_example_domain_test_dir="$(mktemp -d)"
release_env_example_domain_test_file="$release_env_example_domain_test_dir/release.env"
printf 'APP_REVIEW_CONTACT_EMAIL=review@example.org\n' >"$release_env_example_domain_test_file"
if RELEASE_ENV_PATH="$release_env_example_domain_test_file" Scripts/validate_release_env.sh >/tmp/freeprintstudio-example-domain-release-env.log 2>&1; then
  printf 'FAIL: Release environment validation must reject example-domain placeholder emails\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_REVIEW_CONTACT_EMAIL still uses a placeholder value' /tmp/freeprintstudio-example-domain-release-env.log; then
  printf 'FAIL: Release environment placeholder validation must identify example-domain email placeholders\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_example_domain_test_dir"
release_env_invalid_format_test_dir="$(mktemp -d)"
release_env_invalid_format_test_file="$release_env_invalid_format_test_dir/release.env"
cat >"$release_env_invalid_format_test_file" <<'EOF'
DEVELOPMENT_TEAM_ID=too-short
ASC_KEY_ID=short
ASC_ISSUER_ID=not-a-uuid
FASTLANE_ITC_TEAM_ID=team-name
EOF
if RELEASE_ENV_PATH="$release_env_invalid_format_test_file" Scripts/validate_release_env.sh >/tmp/freeprintstudio-invalid-format-release-env.log 2>&1; then
  printf 'FAIL: Release environment validation must reject malformed account identifiers\n'
  failures=$((failures + 1))
elif ! grep -q 'DEVELOPMENT_TEAM_ID must be a 10-character Apple Developer Team ID' /tmp/freeprintstudio-invalid-format-release-env.log \
  || ! grep -q 'ASC_KEY_ID must be a 10-character App Store Connect API key id' /tmp/freeprintstudio-invalid-format-release-env.log \
  || ! grep -q 'ASC_ISSUER_ID must be an App Store Connect issuer UUID' /tmp/freeprintstudio-invalid-format-release-env.log \
  || ! grep -q 'FASTLANE_ITC_TEAM_ID must be numeric' /tmp/freeprintstudio-invalid-format-release-env.log; then
  printf 'FAIL: Release environment invalid-format output must identify malformed account identifiers\n'
  failures=$((failures + 1))
fi
rm -rf "$release_env_invalid_format_test_dir"
check_contains "Scripts/check_app_store_readiness.sh" "source Scripts/load_release_env.sh" "Readiness audit must load Config/release.env"
check_contains "Scripts/check_app_store_readiness.sh" "validate_release_env.sh" "Readiness audit must reject placeholder release environment values"
check_contains "Scripts/check_app_store_connect_credentials.sh" "source Scripts/load_release_env.sh" "Credential audit must load Config/release.env"
check_contains "Scripts/archive_app_store.sh" "source Scripts/load_release_env.sh" "Archive script must load Config/release.env"
check_contains "Scripts/run_fastlane.sh" "source Scripts/load_release_env.sh" "Fastlane wrapper must load Config/release.env"
check_file "fastlane/Deliverfile" "Fastlane Deliverfile is required for repeatable App Store metadata upload"
check_contains "fastlane/Deliverfile" "com.dannagrace.FreePrintStudio" "Deliverfile must target the release bundle id"
check_file "Gemfile" "Bundler Gemfile is required for repeatable Fastlane installation"
check_contains "Gemfile" "fastlane" "Gemfile must declare Fastlane"
check_contains "Gemfile" "< 2.232" "Fastlane dependency must stay compatible with macOS system Ruby 2.6"
check_file "Scripts/install_release_dependencies.sh" "Release dependency installation script is required"
check_contains "Scripts/install_release_dependencies.sh" "vendor/bundle" "Release dependencies must install into a project-local bundle path"
check_file "Scripts/run_fastlane.sh" "Fastlane wrapper script is required"
check_contains "Scripts/run_fastlane.sh" "timeout=15" "Fastlane wrapper must bound Bundler checks"
check_contains "Scripts/run_fastlane.sh" "bundle exec fastlane" "Fastlane wrapper must prefer Bundler when dependencies are installed"
check_contains "Scripts/run_fastlane.sh" "brew install fastlane" "Fastlane wrapper must document the Homebrew fallback"
check_contains "Scripts/check_app_store_readiness.sh" "timeout=15" "Readiness audit must bound Bundler checks"
check_file "fastlane/Fastfile" "Fastlane lanes are required"
check_contains "fastlane/Fastfile" "PROJECT_ROOT" "Fastfile must use project-root absolute paths"
check_contains "fastlane/Fastfile" "require \"json\"" "Fastfile must parse App Store Connect API JSON before upload"
check_contains "fastlane/Fastfile" "require \"pathname\"" "Fastfile must normalize App Store Connect API key paths"
check_contains "fastlane/Fastfile" "api_key_json_path.dirname" "Fastfile must resolve API JSON relative key_filepath values from the JSON file directory"
check_not_contains "fastlane/Fastfile" 'APP_STORE_CONNECT_API_KEY_JSON does not exist: #{api_key_json}' "Fastfile must not print the full App Store Connect API JSON path"
check_not_contains "fastlane/Fastfile" 'ASC_KEY_PATH does not exist: #{key_path}' "Fastfile must not print the full App Store Connect private key path"
check_contains "fastlane/Fastfile" "APP_STORE_CONNECT_API_KEY_JSON does not exist at the configured path" "Fastfile must identify missing API JSON without printing the configured path"
check_contains "fastlane/Fastfile" "ASC_KEY_PATH does not exist at the configured path" "Fastfile must identify missing private key path without printing the configured path"
check_contains "fastlane/Fastfile" "opt_out_usage" "Fastfile must opt out of Fastlane analytics"
check_contains "fastlane/Fastfile" "lane :verify" "Fastfile must expose a verify lane"
check_contains "fastlane/Fastfile" "lane :readiness" "Fastfile must expose a readiness lane"
check_contains "fastlane/Fastfile" "lane :metadata" "Fastfile must expose a metadata lane"
check_contains "fastlane/Fastfile" "lane :privacy_details" "Fastfile must expose an App Privacy Details upload lane"
check_contains "fastlane/Fastfile" "lane :app_store_connect_state" "Fastfile must expose an App Store Connect state preflight lane"
check_contains "fastlane/Fastfile" "lane :archive" "Fastfile must expose an archive lane"
check_contains "fastlane/Fastfile" "lane :upload_testflight" "Fastfile must expose a TestFlight upload lane"
check_contains "fastlane/Fastfile" "lane :submit_review" "Fastfile must expose a guarded App Store review submission lane"
check_contains "fastlane/Fastfile" "validate_app_store_export!" "Fastfile must validate App Store export artifacts before upload"
check_contains "fastlane/Fastfile" "Scripts/preflight_app_store_archive.sh" "Fastfile must run the App Store archive preflight script"
check_contains "fastlane/Fastfile" "app_store_connect_api_key" "Fastfile must support App Store Connect API key upload"
check_contains "fastlane/Fastfile" "upload_to_testflight" "Fastfile must upload the signed IPA to TestFlight"
check_contains "fastlane/Fastfile" "Scripts/preflight_testflight_upload_dependencies.sh" "Fastfile must run the TestFlight upload dependency preflight before archive fallback"
check_contains "fastlane/Fastfile" "upload_app_privacy_details_to_app_store" "Fastfile must support App Privacy Details upload"
check_contains "fastlane/Fastfile" "CONFIRM_UPLOAD_APP_PRIVACY" "Fastfile privacy lane must require explicit upload confirmation"
check_contains "fastlane/Fastfile" "AppStore/app_privacy_details.json" "Fastfile privacy lane must use the reviewed App Privacy Details JSON"
check_contains "fastlane/Fastfile" "Scripts/preflight_app_privacy_upload.sh" "Fastfile must run the App Privacy Details upload preflight script"
check_contains "fastlane/Fastfile" "CONFIRM_SUBMIT_FOR_REVIEW" "Fastfile submit lane must require explicit review-submission confirmation"
check_contains "fastlane/Fastfile" "Scripts/preflight_app_review_submission.sh" "Fastfile must run the App Review submission preflight script"
check_contains "fastlane/Fastfile" "submit_for_review: true" "Fastfile submit lane must submit the selected build for review"
check_contains "fastlane/Fastfile" "automatic_release: false" "Fastfile submit lane must use manual release after approval"
check_contains "fastlane/Fastfile" "submission_information" "Fastfile submit lane must provide submission compliance information"
check_contains "fastlane/Fastfile" "add_id_info_serves_ads: false" "Fastfile submission information must declare that the app does not use IDFA to serve ads"
check_contains "fastlane/Fastfile" "add_id_info_tracks_action: false" "Fastfile submission information must declare that the app does not use IDFA to track actions"
check_contains "fastlane/Fastfile" "add_id_info_tracks_install: false" "Fastfile submission information must declare that the app does not use IDFA to track installs"
check_contains "fastlane/Fastfile" "APP_STORE_BUILD_NUMBER" "Fastfile submit lane must support selecting a processed App Store build"
check_contains "fastlane/Fastfile" "Scripts/check_app_store_connect_state.sh" "Fastfile must run the App Store Connect state preflight script"
check_contains "fastlane/Fastfile" "Scripts/preflight_metadata_upload.sh" "Fastfile must run the metadata upload preflight script"
check_contains "fastlane/Fastfile" "primary_category: PRIMARY_CATEGORY" "Fastfile metadata lane must set the primary App Store category"
check_contains "fastlane/Fastfile" "secondary_category: SECONDARY_CATEGORY" "Fastfile metadata lane must set the secondary App Store category"
check_contains "fastlane/Fastfile" "review_information_options" "Fastfile must prepare App Store review information"
check_contains "fastlane/Fastfile" "APP_REVIEW_CONTACT_EMAIL" "Fastfile must support private App Review contact details"
check_contains "fastlane/Fastfile" "Scripts/validate_release_env.sh" "Fastfile must reject placeholder release inputs before App Store Connect operations"
check_contains "fastlane/Fastfile" "Scripts/validate_app_review_contact.sh" "Fastfile must run App Review contact validation before upload or submission"
check_contains "fastlane/Fastfile" "Scripts/validate_manual_release_verification.sh" "Fastfile must run manual release evidence validation before App Review submission"
check_contains "fastlane/Fastfile" "Scripts/validate_app_store_questionnaires.sh" "Fastfile must run App Store questionnaire validation before upload or submission"
check_contains "fastlane/Fastfile" "Scripts/validate_screenshot_privacy.sh" "Fastfile must run screenshot privacy metadata validation before upload or submission"
check_occurrences_at_least "fastlane/Fastfile" "validate_app_review_contact!" 2 "Fastfile metadata and submit lanes must require App Review contact validation"
check_occurrences_at_least "fastlane/Fastfile" "validate_screenshot_privacy!" 2 "Fastfile metadata and submit lanes must require screenshot privacy metadata validation"
check_occurrences_at_least "fastlane/Fastfile" "validate_app_store_questionnaires!" 4 "Fastfile upload and submit lanes must require App Store questionnaire validation"
check_file "Scripts/validate_fastlane_release_lanes.sh" "Fastlane release lane validation script is required"
if [[ ! -x "Scripts/validate_fastlane_release_lanes.sh" ]]; then
  printf 'FAIL: Fastlane release lane validation script must be executable (Scripts/validate_fastlane_release_lanes.sh)\n'
  failures=$((failures + 1))
fi
if [[ -x "Scripts/validate_fastlane_release_lanes.sh" ]]; then
  Scripts/validate_fastlane_release_lanes.sh || failures=$((failures + 1))
fi
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_release_env!" "Fastlane lane validation must check release environment placeholder gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_app_review_contact!" "Fastlane lane validation must check App Review contact gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_screenshot_privacy!" "Fastlane lane validation must check screenshot privacy metadata gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_manual_release_verification!" "Fastlane lane validation must check manual release evidence gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_app_store_questionnaires!" "Fastlane lane validation must check App Store questionnaire gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "verify_app_store_connect_state!" "Fastlane lane validation must check App Store Connect state preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "preflight_metadata_upload!" "Fastlane lane validation must check metadata upload preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "preflight_testflight_upload_dependencies!" "Fastlane lane validation must check TestFlight upload dependency preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "preflight_app_privacy_upload!" "Fastlane lane validation must check App Privacy Details upload preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "preflight_app_store_archive!" "Fastlane lane validation must check App Store archive preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "preflight_app_review_submission!" "Fastlane lane validation must check App Review submission preflight gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "add_id_info_tracks_install: false" "Fastlane lane validation must check IDFA submission information"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "ipa: ipa_path" "Fastlane lane validation must require TestFlight upload to use the selected IPA"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "skip_waiting_for_build_processing: true" "Fastlane lane validation must require TestFlight upload to avoid implicit processing waits"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "distribute_external: false" "Fastlane lane validation must prevent accidental external TestFlight distribution"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "notify_external_testers: false" "Fastlane lane validation must prevent accidental external tester notifications"
check_file "Scripts/preflight_metadata_upload.sh" "Metadata upload preflight script is required"
if [[ -f "Scripts/preflight_metadata_upload.sh" && ! -x "Scripts/preflight_metadata_upload.sh" ]]; then
  printf 'FAIL: Metadata upload preflight script must be executable (Scripts/preflight_metadata_upload.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_release_env.sh" "Metadata upload preflight must validate private release inputs"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_app_store_metadata.sh" "Metadata upload preflight must validate App Store metadata"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_screenshot_sync.sh" "Metadata upload preflight must validate screenshot sync"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_screenshot_privacy.sh" "Metadata upload preflight must validate screenshot privacy metadata"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_public_pages.sh" "Metadata upload preflight must validate public privacy and support pages"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_app_store_questionnaires.sh" "Metadata upload preflight must validate App Store questionnaires"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/validate_app_review_contact.sh" "Metadata upload preflight must validate App Review contact"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/check_app_store_connect_credentials.sh" "Metadata upload preflight must validate App Store Connect credentials"
check_contains "Scripts/preflight_metadata_upload.sh" "APP_STORE_CONNECT_SKIP_BUILD_CHECK=1 Scripts/check_app_store_connect_state.sh" "Metadata upload preflight must verify App Store Connect app and version without requiring a selected build"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/print_release_input_status.sh --strict" "Metadata upload preflight must print field-level release input status before upload gates"
check_contains "Scripts/preflight_metadata_upload.sh" "Scripts/run_fastlane.sh ios metadata" "Metadata upload preflight must print the metadata upload next command"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_metadata_upload.sh").read_text()
status_index = source.find('run_step "Release input status" Scripts/print_release_input_status.sh --strict')
metadata_index = source.find('run_step "App Store metadata" Scripts/validate_app_store_metadata.sh')
if status_index == -1 or metadata_index == -1 or status_index > metadata_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: Metadata upload preflight must print release input status before metadata validation\n'
  failures=$((failures + 1))
fi
check_file "Scripts/validate_app_privacy_connect_entry.sh" "App Privacy Details App Store Connect confirmation validator is required"
if [[ -f "Scripts/validate_app_privacy_connect_entry.sh" && ! -x "Scripts/validate_app_privacy_connect_entry.sh" ]]; then
  printf 'FAIL: App Privacy Details App Store Connect confirmation validator must be executable (Scripts/validate_app_privacy_connect_entry.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Config/release.env.example" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release environment template must include the App Privacy Details App Store Connect confirmation"
check_contains "Scripts/load_release_env.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release environment loader must preserve the App Privacy Details App Store Connect confirmation"
check_contains "Scripts/validate_release_env.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release environment validation must reject placeholder App Privacy Details App Store Connect confirmations"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_privacy_connect_entry.sh" "Readiness audit must require App Privacy Details confirmation in App Store Connect"
check_contains "Scripts/preflight_app_review_submission.sh" "validate_app_privacy_connect_entry.sh" "App Review submission preflight must require App Privacy Details confirmation in App Store Connect"
check_contains "Scripts/print_release_input_status.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release input status must summarize App Privacy Details confirmation in App Store Connect"
check_contains "README.md" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "README must document App Privacy Details App Store Connect confirmation"
check_contains "AppStore/release-checklist.md" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release checklist must document App Privacy Details App Store Connect confirmation"
check_contains "AppStore/release-inputs-worksheet.md" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT" "Release input worksheet must include App Privacy Details App Store Connect confirmation"
app_privacy_missing_confirmation_test_dir="$(mktemp -d)"
app_privacy_missing_confirmation_env="$app_privacy_missing_confirmation_test_dir/release.env"
app_privacy_missing_confirmation_log="$app_privacy_missing_confirmation_test_dir/app-privacy-confirmation.log"
: >"$app_privacy_missing_confirmation_env"
chmod 600 "$app_privacy_missing_confirmation_env"
if RELEASE_ENV_PATH="$app_privacy_missing_confirmation_env" Scripts/validate_app_privacy_connect_entry.sh >"$app_privacy_missing_confirmation_log" 2>&1; then
  printf 'FAIL: App Privacy Details App Store Connect confirmation must be required before App Review submission\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1' "$app_privacy_missing_confirmation_log"; then
  printf 'FAIL: Missing App Privacy Details App Store Connect confirmation must name APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1\n'
  failures=$((failures + 1))
fi
rm -rf "$app_privacy_missing_confirmation_test_dir"
app_privacy_invalid_confirmation_test_dir="$(mktemp -d)"
app_privacy_invalid_confirmation_env="$app_privacy_invalid_confirmation_test_dir/release.env"
app_privacy_invalid_confirmation_log="$app_privacy_invalid_confirmation_test_dir/app-privacy-confirmation-invalid.log"
printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=yes\n' >"$app_privacy_invalid_confirmation_env"
chmod 600 "$app_privacy_invalid_confirmation_env"
if RELEASE_ENV_PATH="$app_privacy_invalid_confirmation_env" Scripts/validate_app_privacy_connect_entry.sh >"$app_privacy_invalid_confirmation_log" 2>&1; then
  printf 'FAIL: App Privacy Details App Store Connect confirmation must reject non-1 values\n'
  failures=$((failures + 1))
elif ! grep -q 'must be 1 after App Store Connect matches AppStore/app_privacy_details.json' "$app_privacy_invalid_confirmation_log"; then
  printf 'FAIL: Invalid App Privacy Details App Store Connect confirmation must explain the expected value\n'
  failures=$((failures + 1))
fi
rm -rf "$app_privacy_invalid_confirmation_test_dir"
app_privacy_valid_confirmation_test_dir="$(mktemp -d)"
app_privacy_valid_confirmation_env="$app_privacy_valid_confirmation_test_dir/release.env"
app_privacy_valid_confirmation_log="$app_privacy_valid_confirmation_test_dir/app-privacy-confirmation-valid.log"
printf 'APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1\n' >"$app_privacy_valid_confirmation_env"
chmod 600 "$app_privacy_valid_confirmation_env"
if ! RELEASE_ENV_PATH="$app_privacy_valid_confirmation_env" Scripts/validate_app_privacy_connect_entry.sh >"$app_privacy_valid_confirmation_log" 2>&1; then
  printf 'FAIL: App Privacy Details App Store Connect confirmation must pass when APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1\n'
  failures=$((failures + 1))
elif ! grep -q 'App Privacy Details confirmed in App Store Connect' "$app_privacy_valid_confirmation_log"; then
  printf 'FAIL: App Privacy Details App Store Connect confirmation success must be explicit\n'
  failures=$((failures + 1))
fi
rm -rf "$app_privacy_valid_confirmation_test_dir"
check_file "Scripts/preflight_app_privacy_upload.sh" "App Privacy Details upload preflight script is required"
if [[ -f "Scripts/preflight_app_privacy_upload.sh" && ! -x "Scripts/preflight_app_privacy_upload.sh" ]]; then
  printf 'FAIL: App Privacy Details upload preflight script must be executable (Scripts/preflight_app_privacy_upload.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_app_privacy_upload.sh" "CONFIRM_UPLOAD_APP_PRIVACY=1" "App Privacy Details upload preflight must require explicit upload confirmation"
check_contains "Scripts/preflight_app_privacy_upload.sh" "FASTLANE_USER" "App Privacy Details upload preflight must require the Fastlane Apple ID"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/validate_release_env.sh" "App Privacy Details upload preflight must validate private release inputs"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/validate_privacy_surface.sh" "App Privacy Details upload preflight must validate privacy surface"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/validate_app_privacy_details.sh" "App Privacy Details upload preflight must validate App Privacy Details JSON"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/validate_app_store_questionnaires.sh" "App Privacy Details upload preflight must validate App Store questionnaires"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/print_release_input_status.sh --strict" "App Privacy Details upload preflight must print field-level release input status before privacy upload gates"
check_contains "Scripts/preflight_app_privacy_upload.sh" "Scripts/run_fastlane.sh ios privacy_details" "App Privacy Details upload preflight must print the privacy upload next command"
check_not_contains "Scripts/preflight_app_privacy_upload.sh" 'printf '\''Next: FASTLANE_USER=%s' "App Privacy Details upload preflight must not print the real Fastlane Apple ID in the next command"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_app_privacy_upload.sh").read_text()
status_index = source.find('run_step "Release input status" Scripts/print_release_input_status.sh --strict')
privacy_index = source.find('run_step "Privacy surface" Scripts/validate_privacy_surface.sh')
if status_index == -1 or privacy_index == -1 or status_index > privacy_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: App Privacy Details upload preflight must print release input status before privacy validation\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/verify_release.sh" "metadata-preflight" "Release verification must expose metadata upload preflight"
check_contains "Scripts/verify_release.sh" "privacy-preflight" "Release verification must expose App Privacy Details upload preflight"
check_contains "fastlane/Deliverfile" "project_root" "Deliverfile must use project-root absolute paths"
check_contains "fastlane/Deliverfile" "primary_category(\"Graphics & Design\")" "Deliverfile must set the primary App Store category"
check_contains "fastlane/Deliverfile" "secondary_category(\"Productivity\")" "Deliverfile must set the secondary App Store category"
check_file "fastlane/metadata/en-US/name.txt" "Fastlane app name metadata is required"
check_contains "fastlane/metadata/en-US/name.txt" "FreePrint Studio" "Fastlane metadata must include the app name"
check_file "fastlane/metadata/en-US/description.txt" "Fastlane description metadata is required"
check_contains "fastlane/metadata/en-US/description.txt" "exact-size" "Fastlane description must describe exact-size printing"
check_file "fastlane/metadata/en-US/copyright.txt" "Fastlane copyright metadata is required"
check_contains "fastlane/metadata/en-US/copyright.txt" "2026 dannagrace" "Fastlane copyright metadata must name the release copyright year and owner"
check_file "fastlane/metadata/copyright.txt" "Fastlane nonlocalized copyright metadata is required"
check_contains "fastlane/metadata/copyright.txt" "2026 dannagrace" "Fastlane nonlocalized copyright metadata must name the release copyright year and owner"
check_file "fastlane/metadata/en-US/release_notes.txt" "Fastlane release notes metadata is required"
check_contains "fastlane/metadata/en-US/release_notes.txt" "Initial release" "Fastlane release notes must describe the initial release"
check_file "fastlane/metadata/review_information/notes.txt" "Fastlane app review notes metadata is required"
check_contains "fastlane/metadata/review_information/notes.txt" "does not require an account" "Fastlane app review notes must explain that no account is required"
check_file "fastlane/metadata/en-US/privacy_url.txt" "Fastlane privacy URL metadata is required"
check_contains "fastlane/metadata/en-US/privacy_url.txt" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "Fastlane metadata must include the public privacy URL"
check_file "fastlane/metadata/en-US/support_url.txt" "Fastlane support URL metadata is required"
check_contains "fastlane/metadata/en-US/support_url.txt" "https://dannagrace.github.io/FreePrintStudio/support.html" "Fastlane metadata must include the public support URL"
check_file "AppStore/Screenshots/iphone-metric-landscape.jpg" "Reviewed iPhone metric landscape screenshot is required"
check_file "AppStore/Screenshots/iphone-test-ruler.jpg" "Reviewed iPhone Test Ruler screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-main.jpg" "Fastlane iPhone screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-test-ruler.jpg" "Fastlane iPhone Test Ruler screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-fit.jpg" "Fastlane iPhone Fit screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-fill.jpg" "Fastlane iPhone Fill screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-stretch.jpg" "Fastlane iPhone Stretch screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-metric-landscape.jpg" "Fastlane iPhone metric landscape screenshot is required"
check_file "fastlane/screenshots/en-US/ipad-main.jpg" "Fastlane iPad screenshot is required"
check_file "Scripts/archive_app_store.sh" "App Store archive script is required"
check_contains "Scripts/archive_app_store.sh" "xcodebuild" "Archive script must use xcodebuild"
check_contains "Scripts/archive_app_store.sh" "DEVELOPMENT_TEAM_ID" "Archive script must support an explicit Apple Developer Team ID"
check_contains "Scripts/archive_app_store.sh" "Scripts/preflight_app_store_archive.sh" "Archive script must run the archive preflight before creating a signed archive"
check_contains "Scripts/archive_app_store.sh" "safe_output_path" "Archive script must validate archive/export output paths before destructive cleanup"
check_contains "Scripts/archive_app_store.sh" "safe_remove" "Archive script must wrap destructive cleanup in a guarded helper"
check_contains "Scripts/archive_app_store.sh" "Refusing to use" "Archive script must report unsafe archive/export paths clearly"
check_contains "Scripts/archive_app_store.sh" "inside build/" "Archive script must keep archive/export outputs inside the repository build directory"
check_contains "Scripts/archive_app_store.sh" "safe_remove \"\$ARCHIVE_PATH\"" "Archive script must guard archive cleanup"
check_contains "Scripts/archive_app_store.sh" "safe_remove \"\$EXPORT_PATH\"" "Archive script must guard export cleanup"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/archive_app_store.sh").read_text()
preflight_index = source.find("Scripts/preflight_app_store_archive.sh")
archive_index = source.find("archive >")
if preflight_index == -1 or archive_index == -1 or preflight_index > archive_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: Archive script must run Scripts/preflight_app_store_archive.sh before xcodebuild archive\n'
  failures=$((failures + 1))
fi
check_file "Scripts/preflight_app_store_archive.sh" "App Store archive preflight script is required"
if [[ ! -x "Scripts/preflight_app_store_archive.sh" ]]; then
  printf 'FAIL: App Store archive preflight script must be executable (Scripts/preflight_app_store_archive.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/verify_release.sh" "Archive preflight must run the local release gate"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/verify_release.sh store-ready" "Archive preflight must run the full store-ready release gate before signing"
check_contains "Scripts/preflight_app_store_archive.sh" "source Scripts/load_release_env.sh" "Archive preflight must load private release inputs before checking signing assets"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/validate_release_env.sh" "Archive preflight must validate private release env placeholders"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/print_release_input_status.sh --strict" "Archive preflight must print field-level release input status before signing"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/validate_app_review_contact.sh" "Archive preflight must validate App Review contact details"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/check_code_signing_assets.sh" "Archive preflight must validate signing assets"
check_contains "Scripts/preflight_app_store_archive.sh" "Scripts/check_app_store_readiness.sh" "Archive preflight must finish with the full readiness audit"
check_contains "Scripts/preflight_app_store_archive.sh" "App Store archive preflight passed" "Archive preflight must print a clear success message"
check_not_contains "Scripts/preflight_app_store_archive.sh" "DEVELOPMENT_TEAM_ID=<" "Archive preflight success command must use a shell-safe Team ID placeholder"
check_contains "Scripts/preflight_app_store_archive.sh" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Archive preflight success command must show the guarded archive command"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_app_store_archive.sh").read_text()
status_index = source.find('run_step "Release input status" Scripts/print_release_input_status.sh --strict')
store_ready_index = source.find('run_step "Local store-ready release gate" Scripts/verify_release.sh store-ready')
if status_index == -1 or store_ready_index == -1 or status_index > store_ready_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: Archive preflight must print release input status before the full store-ready gate\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/verify_release.sh" "archive-preflight" "Release verification must expose the archive preflight command"
check_file "Scripts/validate_app_store_export.sh" "App Store archive/export validation script is required"
if [[ ! -x "Scripts/validate_app_store_export.sh" ]]; then
  printf 'FAIL: App Store archive/export validation script must be executable (Scripts/validate_app_store_export.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_store_export.sh" "FreePrintStudio.xcarchive" "App Store export validation must inspect the archive"
check_contains "Scripts/validate_app_store_export.sh" "Payload" "App Store export validation must inspect the IPA payload"
check_contains "Scripts/archive_app_store.sh" "validate_app_store_export.sh" "Archive script must validate the exported App Store artifacts"
check_file "Scripts/capture_app_store_screenshot_set.sh" "App Store screenshot set script is required"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-main.jpg" "Screenshot set script must capture the iPhone main screenshot"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "FREEPRINTSTUDIO_APPEARANCE=light" "Screenshot set script must capture the iPhone main screenshot with a deterministic light appearance"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-test-ruler.jpg" "Screenshot set script must capture the iPhone Test Ruler screenshot"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "FREEPRINTSTUDIO_APPEARANCE=light" "Screenshot set script must capture the iPhone Test Ruler screenshot with a deterministic light appearance"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-fit.jpg" "Screenshot set script must capture Fit mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-fill.jpg" "Screenshot set script must capture Fill mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-stretch.jpg" "Screenshot set script must capture Stretch mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-metric-landscape.jpg" "Screenshot set script must capture metric landscape mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "ipad-main.jpg" "Screenshot set script must capture the iPad main screenshot"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_DEVICE_PATTERN" "Screenshot script must support reproducible non-iPhone simulator captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_SCREENSHOT_CONTENT" "Screenshot script must support reproducible content variants"
check_contains "FreePrintStudio/ContentView.swift" "FreePrintStudioUseTestRuler" "Debug screenshot launch must support loading the Test Ruler"
check_contains "Scripts/capture_app_store_screenshots.sh" "Invalid FREEPRINTSTUDIO_PAPER" "Screenshot script must reject invalid paper overrides"
check_contains "Scripts/capture_app_store_screenshots.sh" "Invalid FREEPRINTSTUDIO_FIT_MODE" "Screenshot script must reject invalid fit mode overrides"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_VALIDATE_OPTIONS_ONLY" "Screenshot script must support fast option-only validation"
check_contains "Scripts/capture_app_store_screenshots.sh" "Screenshot capture options valid" "Screenshot script must report successful option-only validation"
check_contains "Scripts/capture_app_store_screenshots.sh" "SIMCTL_TIMEOUT_SECONDS" "Screenshot capture must bound simulator install commands"
check_contains "Scripts/capture_app_store_screenshots.sh" "Skipping simulator after install failure" "Screenshot capture must skip unhealthy simulators"
if [[ -x "Scripts/capture_app_store_screenshots.sh" ]]; then
  if ! FREEPRINTSTUDIO_VALIDATE_OPTIONS_ONLY=1 \
    FREEPRINTSTUDIO_PAPER=a4 \
    FREEPRINTSTUDIO_ORIENTATION=landscape \
    FREEPRINTSTUDIO_UNIT=centimeter \
    FREEPRINTSTUDIO_FIT_MODE=stretch \
    Scripts/capture_app_store_screenshots.sh >/tmp/freeprintstudio-screenshot-options-valid.log 2>&1; then
    printf 'FAIL: Screenshot option-only validation must accept valid paper, orientation, unit, and fit mode overrides\n'
    sed 's/^/  /' /tmp/freeprintstudio-screenshot-options-valid.log
    failures=$((failures + 1))
  fi

  if FREEPRINTSTUDIO_VALIDATE_OPTIONS_ONLY=1 \
    FREEPRINTSTUDIO_PAPER=tabloid \
    Scripts/capture_app_store_screenshots.sh >/tmp/freeprintstudio-screenshot-options-invalid.log 2>&1; then
    printf 'FAIL: Screenshot option-only validation must reject invalid paper overrides\n'
    failures=$((failures + 1))
  elif ! grep -q "Invalid FREEPRINTSTUDIO_PAPER" /tmp/freeprintstudio-screenshot-options-invalid.log; then
    printf 'FAIL: Screenshot option-only validation must explain invalid paper overrides\n'
    sed 's/^/  /' /tmp/freeprintstudio-screenshot-options-invalid.log
    failures=$((failures + 1))
  fi
fi
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_ORIENTATION" "Screenshot script must support reproducible paper orientation captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_UNIT" "Screenshot script must support reproducible measurement unit captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_APPEARANCE" "Screenshot script must support reproducible light/dark captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_CONTENT_SIZE" "Screenshot script must support reproducible Larger Text captures"
check_contains "Scripts/capture_app_store_screenshots.sh" 'XCODEBUILD_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_XCODEBUILD_TIMEOUT_SECONDS:-300}"' "Screenshot capture must bound simulator build time"
check_contains "Scripts/capture_app_store_screenshots.sh" 'BOOTSTATUS_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_BOOTSTATUS_TIMEOUT_SECONDS:-180}"' "Screenshot capture must bound simulator bootstatus"
check_contains "Scripts/capture_app_store_screenshots.sh" "Screenshot capture command timed out" "Screenshot capture must report timeout failures clearly"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl list devices booted" "Screenshot capture must bound booted simulator discovery"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl list devices available" "Screenshot capture must bound available simulator discovery"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl boot \"\$device\"" "Screenshot capture must bound simulator boot commands"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$BOOTSTATUS_TIMEOUT_SECONDS\" xcrun simctl bootstatus \"\$device\" -b" "Screenshot capture must bound simulator bootstatus commands"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$XCODEBUILD_TIMEOUT_SECONDS\" xcodebuild" "Screenshot capture must bound xcodebuild"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl ui \"\$DEVICE\" appearance" "Screenshot capture must bound simulator appearance commands"
check_contains "Scripts/capture_app_store_screenshots.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl ui \"\$DEVICE\" content_size" "Screenshot capture must bound simulator content-size commands"
check_file "Scripts/validate_accessibility_screenshots.sh" "Accessibility screenshot validation script is required"
if [[ ! -x "Scripts/validate_accessibility_screenshots.sh" ]]; then
  printf 'FAIL: Accessibility screenshot validation script must be executable (Scripts/validate_accessibility_screenshots.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_accessibility_screenshots.sh" "FREEPRINTSTUDIO_APPEARANCE=dark" "Accessibility screenshot validation must capture dark mode"
check_contains "Scripts/validate_accessibility_screenshots.sh" "FREEPRINTSTUDIO_CONTENT_SIZE=accessibility-extra-extra-large" "Accessibility screenshot validation must capture Larger Text"
check_contains "Scripts/validate_accessibility_screenshots.sh" "safe_output_dir" "Accessibility screenshot validation must validate output directories before cleanup"
check_contains "Scripts/validate_accessibility_screenshots.sh" "Refusing to use" "Accessibility screenshot validation must explain unsafe output directory overrides"
check_contains "Scripts/validate_accessibility_screenshots.sh" "accessibility screenshot output" "Accessibility screenshot validation must identify unsafe output directory overrides"
check_contains "Scripts/validate_accessibility_screenshots.sh" "/tmp/freeprintstudio-" "Accessibility screenshot validation must allow only namespaced temporary outputs"
check_contains "Scripts/validate_accessibility_screenshots.sh" "build" "Accessibility screenshot validation must allow repository build outputs"
check_contains "Scripts/verify_release.sh" "validate_accessibility_screenshots.sh" "Release verification must expose accessibility screenshot validation"
check_file "Scripts/validate_screenshot_sync.sh" "Screenshot sync validation script is required"
if [[ ! -x "Scripts/validate_screenshot_sync.sh" ]]; then
  printf 'FAIL: Screenshot sync validation script must be executable (Scripts/validate_screenshot_sync.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_screenshot_sync.sh" "AppStore/Screenshots" "Screenshot sync validation must check reviewed App Store screenshots"
check_contains "Scripts/validate_screenshot_sync.sh" "fastlane/screenshots/en-US" "Screenshot sync validation must check Fastlane upload screenshots"
check_contains "Scripts/validate_screenshot_sync.sh" "iphone-test-ruler.jpg" "Screenshot sync validation must require the Test Ruler screenshot"
check_contains "Scripts/verify_release.sh" "validate_screenshot_sync.sh" "Release verification must validate screenshot sync"
check_file "Scripts/validate_screenshot_privacy.sh" "Screenshot privacy metadata validation script is required"
if [[ ! -x "Scripts/validate_screenshot_privacy.sh" ]]; then
  printf 'FAIL: Screenshot privacy metadata validation script must be executable (Scripts/validate_screenshot_privacy.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_screenshot_privacy.sh" "kMDItemLatitude" "Screenshot privacy validation must reject location metadata"
check_contains "Scripts/validate_screenshot_privacy.sh" "kMDItemAcquisitionMake" "Screenshot privacy validation must reject camera make metadata"
check_contains "Scripts/validate_screenshot_privacy.sh" "kMDItemAuthors" "Screenshot privacy validation must reject author metadata"
check_contains "Scripts/validate_screenshot_privacy.sh" "AppStore/Screenshots" "Screenshot privacy validation must check reviewed App Store screenshots"
check_contains "Scripts/validate_screenshot_privacy.sh" "fastlane/screenshots/en-US" "Screenshot privacy validation must check Fastlane upload screenshots"
check_contains "Scripts/verify_release.sh" "validate_screenshot_privacy.sh" "Release verification must validate screenshot privacy metadata"
check_contains "Scripts/preflight_metadata_upload.sh" "validate_screenshot_privacy.sh" "Metadata upload preflight must validate screenshot privacy metadata"
check_contains "Scripts/verify_release.sh" "iphone-test-ruler.jpg" "Release verification must validate the Test Ruler screenshot asset"
check_contains "Scripts/check_app_store_readiness.sh" "iphone-test-ruler.jpg" "Readiness audit must validate the Test Ruler screenshot size"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "iphone-test-ruler.jpg" "Submission packet must include the Test Ruler screenshot"
check_contains "Scripts/verify_release.sh" "run_store_ready_validation" "Release verification must expose a single local store-ready gate"
check_contains "Scripts/verify_release.sh" "store-ready)" "Release verification must accept the store-ready command"
if ! python3 - "Scripts/verify_release.sh" "run_store_ready_validation" "run_public_pages_validation" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
function_name = sys.argv[2]
needle = sys.argv[3]
source = path.read_text()
start = source.find(f"{function_name}() {{")
if start < 0:
    raise SystemExit(1)
end = source.find("\n}", start)
if end < 0:
    raise SystemExit(1)
body = source[start:end]
raise SystemExit(0 if needle in body else 1)
PY
then
  printf 'FAIL: Store-ready verification must strictly validate public privacy and support pages (Scripts/verify_release.sh run_store_ready_validation missing run_public_pages_validation)\n'
  failures=$((failures + 1))
fi
check_file "Scripts/validate_pdf_export.sh" "PDF export validation script is required"
check_contains "Scripts/validate_pdf_export.sh" "FreePrintStudioAutoExportPDFPath" "PDF export validation must exercise the app renderer"
check_contains "Scripts/validate_pdf_export.sh" "FIT_MODES=(fit fill stretch)" "PDF export validation must cover Fit, Fill, and Stretch output modes"
check_contains "Scripts/validate_pdf_export.sh" "Image clip rectangle" "PDF export validation must verify target clip rectangle size"
check_contains "FreePrintStudio/ContentView.swift" "FreePrintStudioOrientation" "Debug PDF export must support paper orientation arguments"
check_contains "Scripts/validate_pdf_export.sh" "landscape-letter-stretch" "PDF export validation must cover landscape paper orientation"
check_contains "FreePrintStudio/ContentView.swift" "FreePrintStudioUnit" "Debug PDF export must support measurement unit arguments"
check_contains "Scripts/validate_pdf_export.sh" "FREEPRINTSTUDIO_UNIT" "PDF export validation must support measurement unit overrides"
check_contains "Scripts/validate_pdf_export.sh" "centimeter-a4-stretch" "PDF export validation must cover centimeter target sizes"
check_contains "Scripts/validate_pdf_export.sh" "millimeter-a4-stretch" "PDF export validation must cover millimeter target sizes"
check_contains "Scripts/validate_pdf_export.sh" "4,5" "PDF export validation must cover localized decimal comma width input"
check_contains "Scripts/validate_pdf_export.sh" "6,25" "PDF export validation must cover localized decimal comma height input"
check_file "Scripts/validate_test_ruler_pdf_export.sh" "Test Ruler PDF export validation script is required"
if [[ ! -x "Scripts/validate_test_ruler_pdf_export.sh" ]]; then
  printf 'FAIL: Test Ruler PDF export validation script must be executable (Scripts/validate_test_ruler_pdf_export.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_test_ruler_pdf_export.sh" "FREEPRINTSTUDIO_PDF_CONTENT=testRuler" "Test Ruler PDF validation must exercise the generated calibration guide"
check_contains "Scripts/validate_test_ruler_pdf_export.sh" "FREEPRINTSTUDIO_TARGET_WIDTH=6" "Test Ruler PDF validation must require a 6 inch output width"
check_contains "Scripts/validate_test_ruler_pdf_export.sh" "FREEPRINTSTUDIO_TARGET_HEIGHT=1" "Test Ruler PDF validation must require a 1 inch output height"
check_contains "Scripts/validate_pdf_export.sh" "FREEPRINTSTUDIO_PDF_CONTENT" "PDF export validation must support generated Test Ruler content"
check_contains "Scripts/validate_pdf_export.sh" "-FreePrintStudioUseTestRuler" "PDF export validation must launch the app with the built-in Test Ruler"
check_contains "Scripts/validate_pdf_export.sh" "test-ruler-stretch" "Default PDF export validation must include the Test Ruler exact-size scenario"
check_contains "Scripts/validate_pdf_export.sh" "PDF_VALIDATION_MANIFEST_PATH" "PDF export validation must write a machine-readable manifest"
check_contains "Scripts/validate_pdf_export.sh" "pdf-export-validation.tsv" "PDF export validation must use a deterministic manifest name"
check_contains "Scripts/validate_pdf_export.sh" "mediaBoxWidthPt" "PDF export validation manifest must include structured page-size columns"
check_contains "Scripts/validate_pdf_export.sh" "drawWidthPt" "PDF export validation manifest must include structured draw-matrix columns"
check_contains "FreePrintStudio/ContentView.swift" "exportDebugPDFIfRequested(arguments: arguments)" "Debug Test Ruler launch must support automatic PDF export"
check_contains "Scripts/verify_release.sh" "validate_pdf_export.sh" "Release verification must validate PDF export including Test Ruler coverage"
check_contains "Scripts/verify_release.sh" "PDF validation manifest missing" "Submission packet generation must rerun PDF validation when evidence is missing"
check_contains "AppStore/release-inputs-worksheet.md" "Scripts/validate_test_ruler_pdf_export.sh" "Release worksheet must document the local Test Ruler PDF evidence command"
check_contains "Scripts/validate_pdf_export.sh" "MAX_SIMULATOR_CANDIDATES" "PDF export validation must limit simulator candidate attempts"
check_contains "Scripts/validate_pdf_export.sh" "TEMPORARY_SIMULATOR_BOOT_TIMEOUT_SECONDS" "PDF export validation must allow fresh simulators enough first-boot time"
check_contains "Scripts/validate_pdf_export.sh" "TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS" "PDF export validation must allow fresh simulators enough install time"
check_contains "Scripts/validate_pdf_export.sh" 'TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_INSTALL_TIMEOUT_SECONDS:-240}"' "PDF export validation must allow enough CI time for first install on a temporary simulator"
check_contains "Scripts/validate_pdf_export.sh" 'TEMPORARY_SIMULATOR_CONTAINER_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_CONTAINER_TIMEOUT_SECONDS:-120}"' "PDF export validation must allow enough CI time to resolve the data container on a temporary simulator"
check_contains "Scripts/validate_pdf_export.sh" "TEMPORARY_SIMULATOR_APP_LAUNCH_TIMEOUT_SECONDS" "PDF export validation must allow fresh simulators enough first-launch time"
check_contains "Scripts/validate_pdf_export.sh" "TEMPORARY_SIMULATOR_APP_LAUNCH_ATTEMPTS" "PDF export validation must retry fresh simulator app launches"
check_contains "Scripts/validate_pdf_export.sh" "TEMPORARY_SIMULATOR_PDF_WAIT_ATTEMPTS" "PDF export validation must allow fresh simulators enough PDF write time"
check_contains "Scripts/validate_pdf_export.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl list devices booted" "PDF export validation must bound booted simulator discovery"
check_contains "Scripts/validate_pdf_export.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl list devices available" "PDF export validation must bound available simulator discovery"
check_contains "Scripts/validate_pdf_export.sh" "create_temporary_simulator" "PDF export validation must create a temporary simulator fallback"
check_contains "Scripts/validate_pdf_export.sh" "xcrun simctl create" "PDF export validation must create a fresh simulator when installed devices fail"
check_contains "Scripts/validate_pdf_export.sh" "cleanup_temporary_simulator" "PDF export validation must clean up temporary simulators"
check_contains "Scripts/validate_pdf_export.sh" "xcrun simctl delete" "PDF export validation must delete temporary simulators after validation"
check_not_contains "Scripts/validate_pdf_export.sh" 'DEVICE="$(select_installed_simulator)"' "PDF export validation must keep simulator selection in the parent shell for cleanup"
check_contains "Scripts/validate_pdf_export.sh" "run_with_timeout \"\$SIMCTL_TIMEOUT_SECONDS\" xcrun simctl boot \"\$device\"" "PDF export validation must bound simulator boot commands"
check_contains "Scripts/validate_pdf_export.sh" "bootstatus_timeout" "PDF export validation must choose a bounded simulator boot wait"
check_contains "Scripts/validate_pdf_export.sh" "xcrun simctl bootstatus" "PDF export validation must wait for simulator boot readiness"
check_contains "Scripts/validate_pdf_export.sh" "XCODEBUILD_TIMEOUT_SECONDS" "PDF export validation must bound simulator build commands"
check_contains "Scripts/validate_pdf_export.sh" "run_with_timeout \"\$container_timeout\" xcrun simctl get_app_container" "PDF export validation must bound simulator container lookup"
check_contains "Scripts/validate_pdf_export.sh" "launch_timeout" "PDF export validation must choose a bounded app launch wait"
check_contains "Scripts/validate_pdf_export.sh" "launch_status" "PDF export validation must inspect exported PDFs after app launch timeouts"
check_contains "Scripts/validate_pdf_export.sh" "launch_attempts" "PDF export validation must bound app launch retries"
check_contains "Scripts/validate_pdf_export.sh" "Retrying PDF export launch" "PDF export validation must log app launch retries clearly"
check_contains "Scripts/validate_pdf_export.sh" "xcrun simctl launch" "PDF export validation must exercise bounded app launch commands"
check_contains "Scripts/validate_pdf_export.sh" "--terminate-running-process" "PDF export validation must force each scenario to relaunch with fresh arguments"
check_file "Scripts/validate_simulator_workflow.sh" "Simulator workflow validation script is required"
if [[ ! -x "Scripts/validate_simulator_workflow.sh" ]]; then
  printf 'FAIL: Simulator workflow validation script must be executable (Scripts/validate_simulator_workflow.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_simulator_workflow.sh" "capture_app_store_screenshots.sh" "Simulator workflow validation must capture an app screenshot"
check_contains "Scripts/validate_simulator_workflow.sh" "validate_pdf_export.sh" "Simulator workflow validation must verify PDF export"
check_contains "Scripts/validate_simulator_workflow.sh" "PDF_VALIDATION_MANIFEST_PATH" "Simulator workflow validation must not overwrite the release PDF manifest"
check_contains "Scripts/validate_simulator_workflow.sh" "FREEPRINTSTUDIO_UNIT=centimeter" "Simulator workflow validation must exercise unit switching"
check_contains "Scripts/validate_simulator_workflow.sh" "validationErrorRedPixels" "Simulator workflow validation must reject validation error screenshots"
check_contains "Scripts/validate_simulator_workflow.sh" "safe_output_dir" "Simulator workflow validation must validate output directories before cleanup"
check_contains "Scripts/validate_simulator_workflow.sh" "Refusing to use" "Simulator workflow validation must explain unsafe output directory overrides"
check_contains "Scripts/validate_simulator_workflow.sh" "simulator workflow output" "Simulator workflow validation must identify unsafe output directory overrides"
check_contains "Scripts/validate_simulator_workflow.sh" "/tmp/freeprintstudio-" "Simulator workflow validation must allow only namespaced temporary outputs"
check_contains "Scripts/validate_simulator_workflow.sh" "build" "Simulator workflow validation must allow repository build outputs"
check_contains "Scripts/verify_release.sh" "validate_simulator_workflow.sh" "Release verification must expose simulator workflow validation"
check_file "Scripts/validate_photo_import.sh" "Photo import validation script is required"
if [[ ! -x "Scripts/validate_photo_import.sh" ]]; then
  printf 'FAIL: Photo import validation script must be executable (Scripts/validate_photo_import.sh)\n'
  failures=$((failures + 1))
fi
check_file "FreePrintStudioUITests/PhotoImportUITests.swift" "Photo import UI test is required"
check_contains "Scripts/validate_photo_import.sh" "simctl addmedia" "Photo import validation must seed the simulator photo library"
check_contains "Scripts/validate_photo_import.sh" "FreePrintStudioUITests/PhotoImportUITests" "Photo import validation must run the dedicated UI test"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "Choose Image" "Photo import UI test must exercise the real Choose Image control"
check_contains "FreePrintStudioUITests/PhotoImportUITests.swift" "Change Image" "Photo import UI test must verify the app receives the selected photo"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "FreePrintStudioUITests" "Xcode project must include the UI test target"
check_contains "FreePrintStudio.xcodeproj/xcshareddata/xcschemes/FreePrintStudio.xcscheme" "FreePrintStudioUITests.xctest" "Shared scheme must expose the photo import UI tests"
check_contains "Scripts/verify_release.sh" "validate_photo_import.sh" "Release verification must expose photo import validation"
check_file "Scripts/validate_review_ui.sh" "Review UI validation script is required"
if [[ -f "Scripts/validate_review_ui.sh" && ! -x "Scripts/validate_review_ui.sh" ]]; then
  printf 'FAIL: Review UI validation script must be executable (Scripts/validate_review_ui.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_review_ui.sh" "testAboutScreenShowsReviewAndSupportInformation" "Review UI validation must run the App Review information UI test"
check_contains "Scripts/validate_review_ui.sh" "CODE_SIGNING_ALLOWED=NO" "Review UI validation must run without signing in CI"
check_contains "Scripts/validate_review_ui.sh" "SIMCTL_TIMEOUT_SECONDS" "Review UI validation must bound simulator discovery and boot commands"
check_contains "Scripts/validate_review_ui.sh" "XCODEBUILD_TIMEOUT_SECONDS" "Review UI validation must bound xcodebuild UI test execution"
check_contains "Scripts/validate_review_ui.sh" "REVIEW_UI_MAX_ATTEMPTS" "Review UI validation must bound retries for transient simulator launch failures"
check_contains "Scripts/validate_review_ui.sh" "Failed to get background assertion" "Review UI validation must identify transient background assertion launch failures"
check_contains "Scripts/validate_review_ui.sh" "Retrying Review UI validation" "Review UI validation must explain transient launch retries"
check_contains "Scripts/validate_review_ui.sh" "xcrun simctl terminate" "Review UI validation must clear the target app before retrying launch flakes"
check_contains "Scripts/validate_review_ui.sh" "run_with_timeout" "Review UI validation must use command-level timeouts"
check_contains "Scripts/validate_review_ui.sh" "xcrun simctl bootstatus" "Review UI validation must wait for simulator boot readiness"
check_contains "Scripts/validate_review_ui.sh" "Review UI validation command timed out" "Review UI validation must report timeout failures clearly"
check_contains "Scripts/verify_release.sh" "validate_review_ui.sh" "Release verification must expose review UI validation"
check_contains "Scripts/verify_release.sh" "review-ui" "Release verification must provide a review-ui command"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh review-ui" "Release workflow must validate review-facing UI information"
check_contains "README.md" "Scripts/verify_release.sh review-ui" "README must document the review UI release gate"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh review-ui" "Release checklist must include review UI validation"
check_file "Scripts/validate_print_sheet.sh" "Print sheet validation script is required"
if [[ ! -x "Scripts/validate_print_sheet.sh" ]]; then
  printf 'FAIL: Print sheet validation script must be executable (Scripts/validate_print_sheet.sh)\n'
  failures=$((failures + 1))
fi
check_contains "FreePrintStudio/ContentView.swift" "FreePrintStudioAutoOpenPrintSheet" "Debug workflow must support automatically opening the system print sheet"
check_contains "FreePrintStudio/ContentView.swift" "FreePrintStudioPrintSheetStatusPath" "Debug workflow must write print sheet validation status"
check_contains "FreePrintStudio/Printing/PrintService.swift" "@discardableResult" "PrintService must expose whether the print sheet was presented"
check_contains "FreePrintStudio/Printing/PrintService.swift" "presentationFailed" "PrintService must report print sheet presentation failure"
check_contains "Scripts/validate_print_sheet.sh" "FreePrintStudioAutoOpenPrintSheet" "Print sheet validation must exercise the debug print sheet workflow"
check_contains "Scripts/validate_print_sheet.sh" "FreePrintStudioPrintSheetStatusPath" "Print sheet validation must read the debug print sheet status"
check_contains "Scripts/verify_release.sh" "validate_print_sheet.sh" "Release verification must expose print sheet validation"
check_contains "Scripts/validate_print_sheet.sh" "SIMCTL_TIMEOUT_SECONDS" "Print sheet validation must bound simulator install commands"
check_contains "Scripts/validate_print_sheet.sh" "Skipping simulator after install failure" "Print sheet validation must skip unhealthy simulators"
check_file "Scripts/check_app_store_readiness.sh" "App Store readiness audit script is required"
check_contains "Scripts/check_app_store_readiness.sh" "DEVELOPMENT_TEAM_ID" "Readiness audit must check Apple Developer Team ID"
check_contains "Scripts/check_app_store_readiness.sh" "check_code_signing_assets.sh" "Readiness audit must run the precise code signing asset preflight"
check_contains "Scripts/check_app_store_readiness.sh" "privacy-policy.html" "Readiness audit must check the public privacy policy URL"
check_contains "Scripts/check_app_store_readiness.sh" "APP_REVIEW_CONTACT_EMAIL" "Readiness audit must check App Review contact variables"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_review_contact.sh" "Readiness audit must validate App Review contact details"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_privacy_details.sh" "Readiness audit must validate App Privacy Details"
check_contains "Scripts/check_app_store_readiness.sh" "validate_privacy_surface.sh" "Readiness audit must validate privacy surface"
check_contains "Scripts/check_app_store_readiness.sh" 'block "Fastlane App Store Connect API credentials are not configured' "Readiness audit must block missing App Store Connect API credentials"
check_not_contains "Scripts/check_app_store_readiness.sh" 'warn "Fastlane App Store Connect API credentials are not configured' "Readiness audit must not downgrade missing App Store Connect API credentials to a warning"
check_contains "Scripts/check_app_store_readiness.sh" "app_store_connect_state_checked" "Readiness audit must only warn about account-specific App Store Connect verification when it could not query account state"
check_contains "Scripts/check_app_store_readiness.sh" "check_app_store_connect_state.sh" "Readiness audit must run the App Store Connect state preflight when credentials are available"
check_contains "Scripts/check_app_store_readiness.sh" "APP_STORE_CONNECT_SKIP_BUILD_CHECK=1" "Archive readiness audit must not require a processed TestFlight build before the first App Store archive"
check_contains "Scripts/check_app_store_readiness.sh" "App Store Connect app record and version preflight passed" "Archive readiness audit must describe the pre-upload App Store Connect check accurately"
check_file "Scripts/check_app_store_connect_credentials.sh" "App Store Connect credential audit script is required"
check_contains "Scripts/check_app_store_connect_credentials.sh" "APP_STORE_CONNECT_API_KEY_JSON" "Credential audit must support Fastlane API key JSON"
check_contains "Scripts/check_app_store_connect_credentials.sh" "ASC_KEY_PATH" "Credential audit must support App Store Connect private key paths"
app_store_connect_api_json_test_dir="$(mktemp -d)"
app_store_connect_api_json_path="$app_store_connect_api_json_test_dir/fastlane-api-key.json"
app_store_connect_api_json_log="$app_store_connect_api_json_test_dir/asc-credentials.log"
app_store_connect_api_json_key_path="$app_store_connect_api_json_test_dir/AuthKey_KEYID12345.p8"
cat >"$app_store_connect_api_json_path" <<EOF
{
  "key_id": "KEYID12345",
  "issuer_id": "00000000-0000-0000-0000-000000000001",
  "key_filepath": "$app_store_connect_api_json_test_dir/missing/AuthKey_KEYID12345.p8"
}
EOF
chmod 600 "$app_store_connect_api_json_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject API JSON whose key_filepath does not exist\n'
  failures=$((failures + 1))
elif ! grep -q 'key_filepath does not exist' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify a missing API JSON key_filepath\n'
  failures=$((failures + 1))
elif grep -Fq "$app_store_connect_api_json_test_dir/missing/AuthKey_KEYID12345.p8" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full missing API JSON key_filepath\n'
  failures=$((failures + 1))
fi
missing_app_store_connect_api_json_path="$app_store_connect_api_json_test_dir/missing/fastlane-api-key.json"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$missing_app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject a missing APP_STORE_CONNECT_API_KEY_JSON file\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_CONNECT_API_KEY_JSON does not exist' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify a missing APP_STORE_CONNECT_API_KEY_JSON file\n'
  failures=$((failures + 1))
elif grep -Fq "$missing_app_store_connect_api_json_path" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full missing APP_STORE_CONNECT_API_KEY_JSON path\n'
  failures=$((failures + 1))
fi
missing_app_store_connect_triplet_path="$app_store_connect_api_json_test_dir/missing/AuthKey_TRIPLET123.p8"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  ASC_KEY_ID=KEYID12345 ASC_ISSUER_ID=00000000-0000-0000-0000-000000000001 ASC_KEY_PATH="$missing_app_store_connect_triplet_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject a missing ASC_KEY_PATH file\n'
  failures=$((failures + 1))
elif ! grep -q 'ASC_KEY_PATH does not exist' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify a missing ASC_KEY_PATH file\n'
  failures=$((failures + 1))
elif grep -Fq "$missing_app_store_connect_triplet_path" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full missing ASC_KEY_PATH path\n'
  failures=$((failures + 1))
fi
cat >"$app_store_connect_api_json_key_path" <<'EOF'
-----BEGIN PRIVATE KEY-----
release-check-placeholder
-----END PRIVATE KEY-----
EOF
chmod 600 "$app_store_connect_api_json_key_path"
cat >"$app_store_connect_api_json_path" <<'EOF'
{
  "key_id": "short",
  "issuer_id": "not-a-uuid",
  "key_filepath": "AuthKey_KEYID12345.p8"
}
EOF
chmod 600 "$app_store_connect_api_json_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject malformed API JSON key_id and issuer_id values\n'
  failures=$((failures + 1))
elif ! grep -q 'key_id must be a 10-character App Store Connect API key id' "$app_store_connect_api_json_log" \
  || ! grep -q 'issuer_id must be an App Store Connect issuer UUID' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit malformed API JSON failure should identify both key_id and issuer_id format issues\n'
  failures=$((failures + 1))
fi
app_store_connect_triplet_key_path="$app_store_connect_api_json_test_dir/AuthKey_TRIPLET123.p8"
cat >"$app_store_connect_triplet_key_path" <<'EOF'
-----BEGIN PRIVATE KEY-----
release-check-placeholder
-----END PRIVATE KEY-----
EOF
chmod 600 "$app_store_connect_triplet_key_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  ASC_KEY_ID=short ASC_ISSUER_ID=not-a-uuid ASC_KEY_PATH="$app_store_connect_triplet_key_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject malformed ASC_KEY_ID and ASC_ISSUER_ID values\n'
  failures=$((failures + 1))
elif ! grep -q 'ASC_KEY_ID must be a 10-character App Store Connect API key id' "$app_store_connect_api_json_log" \
  || ! grep -q 'ASC_ISSUER_ID must be an App Store Connect issuer UUID' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit malformed triplet failure should identify both ASC_KEY_ID and ASC_ISSUER_ID format issues\n'
  failures=$((failures + 1))
fi
cat >"$app_store_connect_api_json_key_path" <<'EOF'
-----BEGIN PRIVATE KEY-----
release-check-placeholder
-----END PRIVATE KEY-----
EOF
chmod 600 "$app_store_connect_api_json_key_path"
cat >"$app_store_connect_api_json_path" <<'EOF'
{
  "key_id": "KEYID12345",
  "issuer_id": "00000000-0000-0000-0000-000000000001",
  "key_filepath": "AuthKey_KEYID12345.p8"
}
EOF
chmod 600 "$app_store_connect_api_json_path"
if ! RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must accept API JSON with a readable relative key_filepath\n'
  failures=$((failures + 1))
fi
loose_app_store_connect_api_json_path="$app_store_connect_api_json_test_dir/loose-fastlane-api-key.json"
cat >"$loose_app_store_connect_api_json_path" <<'EOF'
{
  "key_id": "KEYID12345",
  "issuer_id": "00000000-0000-0000-0000-000000000001",
  "key_filepath": "AuthKey_KEYID12345.p8"
}
EOF
chmod 644 "$loose_app_store_connect_api_json_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$loose_app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject overly broad APP_STORE_CONNECT_API_KEY_JSON file permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_CONNECT_API_KEY_JSON permissions are too broad' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify overly broad APP_STORE_CONNECT_API_KEY_JSON permissions\n'
  failures=$((failures + 1))
elif grep -Fq "$loose_app_store_connect_api_json_path" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full overly broad APP_STORE_CONNECT_API_KEY_JSON path\n'
  failures=$((failures + 1))
fi
chmod 600 "$loose_app_store_connect_api_json_path"
chmod 644 "$app_store_connect_api_json_key_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$loose_app_store_connect_api_json_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject overly broad API JSON key_filepath permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_CONNECT_API_KEY_JSON key_filepath permissions are too broad' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify overly broad API JSON key_filepath permissions\n'
  failures=$((failures + 1))
elif grep -Fq "$app_store_connect_api_json_key_path" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full overly broad API JSON key_filepath\n'
  failures=$((failures + 1))
fi
chmod 600 "$app_store_connect_api_json_key_path"
chmod 644 "$app_store_connect_triplet_key_path"
if RELEASE_ENV_PATH="$app_store_connect_api_json_test_dir/missing-release.env" \
  ASC_KEY_ID=KEYID12345 ASC_ISSUER_ID=00000000-0000-0000-0000-000000000001 ASC_KEY_PATH="$app_store_connect_triplet_key_path" \
  Scripts/check_app_store_connect_credentials.sh >"$app_store_connect_api_json_log" 2>&1; then
  printf 'FAIL: Credential audit must reject overly broad ASC_KEY_PATH file permissions\n'
  failures=$((failures + 1))
elif ! grep -q 'ASC_KEY_PATH permissions are too broad' "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit should identify overly broad ASC_KEY_PATH permissions\n'
  failures=$((failures + 1))
elif grep -Fq "$app_store_connect_triplet_key_path" "$app_store_connect_api_json_log"; then
  printf 'FAIL: Credential audit must not print the full overly broad ASC_KEY_PATH path\n'
  failures=$((failures + 1))
fi
rm -rf "$app_store_connect_api_json_test_dir"
check_file "Scripts/check_code_signing_assets.sh" "Code signing asset preflight script is required"
if [[ ! -x "Scripts/check_code_signing_assets.sh" ]]; then
  printf 'FAIL: Code signing asset preflight script must be executable (Scripts/check_code_signing_assets.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/check_code_signing_assets.sh" "Apple Distribution" "Code signing preflight must require an Apple Distribution identity"
check_contains "Scripts/check_code_signing_assets.sh" "com.dannagrace.FreePrintStudio" "Code signing preflight must verify the release bundle id"
check_contains "Scripts/check_code_signing_assets.sh" "app-store-connect" "Code signing preflight must verify App Store Connect export intent"
check_contains "Scripts/check_code_signing_assets.sh" "ProvisionedDevices" "Code signing preflight must reject development or ad hoc provisioning profiles"
check_not_contains "Scripts/check_code_signing_assets.sh" 'team $team_id' "Code signing preflight must not print the selected Apple Developer Team ID"
check_not_contains "Scripts/check_code_signing_assets.sh" 'team {team_id}' "Code signing preflight must not print the selected Apple Developer Team ID from profile matching"
check_not_contains "Scripts/check_code_signing_assets.sh" 'matches\[0\]' "Code signing preflight must not print provisioning profile names"
check_not_contains "Scripts/check_code_signing_assets.sh" 'profile {path.name}: {exc}' "Code signing preflight must not print provisioning profile filenames or parser errors"
check_file "Scripts/generate_signing_readiness_report.sh" "Signing readiness report generator is required"
if [[ -f "Scripts/generate_signing_readiness_report.sh" && ! -x "Scripts/generate_signing_readiness_report.sh" ]]; then
  printf 'FAIL: Signing readiness report generator must be executable (Scripts/generate_signing_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_signing_readiness_report.sh" "signing-readiness-report.md" "Signing readiness report generator must use a deterministic output name"
check_contains "Scripts/generate_signing_readiness_report.sh" "Apple Distribution" "Signing readiness report must summarize Apple Distribution identity state"
check_contains "Scripts/generate_signing_readiness_report.sh" "ProvisionedDevices" "Signing readiness report must identify App Store provisioning profile requirements"
check_contains "Scripts/generate_signing_readiness_report.sh" "redacted" "Signing readiness report must avoid printing private signing values"
check_not_contains "Scripts/generate_signing_readiness_report.sh" "DEVELOPMENT_TEAM_ID=<" "Signing readiness report must use shell-safe Team ID placeholders"
check_contains "Scripts/generate_signing_readiness_report.sh" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Signing readiness report must show the guarded archive command"
check_file "Scripts/generate_app_store_connect_readiness_report.sh" "App Store Connect readiness report generator is required"
if [[ -f "Scripts/generate_app_store_connect_readiness_report.sh" && ! -x "Scripts/generate_app_store_connect_readiness_report.sh" ]]; then
  printf 'FAIL: App Store Connect readiness report generator must be executable (Scripts/generate_app_store_connect_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "app-store-connect-readiness-report.md" "App Store Connect readiness report generator must use a deterministic output name"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "APP_STORE_CONNECT_API_KEY_JSON" "App Store Connect readiness report must summarize API JSON credential state"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "ASC_KEY_ID" "App Store Connect readiness report must summarize API key ID state"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "ASC_ISSUER_ID" "App Store Connect readiness report must summarize issuer ID state"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "ASC_KEY_PATH" "App Store Connect readiness report must summarize private key file state"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "FASTLANE_USER" "App Store Connect readiness report must summarize Fastlane Apple ID state"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/check_app_store_connect_credentials.sh" "App Store Connect readiness report must reference credential validation"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/run_fastlane.sh ios app_store_connect_state" "App Store Connect readiness report must reference the account state preflight"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/preflight_testflight_upload.sh" "App Store Connect readiness report must reference the TestFlight preflight"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/preflight_app_review_submission.sh" "App Store Connect readiness report must reference the App Review preflight"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "redacted" "App Store Connect readiness report must avoid printing private credentials"
asc_report_loose_json_dir="$(mktemp -d)"
asc_report_loose_json_path="$asc_report_loose_json_dir/fastlane-api-key.json"
asc_report_loose_json_report="$asc_report_loose_json_dir/app-store-connect-readiness-report.md"
cat >"$asc_report_loose_json_path" <<'EOF'
{
  "key_id": "KEYID12345",
  "issuer_id": "00000000-0000-0000-0000-000000000001",
  "key": "-----BEGIN PRIVATE KEY-----\nrelease-check-placeholder\n-----END PRIVATE KEY-----"
}
EOF
chmod 644 "$asc_report_loose_json_path"
RELEASE_ENV_PATH="$asc_report_loose_json_dir/missing-release.env" \
  APP_STORE_CONNECT_API_KEY_JSON="$asc_report_loose_json_path" \
  Scripts/generate_app_store_connect_readiness_report.sh "$asc_report_loose_json_report" >/dev/null
if ! grep -q 'APP_STORE_CONNECT_API_KEY_JSON` permissions.*Too broad' "$asc_report_loose_json_report"; then
  printf 'FAIL: App Store Connect readiness report must flag broad API JSON permissions before parsing private credentials\n'
  failures=$((failures + 1))
fi
if grep -q 'API JSON parses as JSON | Yes' "$asc_report_loose_json_report"; then
  printf 'FAIL: App Store Connect readiness report must not parse overly broad API JSON files\n'
  failures=$((failures + 1))
fi
if grep -Fq "$asc_report_loose_json_path" "$asc_report_loose_json_report"; then
  printf 'FAIL: App Store Connect readiness report must not print the full loose API JSON path\n'
  failures=$((failures + 1))
fi
rm -rf "$asc_report_loose_json_dir"
asc_report_loose_key_dir="$(mktemp -d)"
asc_report_loose_key_path="$asc_report_loose_key_dir/AuthKey_KEYID12345.p8"
asc_report_loose_key_report="$asc_report_loose_key_dir/app-store-connect-readiness-report.md"
cat >"$asc_report_loose_key_path" <<'EOF'
-----BEGIN PRIVATE KEY-----
release-check-placeholder
-----END PRIVATE KEY-----
EOF
chmod 644 "$asc_report_loose_key_path"
RELEASE_ENV_PATH="$asc_report_loose_key_dir/missing-release.env" \
  ASC_KEY_ID=KEYID12345 \
  ASC_ISSUER_ID=00000000-0000-0000-0000-000000000001 \
  ASC_KEY_PATH="$asc_report_loose_key_path" \
  Scripts/generate_app_store_connect_readiness_report.sh "$asc_report_loose_key_report" >/dev/null
if ! grep -q 'ASC_KEY_PATH` permissions.*Too broad' "$asc_report_loose_key_report"; then
  printf 'FAIL: App Store Connect readiness report must flag broad ASC_KEY_PATH permissions before reading private credentials\n'
  failures=$((failures + 1))
fi
if grep -q 'ASC_KEY_PATH` looks like a private key | Yes' "$asc_report_loose_key_report"; then
  printf 'FAIL: App Store Connect readiness report must not read overly broad ASC_KEY_PATH files\n'
  failures=$((failures + 1))
fi
if grep -Fq "$asc_report_loose_key_path" "$asc_report_loose_key_report"; then
  printf 'FAIL: App Store Connect readiness report must not print the full loose ASC_KEY_PATH path\n'
  failures=$((failures + 1))
fi
rm -rf "$asc_report_loose_key_dir"
check_file "Scripts/validate_app_review_contact.sh" "App Review contact validation script is required"
if [[ ! -x "Scripts/validate_app_review_contact.sh" ]]; then
  printf 'FAIL: App Review contact validation script must be executable (Scripts/validate_app_review_contact.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_review_contact.sh" "APP_REVIEW_CONTACT_EMAIL" "App Review contact validation must check the email address"
check_contains "Scripts/validate_app_review_contact.sh" "APP_REVIEW_CONTACT_PHONE" "App Review contact validation must check the phone number"
check_contains "Scripts/validate_app_review_contact.sh" "email pattern" "App Review contact validation must document email format checks"
app_review_contact_placeholder_phone_test_dir="$(mktemp -d)"
app_review_contact_placeholder_phone_env="$app_review_contact_placeholder_phone_test_dir/release.env"
app_review_contact_placeholder_phone_log="$app_review_contact_placeholder_phone_test_dir/app-review-contact.log"
cat >"$app_review_contact_placeholder_phone_env" <<'EOF'
APP_REVIEW_CONTACT_FIRST_NAME=Grace
APP_REVIEW_CONTACT_LAST_NAME=Lee
APP_REVIEW_CONTACT_PHONE=+1-555-0100
APP_REVIEW_CONTACT_EMAIL=review@freeprintstudio.test
EOF
if RELEASE_ENV_PATH="$app_review_contact_placeholder_phone_env" \
  Scripts/validate_app_review_contact.sh >"$app_review_contact_placeholder_phone_log" 2>&1; then
  printf 'FAIL: App Review contact validation must reject 555 placeholder phone numbers\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_REVIEW_CONTACT_PHONE must not use a 555 placeholder number' "$app_review_contact_placeholder_phone_log"; then
  printf 'FAIL: App Review contact placeholder-phone failure should identify the 555 placeholder phone number\n'
  failures=$((failures + 1))
fi
rm -rf "$app_review_contact_placeholder_phone_test_dir"
check_file "Scripts/generate_app_review_contact_readiness_report.sh" "App Review contact readiness report generator is required"
if [[ -f "Scripts/generate_app_review_contact_readiness_report.sh" && ! -x "Scripts/generate_app_review_contact_readiness_report.sh" ]]; then
  printf 'FAIL: App Review contact readiness report generator must be executable (Scripts/generate_app_review_contact_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "app-review-contact-readiness-report.md" "App Review contact readiness report generator must use a deterministic output name"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "APP_REVIEW_CONTACT_FIRST_NAME" "App Review contact readiness report must summarize first name state"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "APP_REVIEW_CONTACT_LAST_NAME" "App Review contact readiness report must summarize last name state"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "APP_REVIEW_CONTACT_PHONE" "App Review contact readiness report must summarize phone state"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "APP_REVIEW_CONTACT_EMAIL" "App Review contact readiness report must summarize email state"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "Scripts/validate_app_review_contact.sh" "App Review contact readiness report must reference the strict validator"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "redacted" "App Review contact readiness report must avoid printing private contact values"
check_file "Scripts/check_app_store_connect_state.sh" "App Store Connect state preflight script is required"
check_contains "Scripts/check_app_store_connect_state.sh" "Spaceship::ConnectAPI::App.find" "App Store Connect state preflight must verify the app record"
check_contains "Scripts/check_app_store_connect_state.sh" "Spaceship::ConnectAPI::Build.all" "App Store Connect state preflight must inspect TestFlight builds"
check_contains "Scripts/check_app_store_connect_state.sh" "APP_STORE_BUILD_NUMBER" "App Store Connect state preflight must support a selected build number"
check_contains "Scripts/check_app_store_connect_state.sh" "APP_STORE_CONNECT_SKIP_BUILD_CHECK" "App Store Connect state preflight must support app/version-only checks before TestFlight upload"
check_contains "Scripts/check_app_store_connect_state.sh" "api_key_json_path.dirname" "App Store Connect state preflight must resolve API JSON relative key_filepath values from the JSON file directory"
check_contains "Scripts/check_app_store_connect_state.sh" "APP_STORE_BUILD_NUMBER still uses a placeholder" "App Store Connect state preflight must reject selected-build placeholders before account queries"
check_contains "Scripts/check_app_store_connect_state.sh" "APP_STORE_BUILD_NUMBER is missing" "App Store Connect state preflight must require a selected build before account queries"
asc_state_missing_build_test_dir="$(mktemp -d)"
asc_state_missing_build_env="$asc_state_missing_build_test_dir/release.env"
asc_state_missing_build_log="$asc_state_missing_build_test_dir/app-store-connect-state-missing-build.log"
: >"$asc_state_missing_build_env"
if RELEASE_ENV_PATH="$asc_state_missing_build_env" \
  Scripts/check_app_store_connect_state.sh >"$asc_state_missing_build_log" 2>&1; then
  printf 'FAIL: App Store Connect state preflight must reject a missing APP_STORE_BUILD_NUMBER before querying account state\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER is missing' "$asc_state_missing_build_log"; then
  printf 'FAIL: App Store Connect state missing-build failure should identify APP_STORE_BUILD_NUMBER as missing\n'
  failures=$((failures + 1))
fi
rm -rf "$asc_state_missing_build_test_dir"
asc_state_placeholder_build_test_dir="$(mktemp -d)"
asc_state_placeholder_build_env="$asc_state_placeholder_build_test_dir/release.env"
asc_state_placeholder_build_log="$asc_state_placeholder_build_test_dir/app-store-connect-state-placeholder.log"
printf 'APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER\n' >"$asc_state_placeholder_build_env"
if RELEASE_ENV_PATH="$asc_state_placeholder_build_env" \
  Scripts/check_app_store_connect_state.sh >"$asc_state_placeholder_build_log" 2>&1; then
  printf 'FAIL: App Store Connect state preflight must reject PROCESSED_BUILD_NUMBER before querying account state\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder' "$asc_state_placeholder_build_log"; then
  printf 'FAIL: App Store Connect state placeholder-build failure should identify APP_STORE_BUILD_NUMBER as a placeholder\n'
  failures=$((failures + 1))
fi
rm -rf "$asc_state_placeholder_build_test_dir"
asc_state_lowercase_placeholder_build_test_dir="$(mktemp -d)"
asc_state_lowercase_placeholder_build_env="$asc_state_lowercase_placeholder_build_test_dir/release.env"
asc_state_lowercase_placeholder_build_log="$asc_state_lowercase_placeholder_build_test_dir/app-store-connect-state-lowercase-placeholder.log"
printf 'APP_STORE_BUILD_NUMBER=todo\n' >"$asc_state_lowercase_placeholder_build_env"
if RELEASE_ENV_PATH="$asc_state_lowercase_placeholder_build_env" \
  Scripts/check_app_store_connect_state.sh >"$asc_state_lowercase_placeholder_build_log" 2>&1; then
  printf 'FAIL: App Store Connect state preflight must reject lowercase todo before querying account state\n'
  failures=$((failures + 1))
elif ! grep -q 'APP_STORE_BUILD_NUMBER still uses a placeholder' "$asc_state_lowercase_placeholder_build_log"; then
  printf 'FAIL: App Store Connect state lowercase placeholder-build failure should identify APP_STORE_BUILD_NUMBER as a placeholder\n'
  failures=$((failures + 1))
fi
rm -rf "$asc_state_lowercase_placeholder_build_test_dir"
check_file "Scripts/preflight_testflight_upload.sh" "TestFlight upload preflight script is required"
if [[ ! -x "Scripts/preflight_testflight_upload.sh" ]]; then
  printf 'FAIL: TestFlight upload preflight script must be executable (Scripts/preflight_testflight_upload.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_testflight_upload.sh" "Scripts/check_app_store_connect_credentials.sh" "TestFlight preflight must validate App Store Connect credentials"
check_contains "Scripts/preflight_testflight_upload.sh" "source Scripts/load_release_env.sh" "TestFlight preflight must load private release inputs before checking credentials and exports"
check_contains "Scripts/preflight_testflight_upload.sh" "Scripts/validate_app_store_export.sh" "TestFlight preflight must validate the signed IPA export"
check_contains "Scripts/preflight_testflight_upload.sh" "APP_STORE_CONNECT_SKIP_BUILD_CHECK=1" "TestFlight preflight must verify the App Store Connect app/version before upload without requiring an existing build"
check_contains "Scripts/preflight_testflight_upload.sh" "Scripts/check_app_store_connect_state.sh" "TestFlight preflight must query App Store Connect state"
check_contains "Scripts/preflight_testflight_upload.sh" "Scripts/print_release_input_status.sh --strict" "TestFlight upload preflight must print field-level release input status before upload gates"
check_contains "Scripts/preflight_testflight_upload.sh" "TestFlight upload preflight passed" "TestFlight preflight must print a clear success message"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_testflight_upload.sh").read_text()
status_index = source.find('run_step "Release input status" Scripts/print_release_input_status.sh --strict')
credentials_index = source.find('run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh')
if status_index == -1 or credentials_index == -1 or status_index > credentials_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: TestFlight upload preflight must print release input status before credential validation\n'
  failures=$((failures + 1))
fi
check_file "Scripts/preflight_testflight_upload_dependencies.sh" "TestFlight upload dependency preflight script is required"
if [[ -f "Scripts/preflight_testflight_upload_dependencies.sh" && ! -x "Scripts/preflight_testflight_upload_dependencies.sh" ]]; then
  printf 'FAIL: TestFlight upload dependency preflight script must be executable (Scripts/preflight_testflight_upload_dependencies.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "Scripts/validate_release_env.sh" "TestFlight dependency preflight must validate private release inputs before archive fallback"
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "Scripts/check_app_store_connect_credentials.sh" "TestFlight dependency preflight must validate App Store Connect credentials before archive fallback"
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "APP_STORE_CONNECT_SKIP_BUILD_CHECK=1" "TestFlight dependency preflight must verify the App Store Connect app/version before archive fallback"
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "Scripts/check_app_store_connect_state.sh" "TestFlight dependency preflight must query App Store Connect state before archive fallback"
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "Scripts/print_release_input_status.sh --strict" "TestFlight dependency preflight must print field-level release input status before archive fallback gates"
check_contains "Scripts/preflight_testflight_upload_dependencies.sh" "TestFlight upload dependency preflight passed" "TestFlight dependency preflight must print a clear success message"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_testflight_upload_dependencies.sh").read_text()
status_index = source.find('run_step "Release input status" Scripts/print_release_input_status.sh --strict')
environment_index = source.find('run_step "Private release environment" Scripts/validate_release_env.sh')
if status_index == -1 or environment_index == -1 or status_index > environment_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: TestFlight upload dependency preflight must print release input status before release environment validation\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/verify_release.sh" "testflight-dependencies-preflight" "Release verification must expose the TestFlight upload dependency preflight command"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/verify_release.sh testflight-dependencies-preflight" "Release input bootstrap next commands must include the TestFlight upload dependency preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/preflight_metadata_upload.sh" "Release input bootstrap next commands must include the metadata upload preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/run_fastlane.sh ios metadata" "Release input bootstrap next commands must include metadata upload"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/preflight_app_privacy_upload.sh" "Release input bootstrap next commands must include the App Privacy Details upload preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/run_fastlane.sh ios privacy_details" "Release input bootstrap next commands must include App Privacy Details upload"
check_contains "Scripts/bootstrap_release_inputs.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh" "Release input bootstrap next commands must include App Privacy Details App Store Connect confirmation"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/preflight_app_store_archive.sh" "Release input bootstrap next commands must include the App Store archive preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Release input bootstrap next commands must include the guarded archive command"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/preflight_testflight_upload.sh" "Release input bootstrap next commands must include the TestFlight upload preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "Scripts/run_fastlane.sh ios upload_testflight" "Release input bootstrap next commands must include TestFlight upload"
check_contains "Scripts/bootstrap_release_inputs.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state" "Release input bootstrap next commands must verify the selected App Store Connect build"
check_contains "Scripts/bootstrap_release_inputs.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh" "Release input bootstrap next commands must include the final App Review preflight"
check_contains "Scripts/bootstrap_release_inputs.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "Release input bootstrap next commands must include the guarded final App Review submission"
check_contains "Scripts/verify_release.sh" "testflight-preflight" "Release verification must expose the TestFlight upload preflight command"
check_file "Scripts/preflight_app_review_submission.sh" "App Review submission preflight script is required"
if [[ ! -x "Scripts/preflight_app_review_submission.sh" ]]; then
  printf 'FAIL: App Review submission preflight script must be executable (Scripts/preflight_app_review_submission.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_app_store_metadata.sh" "App Review preflight must validate App Store metadata"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_screenshot_sync.sh" "App Review preflight must validate screenshot sync"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_screenshot_privacy.sh" "App Review preflight must validate screenshot privacy metadata"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_privacy_surface.sh" "App Review preflight must validate the privacy surface"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_app_privacy_details.sh" "App Review preflight must validate App Privacy Details"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_app_store_questionnaires.sh" "App Review preflight must validate questionnaire consistency"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_app_review_contact.sh" "App Review preflight must validate App Review contact details"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_manual_release_verification.sh" "App Review preflight must validate manual release evidence"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/check_app_store_connect_credentials.sh" "App Review preflight must validate App Store Connect credentials"
check_contains "Scripts/preflight_app_review_submission.sh" "source Scripts/load_release_env.sh" "App Review preflight must load private release inputs before checking selected build and credentials"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/validate_release_env.sh" "App Review preflight must reject placeholder private release inputs"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/print_release_input_status.sh --strict" "App Review preflight must print field-level release input status before final submission"
check_contains "Scripts/preflight_app_review_submission.sh" "Scripts/check_app_store_connect_state.sh" "App Review preflight must require a processed selected build"
check_contains "Scripts/preflight_app_review_submission.sh" "APP_STORE_BUILD_NUMBER" "App Review preflight must require an explicit selected build number"
check_contains "Scripts/preflight_app_review_submission.sh" "PROCESSED_BUILD_NUMBER placeholder" "App Review preflight must reject the selected-build placeholder"
check_contains "Scripts/preflight_app_review_submission.sh" "App Review submission preflight passed" "App Review preflight must print a clear success message"
check_contains "Scripts/preflight_app_review_submission.sh" "APP_STORE_BUILD_NUMBER=%s CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "App Review preflight success command must submit the selected App Store build explicitly"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/preflight_app_review_submission.sh").read_text()


def line_index(pattern: str) -> int:
    for index, line in enumerate(source.splitlines()):
        if line.strip() == pattern:
            return index
    raise SystemExit(1)


build_index = line_index("run_build_number_step")
for later in (
    'run_step "App Store metadata" Scripts/validate_app_store_metadata.sh',
    'run_step "Manual release verification evidence" Scripts/validate_manual_release_verification.sh',
    'run_step "App Store Connect credentials" Scripts/check_app_store_connect_credentials.sh',
    'run_step "App Store Connect selected build" Scripts/check_app_store_connect_state.sh',
):
    if build_index > line_index(later):
        raise SystemExit(1)
PY
then
  printf 'FAIL: App Review preflight must validate APP_STORE_BUILD_NUMBER before heavy metadata, evidence, credential, or account-state checks\n'
  failures=$((failures + 1))
fi
review_preflight_placeholder_test_dir="$(mktemp -d)"
review_preflight_placeholder_output="$review_preflight_placeholder_test_dir/preflight.txt"
APP_STORE_BUILD_NUMBER=todo \
  Scripts/preflight_app_review_submission.sh >"$review_preflight_placeholder_output" 2>&1 || true
if grep -q 'OK: APP_STORE_BUILD_NUMBER is set to todo' "$review_preflight_placeholder_output"; then
  printf 'FAIL: App Review preflight must not mark lowercase todo selected build as OK\n'
  failures=$((failures + 1))
fi
if ! grep -q 'BLOCKED: APP_STORE_BUILD_NUMBER still looks like a placeholder' "$review_preflight_placeholder_output"; then
  printf 'FAIL: App Review preflight must flag lowercase todo selected build as a placeholder\n'
  failures=$((failures + 1))
fi
if ! grep -q 'MISSING_FIELD:' "$review_preflight_placeholder_output"; then
  printf 'FAIL: App Review preflight must print field-level missing release input rows\n'
  failures=$((failures + 1))
fi
rm -rf "$review_preflight_placeholder_test_dir"
check_contains "Scripts/verify_release.sh" "review-preflight" "Release verification must expose the App Review submission preflight command"
check_contains "README.md" "Scripts/run_fastlane.sh ios upload_testflight" "README must document the TestFlight upload command"
check_contains "README.md" "ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8 Scripts/run_fastlane.sh ios metadata" "README metadata upload command must require App Store Connect API credentials"
check_contains "README.md" "Scripts/preflight_metadata_upload.sh" "README must document the metadata upload preflight command"
check_contains "README.md" "Scripts/preflight_testflight_upload_dependencies.sh" "README must document the TestFlight upload dependency preflight command"
check_contains "README.md" "Scripts/preflight_testflight_upload.sh" "README must document the TestFlight upload preflight command"
check_contains "README.md" "Scripts/run_fastlane.sh ios app_store_connect_state" "README must document the App Store Connect state preflight command"
check_contains "README.md" "Scripts/preflight_app_review_submission.sh" "README must document the App Review submission preflight command"
check_contains "README.md" "Scripts/run_fastlane.sh ios privacy_details" "README must document the App Privacy Details upload command"
check_contains "README.md" "Scripts/preflight_app_privacy_upload.sh" "README must document the App Privacy Details upload preflight command"
check_contains "README.md" "Scripts/validate_app_privacy_details.sh" "README must document App Privacy Details validation"
check_contains "README.md" "Scripts/validate_privacy_surface.sh" "README must document privacy surface validation"
check_contains "README.md" "Scripts/validate_release_env.sh" "README must document release environment placeholder validation"
check_contains "README.md" "Scripts/bootstrap_release_env.sh" "README must document release environment bootstrap"
check_contains "README.md" "Scripts/bootstrap_release_inputs.sh" "README must document combined release input bootstrap"
check_contains "README.md" "Scripts/print_release_input_status.sh" "README must document the redacted release input status command"
check_contains "README.md" "Scripts/print_release_input_status.sh --strict" "README must document strict redacted release input status before handoff"
check_contains "README.md" "Scripts/verify_release.sh contact-report" "README must document the App Review contact readiness report command"
check_contains "README.md" "Scripts/verify_release.sh manual-report" "README must document the manual release readiness report command"
check_contains "README.md" "Scripts/verify_release.sh signing-report" "README must document the signing readiness report command"
check_contains "README.md" "Scripts/verify_release.sh asc-report" "README must document the App Store Connect readiness report command"
check_contains "README.md" "Scripts/verify_release.sh public-pages-report" "README must document the public pages readiness report command"
check_contains "README.md" "Scripts/verify_release.sh public-pages" "README must document strict public page validation"
check_contains "README.md" "Scripts/check_code_signing_assets.sh" "README must document precise code signing asset validation"
check_contains "README.md" "Scripts/validate_app_review_contact.sh" "README must document App Review contact validation"
check_contains "README.md" "Scripts/validate_manual_release_verification.sh" "README must document manual release verification evidence validation"
check_not_contains "README.md" "APP_STORE_BUILD_NUMBER=1" "README must not hard-code a selected App Store build number in release handoff commands"
check_not_contains "README.md" "APP_STORE_BUILD_NUMBER=<" "README must use shell-safe selected build placeholders in release handoff commands"
check_contains "README.md" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" "README must show manual release evidence validation against the selected App Store build"
check_contains "README.md" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "README must show final submission against the selected App Store build"
check_contains "README.md" "is a placeholder; replace it with the processed build number selected in App Store Connect" "README must warn that the selected-build placeholder must be replaced"
check_contains "README.md" "leaving it in place is expected to fail locally" "README must explain that selected-build placeholder commands fail locally"
check_contains "README.md" "AppStore/release-inputs-worksheet.md" "README must reference the release input worksheet"
check_contains "README.md" "same APP_STORE_BUILD_NUMBER" "README must document that manual TestFlight evidence must match the selected App Store build"
check_contains "README.md" "Scripts/run_fastlane.sh ios submit_review" "README must document the guarded App Review submission command"
check_contains "README.md" "re-runs manual release evidence validation" "README must document that final App Review submission revalidates manual evidence"
check_contains "README.md" "APP_REVIEW_CONTACT_EMAIL" "README must document private App Review contact variables"
check_contains "README.md" "Scripts/validate_app_store_metadata.sh" "README must document App Store metadata limit validation"
check_contains "README.md" "AppStore/commercial-configuration.md" "README must reference the App Store commercial configuration"
check_contains "README.md" "AppStore/review-guideline-audit.md" "README must reference the App Review guideline self-audit"
check_contains "README.md" "Scripts/validate_app_icon_set.sh" "README must document app icon set validation"
check_contains "README.md" "Scripts/validate_app_store_export.sh" "README must document App Store archive/export validation"
check_contains "README.md" "Scripts/preflight_app_store_archive.sh" "README must document App Store archive preflight validation"
check_contains "README.md" 'Scripts/verify_release.sh store-ready`' "README archive preflight docs must say it runs the full store-ready gate"
check_contains "README.md" "Scripts/validate_app_store_questionnaires.sh" "README must document App Store questionnaire consistency validation"
check_contains "README.md" "Scripts/verify_release.sh questionnaires" "README must document the questionnaire release command"
check_contains "README.md" "Fastlane metadata, App Privacy Details, and final review-submission lanes run the local App Store questionnaire validation" "README must document Fastlane questionnaire validation gates"
check_contains "README.md" "Scripts/validate_simulator_workflow.sh" "README must document simulator workflow validation"
check_contains "README.md" "Scripts/verify_release.sh simulator-workflow" "README must document the simulator workflow release command"
check_contains "README.md" "Scripts/validate_photo_import.sh" "README must document photo import validation"
check_contains "README.md" "Scripts/verify_release.sh photo-import" "README must document the photo import release command"
check_contains "README.md" "About screen review/support information" "README must document About screen review/support UI validation"
check_contains "README.md" "Scripts/validate_accessibility_screenshots.sh" "README must document accessibility screenshot validation"
check_contains "README.md" "Scripts/verify_release.sh accessibility" "README must document the accessibility screenshot release command"
check_contains "README.md" "Scripts/validate_print_sheet.sh" "README must document print sheet validation"
check_contains "README.md" "Scripts/verify_release.sh print-sheet" "README must document the print sheet release command"
check_contains "README.md" "Scripts/prepare_app_store_submission_packet.sh" "README must document the App Store submission packet generator"
check_contains "README.md" "Scripts/verify_release.sh submission-packet" "README must document the submission packet release command"
check_contains "README.md" "Scripts/verify_release.sh store-ready" "README must document the single local store-ready release command"
check_contains "README.md" "strict public privacy/support page validation" "README store-ready gate must document strict public pages validation"
check_contains "README.md" "submission packet generation and validation" "README store-ready gate must document submission packet validation"
check_not_contains "README.md" "DEVELOPMENT_TEAM_ID=ABCDE12345" "README archive commands must use the validated YOURTEAMID placeholder"
check_contains "README.md" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "README must show a shell-safe archive command placeholder"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios upload_testflight" "Release checklist must include the TestFlight upload command"
check_contains "AppStore/release-checklist.md" "configure App Store Connect API credentials, then run \`Scripts/run_fastlane.sh ios metadata\`" "Release checklist metadata automation must require App Store Connect API credentials"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_metadata_upload.sh" "Release checklist must include the metadata upload preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_testflight_upload_dependencies.sh" "Release checklist must include the TestFlight upload dependency preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_testflight_upload.sh" "Release checklist must include the TestFlight upload preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios app_store_connect_state" "Release checklist must include the App Store Connect state preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_app_review_submission.sh" "Release checklist must include the App Review submission preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios privacy_details" "Release checklist must include the App Privacy Details upload command"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_app_privacy_upload.sh" "Release checklist must include the App Privacy Details upload preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_privacy_details.sh" "Release checklist must include App Privacy Details validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_privacy_surface.sh" "Release checklist must include privacy surface validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_release_env.sh" "Release checklist must include release environment placeholder validation"
check_contains "AppStore/release-checklist.md" "generated handoff commands with the processed App Store Connect build number" "Release checklist must warn that generated selected-build placeholders must be replaced"
check_contains "AppStore/release-checklist.md" "validators intentionally reject that placeholder" "Release checklist must document the selected-build placeholder guard"
check_contains "AppStore/release-checklist.md" "Scripts/bootstrap_release_env.sh" "Release checklist must include release environment bootstrap"
check_contains "AppStore/release-checklist.md" "Scripts/bootstrap_release_inputs.sh" "Release checklist must include combined release input bootstrap"
check_contains "AppStore/release-checklist.md" "Scripts/print_release_input_status.sh" "Release checklist must include redacted release input status"
check_not_contains "AppStore/release-checklist.md" "DEVELOPMENT_TEAM_ID=\\.\\.\\." "Release checklist archive commands must use shell-safe Team ID placeholders"
check_contains "AppStore/release-checklist.md" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Release checklist must show a shell-safe archive command placeholder"
check_contains "AppStore/release-checklist.md" "Scripts/print_release_input_status.sh --strict" "Release checklist must require strict redacted release input status before handoff"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh contact-report" "Release checklist must include App Review contact readiness report generation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh manual-report" "Release checklist must include manual release readiness report generation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh signing-report" "Release checklist must include signing readiness report generation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh asc-report" "Release checklist must include App Store Connect readiness report generation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh public-pages-report" "Release checklist must include public pages readiness report generation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh public-pages" "Release checklist must include strict public page validation"
check_contains "AppStore/release-checklist.md" "Scripts/check_code_signing_assets.sh" "Release checklist must include precise code signing asset validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_review_contact.sh" "Release checklist must include App Review contact validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_manual_release_verification.sh" "Release checklist must include manual release verification evidence validation"
check_contains "AppStore/release-checklist.md" "AppStore/release-inputs-worksheet.md" "Release checklist must reference the release input worksheet"
check_contains "AppStore/release-checklist.md" "same APP_STORE_BUILD_NUMBER" "Release checklist must require manual TestFlight evidence for the selected App Store build"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios submit_review" "Release checklist must include the guarded App Review submission command"
check_contains "AppStore/release-checklist.md" "re-runs manual release evidence validation" "Release checklist must document that final App Review submission revalidates manual evidence"
check_contains "AppStore/release-checklist.md" "APP_REVIEW_CONTACT_EMAIL" "Release checklist must include App Review contact configuration"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_store_metadata.sh" "Release checklist must include metadata limit validation"
check_contains "AppStore/release-checklist.md" "AppStore/commercial-configuration.md" "Release checklist must reference commercial configuration"
check_contains "AppStore/release-checklist.md" "AppStore/review-guideline-audit.md" "Release checklist must reference App Review guideline self-audit"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_icon_set.sh" "Release checklist must include app icon set validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_store_export.sh" "Release checklist must include App Store archive/export validation"
check_contains "AppStore/release-checklist.md" "Scripts/preflight_app_store_archive.sh" "Release checklist must include App Store archive preflight validation"
check_contains "AppStore/release-checklist.md" 'Scripts/verify_release.sh store-ready`' "Release checklist archive preflight must say it runs the full store-ready gate"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_store_questionnaires.sh" "Release checklist must include App Store questionnaire consistency validation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh questionnaires" "Release checklist must include the questionnaire release command"
check_contains "AppStore/release-checklist.md" "Scripts/validate_simulator_workflow.sh" "Release checklist must include simulator workflow validation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh simulator-workflow" "Release checklist must include the simulator workflow release command"
check_contains "AppStore/release-checklist.md" "Scripts/validate_photo_import.sh" "Release checklist must include photo import validation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh photo-import" "Release checklist must include the photo import release command"
check_contains "AppStore/release-checklist.md" "About screen privacy/support/version review information" "Release checklist must document About screen review/support UI validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_accessibility_screenshots.sh" "Release checklist must include accessibility screenshot validation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh accessibility" "Release checklist must include the accessibility screenshot release command"
check_contains "AppStore/release-checklist.md" "Scripts/validate_print_sheet.sh" "Release checklist must include print sheet validation"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh print-sheet" "Release checklist must include the print sheet release command"
check_contains "AppStore/release-checklist.md" "Scripts/prepare_app_store_submission_packet.sh" "Release checklist must include the App Store submission packet generator"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh submission-packet" "Release checklist must include the submission packet release command"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh store-ready" "Release checklist must include the single local store-ready release command"
check_contains "AppStore/release-checklist.md" "strict public privacy/support page validation" "Release checklist store-ready gate must document strict public pages validation"
check_contains "AppStore/release-checklist.md" "submission packet generation and validation" "Release checklist store-ready gate must document submission packet validation"
check_file "Scripts/prepare_app_store_submission_packet.sh" "App Store submission packet generator is required"
if [[ ! -x "Scripts/prepare_app_store_submission_packet.sh" ]]; then
  printf 'FAIL: App Store submission packet generator must be executable (Scripts/prepare_app_store_submission_packet.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/prepare_app_store_submission_packet.sh" "AppStore/release-inputs-worksheet.md" "Submission packet generator must include the release input worksheet"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Config/release.env.example" "Submission packet generator must include the private release environment template"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "AppStore/commercial-configuration.md" "Submission packet generator must include the commercial configuration"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "AppStore/review-guideline-audit.md" "Submission packet generator must include the App Review guideline self-audit"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "AppStoreSubmissionPacket" "Submission packet generator must write a deterministic package directory"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "check_app_store_readiness.sh" "Submission packet generator must include the readiness audit"
check_contains "Scripts/prepare_app_store_submission_packet.sh" 'readiness_status="$?"' "Submission packet generator must preserve the readiness audit exit code"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "ACTION_ITEMS.md" "Submission packet generator must write actionable external release blockers"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/bootstrap_release_inputs.sh" "Submission packet action items must include the combined release input bootstrap"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/print_release_input_status.sh" "Submission packet action items must include the redacted release input status command"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/print_release_input_status.sh --strict" "Submission packet action items must require strict redacted release input status before handoff"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/bootstrap_release_env.sh" "Submission packet action items must include the release environment bootstrap"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_metadata_upload.sh" "Submission packet action items must include the metadata upload preflight"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/run_fastlane.sh ios metadata" "Submission packet action items must include metadata upload"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_app_privacy_upload.sh" "Submission packet action items must include the App Privacy Details upload preflight"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/run_fastlane.sh ios privacy_details" "Submission packet action items must include App Privacy Details upload"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh" "Submission packet action items must include App Privacy Details App Store Connect confirmation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_app_store_archive.sh" "Submission packet action items must include the App Store archive preflight"
check_not_contains "Scripts/prepare_app_store_submission_packet.sh" "DEVELOPMENT_TEAM_ID=<" "Submission packet archive commands must use shell-safe Team ID placeholders"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "Submission packet command order must show the guarded archive command"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_testflight_upload_dependencies.sh" "Submission packet action items must include the TestFlight upload dependency preflight"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_testflight_upload.sh" "Submission packet action items must include the TestFlight upload preflight"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/preflight_app_review_submission.sh" "Submission packet action items must include the App Review submission preflight"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/validate_manual_release_verification.sh" "Submission packet action items must include manual release verification evidence validation"
check_not_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_STORE_BUILD_NUMBER=1" "Submission packet command order must not hard-code a selected App Store build number"
check_not_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_STORE_BUILD_NUMBER=<" "Submission packet command order must use shell-safe selected build placeholders"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state" "Submission packet command order must verify the selected App Store build"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/validate_manual_release_verification.sh" "Submission packet command order must validate manual evidence against the selected App Store build"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER CONFIRM_SUBMIT_FOR_REVIEW=1 Scripts/run_fastlane.sh ios submit_review" "Submission packet command order must submit the selected App Store build"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "processed App Store Connect build number before running the selected-build commands" "Submission packet must warn that selected-build placeholders must be replaced"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "placeholder cannot reach App Store Connect" "Submission packet must explain the selected-build placeholder guard"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Readiness Blockers" "Submission packet action items must summarize readiness blockers"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Readiness Warnings" "Submission packet action items must summarize readiness warnings"
check_contains "Scripts/prepare_app_store_submission_packet.sh" 'redact_external_action_item "${line#BLOCKED: }"' "Submission packet action items must redact blocker paths"
check_contains "Scripts/prepare_app_store_submission_packet.sh" 'redact_external_action_item "${line#WARN: }"' "Submission packet action items must redact warning paths"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "external-readiness-actions.tsv" "Submission packet must include a machine-readable external readiness actions manifest"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "write_external_readiness_actions" "Submission packet generator must write categorized external readiness actions"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "redact_external_action_item" "External readiness actions must redact local absolute paths from item text"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "\\[manual-evidence-env\\]" "External readiness actions must redact manual evidence env paths from readiness output"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "\\[release-env\\]" "External readiness actions must redact release env paths from readiness output"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "\\[repo\\]/" "External readiness actions must replace repository absolute paths with a stable placeholder"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "\\[home\\]/" "External readiness actions must replace home-directory absolute paths with a stable placeholder"
check_contains "Scripts/prepare_app_store_submission_packet.sh" $'category\tseverity\towner\tfield\ttarget\titem\tnext_action\tvalidation_command' "External readiness actions manifest must include stable TSV headers with fields, target locations, and validation commands"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "external_action_field_for_item" "External readiness actions must extract the affected release field"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "external_action_target_for_item" "External readiness actions must map each affected release field to the private file, keychain, profile directory, or App Store Connect target"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "MANUAL_RELEASE_VERIFICATION_PATH" "External readiness actions must map missing manual evidence files to the manual evidence path"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Config/manual-release-verification.env" "External readiness actions must identify manual evidence private file targets"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "then run FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/preflight_app_privacy_upload.sh, upload with FASTLANE_USER=apple-id@example.com CONFIRM_UPLOAD_APP_PRIVACY=1 Scripts/run_fastlane.sh ios privacy_details" "External readiness actions must guide App Privacy upload blockers through preflight and upload"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "then run Scripts/preflight_app_store_archive.sh, then DEVELOPMENT_TEAM_ID=YOURTEAMID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive_app_store.sh" "External readiness actions must guide signing blockers through archive preflight and archive"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Config/release.env" "External readiness actions must identify release environment private file targets"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "validation_command" "External readiness actions must include the command that verifies each item"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/validate_app_review_contact.sh" "External readiness actions must point App Review contact items at the contact validator"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/validate_manual_release_verification.sh" "External readiness actions must point manual evidence items at the manual evidence validator"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/check_code_signing_assets.sh" "External readiness actions must point signing items at the signing validator"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/check_app_store_connect_credentials.sh" "External readiness actions must point App Store Connect credential items at the credential validator"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "release-provenance.tsv" "Submission packet generator must include release provenance"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "write_release_provenance" "Submission packet generator must write release provenance"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "git rev-parse HEAD" "Submission packet provenance must record the source commit"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "git status --short" "Submission packet provenance must record worktree cleanliness"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "GITHUB_RUN_ID" "Submission packet provenance must record GitHub Actions run context when available"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`release-provenance.tsv\\`' "Submission packet summary must reference release provenance"
check_contains "Scripts/validate_app_store_submission_packet.sh" "release-provenance.tsv" "Submission packet validator must require release provenance"
check_contains "Scripts/validate_app_store_submission_packet.sh" $'key\tvalue' "Submission packet validator must check release provenance header"
check_contains "Scripts/validate_app_store_submission_packet.sh" "git_commit" "Submission packet validator must require release provenance source commit"
check_contains "Scripts/validate_app_store_submission_packet.sh" "git_branch" "Submission packet validator must require release provenance branch"
check_contains "Scripts/validate_app_store_submission_packet.sh" "git_status" "Submission packet validator must require release provenance worktree status"
check_contains "Scripts/preflight_app_review_submission.sh" "validate_public_pages.sh" "App Review submission preflight must validate public privacy and support pages"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "validate_public_pages.sh" "App Review submission readiness report must include public page validation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "Scripts/verify_release.sh public-pages" "Submission packet command order must include strict public page validation"
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/prepare_app_store_submission_packet.sh").read_text()
asc_index = source.find('*FASTLANE_USER*|*ASC_*|*"App Store Connect"*')
manual_index = source.find('*MANUAL_*|*"Manual "*|*"Real iPhone"*')
if asc_index == -1 or manual_index == -1 or asc_index > manual_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: External readiness actions must classify App Store Connect items before broad TestFlight manual evidence rules\n'
  failures=$((failures + 1))
fi
if ! python3 - <<'PY'
from pathlib import Path

source = Path("Scripts/prepare_app_store_submission_packet.sh").read_text()
target_start = source.find("external_action_target_for_item()")
if target_start == -1:
    raise SystemExit(1)
source = source[target_start:]
app_record_index = source.find('*"app record"*|*"TestFlight status"*)')
manual_index = source.find('*MANUAL_*|*"Manual "*|*"Real iPhone"*|*"AirPrint"*|*"TestFlight"*)')
if app_record_index == -1 or manual_index == -1 or app_record_index > manual_index:
    raise SystemExit(1)
PY
then
  printf 'FAIL: External readiness action targets must map App Store Connect app record/TestFlight status before broad manual TestFlight targets\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/prepare_app_store_submission_packet.sh" "sha256" "Submission packet generator must record file checksums"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "pdf-export-validation.tsv" "Submission packet generator must include the PDF validation manifest"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "test-ruler-stretch" "Submission packet generator must require Test Ruler PDF validation evidence"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "\\[generated-pdf\\]" "Submission packet generator must redact local PDF evidence paths"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "redact_readiness_log" "Submission packet generator must redact readiness audit paths before packaging"
check_file "Scripts/generate_manual_release_evidence_form.sh" "Manual release evidence form generator is required"
if [[ -f "Scripts/generate_manual_release_evidence_form.sh" && ! -x "Scripts/generate_manual_release_evidence_form.sh" ]]; then
  printf 'FAIL: Manual release evidence form generator must be executable (Scripts/generate_manual_release_evidence_form.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_REAL_IPHONE_PHOTOS_IMPORT" "Manual release evidence form must cover real iPhone Photos import evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_REAL_IPHONE_PDF_EXPORT" "Manual release evidence form must cover real iPhone PDF export evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_AIRPRINT_EXACT_SIZE" "Manual release evidence form must cover AirPrint exact-size evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Manual release evidence form must cover AirPrint measured ruler evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_TESTFLIGHT_PRINT_WORKFLOW" "Manual release evidence form must cover TestFlight print workflow evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_IPAD_TESTFLIGHT_LAYOUT" "Manual release evidence form must cover iPad TestFlight layout evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW" "Manual release evidence form must cover iPad TestFlight print workflow evidence"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "Numeric iOS version" "Manual release evidence form must require a traceable numeric iOS version"
check_contains "Scripts/generate_manual_release_evidence_form.sh" "processed App Store Connect build number" "Manual release evidence form must warn that selected-build placeholders must be replaced"
check_file "Scripts/generate_manual_release_readiness_report.sh" "Manual release readiness report generator is required"
if [[ -f "Scripts/generate_manual_release_readiness_report.sh" && ! -x "Scripts/generate_manual_release_readiness_report.sh" ]]; then
  printf 'FAIL: Manual release readiness report generator must be executable (Scripts/generate_manual_release_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_manual_release_readiness_report.sh" "manual-release-readiness-report.md" "Manual release readiness report generator must use a deterministic output name"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_REAL_IPHONE_PHOTOS_IMPORT" "Manual release readiness report must summarize real iPhone Photos evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_AIRPRINT_EXACT_SIZE" "Manual release readiness report must summarize AirPrint exact-size evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_AIRPRINT_RULER_MEASURED_INCHES" "Manual release readiness report must summarize AirPrint measured ruler evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "DEFAULT_AIRPRINT_RULER_TARGET_INCHES" "Manual release readiness report must default the built-in AirPrint target ruler length"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_TESTFLIGHT_BUILD_NUMBER" "Manual release readiness report must summarize selected TestFlight build evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_IPAD_TESTFLIGHT_DEVICE" "Manual release readiness report must summarize iPad TestFlight device evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_IPAD_TESTFLIGHT_LAYOUT" "Manual release readiness report must summarize iPad TestFlight layout evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW" "Manual release readiness report must summarize iPad TestFlight print workflow evidence"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "APP_STORE_BUILD_NUMBER" "Manual release readiness report must compare the selected App Store build"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "Scripts/validate_manual_release_verification.sh" "Manual release readiness report must reference the strict validator"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "ios_version_status" "Manual release readiness report must validate real iPhone iOS version format"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "processed App Store Connect build number" "Manual release readiness report must warn that selected-build placeholders must be replaced"
check_contains "Scripts/generate_manual_release_readiness_report.sh" "redacted" "Manual release readiness report must avoid printing private manual evidence values"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "manual-release-evidence-form.md" "Submission packet generator must include the manual release evidence form"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_manual_release_evidence_form.sh" "Submission packet generator must generate the manual release evidence form"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`manual-release-evidence-form.md\\`' "Submission packet summary must reference the manual release evidence form"
check_contains "Scripts/verify_release.sh" "manual-evidence-form" "Release verification must expose manual evidence form generation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "manual-release-readiness-report.md" "Submission packet generator must include the manual release readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_manual_release_readiness_report.sh" "Submission packet generator must generate the manual release readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`manual-release-readiness-report.md\\`' "Submission packet summary must reference the manual release readiness report"
check_contains "Scripts/verify_release.sh" "manual-report" "Release verification must expose manual release readiness report generation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "app-review-contact-readiness-report.md" "Submission packet generator must include the App Review contact readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_app_review_contact_readiness_report.sh" "Submission packet generator must generate the App Review contact readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`app-review-contact-readiness-report.md\\`' "Submission packet summary must reference the App Review contact readiness report"
check_contains "Scripts/verify_release.sh" "contact-report" "Release verification must expose App Review contact readiness report generation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "public-pages-readiness-report.md" "Submission packet generator must include the public pages readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_public_pages_readiness_report.sh" "Submission packet generator must generate the public pages readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`public-pages-readiness-report.md\\`' "Submission packet summary must reference the public pages readiness report"
check_contains "Scripts/validate_app_store_submission_packet.sh" "public-pages-readiness-report.md" "Submission packet validator must require the public pages readiness report"
check_contains "Scripts/validate_app_store_submission_packet.sh" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "Submission packet validator must require public privacy URL tracking"
check_contains "Scripts/validate_app_store_submission_packet.sh" "https://dannagrace.github.io/FreePrintStudio/support.html" "Submission packet validator must require public support URL tracking"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Public page checks" "Submission packet validator must require public page check status"
check_contains "Scripts/verify_release.sh" "public-pages-report" "Release verification must expose public pages readiness report generation"
check_contains "Scripts/generate_app_review_contact_readiness_report.sh" "processed App Store Connect build number" "App Review contact readiness report must warn that selected-build placeholders must be replaced"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "signing-readiness-report.md" "Submission packet generator must include the signing readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_signing_readiness_report.sh" "Submission packet generator must generate the signing readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`signing-readiness-report.md\\`' "Submission packet summary must reference the signing readiness report"
check_contains "Scripts/verify_release.sh" "signing-report" "Release verification must expose signing readiness report generation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "app-store-connect-readiness-report.md" "Submission packet generator must include the App Store Connect readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_app_store_connect_readiness_report.sh" "Submission packet generator must generate the App Store Connect readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`app-store-connect-readiness-report.md\\`' "Submission packet summary must reference the App Store Connect readiness report"
check_contains "Scripts/verify_release.sh" "asc-report" "Release verification must expose App Store Connect readiness report generation"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "processed App Store Connect build number" "App Store Connect readiness report must warn that selected-build placeholders must be replaced"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/preflight_metadata_upload.sh" "App Store Connect readiness report must include the metadata upload preflight"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/run_fastlane.sh ios metadata" "App Store Connect readiness report must include metadata upload"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/preflight_app_privacy_upload.sh" "App Store Connect readiness report must include the App Privacy Details upload preflight"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "Scripts/run_fastlane.sh ios privacy_details" "App Store Connect readiness report must include App Privacy Details upload"
check_contains "Scripts/generate_app_store_connect_readiness_report.sh" "APP_PRIVACY_DETAILS_CONFIRMED_IN_APP_STORE_CONNECT=1 Scripts/validate_app_privacy_connect_entry.sh" "App Store Connect readiness report must include App Privacy Details App Store Connect confirmation"
check_file "Scripts/generate_app_store_connect_state_report.sh" "App Store Connect state report generator is required"
if [[ -f "Scripts/generate_app_store_connect_state_report.sh" && ! -x "Scripts/generate_app_store_connect_state_report.sh" ]]; then
  printf 'FAIL: App Store Connect state report generator must be executable (Scripts/generate_app_store_connect_state_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_app_store_connect_state_report.sh" "app-store-connect-state-report.md" "App Store Connect state report generator must use a deterministic output name"
check_contains "Scripts/generate_app_store_connect_state_report.sh" "check_app_store_connect_state.sh" "App Store Connect state report must run the selected build state checker"
check_contains "Scripts/generate_app_store_connect_state_report.sh" "Redacted Output" "App Store Connect state report must include redacted selected-build check output"
check_contains "Scripts/generate_app_store_connect_state_report.sh" "Exit Code" "App Store Connect state report must include the selected-build check exit code"
check_contains "Scripts/generate_app_store_connect_state_report.sh" "redacted" "App Store Connect state report must avoid printing private release values"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "app-store-connect-state-report.md" "Submission packet generator must include the App Store Connect state report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_app_store_connect_state_report.sh" "Submission packet generator must generate the App Store Connect state report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`app-store-connect-state-report.md\\`' "Submission packet summary must reference the App Store Connect state report"
check_contains "Scripts/validate_app_store_submission_packet.sh" "app-store-connect-state-report.md" "Submission packet validator must require the App Store Connect state report"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Scripts/check_app_store_connect_state.sh" "Submission packet validator must require selected-build state report command tracking"
check_contains "Scripts/verify_release.sh" "asc-state-report" "Release verification must expose App Store Connect state report generation"
check_contains "README.md" "Scripts/verify_release.sh asc-state-report" "README must document the App Store Connect state report command"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh asc-state-report" "Release checklist must include App Store Connect state report generation"
check_file "Scripts/generate_app_review_submission_readiness_report.sh" "App Review submission readiness report generator is required"
if [[ -f "Scripts/generate_app_review_submission_readiness_report.sh" && ! -x "Scripts/generate_app_review_submission_readiness_report.sh" ]]; then
  printf 'FAIL: App Review submission readiness report generator must be executable (Scripts/generate_app_review_submission_readiness_report.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "app-review-submission-readiness-report.md" "App Review submission readiness report generator must use a deterministic output name"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "preflight_app_review_submission.sh" "App Review submission readiness report must reference the final preflight"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "validate_app_store_metadata.sh" "App Review submission readiness report must summarize metadata validation"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "validate_screenshot_privacy.sh" "App Review submission readiness report must summarize screenshot privacy metadata validation"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "validate_manual_release_verification.sh" "App Review submission readiness report must summarize manual release evidence"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "check_app_store_connect_state.sh" "App Review submission readiness report must summarize selected build state checks"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "Scripts/print_release_input_status.sh --strict" "App Review submission readiness report must include field-level release input status"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "Missing Release Input Fields" "App Review submission readiness report must surface missing release input fields"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "processed App Store Connect build number" "App Review submission readiness report must warn that selected-build placeholders must be replaced"
check_contains "Scripts/generate_app_review_submission_readiness_report.sh" "redacted" "App Review submission readiness report must avoid printing private release values"
selected_build_report_placeholder_test_dir="$(mktemp -d)"
selected_build_asc_report="$selected_build_report_placeholder_test_dir/app-store-connect.md"
selected_build_asc_lowercase_report="$selected_build_report_placeholder_test_dir/app-store-connect-lowercase.md"
selected_build_review_report="$selected_build_report_placeholder_test_dir/app-review.md"
selected_build_review_lowercase_report="$selected_build_report_placeholder_test_dir/app-review-lowercase.md"
selected_build_manual_report="$selected_build_report_placeholder_test_dir/manual.md"
selected_build_manual_lowercase_report="$selected_build_report_placeholder_test_dir/manual-lowercase.md"
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER \
  Scripts/generate_app_store_connect_readiness_report.sh "$selected_build_asc_report" >/dev/null
APP_STORE_BUILD_NUMBER=todo \
  Scripts/generate_app_store_connect_readiness_report.sh "$selected_build_asc_lowercase_report" >/dev/null
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER \
  Scripts/generate_app_review_submission_readiness_report.sh "$selected_build_review_report" >/dev/null
APP_STORE_BUILD_NUMBER=todo \
  Scripts/generate_app_review_submission_readiness_report.sh "$selected_build_review_lowercase_report" >/dev/null
APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER \
  Scripts/generate_manual_release_readiness_report.sh "$selected_build_manual_report" >/dev/null
APP_STORE_BUILD_NUMBER=todo \
  Scripts/generate_manual_release_readiness_report.sh "$selected_build_manual_lowercase_report" >/dev/null
if grep -q '\`APP_STORE_BUILD_NUMBER\` configured | Yes' "$selected_build_asc_report"; then
  printf 'FAIL: App Store Connect readiness report must not mark PROCESSED_BUILD_NUMBER as configured\n'
  failures=$((failures + 1))
fi
if ! grep -q 'APP_STORE_BUILD_NUMBER.*placeholder' "$selected_build_asc_report"; then
  printf 'FAIL: App Store Connect readiness report must flag PROCESSED_BUILD_NUMBER as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
if grep -q '\`APP_STORE_BUILD_NUMBER\` configured | Yes' "$selected_build_asc_lowercase_report"; then
  printf 'FAIL: App Store Connect readiness report must not mark lowercase todo as configured\n'
  failures=$((failures + 1))
fi
if ! grep -q 'APP_STORE_BUILD_NUMBER.*placeholder' "$selected_build_asc_lowercase_report"; then
  printf 'FAIL: App Store Connect readiness report must flag lowercase todo as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
if ! python3 - "$selected_build_asc_report" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.find("## Required Next Actions")
if start == -1:
    raise SystemExit(1)
section = source[start:]
required_commands = [
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/run_fastlane.sh ios app_store_connect_state",
    "APP_STORE_BUILD_NUMBER=PROCESSED_BUILD_NUMBER Scripts/preflight_app_review_submission.sh",
]
if not all(command in section for command in required_commands):
    raise SystemExit(1)
PY
then
  printf 'FAIL: App Store Connect readiness report required actions must include selected-build commands\n'
  failures=$((failures + 1))
fi
if grep -q 'Selected processed build value.*Configured' "$selected_build_review_report"; then
  printf 'FAIL: App Review submission readiness report must not mark PROCESSED_BUILD_NUMBER as configured\n'
  failures=$((failures + 1))
fi
if ! grep -q 'Selected processed build value.*placeholder' "$selected_build_review_report"; then
  printf 'FAIL: App Review submission readiness report must flag PROCESSED_BUILD_NUMBER as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
if grep -q 'Selected processed build value.*Configured' "$selected_build_review_lowercase_report"; then
  printf 'FAIL: App Review submission readiness report must not mark lowercase todo as configured\n'
  failures=$((failures + 1))
fi
if ! grep -q 'Selected processed build value.*placeholder' "$selected_build_review_lowercase_report"; then
  printf 'FAIL: App Review submission readiness report must flag lowercase todo as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
if ! grep -q '## Missing Release Input Fields' "$selected_build_review_report"; then
  printf 'FAIL: App Review submission readiness report must include a missing release input fields section\n'
  failures=$((failures + 1))
fi
if ! grep -q 'MISSING_FIELD:' "$selected_build_review_report"; then
  printf 'FAIL: App Review submission readiness report must include field-level missing release input rows\n'
  failures=$((failures + 1))
fi
if grep -q 'selected build is redacted-MBER' "$selected_build_manual_report"; then
  printf 'FAIL: Manual readiness report must not treat PROCESSED_BUILD_NUMBER as a redacted selected build\n'
  failures=$((failures + 1))
fi
if ! grep -q 'Selected build matches evidence build.*placeholder' "$selected_build_manual_report"; then
  printf 'FAIL: Manual readiness report must flag PROCESSED_BUILD_NUMBER as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
if grep -q 'Selected build matches evidence build.*selected build is redacted-todo' "$selected_build_manual_lowercase_report"; then
  printf 'FAIL: Manual readiness report must not treat lowercase todo as a redacted selected build\n'
  failures=$((failures + 1))
fi
if ! grep -q 'Selected build matches evidence build.*placeholder' "$selected_build_manual_lowercase_report"; then
  printf 'FAIL: Manual readiness report must flag lowercase todo as a selected-build placeholder\n'
  failures=$((failures + 1))
fi
rm -rf "$selected_build_report_placeholder_test_dir"
manual_report_ios_version_test_dir="$(mktemp -d)"
manual_report_ios_version_evidence="$manual_report_ios_version_test_dir/manual-release-verification.env"
manual_report_ios_version_report="$manual_report_ios_version_test_dir/manual-release-readiness-report.md"
today="$(date +%F)"
cat >"$manual_report_ios_version_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="latest-iOS"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
MANUAL_RELEASE_VERIFICATION_PATH="$manual_report_ios_version_evidence" \
  Scripts/generate_manual_release_readiness_report.sh "$manual_report_ios_version_report" >/dev/null
if grep -q 'iOS version.*Recorded; value redacted' "$manual_report_ios_version_report"; then
  printf 'FAIL: Manual readiness report must not mark a malformed iOS version as recorded\n'
  failures=$((failures + 1))
fi
if ! grep -q 'iOS version.*Invalid; expected numeric iOS version' "$manual_report_ios_version_report"; then
  printf 'FAIL: Manual readiness report must identify malformed iOS version evidence\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_report_ios_version_test_dir"
manual_report_default_target_test_dir="$(mktemp -d)"
manual_report_default_target_evidence="$manual_report_default_target_test_dir/manual-release-verification.env"
manual_report_default_target_report="$manual_report_default_target_test_dir/manual-release-readiness-report.md"
cat >"$manual_report_default_target_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
MANUAL_RELEASE_VERIFICATION_PATH="$manual_report_default_target_evidence" \
  Scripts/generate_manual_release_readiness_report.sh "$manual_report_default_target_report" >/dev/null
if grep -q 'Target ruler length.*Missing' "$manual_report_default_target_report"; then
  printf 'FAIL: Manual readiness report must not mark the default built-in AirPrint target ruler length as missing\n'
  failures=$((failures + 1))
fi
if ! grep -q 'Target ruler length.*Defaulted to built-in 6 inch Test Ruler target' "$manual_report_default_target_report"; then
  printf 'FAIL: Manual readiness report should report the default built-in AirPrint target ruler length\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_report_default_target_test_dir"
manual_report_loose_evidence_test_dir="$(mktemp -d)"
manual_report_loose_evidence="$manual_report_loose_evidence_test_dir/manual-release-verification.env"
manual_report_loose_report="$manual_report_loose_evidence_test_dir/manual-release-readiness-report.md"
cat >"$manual_report_loose_evidence" <<EOF
MANUAL_VERIFIER_NAME="Release Tester"
MANUAL_REAL_IPHONE_MODEL="iPhone 15"
MANUAL_REAL_IPHONE_IOS_VERSION="18.5"
MANUAL_REAL_IPHONE_TEST_DATE="$today"
MANUAL_REAL_IPHONE_PHOTOS_IMPORT="pass"
MANUAL_REAL_IPHONE_PDF_EXPORT="pass"
MANUAL_REAL_IPHONE_PRINT_SHEET="pass"
MANUAL_AIRPRINT_TEST_DATE="$today"
MANUAL_AIRPRINT_PRINTER="Production AirPrint validation"
MANUAL_AIRPRINT_EXACT_SIZE="pass"
MANUAL_AIRPRINT_RULER_TARGET_INCHES="6"
MANUAL_AIRPRINT_RULER_MEASURED_INCHES="6.00"
MANUAL_TESTFLIGHT_BUILD_NUMBER="42"
MANUAL_TESTFLIGHT_DEVICE="iPhone 15"
MANUAL_TESTFLIGHT_TEST_DATE="$today"
MANUAL_TESTFLIGHT_INSTALL="pass"
MANUAL_TESTFLIGHT_PRINT_WORKFLOW="pass"
MANUAL_IPAD_TESTFLIGHT_DEVICE="iPad Pro 13-inch"
MANUAL_IPAD_TESTFLIGHT_TEST_DATE="$today"
MANUAL_IPAD_TESTFLIGHT_INSTALL="pass"
MANUAL_IPAD_TESTFLIGHT_LAYOUT="pass"
MANUAL_IPAD_TESTFLIGHT_PRINT_WORKFLOW="pass"
EOF
chmod 644 "$manual_report_loose_evidence"
MANUAL_RELEASE_VERIFICATION_PATH="$manual_report_loose_evidence" \
  Scripts/generate_manual_release_readiness_report.sh "$manual_report_loose_report" >/dev/null
if ! grep -q 'Evidence file permissions: Too broad; run `chmod 600 Config/manual-release-verification.env`' "$manual_report_loose_report"; then
  printf 'FAIL: Manual readiness report must reject broad manual evidence permissions before sourcing private values\n'
  failures=$((failures + 1))
fi
if grep -q 'Evidence file parses as shell env: Yes' "$manual_report_loose_report"; then
  printf 'FAIL: Manual readiness report must not parse broadly-readable manual evidence files\n'
  failures=$((failures + 1))
fi
if grep -Fq "$manual_report_loose_evidence" "$manual_report_loose_report"; then
  printf 'FAIL: Manual readiness report must not print the full loose manual evidence path\n'
  failures=$((failures + 1))
fi
rm -rf "$manual_report_loose_evidence_test_dir"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "app-review-submission-readiness-report.md" "Submission packet generator must include the App Review submission readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "generate_app_review_submission_readiness_report.sh" "Submission packet generator must generate the App Review submission readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`app-review-submission-readiness-report.md\\`' "Submission packet summary must reference the App Review submission readiness report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "screenshot-privacy-metadata-report.txt" "Submission packet generator must include screenshot privacy metadata evidence"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "validate_screenshot_privacy.sh" "Submission packet generator must run screenshot privacy metadata validation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`screenshot-privacy-metadata-report.txt\\`' "Submission packet summary must reference the screenshot privacy metadata report"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "release-input-status.txt" "Submission packet generator must include the redacted release input status output"
check_contains "Scripts/prepare_app_store_submission_packet.sh" "write_release_input_status" "Submission packet generator must write the redacted release input status output"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`release-input-status.txt\\`' "Submission packet summary must reference the redacted release input status output"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`Config/release.env.example\\`' "Submission packet summary must reference the private release environment template"
check_contains "Scripts/verify_release.sh" "review-report" "Release verification must expose App Review submission readiness report generation"
check_contains "README.md" "Scripts/verify_release.sh review-report" "README must document the App Review submission readiness report command"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh review-report" "Release checklist must include App Review submission readiness report generation"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`ACTION_ITEMS.md\\`' "Submission packet summary must reference action items"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`screenshots.tsv\\`' "Submission packet summary must escape Markdown code spans inside the shell heredoc"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`pdf-export-validation.tsv\\`' "Submission packet summary must escape PDF validation manifest code spans inside the shell heredoc"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`file-manifest.tsv\\`' "Submission packet summary must escape file manifest code spans inside the shell heredoc"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`readiness.txt\\`' "Submission packet summary must escape readiness log code spans inside the shell heredoc"
check_contains "Scripts/prepare_app_store_submission_packet.sh" '\\`external-readiness-actions.tsv\\`' "Submission packet summary must reference the external readiness actions manifest"
check_contains "Scripts/verify_release.sh" "prepare_app_store_submission_packet.sh" "Release verification must expose submission packet generation"
check_file "Scripts/validate_app_store_submission_packet.sh" "App Store submission packet validator is required"
if [[ -f "Scripts/validate_app_store_submission_packet.sh" && ! -x "Scripts/validate_app_store_submission_packet.sh" ]]; then
  printf 'FAIL: App Store submission packet validator must be executable (Scripts/validate_app_store_submission_packet.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_store_submission_packet.sh" "ACTION_ITEMS.md" "Submission packet validator must require action items"
check_contains "Scripts/validate_app_store_submission_packet.sh" "files/Config/release.env.example" "Submission packet validator must require the private release environment template in the file manifest"
check_contains "Scripts/validate_app_store_submission_packet.sh" "DEVELOPMENT_TEAM_ID" "Submission packet validator must check the release environment template content"
check_contains "Scripts/validate_app_store_submission_packet.sh" "release-input-status.txt" "Submission packet validator must require redacted release input status"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Missing Release Input Fields" "Submission packet validator must require release input missing field tracking"
check_contains "Scripts/validate_app_store_submission_packet.sh" "MISSING_FIELD:" "Submission packet validator must require field-level missing input output"
check_contains "Scripts/validate_app_store_submission_packet.sh" "external-readiness-actions.tsv" "Submission packet validator must require external readiness actions"
check_contains "Scripts/validate_app_store_submission_packet.sh" $'category\tseverity\towner\tfield\ttarget\titem\tnext_action\tvalidation_command' "Submission packet validator must require external action fields, target locations, and validation commands"
check_contains "Scripts/validate_app_store_submission_packet.sh" "external-readiness-actions.tsv target tracking" "Submission packet validator must reject missing external action target locations"
check_contains "Scripts/validate_app_store_submission_packet.sh" "require_tsv_column_populated" "Submission packet validator must reject missing external action affected fields"
check_contains "Scripts/validate_app_store_submission_packet.sh" "file-manifest.tsv" "Submission packet validator must require the file manifest"
check_contains "Scripts/validate_app_store_submission_packet.sh" "pdf-export-validation.tsv" "Submission packet validator must require PDF validation evidence"
check_contains "Scripts/validate_app_store_submission_packet.sh" "screenshots.tsv" "Submission packet validator must require screenshot evidence"
check_contains "Scripts/validate_app_store_submission_packet.sh" "screenshot-privacy-metadata-report.txt" "Submission packet validator must require screenshot privacy metadata evidence"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Screenshot privacy metadata validation passed." "Submission packet validator must require successful screenshot privacy metadata output"
check_contains "Scripts/validate_app_store_submission_packet.sh" "test-ruler-stretch" "Submission packet validator must require Test Ruler PDF evidence"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Manual Verification" "Submission packet validator must require manual verification tracking"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Manual verifier|Real iPhone|AirPrint|TestFlight|MANUAL_" "Submission packet validator must detect individual manual release evidence blockers"
check_contains "Scripts/validate_app_store_submission_packet.sh" "/Users/" "Submission packet validator must reject leaked absolute local paths"
check_contains "Scripts/validate_app_store_submission_packet.sh" "require_no_forbidden_private_artifacts" "Submission packet validator must reject private release artifacts by filename"
check_contains "Scripts/validate_app_store_submission_packet.sh" "Config/release.env" "Submission packet validator must reject filled private release.env files"
check_contains "Scripts/validate_app_store_submission_packet.sh" "AuthKey_" "Submission packet validator must reject App Store Connect private key files"
check_contains "Scripts/validate_app_store_submission_packet.sh" "fastlane-api-key.json" "Submission packet validator must reject Fastlane API key JSON files"
check_contains "Scripts/validate_app_store_submission_packet.sh" "require_no_private_key_material" "Submission packet validator must reject private key material embedded in packaged text"
check_contains "Scripts/validate_app_store_submission_packet.sh" "BEGIN .*PRIVATE KEY" "Submission packet validator must scan for private key material"
check_contains "Scripts/validate_app_store_submission_packet.sh" "require_no_symlinks" "Submission packet validator must reject symlinks before artifact upload"
check_contains "Scripts/validate_app_store_submission_packet.sh" "find \"\$PACKET_DIR\" -type l" "Submission packet validator must scan for symlinks"
check_contains "Scripts/verify_release.sh" "validate_app_store_submission_packet.sh" "Release verification must expose submission packet validation"
check_contains "Scripts/verify_release.sh" "submission-packet-check" "Release verification must provide a submission-packet-check command"
check_contains "Scripts/verify_release.sh" 'SCREENSHOT_COMMAND_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_COMMAND_TIMEOUT_SECONDS:-30}"' "Screenshot asset checks must bound per-command image metadata work"
check_contains "Scripts/verify_release.sh" 'SCREENSHOT_SYNC_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SCREENSHOT_SYNC_TIMEOUT_SECONDS:-60}"' "Screenshot sync validation must have a command-level timeout"
check_contains "Scripts/verify_release.sh" 'SUBMISSION_PACKET_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SUBMISSION_PACKET_TIMEOUT_SECONDS:-540}"' "Submission packet generation must have enough command-level timeout headroom for slower GitHub Actions runners"
check_contains "Scripts/verify_release.sh" 'SUBMISSION_PACKET_VALIDATION_TIMEOUT_SECONDS="${FREEPRINTSTUDIO_SUBMISSION_PACKET_VALIDATION_TIMEOUT_SECONDS:-60}"' "Submission packet validation must have a command-level timeout"
check_contains "Scripts/verify_release.sh" "Release verification command timed out" "Release verification must report timeout failures clearly"
check_contains "Scripts/verify_release.sh" "run_with_timeout \"\$SCREENSHOT_SYNC_TIMEOUT_SECONDS\" Scripts/validate_screenshot_sync.sh" "Screenshot sync validation must run through the timeout wrapper"
check_contains "Scripts/verify_release.sh" "run_with_timeout \"\$SUBMISSION_PACKET_TIMEOUT_SECONDS\" Scripts/prepare_app_store_submission_packet.sh" "Submission packet generation must run through the timeout wrapper"
check_contains "Scripts/verify_release.sh" "run_with_timeout \"\$SUBMISSION_PACKET_VALIDATION_TIMEOUT_SECONDS\" Scripts/validate_app_store_submission_packet.sh" "Submission packet validation must run through the timeout wrapper"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh submission-packet-check" "Release workflow must validate the generated App Store submission packet before upload"
check_contains "README.md" "Scripts/verify_release.sh submission-packet-check" "README must document the submission packet validation command"
check_contains "AppStore/release-checklist.md" "Scripts/verify_release.sh submission-packet-check" "Release checklist must include submission packet validation"
check_file ".github/workflows/release.yml" "GitHub Actions release gate workflow is required"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh" "Release workflow must run the local release gate"
check_contains ".github/workflows/release.yml" "concurrency:" "Release workflow must define concurrency for stale release gate runs"
check_contains ".github/workflows/release.yml" "cancel-in-progress: true" "Release workflow must cancel stale release gate runs for the same branch or pull request"
check_contains ".github/workflows/release.yml" "timeout-minutes: 45" "Release workflow job must have enough timeout headroom for slow macOS simulator validation and packet generation"
check_contains ".github/workflows/release.yml" "timeout-minutes: 10" "Slow release workflow steps must have command-level timeouts"
check_contains ".github/workflows/release.yml" "timeout-minutes: 20" "PDF export validation must have enough GitHub Actions timeout headroom"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh public-pages" "Release workflow must strictly validate public privacy and support pages"
check_workflow_step_timeout "Static release checks" "5" "Static release workflow step must fail fast if it hangs"
check_workflow_step_timeout "Core checks" "5" "Core release workflow step must fail fast if it hangs"
check_workflow_step_timeout "Property list lint" "2" "Plist lint release workflow step must fail fast if it hangs"
check_workflow_step_timeout "Public pages validation" "2" "Public pages release workflow step must fail fast if deployed pages are unreachable"
check_workflow_step_timeout "Screenshot asset checks" "5" "Screenshot asset release workflow step must fail fast if it hangs"
check_workflow_step_timeout "App Store submission packet" "10" "Submission packet generation release workflow step must allow slower GitHub Actions runners"
check_workflow_step_timeout "Validate App Store submission packet" "2" "Submission packet validation release workflow step must fail fast if it hangs"
check_workflow_step_timeout "Upload App Store submission packet" "2" "Submission packet artifact upload step must fail fast if it hangs"
check_contains ".github/workflows/release.yml" "FREEPRINTSTUDIO_MAX_SIMULATOR_CANDIDATES: 0" "CI PDF export validation must use a fresh temporary simulator"
check_contains ".github/workflows/release.yml" "FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_BOOT_TIMEOUT_SECONDS: 300" "CI PDF export validation must allow enough first-boot time for temporary simulators"
check_contains ".github/workflows/release.yml" "FREEPRINTSTUDIO_TEMPORARY_SIMULATOR_APP_LAUNCH_TIMEOUT_SECONDS: 360" "CI PDF export validation must allow enough first-launch time for temporary simulators"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh submission-packet" "Release workflow must generate the App Store submission packet"
check_contains ".github/workflows/release.yml" "actions/upload-artifact@v7" "Release workflow must upload the App Store submission packet with the current artifact action"
check_contains ".github/workflows/release.yml" "build/AppStoreSubmissionPacket" "Release workflow must upload the generated submission packet directory"
check_file ".github/workflows/pages.yml" "GitHub Pages custom workflow is required"
check_contains ".github/workflows/pages.yml" "actions/checkout@v6" "Pages workflow must use the current checkout action"
check_contains ".github/workflows/pages.yml" "actions/configure-pages@v5" "Pages workflow must configure GitHub Pages through the supported action"
check_contains ".github/workflows/pages.yml" "actions/upload-pages-artifact@v4" "Pages workflow must upload docs as a Pages artifact"
check_contains ".github/workflows/pages.yml" "actions/deploy-pages@v4" "Pages workflow must deploy through the supported Pages action"
check_contains ".github/workflows/pages.yml" "path: docs" "Pages workflow must publish the docs directory"
check_contains ".github/workflows/pages.yml" "pages: write" "Pages workflow must request pages: write permission"
check_contains ".github/workflows/pages.yml" "id-token: write" "Pages workflow must request id-token: write permission"
check_contains ".github/workflows/pages.yml" "workflow_dispatch:" "Pages workflow must be manually runnable after switching Pages source to GitHub Actions"
check_contains "README.md" "GitHub Actions uploads the generated App Store submission packet" "README must document the Release Gates submission packet artifact"
check_contains "AppStore/release-checklist.md" "GitHub Actions uploads the generated App Store submission packet" "Release checklist must document the Release Gates submission packet artifact"
check_contains "FreePrintStudio/Resources/Info.plist" "CFBundleDisplayName" "Info.plist must define display name"
check_contains "FreePrintStudio/Resources/Info.plist" "ITSAppUsesNonExemptEncryption" "Info.plist must declare non-exempt encryption usage"
check_plist_raw_value "FreePrintStudio/Resources/Info.plist" "ITSAppUsesNonExemptEncryption" "false" "Info.plist must declare no non-exempt encryption"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1.0" "Marketing version must be set"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "CURRENT_PROJECT_VERSION = 1" "Build number must be set"

if [[ "$failures" -gt 0 ]]; then
  printf '\nRelease check failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Release check passed.\n'
