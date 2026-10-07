## v0.1.8 (2026-10-07)

### Feat

- **app**: TxWorkshop under the icon and the Utilities category; Direct debug builds sign with the team
- **build**: the hardware wallet option beside Build, and say why a build cannot sync

### Fix

- **keychain**: never lose an API key moving it to or from iCloud Keychain

## v0.1.7 (2026-10-07)

### Feat

- **cip21**: rebuild for hardware wallets with the fee worked out again, and build for them from the start

### Fix

- **validate**: fail a transaction whose fee will be too small once signed

## v0.1.6 (2026-10-06)

### Feat

- **shell**: whole-transaction buttons on every section's toolbar
- **build**: start with no output, for certificate-only transactions
- **overview**: Export & Share menu with text envelope and CBOR, and Replace Transaction
- **inspect**: every field of each certificate
- **build**: choose which UTxOs to spend, and remove a document's blueprints
- **sign**: remove a witness once added

### Fix

- **build**: read a pool.json by its cold key path, and clear stale file errors

## v0.1.5 (2026-10-06)

### Feat

- **direct**: iCloud sync in the Mac download, with a Developer ID profile

## v0.1.4 (2026-10-05)

### Feat

- **chain**: Chain Data screen, and fetch from where it is needed
- **validate**: CIP-21 hardware wallet check and rewrite
- **debug**: named script context, edit and rerun, debug failure
- **debug**: script debugger screen on every platform
- **debug**: step through a redeemer's script run
- **blueprint**: make scripts from validators that take parameters
- **blueprint**: show inspected datums and redeemers by their blueprint types
- **blueprint**: fill datums and redeemers through blueprint forms
- **blueprint**: read CIP-57 blueprints and encode and decode their types
- **build**: construct every Conway certificate, with pool registration from pool.json or chain

### Perf

- **debug**: one redraw per step, and a lazy variables list
- **debug**: drop the timeline slider's per-step tick marks

## v0.1.3 (2026-10-03)

### Feat

- **build**: check the recipe field by field and name each mistake
- **settings**: a switch to sync settings with iCloud, in Settings and the provider set-up
- **settings**: sync providers, their API keys and the explorer through iCloud
- **providers**: a first-run guide to choosing a chain data provider

### Fix

- **settings**: iCloud sync is off until turned on, and untouched until then
- **mac**: autosave within 2 seconds, so iCloud Drive documents rarely conflict

## v0.1.2 (2026-09-30)

### Fix

- the apps carry their real version and build number, not 1.0 (1)

## v0.1.1 (2026-09-30)

### Fix

- **release**: publish the Mac app as Cardano TxWorkshop.app; the cask depends on macOS

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
