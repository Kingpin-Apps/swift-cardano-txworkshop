import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The rules the selected rule uses and is used by, each a link to its
/// definition.
struct RuleLinks: View {
    let rule: CDDLSource.Rule
    let usedBy: [CDDLSource.Rule]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Text(verbatim: rule.name)
                .font(TWFont.sectionTitle)
            links(Text("Uses", bundle: #bundle), names: rule.uses)
            links(Text("Used by", bundle: #bundle), names: usedBy.map(\.name))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TWSpacing.s)
    }

    @ViewBuilder private func links(_ title: Text, names: [String]) -> some View {
        if !names.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                title
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(names, id: \.self) { name in
                            Button {
                                onOpen(name)
                            } label: {
                                Text(verbatim: name)
                                    .font(TWFont.bytesSmall)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}
