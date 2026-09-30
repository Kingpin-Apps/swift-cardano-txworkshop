# Release checklist

What has to be done by hand, once, before the first release. Everything after that is
scripted: Xcode Cloud for the App Store, `just release-direct` for the Developer ID Mac build,
and `just metadata` for the App Store text.

## Signing

- [x] Set `DEVELOPMENT_TEAM: "G88W6X4TCA"` in `project.yml`, then `just generate`.
- [ ] Register the App ID `com.kingpinapps.cardano-txworkshop` in the Developer
      portal with Keychain Sharing, Bluetooth and the hardened-process capabilities.
- [x] Have a Developer ID Application certificate in the login Keychain ("Developer ID
      Application: Adderley Group Ltd. (G88W6X4TCA)").

## App Store

- [ ] Create the app in App Store Connect: iOS, macOS and visionOS, bundle id
      `com.kingpinapps.cardano-txworkshop`, primary category Developer Tools.
- [ ] Connect the repository to Xcode Cloud and add a workflow that archives `TxWorkshop` for
      each platform and ships to TestFlight. `ci_scripts/ci_post_clone.sh` is already in place.
- [ ] Create an editable version on each platform before `just metadata`, or deliver fails.
- [ ] Review the drafted text in `fastlane/metadata/en-US`.
- [x] Support, privacy and marketing URLs: the GitHub Pages site served from this repo's `docs/` folder,
      <https://kingpin-apps.github.io/swift-cardano-txworkshop/> with an app-specific privacy policy.
- [ ] Add screenshots in App Store Connect (fastlane skips them for now).
- [ ] Review the app icon in Icon Composer (`Icon/AppIcon.icon`), including its dark, tinted
      and clear looks. visionOS uses the layered `Icon/AppIconVision.xcassets`.
- [ ] Answer the privacy questionnaire: no data collected. Chain providers are called with the
      person's own API keys.
- [ ] Export compliance: the app uses only standard cryptography (signing, hashing, TLS).

## Developer ID build

- [x] A notarytool profile: the team's `scm-notarytool` profile works for any of its apps, so
      `release-direct.sh` uses it. Set `NOTARY_PROFILE` to use another.
- [ ] Make the Sparkle key: run `generate_keys` from Sparkle's tools
      (`build/direct/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`, after one
      `just release-direct` build). It stores the private key in the login Keychain and prints
      the public key. Put the public key in `SUPublicEDKey` in `project.yml`. Until then the
      updater stays off.
- [ ] Back up the Sparkle private key (`generate_keys -x`) somewhere safe outside the repo.
      Losing it means no more updates for installed copies.
- [x] Make this repo public (2026-09-30). The appcast and DMGs are served from its latest
      GitHub release, and the docs site from `docs/` by GitHub Pages.
- [x] The tap `Kingpin-Apps/homebrew-tap` exists (it carries `scm` and `spcc`).

- [x] The Developer ID pipeline works end to end (2026-09-30): archive, export, signed DMG,
      notarised and stapled, accepted by Gatekeeper, and the app launches. `just release-direct`
      builds and notarises without the Sparkle key; publishing needs it.

## Each release

1. `just bump`, then push the branch and the tag.
2. Xcode Cloud builds the App Store version; submit it from App Store Connect.
3. `just release-direct` to build and notarise; check the DMG; then
   `just release-direct --publish` and push the tap.
4. `source ~/.secrets.zsh && just metadata` if the store text changed. `~/.secrets.zsh`
   must export `APP_REVIEW_PHONE`, the App Review contact number, which is kept out of the repo.
