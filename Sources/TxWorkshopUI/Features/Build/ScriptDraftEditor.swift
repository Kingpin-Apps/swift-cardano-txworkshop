import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Chooses and enters a script: native JSON, Plutus CBOR hex, or a
/// reference script on a UTxO. A script file (a `.plutus` envelope, native
/// script JSON or raw CBOR) sets both the kind and the script.
struct ScriptDraftEditor: View {
    @Binding var script: ScriptDraft
    /// The parameters, when the script is a blueprint validator that takes them.
    @Binding var parameters: BlueprintParameters?
    /// The document's blueprints, whose validators can be picked as the script.
    @Binding var blueprints: [StoredBlueprint]
    /// `mint` or `spend`: which validators to offer.
    let purpose: String
    @Environment(BlueprintLibrary.self) private var library
    @State private var kind = Kind.native
    @State private var text = ""
    @State private var isImporting = false
    @State private var fileProblem: String?
    @State private var showsBlueprintChoices = false

    enum Kind: Hashable { case native, plutusV1, plutusV2, plutusV3, reference }

    var body: some View {
        Group {
            controls
            if parameters != nil {
                BlueprintParametersEditor(parameters: $parameters, script: $script, blueprints: blueprints, purpose: purpose)
            }
        }
        .onAppear(perform: load)
        // A script set from outside, e.g. picked from a blueprint.
        .onChange(of: script) { if script != current { load() } }
        .onChange(of: kind) { sync() }
        .onChange(of: text) { sync() }
    }

    private func load() {
        switch script {
        case .native(let json): kind = .native; text = json
        case .plutus(let version, let hex): kind = [1: .plutusV1, 2: .plutusV2, 3: .plutusV3][version] ?? .plutusV3; text = hex
        case .reference(let input): kind = .reference; text = input
        }
    }

    /// Validators of the right purpose from the document's and the library's
    /// blueprints. Those that take parameters are listed but not offered yet.
    private var blueprintValidators: [(stored: StoredBlueprint, validator: Blueprint.Validator)] {
        let every = blueprints + library.blueprints.filter { kept in !blueprints.contains { $0.id == kept.id } }
        return every.flatMap { stored -> [(stored: StoredBlueprint, validator: Blueprint.Validator)] in
            guard let blueprint = try? BlueprintCatalog.blueprint(stored) else { return [] }
            return blueprint.validators
                .filter { $0.purpose == purpose && !($0.compiledCode ?? "").isEmpty }
                .map { (stored: stored, validator: $0) }
        }
    }

    /// Uses a validator as the script. One that takes parameters starts its
    /// parameter form; the script is filled in once they are.
    private func choose(_ stored: StoredBlueprint, _ validator: Blueprint.Validator) {
        if !blueprints.contains(where: { $0.id == stored.id }) { blueprints.append(stored) }
        if validator.parameters.isEmpty {
            parameters = nil
            script = .plutus(version: validator.plutusVersion, cborHex: validator.compiledCode ?? "")
        } else if let blueprint = try? BlueprintCatalog.blueprint(stored) {
            parameters = BlueprintParameters(
                blueprint: stored.id, validator: validator.title,
                values: validator.parameters.map { blueprint.emptyValue(for: $0.schema) }
            )
            script = .plutus(version: validator.plutusVersion, cborHex: "")
        }
    }

    /// Offers the blueprints' validators as the script, in a dialog: a menu in
    /// a form row would not open, or stretched the row.
    @ViewBuilder private var blueprintMenu: some View {
        let validators = blueprintValidators
        if !validators.isEmpty {
            Button {
                showsBlueprintChoices = true
            } label: {
                Label {
                    Text("From Blueprint", bundle: #bundle)
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            .buttonStyle(.borderless)
            .confirmationDialog(Text("Use a Validator as the Script", bundle: #bundle), isPresented: $showsBlueprintChoices, titleVisibility: .visible) {
                ForEach(validators, id: \.validator.id) { item in
                    Button {
                        choose(item.stored, item.validator)
                    } label: {
                        if item.validator.parameters.isEmpty {
                            Text(verbatim: item.validator.title)
                        } else {
                            Text(String(localized: "\(item.validator.title) (takes parameters)", bundle: #bundle))
                        }
                    }
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: #bundle) }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        Picker(selection: $kind) {
            Text("Native script", bundle: #bundle).tag(Kind.native)
            Text("Plutus V1", bundle: #bundle).tag(Kind.plutusV1)
            Text("Plutus V2", bundle: #bundle).tag(Kind.plutusV2)
            Text("Plutus V3", bundle: #bundle).tag(Kind.plutusV3)
            Text("Reference script", bundle: #bundle).tag(Kind.reference)
        } label: {
            Text("Script", bundle: #bundle)
        }
        if kind == .reference {
            ValueField(kind: .transactionInput, text: $text, prompt: Text("UTxO carrying it (transaction id#index)", bundle: #bundle))
        } else {
            TextEditor(text: $text)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 120)
                .autocorrectionDisabled()
                .accessibilityLabel(kind == .native ? Text("Native script JSON", bundle: #bundle) : Text("Script CBOR hex", bundle: #bundle))
            blueprintMenu
            HStack {
                status
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label {
                        Text("Choose Script File…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.plus")
                    }
                }
                .buttonStyle(.borderless)
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result { load(url) }
            }
        }
    }

    private var valueKind: ValueKind {
        switch kind {
        case .native: .nativeScript
        case .plutusV1: .plutusScript(version: 1)
        case .plutusV2: .plutusScript(version: 2)
        case .plutusV3: .plutusScript(version: 3)
        case .reference: .transactionInput
        }
    }

    @ViewBuilder private var status: some View {
        let message: (String, Bool)? = if let fileProblem {
            (fileProblem, false)
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nil
        } else {
            switch Result(catching: { try ValueReader.read(valueKind, text: text, network: nil) }) {
            case .success(let read): (read.form, true)
            case .failure(let error): (String(describing: error), false)
            }
        }
        if let (text, ok) = message {
            Label {
                Text(verbatim: text)
            } icon: {
                Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle")
            }
            .labelStyle(.status(ok ? TWColor.success : TWColor.warning))
            .font(.caption)
            .foregroundStyle(TWColor.secondaryText)
        }
    }

    /// Reads a script file, taking its kind from what it is.
    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        fileProblem = nil
        guard let data = try? Data(contentsOf: url) else {
            fileProblem = "\(url.lastPathComponent) could not be read."
            return
        }
        let name = url.lastPathComponent
        if let json = String(data: data, encoding: .utf8), let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            // A blueprint: keep it, and take its only validator for this purpose.
            if object["preamble"] != nil, object["validators"] != nil {
                do {
                    _ = try Blueprint(json: data)
                    let stored = StoredBlueprint(json: json)
                    library.add(stored)
                    if !blueprints.contains(where: { $0.id == stored.id }) { blueprints.append(stored) }
                    let offered = blueprintValidators.filter { $0.stored.id == stored.id && $0.validator.parameters.isEmpty }
                    if offered.count == 1, let only = offered.first {
                        script = .plutus(version: only.validator.plutusVersion, cborHex: only.validator.compiledCode ?? "")
                    } else {
                        fileProblem = String(localized: "\(name) is a blueprint: choose its validator from From Blueprint.", bundle: #bundle)
                    }
                } catch {
                    fileProblem = "\(name): \(error)"
                }
                return
            }
            if let type = object["type"] as? String, let hex = object["cborHex"] as? String, type.hasPrefix("PlutusScriptV") {
                switch type {
                case "PlutusScriptV1": kind = .plutusV1
                case "PlutusScriptV2": kind = .plutusV2
                case "PlutusScriptV3": kind = .plutusV3
                default: fileProblem = "\(name) is a \(type), which is not supported."; return
                }
                text = hex
            } else {
                kind = .native
                text = json
            }
            return
        }
        // Raw CBOR: a Plutus script of the version chosen.
        if kind == .native { kind = .plutusV3 }
        text = data.map { String(format: "%02x", $0) }.joined()
    }

    private func sync() {
        // A script typed or chosen here is no longer the blueprint's.
        if script != current {
            script = current
            parameters = nil
        }
    }

    /// The script the editor's kind and text make.
    private var current: ScriptDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch kind {
        case .native: .native(json: text)
        case .plutusV1: .plutus(version: 1, cborHex: trimmed.filter { !$0.isWhitespace })
        case .plutusV2: .plutus(version: 2, cborHex: trimmed.filter { !$0.isWhitespace })
        case .plutusV3: .plutus(version: 3, cborHex: trimmed.filter { !$0.isWhitespace })
        case .reference: .reference(input: trimmed)
        }
    }
}
