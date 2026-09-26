#!/bin/sh
# Xcode Cloud: the Blockfrost and Koios clients generate code with the OpenAPI
# build plugin, and Xcode stops to ask whether to trust package plugins and
# macros. There is no one to ask in CI, so trust them up front.
set -e
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
