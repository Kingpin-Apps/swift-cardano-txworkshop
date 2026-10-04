import Foundation
import TxWorkshopCore

extension Blueprint {
    /// A starting value for `schema`: empty text, empty lists, and the first
    /// constructor of a sum type (`None` for an `Option`). A type that refers
    /// to itself starts on a constructor that ends the recursion.
    public func emptyValue(for schema: BlueprintSchema) -> BlueprintValue {
        emptyValue(for: schema, depth: 0)
    }

    private func emptyValue(for schema: BlueprintSchema, depth: Int) -> BlueprintValue {
        guard let resolved = try? resolve(schema) else { return .data("") }
        switch resolved.kind {
        case .reference, .anyData, .unsupported: return .data("")
        case .integer: return .integer("")
        case .bytes: return .bytes("")
        case .list: return .list([])
        case .tuple(let items): return .list(items.map { emptyValue(for: $0, depth: depth + 1) })
        case .map: return .map([])
        case .constructor(let index, let fields):
            return .constructor(index: index, fields: fields.map { emptyValue(for: $0, depth: depth + 1) })
        case .anyOf(let variants):
            let resolvedVariants = variants.compactMap { try? resolve($0) }
            guard let chosen = preferredVariant(resolvedVariants, typeName: typeName(schema), depth: depth) else { return .data("") }
            return emptyValue(for: chosen, depth: depth + 1)
        case .builtin(let builtin):
            switch builtin {
            case .unit: return .unit
            case .boolean: return .boolean(false)
            case .integer: return .integer("")
            case .bytes: return .bytes("")
            case .string: return .text("")
            case .pair(let left, let right): return .pair(emptyValue(for: left, depth: depth + 1), emptyValue(for: right, depth: depth + 1))
            case .list: return .list([])
            }
        }
    }

    private func preferredVariant(_ variants: [BlueprintSchema], typeName: String?, depth: Int) -> BlueprintSchema? {
        func fieldCount(_ schema: BlueprintSchema) -> Int {
            if case .constructor(_, let fields) = schema.kind { return fields.count }
            return 0
        }
        if typeName?.hasPrefix("Option") == true, let none = variants.first(where: { $0.title == "None" }) { return none }
        // Deep in a recursive type, stop at the simplest constructor.
        if depth > 8 { return variants.min { fieldCount($0) < fieldCount($1) } }
        return variants.first
    }
}
