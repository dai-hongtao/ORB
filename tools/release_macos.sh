#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/client/macos/ORB/ORB.xcodeproj"
SCHEME="ORB"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/ORB-Release-DerivedData}"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_DIR/ORB.app"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="${WORK_DIR:-/private/tmp/ORB-Release-Package}"

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"

log() {
  printf '\n==> %s\n' "$1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "$1" >&2
    exit 1
  fi
}

build_app() {
  log "Building ORB.app"

  local args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED_DATA_PATH"
    clean build
  )

  if [[ -n "$DEVELOPER_ID_APPLICATION" ]]; then
    args+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
    )

    if [[ -n "$TEAM_ID" ]]; then
      args+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi
  else
    printf 'warning: DEVELOPER_ID_APPLICATION is not set; building with local/ad-hoc signing.\n' >&2
  fi

  xcodebuild "${args[@]}"
}

read_app_metadata() {
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
  DMG_BASENAME="ORB-${VERSION}-${BUILD_NUMBER}-macOS"
  DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"
}

verify_signature() {
  log "Verifying app signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  printf 'Bundle ID: %s\n' "$BUNDLE_ID"
  printf 'Version:   %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
}

create_dmg() {
  log "Creating DMG"

  local staging_dir="$WORK_DIR/staging"

  rm -rf "$WORK_DIR"
  mkdir -p "$staging_dir" "$DIST_DIR"
  rm -f "$DMG_PATH"

  ditto "$APP_PATH" "$staging_dir/ORB.app"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "ORB" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$DMG_PATH"

  rm -rf "$WORK_DIR"
}

notarize_dmg() {
  if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    log "Skipping notarization"
    return
  fi

  if [[ -z "$NOTARY_PROFILE" ]]; then
    log "Skipping notarization"
    printf 'Set NOTARY_PROFILE to a notarytool keychain profile name to notarize the DMG.\n' >&2
    return
  fi

  if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
    printf 'error: notarization requires Developer ID signing. Set DEVELOPER_ID_APPLICATION.\n' >&2
    exit 1
  fi

  log "Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
}

print_result() {
  log "Release artifact ready"
  printf '%s\n' "$DMG_PATH"

  if [[ -z "$DEVELOPER_ID_APPLICATION" || -z "$NOTARY_PROFILE" || "$SKIP_NOTARIZATION" == "1" ]]; then
    cat <<'EOF'

Note: this DMG is not a fully notarized public release.
For a Gatekeeper-friendly release, run with:

  DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
  TEAM_ID="TEAMID" \
  NOTARY_PROFILE="orb-notary" \
  tools/release_macos.sh

Create the notary profile once with:

  xcrun notarytool store-credentials orb-notary \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
EOF
  fi
}

main() {
  require_tool xcodebuild
  require_tool hdiutil
  require_tool codesign
  require_tool ditto

  build_app
  read_app_metadata
  verify_signature
  create_dmg
  notarize_dmg
  print_result
}

main "$@"
