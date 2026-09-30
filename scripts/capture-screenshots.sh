#!/usr/bin/env bash
#
# Takes the App Store screenshots on a simulator by running the
# TxWorkshopScreenshots UI test, which opens the sample Minswap transaction and
# walks through Overview, Inputs & Outputs, Validate, a script trace and CBOR.
#
# The test cannot take screenshots on visionOS, so at each snapshot it drops a
# ".request-<name>" file in the output folder and waits for ".done-<name>".
# This script watches for those, takes the screenshot with `simctl io` at the
# simulator's full resolution, and answers. iPhone and iPad work the same way.
#
# Usage: scripts/capture-screenshots.sh <simulator name> <file prefix>
#   e.g. scripts/capture-screenshots.sh "Apple Vision Pro" Vision
set -euo pipefail

DEVICE_NAME="${1:?simulator name required, e.g. \"Apple Vision Pro\"}"
PREFIX="${2:?file prefix required, e.g. Vision}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# fastlane uploads each platform from its own folder.
case "$DEVICE_NAME" in
  *Vision*) OUT="$ROOT/fastlane/screenshots_visionos/en-US" ;;
  *) OUT="$ROOT/fastlane/screenshots/en-US" ;;
esac
mkdir -p "$OUT"
WORK="$ROOT/build/screenshots"
BUNDLE_ID=com.kingpinapps.cardano-txworkshop
SAMPLE="$ROOT/scripts/screenshot-sample/Minswap Batch.txworkshop"

# A booted simulator of that name first, else the one on the newest runtime.
find_udid() {
  xcrun simctl list devices available $1 \
    | awk -v n="$DEVICE_NAME (" 'index($0,n){ if (match($0,/[0-9A-F-]{36}/)) id=substr($0,RSTART,RLENGTH) } END { print id }'
}
udid=$(find_udid booted)
[ -n "$udid" ] || udid=$(find_udid)
[ -n "$udid" ] || { echo "No available '$DEVICE_NAME' simulator" >&2; exit 1; }
echo "▶ $DEVICE_NAME ($udid)"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState discharging --batteryLevel 100 \
  --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

echo "▶ Building"
xcodebuild build-for-testing -project "$ROOT/TxWorkshop.xcodeproj" -scheme TxWorkshopScreenshots \
  -destination "id=$udid" -derivedDataPath "$WORK/derived" \
  -packageAuthorizationProvider netrc -skipPackagePluginValidation -skipMacroValidation \
  > "$WORK.build.log" 2>&1 || { tail -20 "$WORK.build.log" >&2; exit 1; }

# Install the app and put the sample document in its Documents folder.
app=$(find "$WORK/derived/Build/Products" -maxdepth 2 -name "Cardano TxWorkshop.app" -path "*simulator*" | head -1)
xcrun simctl install "$udid" "$app"
docs="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)/Documents"
mkdir -p "$docs"
rm -rf "$docs/Minswap Batch.txworkshop"
cp -R "$SAMPLE" "$docs/"

mkdir -p "$WORK/requests"
rm -f "$WORK/requests"/.request-* "$WORK/requests"/.done-*

echo "▶ Running"
TEST_RUNNER_SCREENSHOT_OUTPUT_DIR="$WORK/requests" \
xcodebuild test-without-building -project "$ROOT/TxWorkshop.xcodeproj" -scheme TxWorkshopScreenshots \
  -destination "id=$udid" -derivedDataPath "$WORK/derived" \
  > "$WORK.test.log" 2>&1 &
test_pid=$!

capture() {
  for request in "$WORK/requests"/.request-*; do
    [ -e "$request" ] || continue
    name="${request##*/.request-}"
    xcrun simctl io "$udid" screenshot "$OUT/$PREFIX-$name.png" >/dev/null 2>&1 || true
    : > "$WORK/requests/.done-$name"
    rm -f "$request"
    echo "  saved $PREFIX-$name.png"
  done
}

while kill -0 "$test_pid" 2>/dev/null; do
  capture
  sleep 0.3
done
capture

set +e; wait "$test_pid"; status=$?; set -e
[ "$status" -eq 0 ] || { grep -E "error|failed|XCTAssert" "$WORK.test.log" | tail -10 >&2; }
echo "▶ Done (xcodebuild exited $status; log: $WORK.test.log)"
exit "$status"
