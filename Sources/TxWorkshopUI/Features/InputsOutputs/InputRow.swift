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
                    TWBytesText(output.address.text, font: TWFont.bytesSmall)
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
            if let output {
                Text(verbatim: TWFormat.ada(output.lovelace))
                    .font(TWFont.figure)
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
            .foregroundStyle(TWColor.success)
        case .spent:
            Label {
                Text("Already spent", bundle: #bundle)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .font(.caption)
            .foregroundStyle(TWColor.failure)
        case .notFound:
            Label {
                Text("Not found, or already spent", bundle: #bundle)
            } icon: {
                Image(systemName: "questionmark.circle")
            }
            .font(.caption)
            .foregroundStyle(TWColor.warning)
        }
    }
}

extension Optional where Wrapped == DatumReference {
    fileprivate var isInline: Bool {
        if case .inline? = self { return true }
        return false
    }
}
