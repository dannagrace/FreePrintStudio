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
check_file "AppStore/metadata.md" "App Store metadata draft is required"
check_contains "AppStore/metadata.md" "Privacy Policy" "Metadata must include privacy policy copy"
check_contains "AppStore/metadata.md" "Privacy Policy URL" "Metadata must include a privacy policy URL field"
check_contains "AppStore/metadata.md" "Support URL" "Metadata must include a support URL field"
check_contains "AppStore/metadata.md" "iphone-main.jpg" "Metadata must name the iPhone screenshot asset"
check_contains "AppStore/metadata.md" "ipad-main.jpg" "Metadata must name the iPad screenshot asset"
check_file "AppStore/app-privacy.md" "App privacy questionnaire answers are required"
check_contains "AppStore/app-privacy.md" "No, we do not collect data from this app" "Privacy answers must state no data collection"
check_contains "AppStore/app-privacy.md" "Tracking: No" "Privacy answers must state no tracking"
check_file "AppStore/age-rating.md" "Age rating questionnaire answers are required"
check_contains "AppStore/age-rating.md" "Expected global age rating: 4+" "Age rating answers must record the expected 4+ rating"
check_contains "AppStore/age-rating.md" "User-generated content: None" "Age rating answers must record no user-generated content"
check_file "AppStore/accessibility-labels.md" "Accessibility Nutrition Label answers are required"
check_contains "AppStore/accessibility-labels.md" "VoiceOver: Supported" "Accessibility answers must record VoiceOver support"
check_contains "AppStore/accessibility-labels.md" "Larger Text: Supported" "Accessibility answers must record Larger Text support"
check_file "docs/privacy-policy.html" "Publishable privacy policy page is required"
check_contains "docs/privacy-policy.html" "FreePrint Studio Privacy Policy" "Privacy page must identify the app and policy"
check_contains "docs/privacy-policy.html" "does not collect" "Privacy page must state no data collection"
check_file "docs/support.html" "Publishable support page is required"
check_contains "docs/support.html" "FreePrint Studio Support" "Support page must identify the app support page"
check_file "Config/ExportOptions-AppStore.plist" "App Store export options plist is required"
check_contains "Config/ExportOptions-AppStore.plist" "app-store-connect" "Export options must use the current App Store Connect export method"
check_file "Config/release.env.example" "Release environment template is required"
check_contains "Config/release.env.example" "DEVELOPMENT_TEAM_ID" "Release environment template must document the Apple Developer Team ID"
check_contains "Config/release.env.example" "ASC_KEY_ID" "Release environment template must document App Store Connect API key variables"
check_contains ".gitignore" "Config/release.env" "Filled release environment files must stay untracked"
check_contains ".gitignore" "*.p8" "App Store Connect private keys must stay untracked"
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
check_contains "fastlane/Fastfile" "lane :archive" "Fastfile must expose an archive lane"
check_contains "fastlane/Fastfile" "lane :upload_testflight" "Fastfile must expose a TestFlight upload lane"
check_contains "fastlane/Fastfile" "app_store_connect_api_key" "Fastfile must support App Store Connect API key upload"
check_contains "fastlane/Fastfile" "upload_to_testflight" "Fastfile must upload the signed IPA to TestFlight"
check_contains "fastlane/Deliverfile" "project_root" "Deliverfile must use project-root absolute paths"
check_file "fastlane/metadata/en-US/name.txt" "Fastlane app name metadata is required"
check_contains "fastlane/metadata/en-US/name.txt" "FreePrint Studio" "Fastlane metadata must include the app name"
check_file "fastlane/metadata/en-US/description.txt" "Fastlane description metadata is required"
check_contains "fastlane/metadata/en-US/description.txt" "exact-size" "Fastlane description must describe exact-size printing"
check_file "fastlane/metadata/en-US/privacy_url.txt" "Fastlane privacy URL metadata is required"
check_contains "fastlane/metadata/en-US/privacy_url.txt" "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html" "Fastlane metadata must include the public privacy URL"
check_file "fastlane/metadata/en-US/support_url.txt" "Fastlane support URL metadata is required"
check_contains "fastlane/metadata/en-US/support_url.txt" "https://dannagrace.github.io/FreePrintStudio/support.html" "Fastlane metadata must include the public support URL"
check_file "fastlane/screenshots/en-US/iphone-main.jpg" "Fastlane iPhone screenshot is required"
check_file "fastlane/screenshots/en-US/ipad-main.jpg" "Fastlane iPad screenshot is required"
check_file "Scripts/archive_app_store.sh" "App Store archive script is required"
check_contains "Scripts/archive_app_store.sh" "xcodebuild" "Archive script must use xcodebuild"
check_contains "Scripts/archive_app_store.sh" "DEVELOPMENT_TEAM_ID" "Archive script must support an explicit Apple Developer Team ID"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_APPEARANCE" "Screenshot script must support reproducible light/dark captures"
check_contains "Scripts/capture_app_store_screenshots.sh" "FREEPRINTSTUDIO_CONTENT_SIZE" "Screenshot script must support reproducible Larger Text captures"
check_file "Scripts/validate_pdf_export.sh" "PDF export validation script is required"
check_contains "Scripts/validate_pdf_export.sh" "FreePrintStudioAutoExportPDFPath" "PDF export validation must exercise the app renderer"
check_file "Scripts/check_app_store_readiness.sh" "App Store readiness audit script is required"
check_contains "Scripts/check_app_store_readiness.sh" "DEVELOPMENT_TEAM_ID" "Readiness audit must check Apple Developer Team ID"
check_contains "Scripts/check_app_store_readiness.sh" "privacy-policy.html" "Readiness audit must check the public privacy policy URL"
check_file "Scripts/check_app_store_connect_credentials.sh" "App Store Connect credential audit script is required"
check_contains "Scripts/check_app_store_connect_credentials.sh" "APP_STORE_CONNECT_API_KEY_JSON" "Credential audit must support Fastlane API key JSON"
check_contains "Scripts/check_app_store_connect_credentials.sh" "ASC_KEY_PATH" "Credential audit must support App Store Connect private key paths"
check_contains "README.md" "Scripts/run_fastlane.sh ios upload_testflight" "README must document the TestFlight upload command"
check_contains "AppStore/release-checklist.md" "Scripts/run_fastlane.sh ios upload_testflight" "Release checklist must include the TestFlight upload command"
check_file ".github/workflows/release.yml" "GitHub Actions release gate workflow is required"
check_contains ".github/workflows/release.yml" "Scripts/verify_release.sh" "Release workflow must run the local release gate"
check_contains ".github/workflows/release.yml" "timeout-minutes: 10" "Slow release workflow steps must have command-level timeouts"
check_contains "FreePrintStudio/Resources/Info.plist" "CFBundleDisplayName" "Info.plist must define display name"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "MARKETING_VERSION = 1.0" "Marketing version must be set"
check_contains "FreePrintStudio.xcodeproj/project.pbxproj" "CURRENT_PROJECT_VERSION = 1" "Build number must be set"

if [[ "$failures" -gt 0 ]]; then
  printf '\nRelease check failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Release check passed.\n'
