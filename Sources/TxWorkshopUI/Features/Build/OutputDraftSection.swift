import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One output of the recipe: where, how much, which assets, and a datum.
struct OutputDraftSection: View {
    @Binding var output: OutputDraft
    @Binding var blueprints: [StoredBlueprint]
    var applied: [String: BlueprintParameters] = [:]
    let onRemove: () -> Void
    @Environment(\.documentNetwork) private var network
    @State private var datumKind = DatumKind.none
    @State private var datumHex = ""

    enum DatumKind: Hashable { case none, hash, hashed, inline }

    var body: some View {
        Section {
            ValueField(kind: .address, text: $output.address, prompt: Text("Address, hex or payment key", bundle: #bundle))
            TWLabeledField(Text("Lovelace (empty for the minimum)", bundle: #bundle), value: $output.lovelace, format: .number)
            .font(TWFont.figure)
            if let lovelace = output.lovelace {
                Text(verbatim: TWFormat.ada(lovelace))
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
            ForEach($output.assets) { $asset in
                AssetDraftRow(asset: $asset) {
                    output.assets.removeAll { $0.id == asset.id }
                }
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
                Text("Datum by hash, included", bundle: #bundle).tag(DatumKind.hashed)
            } label: {
                Text("Datum", bundle: #bundle)
            }
            if datumKind == .hash {
                TWLabeledField(Text("Hash (hex)", bundle: #bundle), text: $datumHex)
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            } else if datumKind == .inline || datumKind == .hashed {
                BlueprintDataField(
                    role: .datum, text: $datumHex, form: $output.datumForm, blueprints: $blueprints,
                    scriptHash: BlueprintCatalog.scriptHash(address: output.address, network: network), purpose: "spend", applied: applied,
                    label: datumKind == .inline ? Text("Inline datum", bundle: #bundle) : Text("Datum", bundle: #bundle),
                    prompt: Text("Plutus data (CBOR hex, JSON or a file)", bundle: #bundle)
                )
                if datumKind == .hashed {
                    Text("The output carries the datum's hash, and the datum goes in the transaction, where scripts read it.", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
            }
        } header: {
            RemovableHeader(title: Text("Output", bundle: #bundle), onRemove: onRemove)
        }
        .onAppear {
            switch output.datum {
            case .none: datumKind = .none
            case .hash(let hex): datumKind = .hash; datumHex = hex
            case .inline(let hex): datumKind = .inline; datumHex = hex
            case .hashed(let hex): datumKind = .hashed; datumHex = hex
            }
        }
        .onChange(of: datumKind) { syncDatum() }
        .onChange(of: datumHex) { syncDatum() }
    }

    private func syncDatum() {
        if datumKind != .inline && datumKind != .hashed { output.datumForm = nil }
        output.datum = switch datumKind {
        case .none: .none
        case .hash: .hash(datumHex.filter { !$0.isWhitespace })
        // Read in any form when built: CBOR hex, JSON or an integer.
        case .inline: .inline(datumHex.trimmingCharacters(in: .whitespacesAndNewlines))
        case .hashed: .hashed(datumHex.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
