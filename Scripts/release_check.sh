#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
  if ! grep -q "$pattern" "$path"; then
    printf 'FAIL: %s (%s missing %s)\n' "$message" "$path" "$pattern"
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
  count="$(grep -c "$pattern" "$path" || true)"
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
check_file "FreePrintStudio/Resources/PrivacyInfo.xcprivacy" "Privacy manifest is required for release documentation"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "PrivacyInfo.xcprivacy" "Privacy manifest must be included in the Xcode project"
check_contains "FreePrintStudio/ContentView.swift" "About FreePrint Studio" "App must expose an About screen"
check_contains "FreePrintStudio/ContentView.swift" "Privacy Policy" "App must expose privacy policy text"
check_contains "FreePrintStudio/ContentView.swift" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "About screen must link to the public privacy policy"
check_contains "FreePrintStudio/ContentView.swift" "https://dannagrace.github.io/FreePrintStudio/support.html" "About screen must link to the public support page"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityLabel(\"Choose Image\")" "Choose Image control must have an explicit VoiceOver label"
check_contains "FreePrintStudio/ContentView.swift" "accessibilityLabel(\"Print preview\")" "Print preview must have an explicit VoiceOver label"
check_contains "FreePrintStudio/ContentView.swift" "Enter the target print width" "Width field must have a VoiceOver hint"
check_contains "FreePrintStudio/ContentView.swift" "Enter the target print height" "Height field must have a VoiceOver hint"
check_contains "FreePrintStudio/ContentView.swift" "selectedImage != nil && isTargetSizeValid" "Export and print actions must require both a selected image and a valid target size"
check_contains "FreePrintStudio/ContentView.swift" ".disabled(!isOutputReady)" "Export and print buttons must be disabled until output is ready"
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
check_contains "AppStore/metadata.md" "Privacy Policy" "Metadata must include privacy policy copy"
check_contains "AppStore/metadata.md" "Privacy Policy URL" "Metadata must include a privacy policy URL field"
check_contains "AppStore/metadata.md" "Support URL" "Metadata must include a support URL field"
check_contains "AppStore/metadata.md" "Copyright" "Metadata must include copyright copy"
check_contains "AppStore/metadata.md" "Version Release Notes" "Metadata must include version release notes"
check_contains "AppStore/metadata.md" "iphone-main.jpg" "Metadata must name the iPhone screenshot asset"
check_contains "AppStore/metadata.md" "iphone-fit.jpg" "Metadata must name the iPhone Fit screenshot asset"
check_contains "AppStore/metadata.md" "iphone-fill.jpg" "Metadata must name the iPhone Fill screenshot asset"
check_contains "AppStore/metadata.md" "iphone-stretch.jpg" "Metadata must name the iPhone Stretch screenshot asset"
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
check_file "docs/privacy-policy.html" "Publishable privacy policy page is required"
check_contains "docs/privacy-policy.html" "FreePrint Studio Privacy Policy" "Privacy page must identify the app and policy"
check_contains "docs/privacy-policy.html" "does not collect" "Privacy page must state no data collection"
check_file "docs/support.html" "Publishable support page is required"
check_contains "docs/support.html" "FreePrint Studio Support" "Support page must identify the app support page"
check_file "Config/ExportOptions-AppStore.plist" "App Store export options plist is required"
check_contains "Config/ExportOptions-AppStore.plist" "app-store-connect" "Export options must use the current App Store Connect export method"
check_file "Config/release.env.example" "Release environment template is required"
check_contains "Config/release.env.example" "DEVELOPMENT_TEAM_ID" "Release environment template must document the Apple Developer Team ID"
check_contains "Config/release.env.example" "# DEVELOPMENT_TEAM_ID=" "Release environment template must keep placeholder Team ID commented out"
check_contains "Config/release.env.example" "ASC_KEY_ID" "Release environment template must document App Store Connect API key variables"
check_contains "Config/release.env.example" "APP_REVIEW_CONTACT_EMAIL" "Release environment template must document App Review contact variables"
check_contains "Config/release.env.example" "CONFIRM_UPLOAD_APP_PRIVACY" "Release environment template must document the App Privacy Details upload guard"
check_contains "Config/release.env.example" "CONFIRM_SUBMIT_FOR_REVIEW" "Release environment template must document the final App Review submission guard"
check_contains ".gitignore" "Config/release.env" "Filled release environment files must stay untracked"
check_contains ".gitignore" "*.p8" "App Store Connect private keys must stay untracked"
check_file "Scripts/load_release_env.sh" "Release environment loader script is required"
check_contains "Scripts/load_release_env.sh" "Config/release.env" "Release environment loader must read the untracked release.env file"
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
check_contains "fastlane/Fastfile" "opt_out_usage" "Fastfile must opt out of Fastlane analytics"
check_contains "fastlane/Fastfile" "lane :verify" "Fastfile must expose a verify lane"
check_contains "fastlane/Fastfile" "lane :readiness" "Fastfile must expose a readiness lane"
check_contains "fastlane/Fastfile" "lane :metadata" "Fastfile must expose a metadata lane"
check_contains "fastlane/Fastfile" "lane :privacy_details" "Fastfile must expose an App Privacy Details upload lane"
check_contains "fastlane/Fastfile" "lane :app_store_connect_state" "Fastfile must expose an App Store Connect state preflight lane"
check_contains "fastlane/Fastfile" "lane :archive" "Fastfile must expose an archive lane"
check_contains "fastlane/Fastfile" "lane :upload_testflight" "Fastfile must expose a TestFlight upload lane"
check_contains "fastlane/Fastfile" "lane :submit_review" "Fastfile must expose a guarded App Store review submission lane"
check_contains "fastlane/Fastfile" "app_store_connect_api_key" "Fastfile must support App Store Connect API key upload"
check_contains "fastlane/Fastfile" "upload_to_testflight" "Fastfile must upload the signed IPA to TestFlight"
check_contains "fastlane/Fastfile" "upload_app_privacy_details_to_app_store" "Fastfile must support App Privacy Details upload"
check_contains "fastlane/Fastfile" "CONFIRM_UPLOAD_APP_PRIVACY" "Fastfile privacy lane must require explicit upload confirmation"
check_contains "fastlane/Fastfile" "AppStore/app_privacy_details.json" "Fastfile privacy lane must use the reviewed App Privacy Details JSON"
check_contains "fastlane/Fastfile" "CONFIRM_SUBMIT_FOR_REVIEW" "Fastfile submit lane must require explicit review-submission confirmation"
check_contains "fastlane/Fastfile" "submit_for_review: true" "Fastfile submit lane must submit the selected build for review"
check_contains "fastlane/Fastfile" "automatic_release: false" "Fastfile submit lane must use manual release after approval"
check_contains "fastlane/Fastfile" "submission_information" "Fastfile submit lane must provide submission compliance information"
check_contains "fastlane/Fastfile" "APP_STORE_BUILD_NUMBER" "Fastfile submit lane must support selecting a processed App Store build"
check_contains "fastlane/Fastfile" "Scripts/check_app_store_connect_state.sh" "Fastfile must run the App Store Connect state preflight script"
check_contains "fastlane/Fastfile" "primary_category: PRIMARY_CATEGORY" "Fastfile metadata lane must set the primary App Store category"
check_contains "fastlane/Fastfile" "secondary_category: SECONDARY_CATEGORY" "Fastfile metadata lane must set the secondary App Store category"
check_contains "fastlane/Fastfile" "review_information_options" "Fastfile must prepare App Store review information"
check_contains "fastlane/Fastfile" "APP_REVIEW_CONTACT_EMAIL" "Fastfile must support private App Review contact details"
check_contains "fastlane/Fastfile" "Scripts/validate_app_review_contact.sh" "Fastfile must run App Review contact validation before upload or submission"
check_occurrences_at_least "fastlane/Fastfile" "validate_app_review_contact!" 2 "Fastfile metadata and submit lanes must require App Review contact validation"
check_file "Scripts/validate_fastlane_release_lanes.sh" "Fastlane release lane validation script is required"
if [[ ! -x "Scripts/validate_fastlane_release_lanes.sh" ]]; then
  printf 'FAIL: Fastlane release lane validation script must be executable (Scripts/validate_fastlane_release_lanes.sh)\n'
  failures=$((failures + 1))
fi
if [[ -x "Scripts/validate_fastlane_release_lanes.sh" ]]; then
  Scripts/validate_fastlane_release_lanes.sh || failures=$((failures + 1))
fi
check_contains "Scripts/validate_fastlane_release_lanes.sh" "validate_app_review_contact!" "Fastlane lane validation must check App Review contact gates"
check_contains "Scripts/validate_fastlane_release_lanes.sh" "verify_app_store_connect_state!" "Fastlane lane validation must check App Store Connect state preflight gates"
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
check_file "fastlane/screenshots/en-US/iphone-main.jpg" "Fastlane iPhone screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-fit.jpg" "Fastlane iPhone Fit screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-fill.jpg" "Fastlane iPhone Fill screenshot is required"
check_file "fastlane/screenshots/en-US/iphone-stretch.jpg" "Fastlane iPhone Stretch screenshot is required"
check_file "fastlane/screenshots/en-US/ipad-main.jpg" "Fastlane iPad screenshot is required"
check_file "Scripts/archive_app_store.sh" "App Store archive script is required"
check_contains "Scripts/archive_app_store.sh" "xcodebuild" "Archive script must use xcodebuild"
check_contains "Scripts/archive_app_store.sh" "DEVELOPMENT_TEAM_ID" "Archive script must support an explicit Apple Developer Team ID"
check_file "Scripts/capture_app_store_screenshot_set.sh" "App Store screenshot set script is required"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-fit.jpg" "Screenshot set script must capture Fit mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-fill.jpg" "Screenshot set script must capture Fill mode"
check_contains "Scripts/capture_app_store_screenshot_set.sh" "iphone-stretch.jpg" "Screenshot set script must capture Stretch mode"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_APPEARANCE" "Screenshot script must support reproducible light/dark captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_CONTENT_SIZE" "Screenshot script must support reproducible Larger Text captures"
check_file "Scripts/validate_screenshot_sync.sh" "Screenshot sync validation script is required"
if [[ ! -x "Scripts/validate_screenshot_sync.sh" ]]; then
  printf 'FAIL: Screenshot sync validation script must be executable (Scripts/validate_screenshot_sync.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_screenshot_sync.sh" "AppStore/Screenshots" "Screenshot sync validation must check reviewed App Store screenshots"
check_contains "Scripts/validate_screenshot_sync.sh" "fastlane/screenshots/en-US" "Screenshot sync validation must check Fastlane upload screenshots"
check_contains "Scripts/verify_release.sh" "validate_screenshot_sync.sh" "Release verification must validate screenshot sync"
check_file "Scripts/validate_pdf_export.sh" "PDF export validation script is required"
check_contains "Scripts/validate_pdf_export.sh" "FreePrintStudioAutoExportPDFPath" "PDF export validation must exercise the app renderer"
check_contains "Scripts/validate_pdf_export.sh" "FIT_MODES=(fit fill stretch)" "PDF export validation must cover Fit, Fill, and Stretch output modes"
check_file "Scripts/check_app_store_readiness.sh" "App Store readiness audit script is required"
check_contains "Scripts/check_app_store_readiness.sh" "DEVELOPMENT_TEAM_ID" "Readiness audit must check Apple Developer Team ID"
check_contains "Scripts/check_app_store_readiness.sh" "check_code_signing_assets.sh" "Readiness audit must run the precise code signing asset preflight"
check_contains "Scripts/check_app_store_readiness.sh" "privacy-policy.html" "Readiness audit must check the public privacy policy URL"
check_contains "Scripts/check_app_store_readiness.sh" "APP_REVIEW_CONTACT_EMAIL" "Readiness audit must check App Review contact variables"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_review_contact.sh" "Readiness audit must validate App Review contact details"
check_contains "Scripts/check_app_store_readiness.sh" "validate_app_privacy_details.sh" "Readiness audit must validate App Privacy Details"
check_contains "Scripts/check_app_store_readiness.sh" "validate_privacy_surface.sh" "Readiness audit must validate privacy surface"
check_contains "Scripts/check_app_store_readiness.sh" "check_app_store_connect_state.sh" "Readiness audit must run the App Store Connect state preflight when credentials are available"
check_file "Scripts/check_app_store_connect_credentials.sh" "App Store Connect credential audit script is required"
check_contains "Scripts/check_app_store_connect_credentials.sh" "APP_STORE_CONNECT_API_KEY_JSON" "Credential audit must support Fastlane API key JSON"
check_contains "Scripts/check_app_store_connect_credentials.sh" "ASC_KEY_PATH" "Credential audit must support App Store Connect private key paths"
check_file "Scripts/check_code_signing_assets.sh" "Code signing asset preflight script is required"
if [[ ! -x "Scripts/check_code_signing_assets.sh" ]]; then
  printf 'FAIL: Code signing asset preflight script must be executable (Scripts/check_code_signing_assets.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/check_code_signing_assets.sh" "Apple Distribution" "Code signing preflight must require an Apple Distribution identity"
check_contains "Scripts/check_code_signing_assets.sh" "com.dannagrace.FreePrintStudio" "Code signing preflight must verify the release bundle id"
check_contains "Scripts/check_code_signing_assets.sh" "app-store-connect" "Code signing preflight must verify App Store Connect export intent"
check_contains "Scripts/check_code_signing_assets.sh" "ProvisionedDevices" "Code signing preflight must reject development or ad hoc provisioning profiles"
check_file "Scripts/validate_app_review_contact.sh" "App Review contact validation script is required"
if [[ ! -x "Scripts/validate_app_review_contact.sh" ]]; then
  printf 'FAIL: App Review contact validation script must be executable (Scripts/validate_app_review_contact.sh)\n'
  failures=$((failures + 1))
fi
check_contains "Scripts/validate_app_review_contact.sh" "APP_REVIEW_CONTACT_EMAIL" "App Review contact validation must check the email address"
check_contains "Scripts/validate_app_review_contact.sh" "APP_REVIEW_CONTACT_PHONE" "App Review contact validation must check the phone number"
check_contains "Scripts/validate_app_review_contact.sh" "email pattern" "App Review contact validation must document email format checks"
check_file "Scripts/check_app_store_connect_state.sh" "App Store Connect state preflight script is required"
check_contains "Scripts/check_app_store_connect_state.sh" "Spaceship::ConnectAPI::App.find" "App Store Connect state preflight must verify the app record"
check_contains "Scripts/check_app_store_connect_state.sh" "Spaceship::ConnectAPI::Build.all" "App Store Connect state preflight must inspect TestFlight builds"
check_contains "Scripts/check_app_store_connect_state.sh" "APP_STORE_BUILD_NUMBER" "App Store Connect state preflight must support a selected build number"
check_contains "README.md" "Scripts/run_fastlane.sh ios upload_testflight" "README must document the TestFlight upload command"
check_contains "README.md" "Scripts/run_fastlane.sh ios app_store_connect_state" "README must document the App Store Connect state preflight command"
check_contains "README.md" "Scripts/run_fastlane.sh ios privacy_details" "README must document the App Privacy Details upload command"
check_contains "README.md" "Scripts/validate_app_privacy_details.sh" "README must document App Privacy Details validation"
check_contains "README.md" "Scripts/validate_privacy_surface.sh" "README must document privacy surface validation"
check_contains "README.md" "Scripts/validate_release_env.sh" "README must document release environment placeholder validation"
check_contains "README.md" "Scripts/check_code_signing_assets.sh" "README must document precise code signing asset validation"
check_contains "README.md" "Scripts/validate_app_review_contact.sh" "README must document App Review contact validation"
check_contains "README.md" "Scripts/run_fastlane.sh ios submit_review" "README must document the guarded App Review submission command"
check_contains "README.md" "APP_REVIEW_CONTACT_EMAIL" "README must document private App Review contact variables"
check_contains "README.md" "Scripts/validate_app_store_metadata.sh" "README must document App Store metadata limit validation"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios upload_testflight" "Release checklist must include the TestFlight upload command"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios app_store_connect_state" "Release checklist must include the App Store Connect state preflight command"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios privacy_details" "Release checklist must include the App Privacy Details upload command"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_privacy_details.sh" "Release checklist must include App Privacy Details validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_privacy_surface.sh" "Release checklist must include privacy surface validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_release_env.sh" "Release checklist must include release environment placeholder validation"
check_contains "AppStore/release-checklist.md" "Scripts/check_code_signing_assets.sh" "Release checklist must include precise code signing asset validation"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_review_contact.sh" "Release checklist must include App Review contact validation"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios submit_review" "Release checklist must include the guarded App Review submission command"
check_contains "AppStore/release-checklist.md" "APP_REVIEW_CONTACT_EMAIL" "Release checklist must include App Review contact configuration"
check_contains "AppStore/release-checklist.md" "Scripts/validate_app_store_metadata.sh" "Release checklist must include metadata limit validation"
check_file ".github/workflows/release.yml" "GitHub Actions release gate workflow is required"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh" "Release workflow must run the local release gate"
check_contains ".github/workflows/release.yml" "timeout-minutes: 10" "Slow release workflow steps must have command-level timeouts"
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
