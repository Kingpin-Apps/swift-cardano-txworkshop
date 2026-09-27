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
    {{xcodebuild}} -scheme TxWorkshopWatch -destination "generic/platform=watchOS Simulator" build

# Fill the String Catalogs from the source (builds macOS, iOS and watchOS)
strings:
    scripts/sync-strings.sh

# Update the changelog
changelog:
    cz ch

# Bump the version from the commits since the last tag
bump: changelog
    cz bump
