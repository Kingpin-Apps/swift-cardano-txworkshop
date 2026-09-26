import SwiftUI
import TxWorkshopCore

struct ProviderRow: View {
    let provider: ProviderConfiguration
    let isSelected: Bool
    let select: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack {
            Button(action: select) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    VStack(alignment: .leading) {
                        Text(verbatim: provider.name)
                        Text(provider.kind.name)
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button(action: edit) {
                Label {
                    Text("Edit", bundle: #bundle)
                } icon: {
                    Image(systemName: "pencil")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }
}
