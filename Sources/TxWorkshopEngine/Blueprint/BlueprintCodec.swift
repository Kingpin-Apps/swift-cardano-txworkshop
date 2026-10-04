import BigInt
import Foundation
import OrderedCollections
import SwiftCardanoCore
import TxWorkshopCore

extension Blueprint {
    /// `value` as Plutus data of type `schema`, written the way Aiken and
    /// cardano-cli write it. Throws ``BlueprintError/invalid(_:)`` with every
    /// field that is wrong.
    public func encode(_ value: BlueprintValue, as schema: BlueprintSchema, path: String) throws -> PlutusData {
        var problems: [BlueprintProblem] = []
        let data = encode(value, schema, path: path, problems: &problems)
        guard problems.isEmpty, let data else { throw BlueprintError.invalid(problems) }
        return data
    }

    /// `value` as CBOR hex: what the build recipe stores.
    public func cborHex(_ value: BlueprintValue, as schema: BlueprintSchema, path: String) throws -> String {
        try encode(value, as: schema, path: path).toCBORData().hex
    }

    /// Every field of `value` that does not fit `schema`.
    public func problems(_ value: BlueprintValue, as schema: BlueprintSchema, path: String) -> [BlueprintProblem] {
        var problems: [BlueprintProblem] = []
        _ = encode(value, schema, path: path, problems: &problems)
        return problems
    }

    /// `data` read as type `schema`, to fill a form. Throws
    /// ``BlueprintError/mismatch(path:_:)`` where the data parts from the type.
    public func decode(_ data: PlutusData, as schema: BlueprintSchema, path: String) throws -> BlueprintValue {
        let resolved = try resolve(schema)
        func mismatch(_ expected: String) -> BlueprintError {
            .mismatch(path: path, "\(expected) expected, but the data is \(Self.shape(data)).")
        }
        switch resolved.kind {
        case .reference, .unsupported, .anyData:
            return .data(try data.toCBORData().hex)
        case .integer:
            guard case .bigInt(let integer) = data else { throw mismatch("A whole number") }
            return .integer(String(integer.value))
        case .bytes:
            guard case .bytes(let bytes) = data else { throw mismatch("Bytes") }
            return .bytes(bytes.data.hex)
        case .list(let items, _):
            guard let elements = Self.elements(data) else { throw mismatch("A list") }
            return .list(try elements.enumerated().map { try decode($1, as: items, path: "\(path)[\($0)]") })
        case .tuple(let items):
            guard let elements = Self.elements(data) else { throw mismatch("A tuple") }
            guard elements.count == items.count else {
                throw BlueprintError.mismatch(path: path, "A tuple of \(items.count) expected, but the list has \(elements.count).")
            }
            return .list(try zip(items, elements).enumerated().map { index, pair in
                try decode(pair.1, as: pair.0, path: "\(path)[\(index)]")
            })
        case .map(let keys, let values, _):
            guard case .map(let pairs) = data else { throw mismatch("A map") }
            return .map(try pairs.enumerated().map { index, pair in
                BlueprintValue.Entry(
                    key: try decode(pair.key, as: keys, path: "\(path)[\(index)].key"),
                    value: try decode(pair.value, as: values, path: "\(path)[\(index)].value")
                )
            })
        case .constructor(let index, let fields):
            guard case .constructor(let constr) = data else { throw mismatch("Constructor \(index)") }
            guard constr.tag.map(Int.init) == index else {
                throw BlueprintError.mismatch(path: path, "Constructor \(index) expected, but the data is constructor \(constr.tag.map(String.init) ?? "?").")
            }
            guard constr.fields.count == fields.count else {
                throw BlueprintError.mismatch(path: path, "\(resolved.title ?? "Constructor \(index)") has \(fields.count) fields, but the data has \(constr.fields.count).")
            }
            return .constructor(index: index, fields: try zip(fields, constr.fields).enumerated().map { position, pair in
                try decode(pair.1, as: pair.0, path: Self.fieldPath(path, pair.0, position))
            })
        case .anyOf(let variants):
            var reasons: [String] = []
            for variant in variants {
                do {
                    return try decode(data, as: variant, path: path)
                } catch let error as BlueprintError {
                    reasons.append(error.description)
                }
            }
            if case .constructor(let constr) = data, let tag = constr.tag,
                !variants.contains(where: { (try? resolve($0)).map { Self.constructorIndex($0) == Int(tag) } ?? false }) {
                throw BlueprintError.mismatch(path: path, "\(typeName(schema) ?? "The type") has no constructor \(tag).")
            }
            throw BlueprintError.mismatch(path: path, "None of \(typeName(schema) ?? "the type")'s forms fit: \(reasons.joined(separator: "; "))")
        case .builtin:
            throw BlueprintError.mismatch(path: path, "A UPLC builtin is a script parameter, not Plutus data.")
        }
    }

    /// Reads CBOR hex as `schema`.
    public func decode(cborHex: String, as schema: BlueprintSchema, path: String) throws -> BlueprintValue {
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: cborHex.filter { !$0.isWhitespace }),
            let data = try? PlutusData.fromCBOR(data: bytes)
        else { throw BlueprintError.mismatch(path: path, "Not Plutus data in CBOR.") }
        return try decode(data, as: schema, path: path)
    }

    // MARK: - Encoding

    private func encode(_ value: BlueprintValue, _ schema: BlueprintSchema, path: String, problems: inout [BlueprintProblem]) -> PlutusData? {
        func problem(_ message: String) -> PlutusData? {
            problems.append(BlueprintProblem(path: path, message: message))
            return nil
        }
        let resolved: BlueprintSchema
        do {
            resolved = try resolve(schema)
        } catch {
            return problem(String(describing: error))
        }

        switch resolved.kind {
        case .reference, .anyData, .unsupported:
            guard case .data(let text) = value else { return problem("Enter Plutus data.") }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return problem("Enter Plutus data: CBOR hex, JSON or a number.") }
            do {
                let hex = try ValueReader.plutusData(trimmed).value
                return try PlutusData.fromCBOR(data: try TxDocumentCodec.bytes(fromHex: hex))
            } catch {
                return problem(String(describing: error))
            }

        case .integer(let limits):
            guard case .integer(let text) = value else { return problem("A whole number expected.") }
            guard let integer = Self.integer(text) else {
                return problem(text.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a whole number." : "\"\(text)\" is not a whole number.")
            }
            if let message = Self.check(integer, limits) { return problem(message) }
            if let small = Int64(exactly: integer) { return .bigInt(.int(small)) }
            return .bigInt(.bigNInt(integer))

        case .bytes(let limits):
            guard case .bytes(let text) = value else { return problem("Bytes expected.") }
            // A key hash may be given as an address, a bech32 key or a key file.
            guard let bytes = Self.bytes(text) ?? (try? ValueReader.anyKeyHash(text.trimmingCharacters(in: .whitespacesAndNewlines)))
                .flatMap({ Self.bytes($0.value) })
            else { return problem("Bytes are written in hex: two digits 0–9, a–f a byte.") }
            if let minimum = limits.minLength, bytes.count < minimum {
                return problem(limits.maxLength == minimum ? "\(minimum) bytes expected, not \(bytes.count)." : "At least \(minimum) bytes expected, not \(bytes.count).")
            }
            if let maximum = limits.maxLength, bytes.count > maximum { return problem("At most \(maximum) bytes, not \(bytes.count).") }
            if let allowed = limits.allowed, !allowed.contains(bytes.hex) {
                return problem("Must be one of \(allowed.joined(separator: ", ")).")
            }
            return try? .bytes(Bytes(from: bytes))

        case .list(let items, let limits):
            guard case .list(let elements) = value else { return problem("A list expected.") }
            if let message = Self.check(count: elements.count, limits) { _ = problem(message) }
            let encoded = elements.enumerated().map { encode($1, items, path: "\(path)[\($0)]", problems: &problems) }
            if limits.uniqueItems, Set(elements).count < elements.count { _ = problem("The items must all differ.") }
            return Self.list(encoded)

        case .tuple(let items):
            guard case .list(let elements) = value, elements.count == items.count else { return problem("A tuple of \(items.count) expected.") }
            return Self.list(zip(elements, items).enumerated().map { index, pair in
                encode(pair.0, pair.1, path: "\(path)[\(index)]", problems: &problems)
            })

        case .map(let keys, let values, let limits):
            guard case .map(let entries) = value else { return problem("A map expected.") }
            if let message = Self.check(count: entries.count, limits) { _ = problem(message) }
            var pairs = OrderedDictionary<PlutusData, PlutusData>()
            var complete = true
            for (index, entry) in entries.enumerated() {
                let key = encode(entry.key, keys, path: "\(path)[\(index)].key", problems: &problems)
                let item = encode(entry.value, values, path: "\(path)[\(index)].value", problems: &problems)
                guard let key, let item else { complete = false; continue }
                if pairs[key] != nil {
                    problems.append(BlueprintProblem(path: "\(path)[\(index)].key", message: "This key is already in the map."))
                    complete = false
                }
                pairs[key] = item
            }
            return complete ? .map(pairs) : nil

        case .constructor(let index, let fields):
            guard case .constructor(let chosen, let elements) = value, chosen == index else {
                return problem("\(resolved.title ?? "Constructor \(index)") expected.")
            }
            guard elements.count == fields.count else { return problem("\(fields.count) fields expected, not \(elements.count).") }
            let encoded = zip(elements, fields).enumerated().map { position, pair in
                encode(pair.0, pair.1, path: Self.fieldPath(path, pair.1, position), problems: &problems)
            }
            guard encoded.allSatisfy({ $0 != nil }) else { return nil }
            return .constructor(Constr(tag: UInt64(index), fields: encoded.compactMap { $0 }, useIndefiniteList: true))

        case .anyOf(let variants):
            let resolvedVariants = variants.compactMap { try? resolve($0) }
            // A sum of constructors: the value names its constructor.
            if case .constructor(let chosen, _) = value,
                let variant = resolvedVariants.first(where: { Self.constructorIndex($0) == chosen }) {
                return encode(value, variant, path: path, problems: &problems)
            }
            // Otherwise the first form the value fits.
            for variant in resolvedVariants {
                var attempt: [BlueprintProblem] = []
                if let data = encode(value, variant, path: path, problems: &attempt), attempt.isEmpty { return data }
            }
            return problem("This is not one of \(typeName(schema) ?? "the type")'s forms.")

        case .builtin:
            return problem("A UPLC builtin is a script parameter, not Plutus data.")
        }
    }

    // MARK: - Helpers

    /// A non-empty list is written with indefinite length, as the ledger's own
    /// tools write it, so that datum hashes agree.
    private static func list(_ items: [PlutusData?]) -> PlutusData? {
        guard items.allSatisfy({ $0 != nil }) else { return nil }
        let present = items.compactMap { $0 }
        return present.isEmpty ? .array([]) : .indefiniteArray(IndefiniteList(present))
    }

    private static func elements(_ data: PlutusData) -> [PlutusData]? {
        switch data {
        case .array(let items): items
        case .indefiniteArray(let items): Array(items)
        default: nil
        }
    }

    public static func constructorIndex(_ schema: BlueprintSchema) -> Int? {
        if case .constructor(let index, _) = schema.kind { return index }
        return nil
    }

    /// A field's path: its title when it has one, else its position.
    public static func fieldPath(_ path: String, _ field: BlueprintSchema, _ position: Int) -> String {
        if let title = field.title, !title.isEmpty, case .reference = field.kind { return "\(path).\(title)" }
        if let title = field.title, !title.isEmpty, !Self.isTypeTitle(field) { return "\(path).\(title)" }
        return "\(path)[\(position)]"
    }

    /// Whether a schema's title names its type rather than a field (an inline
    /// `{"dataType": "integer", "title": "Int"}`).
    private static func isTypeTitle(_ schema: BlueprintSchema) -> Bool {
        switch schema.kind {
        case .reference: false
        default: schema.title.map { $0.first?.isUppercase == true } ?? false
        }
    }

    static func integer(_ text: String) -> BigInt? {
        let cleaned = text.filter { $0 != "_" && !$0.isWhitespace }
        guard !cleaned.isEmpty, cleaned.dropFirst(cleaned.first == "-" || cleaned.first == "+" ? 1 : 0).allSatisfy(\.isASCII),
            cleaned.dropFirst(cleaned.first == "-" || cleaned.first == "+" ? 1 : 0).allSatisfy(\.isNumber)
        else { return nil }
        return BigInt(cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned)
    }

    static func bytes(_ text: String) -> Data? {
        var cleaned = text.filter { !$0.isWhitespace }
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") { cleaned.removeFirst(2) }
        if cleaned.isEmpty { return Data() }
        return try? TxDocumentCodec.bytes(fromHex: cleaned)
    }

    private static func check(_ integer: BigInt, _ limits: BlueprintSchema.IntegerLimits) -> String? {
        func decimal(_ value: BigInt) -> Decimal? { Decimal(string: String(value)) }
        guard let value = decimal(integer) else { return nil }
        if let minimum = limits.minimum, value < minimum { return "At least \(minimum)." }
        if let maximum = limits.maximum, value > maximum { return "At most \(maximum)." }
        if let minimum = limits.exclusiveMinimum, value <= minimum { return "More than \(minimum)." }
        if let maximum = limits.exclusiveMaximum, value >= maximum { return "Less than \(maximum)." }
        if let step = limits.multipleOf, step != 0, let divisor = BigInt(exactly: NSDecimalNumber(decimal: step).intValue), divisor != 0,
            integer % divisor != 0 {
            return "A multiple of \(step)."
        }
        return nil
    }

    private static func check(count: Int, _ limits: BlueprintSchema.ItemLimits) -> String? {
        if let minimum = limits.minItems, count < minimum { return "At least \(minimum) items." }
        if let maximum = limits.maxItems, count > maximum { return "At most \(maximum) items." }
        return nil
    }

    /// A short name for what a piece of data is, for mismatch messages.
    static func shape(_ data: PlutusData) -> String {
        switch data {
        case .constructor(let constr): "constructor \(constr.tag.map(String.init) ?? "?")"
        case .map: "a map"
        case .array, .indefiniteArray: "a list"
        case .bigInt: "a number"
        case .bytes: "bytes"
        }
    }
}
