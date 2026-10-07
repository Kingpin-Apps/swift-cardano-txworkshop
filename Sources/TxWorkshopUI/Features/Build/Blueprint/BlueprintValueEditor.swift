import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Form rows for one value of a blueprint type, and, nested below them, its
/// fields, items or entries.
struct BlueprintValueEditor: View {
    let blueprint: Blueprint
    /// The schema as the parent gives it, so a field keeps its own title.
    let schema: BlueprintSchema
    @Binding var value: BlueprintValue
    let path: String
    let label: String
    /// Problems by field path, for the whole form.
    let problems: [String: String]
    var depth = 0
    var onRemove: (() -> Void)?

    private var resolved: BlueprintSchema {
        (try? blueprint.resolve(schema)) ?? BlueprintSchema(kind: .anyData)
    }

    var body: some View {
        Group {
            switch resolved.kind {
            case .integer, .builtin(.integer):
                row { textField(integerText, prompt: "0").font(TWFont.figure) }
            case .bytes, .builtin(.bytes):
                row { textField(bytesText, prompt: String(localized: "Hex", bundle: #bundle)).font(TWFont.bytesSmall) }
            case .builtin(.string):
                row { textField(stringText, prompt: "") }
            case .builtin(.boolean):
                row { Toggle(isOn: booleanValue) { EmptyView() }.labelsHidden() }
            case .builtin(.unit):
                row { Text(verbatim: "()").foregroundStyle(TWColor.secondaryText) }
            case .anyOf(let variants):
                sum(variants.compactMap { try? blueprint.resolve($0) })
            case .constructor(_, let fields):
                header
                children(fields)
            case .tuple(let items):
                header
                children(items)
            case .builtin(.pair(let left, let right)):
                header
                children([left, right])
            case .list(let items, _), .builtin(.list(let items)):
                list(items)
            case .map(let keys, let values, _):
                map(keys, values)
            case .reference, .anyData, .unsupported:
                VStack(alignment: .leading, spacing: TWSpacing.xs) {
                    fieldLabel
                    ValueField(kind: .plutusData, text: dataText, prompt: Text("Plutus data (CBOR hex, JSON or a number)", bundle: #bundle))
                }
                .padding(.leading, indent)
                problem
            }
        }
    }

    // MARK: - Rows

    private var indent: CGFloat { CGFloat(depth) * 14 }

    /// The field's name, with its type beside it when that says more.
    private var fieldLabel: some View {
        HStack(spacing: TWSpacing.xs) {
            Text(verbatim: label)
            if let type = blueprint.typeName(schema), type != label {
                Text(verbatim: type)
                    .font(.caption)
                    .foregroundStyle(TWColor.secondaryText)
            }
        }
    }

    private func row(@ViewBuilder _ control: () -> some View) -> some View {
        Group {
            LabeledContent {
                HStack {
                    control()
                    removeButton
                }
            } label: {
                fieldLabel
            }
            .padding(.leading, indent)
            problem
        }
    }

    /// A row naming a value whose parts follow below it.
    private var header: some View {
        Group {
            HStack {
                fieldLabel
                Spacer()
                removeButton
            }
            .padding(.leading, indent)
            problem
        }
    }

    @ViewBuilder private var removeButton: some View {
        if let onRemove {
            Button(role: .destructive, action: onRemove) {
                Label {
                    Text("Remove", bundle: #bundle)
                } icon: {
                    Image(systemName: "minus.circle")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
        }
    }

    /// A field not filled in yet is left unmarked; the build's checks still list it.
    private var isUnfilled: Bool {
        switch value {
        case .integer(let text), .data(let text), .text(let text): text.trimmingCharacters(in: .whitespaces).isEmpty
        default: false
        }
    }

    @ViewBuilder private var problem: some View {
        if let message = problems[path], !isUnfilled {
            TWErrorText(message)
                .padding(.leading, indent)
        }
    }

    private func textField(_ text: Binding<String>, prompt: String) -> some View {
        TWLabeledField(Text(verbatim: label), text: text, prompt: Text(verbatim: prompt))
        .autocorrectionDisabled()
        .accessibilityIdentifier(path)
        #if os(iOS) || os(visionOS)
        .textInputAutocapitalization(.never)
        #endif
    }

    // MARK: - Sums, lists and maps

    /// A choice of constructors: a switch for a Bool, a picker otherwise, then
    /// the chosen constructor's fields.
    @ViewBuilder private func sum(_ variants: [BlueprintSchema]) -> some View {
        let titles = variants.map { $0.title ?? "" }
        if variants.count == 1, case .constructor(_, let fields) = variants[0].kind {
            header
            children(fields)
        } else if titles == ["False", "True"], variants.allSatisfy(Self.isNullary) {
            row { Toggle(isOn: constructorFlag) { EmptyView() }.labelsHidden() }
        } else {
            row {
                Picker(selection: variantIndex(variants)) {
                    ForEach(variants.indices, id: \.self) { index in
                        Text(verbatim: variants[index].title ?? "#\(index)").tag(index)
                    }
                } label: {
                    Text(verbatim: label)
                }
                .labelsHidden()
                .fixedSize()
            }
            if let chosen = chosenVariant(variants), case .constructor(_, let fields) = chosen.kind {
                children(fields)
            }
        }
    }

    private func children(_ fields: [BlueprintSchema]) -> some View {
        ForEach(fields.indices, id: \.self) { index in
            AnyView(BlueprintValueEditor(
                blueprint: blueprint, schema: fields[index], value: part(index), path: childPath(fields[index], index),
                label: fields[index].title ?? "\(index)", problems: problems, depth: depth + 1
            ))
        }
    }

    @ViewBuilder private func list(_ items: BlueprintSchema) -> some View {
        let elements = listElements
        HStack {
            fieldLabel
            Text(String(localized: "\(elements.count) items", bundle: #bundle))
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            Spacer()
            Button {
                value = .list(elements + [blueprint.emptyValue(for: items)])
            } label: {
                Label {
                    Text("Add Item", bundle: #bundle)
                } icon: {
                    Image(systemName: "plus.circle")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
            removeButton
        }
        .padding(.leading, indent)
        problem
        ForEach(elements.indices, id: \.self) { index in
            AnyView(BlueprintValueEditor(
                blueprint: blueprint, schema: items, value: part(index), path: "\(path)[\(index)]",
                label: String(localized: "Item \(index + 1)", bundle: #bundle), problems: problems, depth: depth + 1,
                onRemove: { removeItem(index) }
            ))
        }
    }

    @ViewBuilder private func map(_ keys: BlueprintSchema, _ values: BlueprintSchema) -> some View {
        let entries = mapEntries
        HStack {
            fieldLabel
            Text(String(localized: "\(entries.count) entries", bundle: #bundle))
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            Spacer()
            Button {
                value = .map(entries + [BlueprintValue.Entry(key: blueprint.emptyValue(for: keys), value: blueprint.emptyValue(for: values))])
            } label: {
                Label {
                    Text("Add Entry", bundle: #bundle)
                } icon: {
                    Image(systemName: "plus.circle")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
            removeButton
        }
        .padding(.leading, indent)
        problem
        ForEach(entries.indices, id: \.self) { index in
            AnyView(BlueprintValueEditor(
                blueprint: blueprint, schema: keys, value: entryPart(index, key: true), path: "\(path)[\(index)].key",
                label: String(localized: "Key \(index + 1)", bundle: #bundle), problems: problems, depth: depth + 1,
                onRemove: { removeEntry(index) }
            ))
            AnyView(BlueprintValueEditor(
                blueprint: blueprint, schema: values, value: entryPart(index, key: false), path: "\(path)[\(index)].value",
                label: String(localized: "Value \(index + 1)", bundle: #bundle), problems: problems, depth: depth + 1
            ))
        }
    }

    // MARK: - Bindings into the value

    private func childPath(_ field: BlueprintSchema, _ index: Int) -> String {
        switch resolved.kind {
        case .tuple, .builtin(.pair): "\(path)[\(index)]"
        default: Blueprint.fieldPath(path, field, index)
        }
    }

    private var integerText: Binding<String> {
        Binding { if case .integer(let text) = value { text } else { "" } } set: { value = .integer($0) }
    }

    private var bytesText: Binding<String> {
        Binding { if case .bytes(let text) = value { text } else { "" } } set: { value = .bytes($0) }
    }

    private var stringText: Binding<String> {
        Binding { if case .text(let text) = value { text } else { "" } } set: { value = .text($0) }
    }

    private var dataText: Binding<String> {
        Binding { if case .data(let text) = value { text } else { "" } } set: { value = .data($0) }
    }

    private var booleanValue: Binding<Bool> {
        Binding { if case .boolean(let flag) = value { flag } else { false } } set: { value = .boolean($0) }
    }

    /// A Bool written as constructors: False is 0, True is 1.
    private var constructorFlag: Binding<Bool> {
        Binding { if case .constructor(let index, _) = value { index == 1 } else { false } } set: {
            value = .constructor(index: $0 ? 1 : 0, fields: [])
        }
    }

    private func variantIndex(_ variants: [BlueprintSchema]) -> Binding<Int> {
        Binding {
            guard case .constructor(let index, _) = value else { return 0 }
            return variants.firstIndex { Blueprint.constructorIndex($0) == index } ?? 0
        } set: { position in
            guard variants.indices.contains(position) else { return }
            value = blueprint.emptyValue(for: variants[position])
        }
    }

    private func chosenVariant(_ variants: [BlueprintSchema]) -> BlueprintSchema? {
        guard case .constructor(let index, _) = value else { return nil }
        return variants.first { Blueprint.constructorIndex($0) == index }
    }

    private var listElements: [BlueprintValue] {
        if case .list(let elements) = value { elements } else { [] }
    }

    private var mapEntries: [BlueprintValue.Entry] {
        if case .map(let entries) = value { entries } else { [] }
    }

    /// The part at `index`: a constructor's field, a list's item, a pair's side.
    private func part(_ index: Int) -> Binding<BlueprintValue> {
        Binding {
            switch value {
            case .constructor(_, let fields) where fields.indices.contains(index): fields[index]
            case .list(let items) where items.indices.contains(index): items[index]
            case .pair(let left, let right): index == 0 ? left : right
            default: .data("")
            }
        } set: { part in
            switch value {
            case .constructor(let constructor, var fields) where fields.indices.contains(index):
                fields[index] = part
                value = .constructor(index: constructor, fields: fields)
            case .list(var items) where items.indices.contains(index):
                items[index] = part
                value = .list(items)
            case .pair(let left, let right):
                value = index == 0 ? .pair(part, right) : .pair(left, part)
            default:
                break
            }
        }
    }

    private func entryPart(_ index: Int, key: Bool) -> Binding<BlueprintValue> {
        Binding {
            guard case .map(let entries) = value, entries.indices.contains(index) else { return .data("") }
            return key ? entries[index].key : entries[index].value
        } set: { part in
            guard case .map(var entries) = value, entries.indices.contains(index) else { return }
            if key { entries[index].key = part } else { entries[index].value = part }
            value = .map(entries)
        }
    }

    private func removeItem(_ index: Int) {
        guard case .list(var items) = value, items.indices.contains(index) else { return }
        items.remove(at: index)
        value = .list(items)
    }

    private func removeEntry(_ index: Int) {
        guard case .map(var entries) = value, entries.indices.contains(index) else { return }
        entries.remove(at: index)
        value = .map(entries)
    }

    private static func isNullary(_ schema: BlueprintSchema) -> Bool {
        if case .constructor(_, let fields) = schema.kind { return fields.isEmpty }
        return false
    }
}
