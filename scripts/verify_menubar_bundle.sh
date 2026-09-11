#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Debug/Usage.app}"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ASSETS_CAR="$APP_PATH/Contents/Resources/Assets.car"
EXPECTED_BUNDLE_ID="com.example.usageagents"
EXPECTED_GROUP="XXXXXXXXXX.com.example.usageagents"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

[[ -d "$APP_PATH" ]] || fail "App bundle not found: $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "Info.plist not found: $INFO_PLIST"

BUNDLE_ID="$(plist_value CFBundleIdentifier)"
DISPLAY_NAME="$(plist_value CFBundleDisplayName)"
EXECUTABLE_NAME="$(plist_value CFBundleExecutable)"
LSUIELEMENT="$(plist_value LSUIElement)"

[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] \
  || fail "CFBundleIdentifier is '$BUNDLE_ID', expected '$EXPECTED_BUNDLE_ID'"
[[ "$DISPLAY_NAME" == "Usage Agents" ]] \
  || fail "CFBundleDisplayName is '$DISPLAY_NAME', expected 'Usage Agents'"
[[ "$EXECUTABLE_NAME" == "Usage" ]] \
  || fail "CFBundleExecutable is '$EXECUTABLE_NAME', expected 'Usage'"
[[ "$LSUIELEMENT" == "false" || "$LSUIELEMENT" == "0" ]] \
  || fail "LSUIElement is '$LSUIELEMENT', expected false"
[[ -x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" ]] \
  || fail "Executable is missing or not executable"
[[ -f "$ASSETS_CAR" ]] || fail "Compiled asset catalog is missing: $ASSETS_CAR"
if [[ -f "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES_APP_STORE.md" ]]; then
  THIRD_PARTY_NOTICES="$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES_APP_STORE.md"
  CANONICAL_NOTICES="$ROOT_DIR/THIRD_PARTY_NOTICES_APP_STORE.md"
  REQUIRED_NOTICE_HEADINGS=("## Lobe Icons" "## X brand asset")
elif [[ -f "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]; then
  THIRD_PARTY_NOTICES="$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
  CANONICAL_NOTICES="$ROOT_DIR/THIRD_PARTY_NOTICES.md"
  # The Developer ID binary statically links these four through CodexBarCore.
  # Verified 2026-09-02 from Release-binary symbol counts, not from the resolved
  # graph — Package.resolved lists nine packages but only these are linked.
  REQUIRED_NOTICE_HEADINGS=(
    "## CodexBar"
    "## quickjs-ng"
    "## SweetCookieKit"
    "## swift-crypto"
    "## swift-log"
    "## Lobe Icons"
    "## X brand asset")
else
  fail "Bundled third-party notices are missing"
fi
cmp -s "$CANONICAL_NOTICES" "$THIRD_PARTY_NOTICES" \
  || fail "Bundled third-party notices differ from the canonical edition inventory"
for heading in "${REQUIRED_NOTICE_HEADINGS[@]}"; do
  grep -Fq "$heading" "$THIRD_PARTY_NOTICES" \
    || fail "Bundled third-party notices are missing: $heading"
done
# Apache-2.0 section 4(d) requires the upstream NOTICE, not just the license.
# Only the Developer ID edition links these two.
if [[ "$CANONICAL_NOTICES" == "$ROOT_DIR/THIRD_PARTY_NOTICES.md" ]]; then
  for notice_owner in "SwiftCrypto Project" "SwiftLog Project"; do
    grep -Fq "$notice_owner" "$THIRD_PARTY_NOTICES" \
      || fail "Bundled notices are missing the Apache NOTICE attribution: $notice_owner"
  done
  [[ "$(grep -c '^### NOTICE.txt' "$THIRD_PARTY_NOTICES")" == "2" ]] \
    || fail "Expected 2 Apache NOTICE.txt sections in the bundled notices"
fi
grep -q 'ThirdPartyNoticesButton' "$ROOT_DIR/Sources/UsageApp/DashboardView.swift" \
  || fail "Settings does not expose the bundled third-party notices"
grep -q 'THIRD_PARTY_NOTICES' "$ROOT_DIR/Sources/UsageApp/ThirdPartyNoticesView.swift" \
  || fail "Third-party notice loader is missing"

ASSET_INFO="$(xcrun assetutil --info "$ASSETS_CAR" 2>/dev/null)" \
  || fail "Could not inspect compiled asset catalog"
for asset_name in ProviderClaude ProviderOpenAI ProviderX; do
  grep -Fq "\"Name\" : \"$asset_name\"" <<<"$ASSET_INFO" \
    || fail "Compiled provider asset is missing: $asset_name"
done

# The original Usage app icon (family coral/orange mark) must be compiled in.
grep -Fq '"Name" : "AppIcon"' <<<"$ASSET_INFO" \
  || fail "Compiled AppIcon is missing from the asset catalog"

# --- Widget extension gates (static, headless) ---
APPEX_PATH="$APP_PATH/Contents/PlugIns/UsageWidget.appex"
APPEX_INFO_PLIST="$APPEX_PATH/Contents/Info.plist"
APPEX_ASSETS_CAR="$APPEX_PATH/Contents/Resources/Assets.car"

[[ -d "$APPEX_PATH" ]] || fail "Widget extension is not embedded: $APPEX_PATH"
[[ -f "$APPEX_INFO_PLIST" ]] || fail "Widget Info.plist not found"

apex_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$APPEX_INFO_PLIST" 2>/dev/null || true
}

APPEX_EXTENSION_ID="$(apex_plist_value NSExtension:NSExtensionPointIdentifier)"
APPEX_BUNDLE_ID="$(apex_plist_value CFBundleIdentifier)"
APPEX_PACKAGE_TYPE="$(apex_plist_value CFBundlePackageType)"
APPEX_VERSION="$(apex_plist_value CFBundleVersion)"
APPEX_SHORT_VERSION="$(apex_plist_value CFBundleShortVersionString)"
APPEX_EXECUTABLE="$(apex_plist_value CFBundleExecutable)"
APPEX_DISPLAY_NAME="$(apex_plist_value CFBundleDisplayName)"
APP_VERSION="$(plist_value CFBundleVersion)"
APP_SHORT_VERSION="$(plist_value CFBundleShortVersionString)"
APP_GROUP_ID="$(plist_value UsageAppGroupID)"
APPEX_GROUP_ID="$(apex_plist_value UsageAppGroupID)"

# A no-argument run exercises this repo's own default Debug build, which can
# silently go stale (a 2.0.31 bundle once earned a PASS while project.yml
# declared 2.0.33). Only the default-path call is version-checked: explicit
# paths verify freshly built or other-project bundles (e.g. the
# project-appstore.yml App Store build pinned at a different version) and must
# not be compared against this tree.
if [[ $# -eq 0 ]]; then
  EXPECTED_MARKETING_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' "$ROOT_DIR/project.yml")"
  [[ -n "$EXPECTED_MARKETING_VERSION" ]] \
    || fail "Could not read MARKETING_VERSION from $ROOT_DIR/project.yml"
  [[ "$APP_SHORT_VERSION" == "$EXPECTED_MARKETING_VERSION" ]] \
    || fail "Default-path bundle is $APP_SHORT_VERSION but project.yml declares $EXPECTED_MARKETING_VERSION; rebuild or pass an explicit .app path (explicit paths are exempt on purpose)"
fi

[[ "$APPEX_EXTENSION_ID" == "com.apple.widgetkit-extension" ]] \
  || fail "Widget NSExtensionPointIdentifier is '$APPEX_EXTENSION_ID', expected com.apple.widgetkit-extension"
[[ "$APPEX_BUNDLE_ID" == "com.example.usageagents.widget" ]] \
  || fail "Widget CFBundleIdentifier is '$APPEX_BUNDLE_ID', expected com.example.usageagents.widget"
[[ "$APPEX_PACKAGE_TYPE" == "XPC!" ]] \
  || fail "Widget CFBundlePackageType is '$APPEX_PACKAGE_TYPE', expected XPC!"
[[ "$APPEX_DISPLAY_NAME" == "Usage Agents" ]] \
  || fail "Widget CFBundleDisplayName is '$APPEX_DISPLAY_NAME', expected 'Usage Agents'"
[[ -n "$APPEX_EXECUTABLE" && -x "$APPEX_PATH/Contents/MacOS/$APPEX_EXECUTABLE" ]] \
  || fail "Widget executable is missing or not executable: $APPEX_PATH/Contents/MacOS/$APPEX_EXECUTABLE"
[[ "$APPEX_VERSION" == "$APP_VERSION" ]] \
  || fail "Widget CFBundleVersion ($APPEX_VERSION) != app CFBundleVersion ($APP_VERSION)"
[[ "$APPEX_SHORT_VERSION" == "$APP_SHORT_VERSION" ]] \
  || fail "Widget CFBundleShortVersionString ($APPEX_SHORT_VERSION) != app ($APP_SHORT_VERSION)"
[[ "$APP_GROUP_ID" == "$EXPECTED_GROUP" ]] \
  || fail "App UsageAppGroupID is '$APP_GROUP_ID'; expected '$EXPECTED_GROUP'"
[[ "$APPEX_GROUP_ID" == "$APP_GROUP_ID" ]] \
  || fail "Widget app group ($APPEX_GROUP_ID) != app app group ($APP_GROUP_ID)"
[[ -f "$APPEX_ASSETS_CAR" ]] || fail "Widget compiled asset catalog is missing: $APPEX_ASSETS_CAR"
# UsageCore is embed:false by design — the appex reaches the app's copy via
# rpath. A Frameworks directory inside the appex means duplicate embedding.
[[ ! -d "$APPEX_PATH/Contents/Frameworks" ]] \
  || fail "Widget appex must not embed its own Frameworks directory (UsageCore embed:false + rpath contract)"

APPEX_ASSET_INFO="$(xcrun assetutil --info "$APPEX_ASSETS_CAR" 2>/dev/null)" \
  || fail "Could not inspect widget compiled asset catalog"
for asset_name in ProviderClaude ProviderOpenAI ProviderX; do
  grep -Fq "\"Name\" : \"$asset_name\"" <<<"$APPEX_ASSET_INFO" \
    || fail "Widget compiled provider asset is missing: $asset_name"
done

echo "PASS: Usage bundle metadata is valid for MenuBarExtra"
echo "PASS: LSUIElement=false"
echo "PASS: Claude, OpenAI, and X vector assets are compiled"
echo "PASS: canonical third-party notices are bundled and exposed from Settings"
echo "PASS: UsageWidget.appex embedded: widgetkit-extension point, XPC!, executable, no nested Frameworks"
echo "PASS: App and widget versions match ($APP_SHORT_VERSION build $APP_VERSION)"
echo "PASS: App and widget resolve the same app group '$APP_GROUP_ID'"
echo "HEADLESS ONLY: this gate did not launch or terminate Usage.app"
