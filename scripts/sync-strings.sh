#!/usr/bin/env bash
# Fills the String Catalogs from the source, as Xcode does when it builds in the IDE:
# builds each platform with string extraction on, then merges what the compiler found
# into each module's Localizable.xcstrings. Platform-only strings are kept (not marked
# stale) because each build sees only its own platform's code.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="$(mktemp -d)"
trap 'rm -rf "$DD"' EXIT

build() { # scheme destination
  xcodebuild -project TxWorkshop.xcodeproj -scheme "$1" -destination "$2" -derivedDataPath "$DD" \
    -skipPackagePluginValidation -skipMacroValidation SWIFT_EMIT_LOC_STRINGS=YES build >/dev/null
}

sync() { # module
  local files=()
  while IFS= read -r file; do files+=("$file"); done < <(find "$DD" -name "*.stringsdata" -path "*/$1-t.build/*")
  [ ${#files[@]} -eq 0 ] && return
  xcrun xcstringstool sync "Sources/$1/Resources/Localizable.xcstrings" --skip-marking-strings-stale --stringsdata "${files[@]}"
}

for destination in "platform=macOS" "generic/platform=iOS Simulator"; do
  build TxWorkshop "$destination"
  sync TxWorkshopCore
  sync TxWorkshopUI
  rm -rf "$DD"/Build
done
build TxWorkshopWatch "generic/platform=watchOS Simulator"
sync TxWorkshopWatchUI
echo "String Catalogs synced."
