xcodebuild := "xcodebuild -project TxWorkshop.xcodeproj -skipPackagePluginValidation -skipMacroValidation"

# Regenerate TxWorkshop.xcodeproj from project.yml
generate:
    xcodegen generate

# Build the package
build:
    swift build

# Run the package tests
test:
    swift test

# Build every app target for every platform
build-apps:
    {{xcodebuild}} -scheme TxWorkshop -destination "generic/platform=macOS" build
    {{xcodebuild}} -scheme TxWorkshopDirect -destination "generic/platform=macOS" build
    {{xcodebuild}} -scheme TxWorkshop -destination "generic/platform=iOS Simulator" build
    {{xcodebuild}} -scheme TxWorkshop -destination "generic/platform=visionOS Simulator" build

# Fill the String Catalogs from the source (builds macOS and iOS)
strings:
    scripts/sync-strings.sh

# Update the changelog
changelog:
    cz ch

# Bump the version from the commits since the last tag
bump: changelog
    cz bump

# Build, notarise and package the Developer ID Mac build (add --publish to release it)
release-direct *args:
    scripts/release-direct.sh {{args}}

# Upload the App Store text for every platform (source ~/.secrets.zsh first)
metadata:
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane upload_metadata_all
