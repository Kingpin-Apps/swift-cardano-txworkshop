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

    enum DatumKind: Hashable { case none, hash, inline }

    var body: some View {
        Section {
            ValueField(kind: .address, text: $output.address, prompt: Text("Address, hex or payment key", bundle: #bundle))
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
            } label: {
                Text("Datum", bundle: #bundle)
            }
            if datumKind == .hash {
                TextField(text: $datumHex) {
                    Text("Hash (hex)", bundle: #bundle)
                }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            } else if datumKind == .inline {
                BlueprintDataField(
                    role: .datum, text: $datumHex, form: $output.datumForm, blueprints: $blueprints,
                    scriptHash: BlueprintCatalog.scriptHash(address: output.address, network: network), purpose: "spend", applied: applied,
                    label: Text("Inline datum", bundle: #bundle), prompt: Text("Plutus data (CBOR hex, JSON or a file)", bundle: #bundle)
                )
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
        if datumKind != .inline { output.datumForm = nil }
        output.datum = switch datumKind {
        case .none: .none
        case .hash: .hash(datumHex.filter { !$0.isWhitespace })
        // Read in any form when built: CBOR hex, JSON or an integer.
        case .inline: .inline(datumHex.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
