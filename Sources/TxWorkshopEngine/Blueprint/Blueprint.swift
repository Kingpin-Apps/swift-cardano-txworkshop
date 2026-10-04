import Foundation
import SwiftCardanoCore

/// A CIP-57 Plutus contract blueprint (`plutus.json`): a project's validators,
/// with the types of their datums, redeemers and parameters.
public struct Blueprint: Sendable, Equatable {
    public struct Preamble: Sendable, Equatable {
        public var title: String
        public var description: String?
        public var version: String?
        /// 1, 2 or 3.
        public var plutusVersion: Int?
        /// The compiler's name and version, e.g. `Aiken v1.1.19`.
        public var compiler: String?
    }

    /// A datum, redeemer or parameter: its name and its type.
    public struct Argument: Sendable, Equatable {
        public var title: String?
        public var description: String?
        public var schema: BlueprintSchema
    }

    public struct Validator: Sendable, Equatable, Identifiable {
        /// `module.validator.purpose` (Aiken 1.1), or `module.validator`.
        public var title: String
        public var description: String?
        public var datum: Argument?
        public var redeemer: Argument?
        /// What the validator takes before it is a script, in the order they are applied.
        public var parameters: [Argument]
        /// The script's flat bytes in CBOR, as hex.
        public var compiledCode: String?
        /// The script hash the blueprint states, as hex.
        public var hash: String?
        public var plutusVersion: Int

        public var id: String { title }

        /// The purpose a validator was compiled for (`spend`, `mint` …), from
        /// the last part of an Aiken 1.1 title; `nil` for older titles.
        public var purpose: String? {
            let parts = title.split(separator: ".")
            guard parts.count >= 3, let last = parts.last else { return nil }
            return ["spend", "mint", "withdraw", "publish", "vote", "propose", "else"].contains(String(last)) ? String(last) : nil
        }

        /// The script hash of `compiledCode`, worked out here rather than taken
        /// from the blueprint; `nil` when there is no code.
        public func computedHash() throws -> String? {
            guard let compiledCode, !compiledCode.isEmpty else { return nil }
            let script = try TransactionComposer.plutusScript(version: plutusVersion, hex: compiledCode)
            return try scriptHash(script: script).payload.hex
        }
    }

    public var preamble: Preamble
    public var validators: [Validator]
    /// Named types, by their unescaped names (`market/Order`).
    public var definitions: [String: BlueprintSchema]

    public init(json data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw BlueprintError.notABlueprint("That is not a JSON object.")
        }
        guard let preamble = root["preamble"] as? [String: Any], let validators = root["validators"] as? [Any] else {
            throw BlueprintError.notABlueprint("A blueprint has a preamble and validators.")
        }
        let compiler = (preamble["compiler"] as? [String: Any]).map { compiler in
            [compiler["name"] as? String, compiler["version"] as? String].compactMap { $0 }.joined(separator: " ")
        }
        self.preamble = Preamble(
            title: preamble["title"] as? String ?? "Blueprint",
            description: preamble["description"] as? String,
            version: preamble["version"] as? String,
            plutusVersion: Self.plutusVersion(preamble["plutusVersion"]),
            compiler: compiler
        )

        var definitions: [String: BlueprintSchema] = [:]
        for (name, schema) in root["definitions"] as? [String: Any] ?? [:] {
            let unescaped = name.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            definitions[unescaped] = try BlueprintSchema.parse(schema, at: "definitions.\(name)")
        }
        self.definitions = definitions

        let defaultVersion = self.preamble.plutusVersion ?? 3
        self.validators = try validators.enumerated().map { index, value in
            guard let object = value as? [String: Any], let title = object["title"] as? String else {
                throw BlueprintError.notABlueprint("validators[\(index)] has no title.")
            }
            func argument(_ value: Any?, _ name: String) throws -> Argument? {
                guard let object = value as? [String: Any] else { return nil }
                return Argument(
                    title: object["title"] as? String, description: object["description"] as? String,
                    schema: try BlueprintSchema.parse(object["schema"] ?? [String: Any](), at: "\(title).\(name)")
                )
            }
            return Validator(
                title: title,
                description: object["description"] as? String,
                datum: try argument(object["datum"], "datum"),
                redeemer: try argument(object["redeemer"], "redeemer"),
                parameters: try (object["parameters"] as? [Any] ?? []).enumerated().compactMap { try argument($1, "parameters[\($0)]") },
                compiledCode: object["compiledCode"] as? String,
                hash: (object["hash"] as? String)?.lowercased(),
                plutusVersion: Self.plutusVersion(object["plutusVersion"]) ?? defaultVersion
            )
        }
        for reference in Self.references(in: self) where definitions[reference] == nil {
            throw BlueprintError.unknownReference(reference)
        }
    }

    /// `schema` with references followed to the type they name. The field's
    /// own title and description are kept over the type's.
    public func resolve(_ schema: BlueprintSchema) throws -> BlueprintSchema {
        var current = schema
        var seen: Set<String> = []
        while case .reference(let name) = current.kind {
            guard seen.insert(name).inserted else { throw BlueprintError.unknownReference("\(name) (it refers to itself)") }
            guard let target = definitions[name] else { throw BlueprintError.unknownReference(name) }
            current = BlueprintSchema(
                title: current.title ?? target.title, description: current.description ?? target.description, kind: target.kind
            )
        }
        return current
    }

    /// The type's own name, for a reference: `Order`, `Option<Int>` …
    public func typeName(_ schema: BlueprintSchema) -> String? {
        if case .reference(let name) = schema.kind {
            // Aiken names generic instances `List$ByteArray`, `Option$Int`.
            if name.contains("$") { return Self.genericName(name) }
            return definitions[name]?.title ?? Self.shortName(name)
        }
        return schema.title
    }

    /// `Pairs$ByteArray_Int` → `Pairs<ByteArray, Int>`; module paths are dropped.
    static func genericName(_ name: String) -> String {
        let parts = name.split(separator: "$", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return shortName(name) }
        let arguments = parts[1].split(separator: "_").map { shortName(String($0)) }
        return "\(shortName(parts[0]))<\(arguments.joined(separator: ", "))>"
    }

    static func shortName(_ name: String) -> String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// The validators whose script hash is `hash` (one per purpose).
    public func validators(forScriptHash hash: String) -> [Validator] {
        validators.filter { $0.hash == hash.lowercased() }
    }

    private static func plutusVersion(_ value: Any?) -> Int? {
        switch (value as? String)?.lowercased() {
        case "v1": 1
        case "v2": 2
        case "v3": 3
        default: nil
        }
    }

    /// Every definition name a schema in the blueprint refers to.
    private static func references(in blueprint: Blueprint) -> Set<String> {
        var found: Set<String> = []
        func walk(_ schema: BlueprintSchema) {
            switch schema.kind {
            case .reference(let name): found.insert(name)
            case .list(let items, _): walk(items)
            case .tuple(let items): items.forEach(walk)
            case .map(let keys, let values, _): walk(keys); walk(values)
            case .constructor(_, let fields): fields.forEach(walk)
            case .anyOf(let variants): variants.forEach(walk)
            case .builtin(.pair(let left, let right)): walk(left); walk(right)
            case .builtin(.list(let items)): walk(items)
            default: break
            }
        }
        blueprint.definitions.values.forEach(walk)
        for validator in blueprint.validators {
            ([validator.datum, validator.redeemer].compactMap { $0 } + validator.parameters).forEach { walk($0.schema) }
        }
        return found
    }
}

public enum BlueprintError: Error, Sendable, Equatable, CustomStringConvertible {
    case notABlueprint(String)
    case unknownReference(String)
    /// The value does not fit its type; each problem names its field.
    case invalid([BlueprintProblem])
    /// The data does not have the shape the type describes, at `path`.
    case mismatch(path: String, String)

    public var description: String {
        switch self {
        case .notABlueprint(let reason): "Not a Plutus blueprint: \(reason)"
        case .unknownReference(let name): "The blueprint refers to a type it does not define: \(name)."
        case .invalid(let problems): problems.map(\.description).joined(separator: "\n")
        case .mismatch(let path, let reason): "\(path): \(reason)"
        }
    }
}

/// Something wrong with one field of a value.
public struct BlueprintProblem: Sendable, Equatable, CustomStringConvertible {
    /// Where, as field names from the root: `datum.payout.payment_credential`.
    public let path: String
    public let message: String

    public var description: String { "\(path): \(message)" }
}
