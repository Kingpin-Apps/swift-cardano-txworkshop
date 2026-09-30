import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One input, and what it spends once it has been looked up.
struct InputRow: View {
    let input: InputDetail

    var body: some View {
        if let output = input.output {
            DisclosureGroup {
                TWFieldRow(LocalizedStringResource("Address", bundle: #bundle)) {
                    HStack(alignment: .firstTextBaseline) {
                        TWBytesText(output.address.text, font: TWFont.bytesSmall)
                        ExplorerLinkButton(item: ExplorerItem.address(output.address.text))
                    }
                }
                ForEach(output.assets) { asset in
                    AssetRow(asset: asset)
                }
                if output.datum != nil {
                    TWFieldRow(LocalizedStringResource("Datum", bundle: #bundle)) {
                        Text(output.datum.isInline ? "Inline" : "By hash", bundle: #bundle)
                    }
                }
            } label: {
                summary(output)
            }
        } else {
            summary(nil)
        }
    }

    private func summary(_ output: OutputDetail?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                TWBytesText(input.id, font: TWFont.bytesSmall)
                InputStatusLabel(status: input.status)
            }
            Spacer()
            ExplorerLinkButton(item: ExplorerItem.transaction(input.transactionID))
            if let output {
                // The amount stays on one line; the id gives way first.
                Text(verbatim: TWFormat.ada(output.lovelace))
                    .font(TWFont.figure)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
            }
        }
    }
}

private struct InputStatusLabel: View {
    let status: InputDetail.Status

    var body: some View {
        switch status {
        case .unresolved:
            EmptyView()
        case .unspent:
            Label {
                Text("Unspent", bundle: #bundle)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.caption)
            .labelStyle(.status(TWColor.success))
        case .spent:
            Label {
                Text("Already spent", bundle: #bundle)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .font(.caption)
            .labelStyle(.status(TWColor.failure))
        case .notFound:
            Label {
                Text("Not found, or already spent", bundle: #bundle)
            } icon: {
                Image(systemName: "questionmark.circle")
            }
            .font(.caption)
            .labelStyle(.status(TWColor.warning))
        }
    }
}

extension Optional where Wrapped == DatumReference {
    fileprivate var isInline: Bool {
        if case .inline? = self { return true }
        return false
    }
}
