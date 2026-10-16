fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload iPhone and iPad metadata

### ios upload_metadata_macos

```sh
[bundle exec] fastlane ios upload_metadata_macos
```

Upload Mac metadata

### ios upload_metadata_visionos

```sh
[bundle exec] fastlane ios upload_metadata_visionos
```

Upload Apple Vision Pro metadata

### ios upload_metadata_all

```sh
[bundle exec] fastlane ios upload_metadata_all
```

Upload metadata for every store platform

### ios store_version

```sh
[bundle exec] fastlane ios store_version
```

Rename each platform's editable App Store version to the version in project.yml

### ios direct_profile

```sh
[bundle exec] fastlane ios direct_profile
```

Make or renew the Developer ID provisioning profile, with iCloud, and install it

### ios check

```sh
[bundle exec] fastlane ios check
```

Check the metadata for common App Review problems

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
