# Release checklist

What has to be done by hand, once, before the first release. Everything after that is
scripted: Xcode Cloud for the App Store, `just release-direct` for the Developer ID Mac build,
and `just metadata` for the App Store text.

## Signing

- [ ] Set `DEVELOPMENT_TEAM: "G88W6X4TCA"` in `project.yml`, then `just generate`.
- [ ] Register the App ID `com.kingpinapps.txworkshop` in the Developer
      portal with Keychain Sharing, Bluetooth and the hardened-process capabilities.
- [ ] Have a Developer ID Application certificate in the login Keychain.

## App Store

- [ ] Create the app in App Store Connect: iOS, macOS and visionOS, bundle id
      `com.kingpinapps.txworkshop`, primary category Developer Tools.
- [ ] Connect the repository to Xcode Cloud and add a workflow that archives `TxWorkshop` for
      each platform and ships to TestFlight. `ci_scripts/ci_post_clone.sh` is already in place.
- [ ] Create an editable version on each platform before `just metadata`, or deliver fails.
- [ ] Review the drafted text in `fastlane/metadata/en-US`, and check the support and privacy
      URLs exist.
- [ ] Add screenshots in App Store Connect (fastlane skips them for now).
- [ ] Answer the privacy questionnaire: no data collected. Chain providers are called with the
      person's own API keys.
- [ ] Export compliance: the app uses only standard cryptography (signing, hashing, TLS).

## Developer ID build

- [ ] Store a notarytool profile:
      `xcrun notarytool store-credentials txworkshop-notary --team-id G88W6X4TCA`.
- [ ] Make the Sparkle key: run `generate_keys` from Sparkle's tools
      (`build/direct/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`, after one
      `just release-direct` build). It stores the private key in the login Keychain and prints
      the public key. Put the public key in `SUPublicEDKey` in `project.yml`. Until then the
      updater stays off.
- [ ] Back up the Sparkle private key (`generate_keys -x`) somewhere safe outside the repo.
      Losing it means no more updates for installed copies.
- [ ] Create the public repo `Kingpin-Apps/tx-workshop-releases`. The appcast is served from its
      latest release.
- [ ] Create the tap `Kingpin-Apps/homebrew-tap` and `brew tap kingpin-apps/tap`.

## Each release

1. `just bump`, then push the branch and the tag.
2. Xcode Cloud builds the App Store version; submit it from App Store Connect.
3. `just release-direct` to build and notarise; check the DMG; then
   `just release-direct --publish` and push the tap.
4. `source ~/.secrets.zsh && just metadata` if the store text changed.
