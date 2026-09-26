import SwiftUI
import TxWorkshopCore

/// Assets minted or burned under one policy.
struct MintDraftSection: View {
    @Binding var mint: MintDraft
    let onRemove: () -> Void

    var body: some View {
        Section {
            ScriptDraftEditor(script: $mint.script)
            ForEach($mint.assets) { $asset in
                HStack {
                    TextField(text: $asset.assetNameHex) { Text("Asset name (hex)", bundle: #bundle) }
                        .font(TWFont.bytesSmall)
                    TextField(value: $asset.quantity, format: .number) { Text("Quantity", bundle: #bundle) }
                        .font(TWFont.figure)
                        .frame(maxWidth: 140)
                    Button {
                        mint.assets.removeAll { $0.id == asset.id }
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
                mint.assets.append(AssetDraft())
            } label: {
                Text("Add Asset", bundle: #bundle)
            }
            .buttonStyle(.borderless)
            if case .native = mint.script {} else {
                TextField(text: $mint.redeemer) {
                    Text("Redeemer (Plutus data CBOR hex)", bundle: #bundle)
                }
                .font(TWFont.bytesSmall)
                .autocorrectionDisabled()
            }
        } header: {
            RemovableHeader(title: Text("Mint or burn", bundle: #bundle), onRemove: onRemove)
        } footer: {
            Text("Negative quantities burn. The policy id comes from the script.", bundle: #bundle)
        }
    }
}

/// A script-locked UTxO to spend.
struct ScriptInputSection: View {
    @Binding var input: ScriptInputDraft
    let onRemove: () -> Void
    @State private var hasScript = false
    @State private var script = ScriptDraft.plutus(version: 3, cborHex: "")

    var body: some View {
        Section {
            TextField(text: $input.input) {
                Text("UTxO (transaction id#index)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            Toggle(isOn: $hasScript) {
                Text("Give the script here", bundle: #bundle)
            }
            if hasScript {
                ScriptDraftEditor(script: $script)
            }
            TextField(text: $input.datum) {
                Text("Datum (CBOR hex; only for a datum hash)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            TextField(text: $input.redeemer) {
                Text("Redeemer (Plutus data CBOR hex)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
        } header: {
            RemovableHeader(title: Text("Script input", bundle: #bundle), onRemove: onRemove)
        } footer: {
            Text("Leave the script out when a reference script on the UTxO or a reference input carries it.", bundle: #bundle)
        }
        .onAppear {
            hasScript = input.script != nil
            if let given = input.script { script = given }
        }
        .onChange(of: hasScript) { input.script = hasScript ? script : nil }
        .onChange(of: script) { if hasScript { input.script = script } }
    }
}

/// A section header with a Remove button.
struct RemovableHeader: View {
    let title: Text
    let onRemove: () -> Void

    var body: some View {
        HStack {
            title
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Text("Remove", bundle: #bundle)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}
