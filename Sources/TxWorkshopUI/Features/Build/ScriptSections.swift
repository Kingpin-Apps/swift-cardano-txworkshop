import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Assets minted or burned under one policy.
struct MintDraftSection: View {
    @Binding var mint: MintDraft
    @Binding var blueprints: [StoredBlueprint]
    let onRemove: () -> Void

    var body: some View {
        Section {
            ScriptDraftEditor(script: $mint.script, blueprints: $blueprints, purpose: "mint")
            ForEach($mint.assets) { $asset in
                AssetDraftRow(asset: $asset, showsPolicy: false) {
                    mint.assets.removeAll { $0.id == asset.id }
                }
            }
            Button {
                mint.assets.append(AssetDraft())
            } label: {
                Text("Add Asset", bundle: #bundle)
            }
            .buttonStyle(.borderless)
            if case .native = mint.script {} else {
                BlueprintDataField(
                    role: .redeemer, text: $mint.redeemer, form: $mint.redeemerForm, blueprints: $blueprints,
                    scriptHash: BlueprintCatalog.scriptHash(mint.script), purpose: "mint",
                    label: Text("Redeemer", bundle: #bundle), prompt: Text("Redeemer (CBOR hex, JSON or a file)", bundle: #bundle)
                )
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
    @Binding var blueprints: [StoredBlueprint]
    let onRemove: () -> Void
    @State private var hasScript = false
    @State private var script = ScriptDraft.plutus(version: 3, cborHex: "")

    var body: some View {
        Section {
            ValueField(kind: .transactionInput, text: $input.input, prompt: Text("UTxO (transaction id#index)", bundle: #bundle))
            Toggle(isOn: $hasScript) {
                Text("Give the script here", bundle: #bundle)
            }
            if hasScript {
                ScriptDraftEditor(script: $script, blueprints: $blueprints, purpose: "spend")
            }
            BlueprintDataField(
                role: .datum, text: $input.datum, form: $input.datumForm, blueprints: $blueprints,
                scriptHash: BlueprintCatalog.scriptHash(input.script), purpose: "spend",
                label: Text("Datum", bundle: #bundle), prompt: Text("Datum (only for a datum hash; CBOR hex, JSON or a file)", bundle: #bundle)
            )
            BlueprintDataField(
                role: .redeemer, text: $input.redeemer, form: $input.redeemerForm, blueprints: $blueprints,
                scriptHash: BlueprintCatalog.scriptHash(input.script), purpose: "spend",
                label: Text("Redeemer", bundle: #bundle), prompt: Text("Redeemer (CBOR hex, JSON or a file)", bundle: #bundle)
            )
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
                    .twHitTarget()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}
