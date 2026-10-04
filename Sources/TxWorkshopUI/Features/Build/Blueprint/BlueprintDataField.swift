import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// A datum or redeemer: typed in as Plutus data, or filled in through a form
/// made from a CIP-57 blueprint. The form keeps the draft's text set to the
/// CBOR it makes, so the recipe builds as it always has.
struct BlueprintDataField: View {
    let role: BlueprintRole
    @Binding var text: String
    @Binding var form: BlueprintForm?
    /// The document's blueprints; one chosen from the library is copied in.
    @Binding var blueprints: [StoredBlueprint]
    /// The script the value is for, to find its validator by hash.
    let scriptHash: String?
    /// `spend`, `mint` …, to prefer that validator of a script.
    let purpose: String?
    let label: Text
    let prompt: Text
    var required = true
    @Environment(BlueprintLibrary.self) private var library
    @State private var isImporting = false
    @State private var importProblem: String?

    private var everyBlueprint: [StoredBlueprint] {
        blueprints + library.blueprints.filter { kept in !blueprints.contains { $0.id == kept.id } }
    }

    private var choice: BlueprintChoice? {
        form.flatMap { BlueprintCatalog.choice(for: $0, in: blueprints) }
    }

    var body: some View {
        HStack {
            label
            Spacer()
            blueprintMenu
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { importBlueprint(url) }
        }
        .onChange(of: scriptHash, initial: true) { attachMatching() }
        if let form, let choice, let argument = role.argument(of: choice.validator) {
            Text(verbatim: "\(choice.blueprint.typeName(argument.schema) ?? role.path) · \(choice.validator.title)")
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            BlueprintValueEditor(
                blueprint: choice.blueprint, schema: argument.schema, value: formValue, path: role.path,
                label: choice.blueprint.typeName(argument.schema) ?? role.path,
                problems: Dictionary(problems(form).map { ($0.path, $0.message) }, uniquingKeysWith: { first, _ in first })
            )
        } else {
            if form != nil {
                TWErrorText(String(localized: "This form's blueprint is no longer in the document. Choose it again, or enter the data as Raw.", bundle: #bundle))
            }
            ValueField(kind: .plutusData, text: $text, prompt: prompt)
        }
        if let importProblem { TWErrorText(importProblem) }
    }

    // MARK: - Choosing a blueprint

    private var blueprintMenu: some View {
        let matching = scriptHash.map { BlueprintCatalog.choices(everyBlueprint, scriptHash: $0, role: role, purpose: purpose) } ?? []
        let others = BlueprintCatalog.choices(everyBlueprint, role: role, purpose: purpose).filter { other in !matching.contains { $0.id == other.id } }
        return Menu {
            if !matching.isEmpty {
                Section {
                    ForEach(matching) { choice in choiceButton(choice) }
                } header: {
                    Text("For this script", bundle: #bundle)
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { choice in choiceButton(choice) }
                } header: {
                    Text("Other blueprints", bundle: #bundle)
                }
            }
            Button {
                isImporting = true
            } label: {
                Label {
                    Text("Import plutus.json…", bundle: #bundle)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            if form != nil {
                Divider()
                Button {
                    form = nil
                } label: {
                    Label {
                        Text("Enter as Raw Data", bundle: #bundle)
                    } icon: {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
        } label: {
            Label {
                Text(form == nil ? String(localized: "Raw", bundle: #bundle) : String(localized: "Form", bundle: #bundle))
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(Text("Blueprint", bundle: #bundle))
        .accessibilityIdentifier("blueprintMenu-\(role.path)")
    }

    private func choiceButton(_ choice: BlueprintChoice) -> some View {
        Button {
            use(choice)
        } label: {
            let type = role.argument(of: choice.validator).flatMap { choice.blueprint.typeName($0.schema) }
            Text(verbatim: [type, choice.validator.title].compactMap { $0 }.joined(separator: " · "))
        }
    }

    /// Fills the form from `choice`: from the current data when it fits the
    /// type, or empty.
    private func use(_ choice: BlueprintChoice) {
        guard let argument = role.argument(of: choice.validator) else { return }
        if !blueprints.contains(where: { $0.id == choice.stored.id }) { blueprints.append(choice.stored) }
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = choice.blueprint.emptyValue(for: argument.schema)
        if !current.isEmpty, let hex = try? ValueReader.read(.plutusData, text: current, network: nil).value,
            let decoded = try? choice.blueprint.decode(cborHex: hex, as: argument.schema, path: role.path) {
            value = decoded
        }
        form = BlueprintForm(blueprint: choice.stored.id, validator: choice.validator.title, value: value)
        apply(value)
    }

    /// A field left empty whose script has a known validator starts as its form.
    private func attachMatching() {
        guard form == nil, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let scriptHash,
            let match = BlueprintCatalog.choices(everyBlueprint, scriptHash: scriptHash, role: role, purpose: purpose).first
        else { return }
        use(match)
    }

    private func importBlueprint(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let stored = try BlueprintImport.read(url)
            library.add(stored)
            if !blueprints.contains(where: { $0.id == stored.id }) { blueprints.append(stored) }
            importProblem = nil
            let choices = BlueprintCatalog.choices([stored], role: role, purpose: purpose)
            let matching = scriptHash.map { hash in choices.filter { $0.validator.hash == hash } } ?? []
            if let only = matching.first ?? (choices.count == 1 ? choices.first : nil) { use(only) }
        } catch {
            importProblem = "\(url.lastPathComponent): \(error)"
        }
    }

    // MARK: - Keeping the text in step

    private var formValue: Binding<BlueprintValue> {
        Binding { form?.value ?? .data("") } set: { value in
            form?.value = value
            apply(value)
        }
    }

    private func problems(_ form: BlueprintForm) -> [BlueprintProblem] {
        BlueprintCatalog.problems(form, role: role, in: blueprints)
    }

    /// Sets the draft's text to the form's CBOR, or empties it while the form
    /// has problems, so a stale value is never built.
    private func apply(_ value: BlueprintValue) {
        guard let form, let choice = BlueprintCatalog.choice(for: form, in: blueprints),
            let argument = role.argument(of: choice.validator)
        else { return }
        text = (try? choice.blueprint.cborHex(value, as: argument.schema, path: role.path)) ?? ""
    }
}

/// Reading a `plutus.json` file the person chose.
enum BlueprintImport {
    static func read(_ url: URL) throws -> StoredBlueprint {
        let data = try Data(contentsOf: url)
        _ = try Blueprint(json: data)
        guard let json = String(data: data, encoding: .utf8) else { throw BlueprintError.notABlueprint("The file is not UTF-8 text.") }
        return StoredBlueprint(json: json)
    }
}
