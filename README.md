# Cardano TxWorkshop

A native app for Cardano transactions: inspect, validate, debug, build, sign, submit and track them.
Runs on macOS, iPadOS, iOS and visionOS. Open source under
Apache-2.0.

It works on documents. A `.txworkshop` document holds one transaction as it was written, the
chain data needed to validate it again offline, notes, the witnesses collected for it, and its
validation history. The app also opens bare transactions: cardano-cli text envelopes (`.tx`,
`.signed`), raw CBOR (`.cbor`) and hex (`.hex`), and anything pasted as hex, base64 or an envelope.

**Website and guide:** <https://kingpin-apps.github.io/swift-cardano-txworkshop/> ·
[Privacy policy](https://kingpin-apps.github.io/swift-cardano-txworkshop/privacy/) ·
[Support](https://kingpin-apps.github.io/swift-cardano-txworkshop/support/)

## Install

- **App Store** (Mac, iPhone, iPad, Apple Vision Pro): coming soon.
- **Mac download** (Developer ID, adds a local cardano-node and cardano-cli; macOS 27):
  `brew install --cask kingpin-apps/tap/cardano-txworkshop`, or the DMG from the
  [latest release](https://github.com/Kingpin-Apps/swift-cardano-txworkshop/releases/latest).
  It updates itself.

The website is the static site in `docs/`, served by GitHub Pages; edit the HTML there.

## Requirements

- Xcode 27 (Swift 6.4)
- macOS, iOS, iPadOS or visionOS 27

## Layout

| Module | What it holds |
|---|---|
| `TxWorkshopCore` | The document format, models, provider settings and design system. |
| `TxWorkshopEngine` | Decoding, inspection, validation and chain providers over the swift-cardano stack. |
| `TxWorkshopUI` | The SwiftUI app: document scene, shell and features. |
| `TxWorkshopDirect` | What only the Developer ID build may do: a local node, cardano-cli. |

The apps are XcodeGen targets (`project.yml`): `TxWorkshop` for the App Store on every platform,
`TxWorkshopDirect` for the notarised Developer ID Mac build.

## Building

```sh
just generate     # regenerate TxWorkshop.xcodeproj after editing project.yml
just test         # package tests
just build-apps   # every app target, every platform
```

Command-line builds pass `-skipPackagePluginValidation`, because the Blockfrost and Koios clients
generate their code with the OpenAPI build plugin. In Xcode, trust the plugin once when asked.

## Providers and secrets

Chain data comes from Blockfrost, Koios, Ogmios (optionally with Kupo), Yaci DevKit, or nothing
at all (offline). The Developer ID build adds a local node and cardano-cli. API keys are kept in
the Keychain, never in documents or settings, and on the device only unless Sync with iCloud is
on, when they go in iCloud Keychain. Signing keys never leave the device.

## License

Apache License 2.0. See [LICENSE](LICENSE).
