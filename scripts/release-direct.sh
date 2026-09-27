#!/bin/zsh
# Builds, notarises and publishes the Developer ID Mac build.
#
#   scripts/release-direct.sh            build, notarise and package into build/direct
#   scripts/release-direct.sh --publish  also publish the GitHub release and the Homebrew cask
#
# Needs, once (see docs/release-checklist.md):
#   - DEVELOPMENT_TEAM set in project.yml, and a Developer ID Application certificate
#   - a notarytool keychain profile named "txworkshop-notary" (or NOTARY_PROFILE)
#   - the Sparkle EdDSA private key in the login Keychain (Sparkle's generate_keys)
#   - the public repo Kingpin-Apps/tx-workshop-releases and the tap kingpin-apps/homebrew-tap
set -euo pipefail

cd "$(dirname "$0")/.."

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

NOTARY_PROFILE="${NOTARY_PROFILE:-txworkshop-notary}"
RELEASES_REPO="${RELEASES_REPO:-Kingpin-Apps/tx-workshop-releases}"
TAP_DIR="${TAP_DIR:-$(brew --repository 2>/dev/null)/Library/Taps/kingpin-apps/homebrew-tap}"
OUT="build/direct"
DERIVED="build/direct/DerivedData"
ARCHIVE="$OUT/TxWorkshopDirect.xcarchive"

VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "No MARKETING_VERSION in project.yml" >&2; exit 1; }
TEAM=$(sed -n 's/^ *DEVELOPMENT_TEAM: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in project.yml first" >&2; exit 1; }
PUBLIC_KEY=$(sed -n 's/^ *SUPublicEDKey: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$PUBLIC_KEY" ]] || { echo "Set SUPublicEDKey in project.yml first (Sparkle generate_keys)" >&2; exit 1; }

echo "▶ Tx Workshop $VERSION (Developer ID)"
rm -rf "$OUT/export" "$ARCHIVE"
mkdir -p "$OUT"

xcodegen generate

echo "▶ Archiving"
xcodebuild -project TxWorkshop.xcodeproj -scheme TxWorkshopDirect \
    -skipPackagePluginValidation -skipMacroValidation -packageAuthorizationProvider netrc \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" archive > "$OUT/archive.log" 2>&1 \
    || { tail -30 "$OUT/archive.log" >&2; echo "Archive failed; see $OUT/archive.log" >&2; exit 1; }

echo "▶ Exporting for Developer ID"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
APP="$OUT/export/Tx Workshop Direct.app"
[[ -d "$APP" ]] || { echo "No app in $OUT/export" >&2; exit 1; }

echo "▶ Packaging"
DMG="$OUT/TxWorkshop-$VERSION.dmg"
rm -f "$DMG"
create-dmg --volname "Tx Workshop $VERSION" --app-drop-link 480 170 \
    --window-size 640 360 --icon "$(basename "$APP")" 160 170 "$DMG" "$APP"

echo "▶ Notarising"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "▶ Appcast"
# Sparkle's tools come with its Swift package.
SPARKLE_BIN=$(find "$DERIVED/SourcePackages/artifacts" -path "*/Sparkle/bin" -type d | head -1)
[[ -n "$SPARKLE_BIN" ]] || { echo "Sparkle tools not found in $DERIVED" >&2; exit 1; }
mkdir -p "$OUT/updates"
cp "$DMG" "$OUT/updates/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$RELEASES_REPO/releases/download/v$VERSION/" \
    "$OUT/updates"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

echo "✓ Built $DMG ($SHA)"

if (( ! PUBLISH )); then
    echo "Run again with --publish to release it."
    exit 0
fi

echo "▶ Publishing the GitHub release"
gh release create "v$VERSION" "$DMG" "$OUT/updates/appcast.xml" \
    --repo "$RELEASES_REPO" --title "Tx Workshop $VERSION" \
    --notes "Tx Workshop $VERSION for Mac. The App Store version is on the App Store."

echo "▶ Updating the Homebrew cask"
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/tx-workshop.rb" <<EOF
cask "tx-workshop" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$RELEASES_REPO/releases/download/v#{version}/TxWorkshop-#{version}.dmg"
  name "Cardano Tx Workshop"
  desc "Inspect, validate, build and sign Cardano transactions"
  homepage "https://github.com/$RELEASES_REPO"

  # Sparkle updates it in place.
  auto_updates true

  app "$(basename "$APP")"

  zap trash: [
    "~/Library/Application Support/com.kingpinapps.txworkshop",
    "~/Library/Caches/com.kingpinapps.txworkshop",
    "~/Library/Preferences/com.kingpinapps.txworkshop.plist",
  ]
end
EOF
git -C "$TAP_DIR" add Casks/tx-workshop.rb
git -C "$TAP_DIR" commit -m "chore(tx-workshop): $VERSION"
echo "✓ Cask committed in $TAP_DIR. Push it when ready."
