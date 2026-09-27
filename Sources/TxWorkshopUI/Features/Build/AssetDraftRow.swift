import SwiftUI
import TxWorkshopCore

/// An asset's name, quantity and, for outputs, policy id. Side by side when
/// there is room; stacked on a phone or at large text sizes.
struct AssetDraftRow: View {
    @Binding var asset: AssetDraft
    /// Mints take the policy id from their script.
    var showsPolicy = true
    let onRemove: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isStacked: Bool { sizeClass == .compact || typeSize.isAccessibilitySize }

    var body: some View {
        let layout = isStacked ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
        HStack(alignment: .center) {
            layout {
                if showsPolicy {
                    TextField(text: $asset.policyID) { Text("Policy id", bundle: #bundle) }
                        .font(TWFont.bytesSmall)
                }
                TextField(text: $asset.assetNameHex) {
                    showsPolicy ? Text("Name (hex)", bundle: #bundle) : Text("Asset name (hex)", bundle: #bundle)
                }
                .font(TWFont.bytesSmall)
                .frame(maxWidth: isStacked || !showsPolicy ? .infinity : 160)
                TextField(value: $asset.quantity, format: .number) { Text("Quantity", bundle: #bundle) }
                    .font(TWFont.figure)
                    .frame(maxWidth: isStacked ? .infinity : showsPolicy ? 110 : 140)
            }
            Button(action: onRemove) {
                Label {
                    Text("Remove Asset", bundle: #bundle)
                } icon: {
                    Image(systemName: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
        }
        .autocorrectionDisabled()
    }
}
