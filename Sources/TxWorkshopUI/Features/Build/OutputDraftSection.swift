import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One output of the recipe: where, how much, which assets, and a datum.
struct OutputDraftSection: View {
    @Binding var output: OutputDraft
    let onRemove: () -> Void
    @State private var datumKind = DatumKind.none
    @State private var datumHex = ""

    enum DatumKind: Hashable { case none, hash, inline }

    var body: some View {
        Section {
            TextField(text: $output.address) {
                Text("Address", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            TextField(value: $output.lovelace, format: .number) {
                Text("Lovelace (empty for the minimum)", bundle: #bundle)
            }
            .font(TWFont.figure)
            if let lovelace = output.lovelace {
                Text(verbatim: TWFormat.ada(lovelace))
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
            ForEach($output.assets) { $asset in
                HStack {
                    TextField(text: $asset.policyID) { Text("Policy id", bundle: #bundle) }
                        .font(TWFont.bytesSmall)
                    TextField(text: $asset.assetNameHex) { Text("Name (hex)", bundle: #bundle) }
                        .font(TWFont.bytesSmall)
                        .frame(maxWidth: 160)
                    TextField(value: $asset.quantity, format: .number) { Text("Quantity", bundle: #bundle) }
                        .font(TWFont.figure)
                        .frame(maxWidth: 110)
                    Button {
                        output.assets.removeAll { $0.id == asset.id }
                    } label: {
                        Label {
                            Text("Remove Asset", bundle: #bundle)
                        } icon: {
                            Image(systemName: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
                .autocorrectionDisabled()
            }
            Button {
                output.assets.append(AssetDraft())
            } label: {
                Text("Add Asset", bundle: #bundle)
            }
            .buttonStyle(.borderless)
            Picker(selection: $datumKind) {
                Text("No datum", bundle: #bundle).tag(DatumKind.none)
                Text("Datum hash", bundle: #bundle).tag(DatumKind.hash)
                Text("Inline datum", bundle: #bundle).tag(DatumKind.inline)
            } label: {
                Text("Datum", bundle: #bundle)
            }
            if datumKind != .none {
                TextField(text: $datumHex) {
                    datumKind == .hash ? Text("Hash (hex)", bundle: #bundle) : Text("Plutus data (CBOR hex)", bundle: #bundle)
                }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            }
        } header: {
            RemovableHeader(title: Text("Output", bundle: #bundle), onRemove: onRemove)
        }
        .onAppear {
            switch output.datum {
            case .none: datumKind = .none
            case .hash(let hex): datumKind = .hash; datumHex = hex
            case .inline(let hex): datumKind = .inline; datumHex = hex
            }
        }
        .onChange(of: datumKind) { syncDatum() }
        .onChange(of: datumHex) { syncDatum() }
    }

    private func syncDatum() {
        let hex = datumHex.filter { !$0.isWhitespace }
        output.datum = switch datumKind {
        case .none: .none
        case .hash: .hash(hex)
        case .inline: .inline(hex)
        }
    }
}
