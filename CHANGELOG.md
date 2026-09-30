## v0.1.0 (2026-09-30)

### Feat

- **ui**: clearer toolbar icons with tooltips; fetch sits apart
- open transactions, addresses, pools, DReps, actions and assets in a chosen block explorer
- **providers**: local node over its socket, and cardano-cli, in the Developer ID build
- **network**: network in every toolbar, on the Build page, and guessed from addresses
- **build**: read every value in any form or from a file, as scm does
- open a transaction from a file, including .json envelopes
- fetch a transaction by id or explorer link, without a provider
- lens app icon
- app icon
- **ui**: Workbench palette with an Appearance setting
- **direct**: Sparkle updates for the Developer ID build
- fill the String Catalogs, with a script to keep them in sync
- watch companion with tracked submissions and co-signing review
- sign with a Keystone through animated QR codes on iOS
- **ui**: import hardware accounts and sign with Ledger or Trezor
- **engine**: sign through Ledger and Trezor with swift-cardano-hw-wallet
- **ui**: sign with stored keys, collect witnesses, submit and track
- **engine**: submit through a provider and check for confirmation
- **core**: signing keys in the Keychain and submission records
- **engine**: sign from a mnemonic or key file and merge witnesses byte for byte
- **ui**: staking, governance and donation in the builder
- **engine**: build certificates, withdrawals, votes and proposals, with deposits
- **core**: recipe certificates, withdrawals, votes, proposals and donation
- **ui**: mint, burn and spend script inputs in the builder
- **engine**: build with minting, script inputs and local ex-unit evaluation
- **core**: recipe minting, script inputs and collateral
- **ui**: build a transaction from a form and use it as the document's
- **engine**: build transactions from a recipe, offline or through a provider
- **core**: keep the builder's recipe in the document
- **ui**: export validation reports and batch-validate a folder on the Mac
- **engine**: validation reports and batch validation
- trace a script's run as a budget timeline
- **ui**: compare script budgets after a what-if change
- **engine**: rerun scripts with changed redeemers or datums
- **ui**: validate from saved chain data, with findings marked in the CBOR
- **engine**: validate offline from saved chain data
- **core**: keep ledger state in the chain snapshot
- **ui**: browse and edit CDDL schemas with go-to-definition
- **engine**: parse CDDL sources with rule uses and custom checks
- **core**: keep a document's own CDDL schema in its package
- **ui**: check the transaction or an item against a schema rule
- **engine**: check CBOR against the era CDDL schemas
- **ui**: edit the transaction's bytes as hex, with undo
- **ui**: explore the transaction's CBOR beside its hex
- **engine**: explore CBOR with byte spans, flags and diagnostic notation
- **engine**: group diff changes by section
- **ui**: export JSON, Markdown and a PDF report
- **engine**: export reports as Markdown and JSON
- **ui**: compare the document with another transaction
- **engine**: compare two transactions
- **ui**: look up inputs and name assets
- **engine**: look up inputs and token names
- **core**: keep spent inputs and token names in the chain snapshot
- **ui**: verify anchors from certificates, votes and proposals
- **engine**: verify governance anchors against their hash
- **ui**: fetch, drop, share and set the network of a transaction
- **engine**: fetch a transaction by id across networks
- **ui**: add the inputs, body, scripts and metadata sections
- **engine**: inspect outputs, scripts, datums, metadata and validity
- scaffold the Tx Workshop app

### Fix

- **ui**: indent nested data tree fields on iOS and visionOS
- **ui**: keep ada amounts on one line
- **deps**: txvalidator 0.4.2 for withdrawals from bech32 and script accounts
- **ui**: refresh Validate and Sign when chain data arrives
- **release**: a rising build number for Sparkle
- **app**: declare supported interface orientations
- **ui**: use a download icon for fetch by ID
- **providers**: say when cardano-node is not answering at its socket
- open dropped transaction files by their content, such as .json envelopes
- **ui**: visionOS hex glass and settings
- clear build warnings
- **ui**: keep visionOS glass; sync strings
- **ui**: launch screen, sheet close buttons and iPhone loading
- **ui**: iPad selection, hex width and appearance
- **a11y**: contrast, VoiceOver, touch targets and compact layouts
- **engine**: tell hardware wallets when the body tags its sets
- **engine**: validate with only the UTxOs the transaction uses
- **engine**: require swift-cddl 0.2.2 for deeply nested annotated trees
- **engine**: require swift-cardano-core 0.8.2 for deeply nested datums
- **ui**: address Phase 2 review findings
- **engine**: leave inputs unresolved when only names were looked up
- **engine**: use Endpoint.preprod now that it points at the live server
- **engine**: use the live testnet token registry for preprod
- **ui**: hide the notes field's label on macOS

### Refactor

- **overview**: leave the network to the toolbar; suggest only on a mismatch
- **build**: leave the network to the toolbar; suggest only on a mismatch
- drop the watchOS companion
- **engine**: inspect scripts on the calling thread
