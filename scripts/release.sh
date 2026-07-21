#!/usr/bin/env bash
#
# Build a distributable DMG of HRV-CV Monitor.
#
#   Usage:  scripts/release.sh [version]        # e.g. scripts/release.sh 1.0.0
#   Output: build/HRV-CV-Monitor-<version>.dmg
#
# Why this is more involved than a plain `xcodebuild archive`:
# we distribute WITHOUT an Apple Developer ID (no notarization). Two consequences
# drive every non-obvious step below:
#
#   1. On Apple Silicon an app must be at least AD-HOC signed to launch at all,
#      so we sign with `-` (Sign to Run Locally).
#   2. Xcode's own codesign phase FAILS on CLI builds with
#         "resource fork, Finder information, or similar detritus not allowed"
#      because macOS stamps `com.apple.FinderInfo` onto icon-bearing .app
#      bundles. And packing the bundle (ditto / hdiutil) RE-stamps it. So we
#      build unsigned, then strip the detritus and ad-hoc sign ourselves — and
#      we do that final clean+sign INSIDE a read-write disk image, as the last
#      operation before converting to the compressed .dmg, so the signature is
#      valid exactly as it ships.
#
# Friends still see Gatekeeper on first launch (unsigned/not notarized). They
# clear it once with:  xattr -dr com.apple.quarantine "/Applications/HRV-CV Monitor.app"
#
set -euo pipefail

VERSION="${1:-1.0.0}"
PROJECT="HRV-CV Monitor.xcodeproj"
SCHEME="HRV-CV Monitor"
APP_NAME="HRV-CV Monitor.app"
VOL_NAME="HRV-CV Monitor"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DD="$ROOT/build/dd"
STAGE="$ROOT/build/dmg-staging"
RW="$ROOT/build/rw.dmg"
OUT="$ROOT/build/HRV-CV-Monitor-$VERSION.dmg"
ENT="$ROOT/build/entitlements.plist"
MNT="/tmp/hrvcv_dmg_mnt.$$"

echo "▶ Building $SCHEME (Release, unsigned)…"
rm -rf "$DD"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DD" -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO clean build >/dev/null

APP="$DD/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || { echo "✗ build produced no .app at $APP"; exit 1; }

echo "▶ Writing distribution entitlements (sandbox + network, no debug get-task-allow)…"
cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
  <key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST

echo "▶ Staging app + /Applications symlink…"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

echo "▶ Packing read-write image…"
rm -f "$RW" "$OUT"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -format UDRW -ov "$RW" >/dev/null

echo "▶ Cleaning detritus + ad-hoc signing inside the image (final op)…"
rm -rf "$MNT"; mkdir -p "$MNT"
hdiutil attach "$RW" -nobrowse -owners on -mountpoint "$MNT" >/dev/null
APPIN="$MNT/$APP_NAME"
find "$APPIN" -exec xattr -c {} \; 2>/dev/null || true
codesign --force --deep --sign - --entitlements "$ENT" --timestamp=none --generate-entitlement-der "$APPIN"
codesign --verify --strict "$APPIN"
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT" 2>/dev/null || true

echo "▶ Converting to compressed image…"
hdiutil convert "$RW" -format UDZO -o "$OUT" -ov >/dev/null
rm -f "$RW"

SIZE="$(du -h "$OUT" | cut -f1)"
echo "✓ $OUT ($SIZE)"
echo
echo "Next, to publish a GitHub release:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION \"$OUT\" --title \"v$VERSION\" --notes \"…\""
