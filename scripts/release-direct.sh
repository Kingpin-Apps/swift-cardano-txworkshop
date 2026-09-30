#!/bin/zsh
# Builds, notarises and publishes the Developer ID Mac build.
#
#   scripts/release-direct.sh            build, notarise and package into build/direct
#   scripts/release-direct.sh --publish  also publish the GitHub release and the Homebrew cask
#
# Needs, once:
#   - DEVELOPMENT_TEAM set in project.yml, and a Developer ID Application certificate
#   - a notarytool keychain profile: the team's "scm-notarytool" (or NOTARY_PROFILE)
#   - the Sparkle EdDSA private key in the login Keychain (Sparkle's generate_keys)
#   - the public repo Kingpin-Apps/swift-cardano-txworkshop and the tap kingpin-apps/homebrew-tap
set -euo pipefail

cd "$(dirname "$0")/.."

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

NOTARY_PROFILE="${NOTARY_PROFILE:-scm-notarytool}"
RELEASES_REPO="${RELEASES_REPO:-Kingpin-Apps/swift-cardano-txworkshop}"
TAP_DIR="${TAP_DIR:-$(brew --repository 2>/dev/null)/Library/Taps/kingpin-apps/homebrew-tap}"
OUT="build/direct"
DERIVED="build/direct/DerivedData"
ARCHIVE="$OUT/TxWorkshopDirect.xcarchive"

VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "No MARKETING_VERSION in project.yml" >&2; exit 1; }
# The team set on the App Store target; the base setting is empty.
TEAM="${TEAM:-$(sed -n 's/^ *DEVELOPMENT_TEAM: "*\([A-Z0-9]\{10\}\)"*$/\1/p' project.yml | head -1)}"
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in project.yml first" >&2; exit 1; }
PUBLIC_KEY=$(sed -n 's/^ *SUPublicEDKey: "\(.*\)"/\1/p' project.yml | head -1)
# Without the Sparkle key the build can still be made and notarised, to test the
# pipeline; it just can't be published, since installed copies could not update.
if [[ -z "$PUBLIC_KEY" ]]; then
    (( PUBLISH )) && { echo "Set SUPublicEDKey in project.yml first (Sparkle generate_keys)" >&2; exit 1; }
    echo "⚠ No SUPublicEDKey yet: building without an appcast, and not publishing."
fi

echo "▶ Cardano TxWorkshop $VERSION (Developer ID)"
rm -rf "$OUT/export" "$ARCHIVE"
mkdir -p "$OUT"

xcodegen generate

# Sparkle compares build numbers, so each release needs a higher one: the
# commit count only grows. Xcode Cloud numbers the App Store builds itself.
BUILD=$(git rev-list --count HEAD)

echo "▶ Archiving build $BUILD"
xcodebuild -project TxWorkshop.xcodeproj -scheme TxWorkshopDirect CURRENT_PROJECT_VERSION="$BUILD" \
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
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export"
APP="$OUT/export/Cardano TxWorkshop.app"
[[ -d "$APP" ]] || { echo "No app in $OUT/export" >&2; exit 1; }

echo "▶ Packaging"
DMG="$OUT/CardanoTxWorkshop-$VERSION.dmg"
rm -f "$DMG"
create-dmg --volname "Cardano TxWorkshop $VERSION" --app-drop-link 480 170 \
    --window-size 640 360 --icon "$(basename "$APP")" 160 170 "$DMG" "$APP"

# Gatekeeper checks the disk image's own signature as well as the app's.
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo "▶ Notarising"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

if [[ -z "$PUBLIC_KEY" ]]; then
    echo "✓ Built and notarised $DMG ($(shasum -a 256 "$DMG" | cut -d' ' -f1))"
    echo "Make the Sparkle key (Sparkle's generate_keys) and set SUPublicEDKey before publishing."
    exit 0
fi

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
    --repo "$RELEASES_REPO" --title "Cardano TxWorkshop $VERSION" \
    --notes "Cardano TxWorkshop $VERSION for Mac. The App Store version is on the App Store."

echo "▶ Updating the Homebrew cask"
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/cardano-txworkshop.rb" <<EOF
cask "cardano-txworkshop" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$RELEASES_REPO/releases/download/v#{version}/CardanoTxWorkshop-#{version}.dmg"
  name "Cardano TxWorkshop"
  desc "Inspect, validate, build and sign Cardano transactions"
  homepage "https://github.com/$RELEASES_REPO"

  # Sparkle updates it in place.
  auto_updates true
  depends_on :macos

  app "$(basename "$APP")"

  zap trash: [
    "~/Library/Application Support/com.kingpinapps.cardano-txworkshop",
    "~/Library/Caches/com.kingpinapps.cardano-txworkshop",
    "~/Library/Preferences/com.kingpinapps.cardano-txworkshop.plist",
  ]
end
EOF
git -C "$TAP_DIR" add Casks/cardano-txworkshop.rb
git -C "$TAP_DIR" commit -m "chore(cardano-txworkshop): $VERSION"
echo "✓ Cask committed in $TAP_DIR. Push it when ready."
