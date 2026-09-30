# Xcode Security Settings

Security build settings decisions for Cardano TxWorkshop. Settings live in `project.yml`
(XcodeGen) and the targets' `.entitlements` files.

## Enabled settings

- `ENABLE_ENHANCED_SECURITY` to `YES` at the project level (2026-09-26). Brings stack
  zero-initialisation, typed-allocator support and the security compiler warnings.
- Hardened-process entitlements on `TxWorkshop` (iOS, macOS, visionOS) and
  `TxWorkshopDirect` (macOS):
  - `com.apple.security.hardened-process`
  - `com.apple.security.hardened-process.enhanced-security-version-string` = `2`
  - `com.apple.security.hardened-process.hardened-heap`
  - `com.apple.security.hardened-process.dyld-ro`
  - `com.apple.security.hardened-process.platform-restrictions-string` = `2`
- Hardware memory tagging in soft mode on the same targets:
  - `com.apple.security.hardened-process.checked-allocations`
  - `com.apple.security.hardened-process.checked-allocations.soft-mode`

  Soft mode records simulated crash reports instead of terminating. Review and fix them on
  A19+ iPhone/iPad, M5+ Mac or Vision Pro hardware before turning soft mode off.

## Disabled settings

- `ENABLE_POINTER_AUTHENTICATION` to `NO` on `TxWorkshop` and `TxWorkshopDirect`: the stack links prebuilt binaries with no `arm64e` slice, so an `arm64e`
  build cannot link. Re-checked 2026-09-30; none of them ships `arm64e` yet:
  - libsodium (swift-nacl `Clibsodium.xcframework`)
  - BLST (swift-blst `CBlst.xcframework`)
  - the Keystone SDK's `URRegistryFFI.xcframework` (iOS only)
  - Sparkle (`Sparkle.xcframework`, Developer ID build only)

  Lift this once they all ship `arm64e`; swift-nacl and swift-blst are Kingpin packages, so those two can be
  rebuilt with it.
- `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` to `NO` on the same targets: the
  `arm64e.x1` slice is a pointer-authentication slice and cannot be built without it.

## Deferred

- Checked pointer arithmetic
  (`com.apple.security.hardened-process.checked-allocations.enforce-checked-pointer-arithmetic-overflow`):
  needs the `arm64e.x1` slice, so it waits on pointer authentication.
- Hardware memory tagging enforcement (turning soft mode off): after the simulated crash
  reports from soft mode have been reviewed on supported hardware.
- Compiler, static analyzer and clang-tidy warning groups: they apply to C-family code, and
  the app is Swift only. Revisit if C, C++ or Objective-C is added.

## Audit history

- 2026-09-26: first audit; the settings above were applied.
- 2026-09-30: re-audited before release. Everything in scope was already configured; no
  changes. The two app targets are Swift only, so the C-family warning groups still don't
  apply.
