#!/usr/bin/env bash
#
# Runs the TransactionEditorUITests on a simulator, each test on a fresh
# install: the app is reinstalled before every test and its Documents seeded
# with the samples in scripts/screenshot-sample and a throwaway signing key
# file, made for the run and never kept. Screenshots go to build/ui-tests/shots.
#
# Usage: scripts/ui-tests.sh <simulator name> [test name …]
#   e.g. scripts/ui-tests.sh "iPhone 17"
#        scripts/ui-tests.sh "Apple Vision Pro" testSigningKeyFile
set -euo pipefail

DEVICE_NAME="${1:?simulator name required, e.g. \"iPhone 17\"}"
shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/ui-tests"
BUNDLE_ID=com.kingpinapps.cardano-txworkshop
CLASS=TransactionEditorUITests
TESTS=("$@")
if [ ${#TESTS[@]} -eq 0 ]; then
  TESTS=(testConfirmedSubmissionLinksToTheExplorer testEditInBuildBuildsTheTransactionAgain
    testEditWithoutChainDataPointsToChainData testSigningKeyFile testStartOverClearsTheForm)
fi

udid=$(xcrun simctl list devices available \
  | awk -v n="$DEVICE_NAME (" 'index($0,n){ if (match($0,/[0-9A-F-]{36}/)) id=substr($0,RSTART,RLENGTH) } END { print id }')
[ -n "$udid" ] || { echo "No available '$DEVICE_NAME' simulator" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
mkdir -p "$WORK/shots"

echo "▶ Building for $DEVICE_NAME"
xcodebuild build-for-testing -project "$ROOT/TxWorkshop.xcodeproj" -scheme TxWorkshopScreenshots \
  -destination "id=$udid" -derivedDataPath "$WORK/derived" \
  -packageAuthorizationProvider netrc -skipPackagePluginValidation -skipMacroValidation \
  > "$WORK/build.log" 2>&1 || { grep -E " error:" "$WORK/build.log" | head -5 >&2; exit 1; }
# Both platforms build into one folder: take the app for this one.
case "$DEVICE_NAME" in
  *Vision*) products="Debug-xrsimulator" ;;
  *) products="Debug-iphonesimulator" ;;
esac
app="$WORK/derived/Build/Products/$products/TxWorkshop.app"
[ -d "$app" ] || { echo "No build at $app" >&2; exit 1; }

failed=0
for test in "${TESTS[@]}"; do
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"
  docs="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)/Documents"
  mkdir -p "$docs"
  cp -R "$ROOT/scripts/screenshot-sample/Edit Me.txworkshop" "$ROOT/scripts/screenshot-sample/Needs Chain Data.txworkshop" "$docs/"
  python3 -c 'import json, os, sys; json.dump({"type": "PaymentSigningKeyShelley_ed25519", "description": "Payment Signing Key", "cborHex": "5820" + os.urandom(32).hex()}, open(sys.argv[1], "w"))' "$docs/payment.skey"

  rm -rf "$WORK/$test.xcresult"
  if TEST_RUNNER_UITEST_SCREENSHOTS="$WORK/shots" xcodebuild test-without-building \
    -project "$ROOT/TxWorkshop.xcodeproj" -scheme TxWorkshopScreenshots -destination "id=$udid" \
    -derivedDataPath "$WORK/derived" -resultBundlePath "$WORK/$test.xcresult" \
    -only-testing:"TxWorkshopScreenshots/$CLASS/$test" > "$WORK/$test.log" 2>&1; then
    echo "✓ $test"
  else
    echo "✗ $test"
    grep -E "error:" "$WORK/$test.log" | grep -v BLSXPC | sed 's/^.*error: //' | head -3
    failed=$((failed + 1))
  fi
done
xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
echo "$(( ${#TESTS[@]} - failed )) of ${#TESTS[@]} passed on $DEVICE_NAME."
[ "$failed" -eq 0 ]
