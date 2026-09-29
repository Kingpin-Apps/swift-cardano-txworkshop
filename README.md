# Cardano TxWorkshop

A native app for Cardano transactions: inspect, validate, build, sign, submit and track them.
Runs on macOS, iPadOS, iOS and visionOS. Open source under
Apache-2.0.

It works on documents. A `.txworkshop` document holds one transaction as it was written, the
chain data needed to validate it again offline, notes, the witnesses collected for it, and its
validation history. The app also opens bare transactions: cardano-cli text envelopes (`.tx`,
`.signed`), raw CBOR (`.cbor`) and hex (`.hex`), and anything pasted as hex, base64 or an envelope.

> Status: feature complete for a first release: inspection, the CBOR and CDDL tools, offline
> validation with script traces, the builder, and signing with keys or a Ledger, Trezor or
> Keystone. Not yet released; see [the release checklist](docs/release-checklist.md).

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

## Releasing

The App Store build ships through Xcode Cloud; fastlane manages only the store text
(`just metadata`). The Developer ID Mac build updates itself with Sparkle and ships from
`just release-direct` as a notarised DMG, a GitHub release and a Homebrew cask. The one-time
setup is in [docs/release-checklist.md](docs/release-checklist.md).

## Providers and secrets

Chain data comes from Blockfrost, Koios, Ogmios (optionally with Kupo), Yaci DevKit, or nothing
at all (offline). The Developer ID build adds a local node. API keys are kept in the Keychain,
on the device only, and never in documents or settings.

## License

Apache License 2.0. See [LICENSE](LICENSE).
