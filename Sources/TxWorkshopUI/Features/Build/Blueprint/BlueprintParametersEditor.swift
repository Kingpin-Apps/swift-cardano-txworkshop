import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The parameters of a blueprint validator, applied to its code to give the
/// script: its hash and, for a spending validator, its address.
struct BlueprintParametersEditor: View {
    @Binding var parameters: BlueprintParameters?
    @Binding var script: ScriptDraft
    let blueprints: [StoredBlueprint]
    let purpose: String
    @Environment(\.documentNetwork) private var network

    private var choice: BlueprintChoice? {
        parameters.flatMap { BlueprintCatalog.choice(for: $0, in: blueprints) }
    }

    var body: some View {
        if let parameters, let choice {
            let problems = choice.blueprint.parameterProblems(parameters.values, for: choice.validator)
            let byPath = Dictionary(problems.map { ($0.path, $0.message) }, uniquingKeysWith: { first, _ in first })
            Text(String(localized: "Parameters of \(choice.validator.title)", bundle: #bundle))
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            ForEach(choice.validator.parameters.indices, id: \.self) { index in
                let parameter = choice.validator.parameters[index]
                BlueprintValueEditor(
                    blueprint: choice.blueprint, schema: parameter.schema, value: value(index), path: "parameters.\(parameter.title ?? "\(index)")",
                    label: parameter.title ?? "\(index)", problems: byPath
                )
            }
            if problems.isEmpty, let applied = try? choice.blueprint.apply(parameters.values, to: choice.validator) {
                LabeledContent {
                    Text(verbatim: applied.hash)
                        .font(TWFont.bytesSmall)
                        .textSelection(.enabled)
                } label: {
                    Text("Script hash", bundle: #bundle)
                }
                if purpose == "spend", let address = scriptAddress(applied.hash) {
                    LabeledContent {
                        Text(verbatim: address)
                            .font(TWFont.bytesSmall)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } label: {
                        Text("Script address", bundle: #bundle)
                    }
                }
            } else {
                Text("The script is made once every parameter is filled in.", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
        } else if parameters != nil {
            TWErrorText(String(localized: "These parameters' blueprint is no longer in the document. Choose the validator again.", bundle: #bundle))
        }
    }

    private func value(_ index: Int) -> Binding<BlueprintValue> {
        Binding {
            parameters?.values.indices.contains(index) == true ? parameters!.values[index] : .data("")
        } set: { value in
            guard var updated = parameters, updated.values.indices.contains(index) else { return }
            updated.values[index] = value
            parameters = updated
            apply(updated)
        }
    }

    /// Fills in the script from the parameters, or empties it while they have problems.
    private func apply(_ parameters: BlueprintParameters) {
        guard let choice = BlueprintCatalog.choice(for: parameters, in: blueprints) else { return }
        let applied = try? choice.blueprint.apply(parameters.values, to: choice.validator)
        script = .plutus(version: choice.validator.plutusVersion, cborHex: applied?.compiledCode ?? "")
    }

    /// The enterprise address the script locks, on the document's network.
    private func scriptAddress(_ hash: String) -> String? {
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hash) else { return nil }
        return BlueprintCatalog.scriptAddress(hash: bytes, network: network)
    }
}
