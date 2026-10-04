import Foundation

/// One type in a CIP-57 Plutus blueprint: what shape of Plutus data a datum,
/// redeemer, parameter or one of their fields takes.
public struct BlueprintSchema: Sendable, Equatable {
    /// The type's title, or the field's when the schema names a field.
    public var title: String?
    public var description: String?
    public var kind: Kind

    public init(title: String? = nil, description: String? = nil, kind: Kind) {
        self.title = title
        self.description = description
        self.kind = kind
    }

    public indirect enum Kind: Sendable, Equatable {
        /// A type defined under `definitions`, by its unescaped name.
        case reference(String)
        /// Any Plutus data (`{}`, Aiken's `Data`).
        case anyData
        case integer(IntegerLimits)
        case bytes(BytesLimits)
        /// A list whose items all share one type.
        case list(BlueprintSchema, ItemLimits)
        /// A list of a fixed length whose items each have their own type.
        case tuple([BlueprintSchema])
        case map(keys: BlueprintSchema, values: BlueprintSchema, ItemLimits)
        /// A constructor: its alternative index and its fields, in order.
        case constructor(index: Int, fields: [BlueprintSchema])
        /// One of several types; usually the constructors of a sum type.
        case anyOf([BlueprintSchema])
        /// A UPLC builtin type (`#integer`, `#pair` …), which only a parameter
        /// can take: it is applied to the script as a constant, not as data.
        case builtin(Builtin)
        /// A schema keyword the editor does not handle (`allOf`, `not`); the
        /// value is then entered as raw Plutus data.
        case unsupported(String)
    }

    public indirect enum Builtin: Sendable, Equatable {
        case unit
        case boolean
        case integer
        case bytes
        case string
        case pair(BlueprintSchema, BlueprintSchema)
        case list(BlueprintSchema)
    }

    public struct IntegerLimits: Sendable, Equatable {
        public var minimum: Decimal?
        public var maximum: Decimal?
        public var exclusiveMinimum: Decimal?
        public var exclusiveMaximum: Decimal?
        public var multipleOf: Decimal?
        public static let none = IntegerLimits()
    }

    public struct BytesLimits: Sendable, Equatable {
        public var minLength: Int?
        public var maxLength: Int?
        /// The only values allowed, as hex.
        public var allowed: [String]?
        public static let none = BytesLimits()
    }

    public struct ItemLimits: Sendable, Equatable {
        public var minItems: Int?
        public var maxItems: Int?
        public var uniqueItems: Bool = false
        public static let none = ItemLimits()
    }
}

extension BlueprintSchema {
    /// Reads a schema object from a blueprint's JSON.
    static func parse(_ json: Any, at path: String) throws -> BlueprintSchema {
        guard let object = json as? [String: Any] else {
            throw BlueprintError.notABlueprint("\(path) is not a schema object.")
        }
        let title = object["title"] as? String
        let description = object["description"] as? String
        func schema(_ kind: Kind) -> BlueprintSchema { BlueprintSchema(title: title, description: description, kind: kind) }
        func child(_ value: Any?, _ name: String) throws -> BlueprintSchema {
            guard let value else { throw BlueprintError.notABlueprint("\(path) has no \(name).") }
            return try parse(value, at: "\(path).\(name)")
        }

        if let reference = object["$ref"] as? String {
            return schema(.reference(try Self.definitionName(reference)))
        }
        if let variants = (object["anyOf"] ?? object["oneOf"]) as? [Any] {
            return schema(.anyOf(try variants.enumerated().map { try parse($1, at: "\(path).anyOf[\($0)]") }))
        }
        for keyword in ["allOf", "not"] where object[keyword] != nil {
            return schema(.unsupported(keyword))
        }
        guard let dataType = object["dataType"] as? String else { return schema(.anyData) }
        switch dataType {
        case "integer":
            return schema(.integer(IntegerLimits(
                minimum: decimal(object["minimum"]), maximum: decimal(object["maximum"]),
                exclusiveMinimum: decimal(object["exclusiveMinimum"]), exclusiveMaximum: decimal(object["exclusiveMaximum"]),
                multipleOf: decimal(object["multipleOf"])
            )))
        case "bytes":
            return schema(.bytes(BytesLimits(
                minLength: object["minLength"] as? Int, maxLength: object["maxLength"] as? Int,
                allowed: (object["enum"] as? [String])?.map { $0.lowercased() }
            )))
        case "list":
            if let items = object["items"] as? [Any] {
                return schema(.tuple(try items.enumerated().map { try parse($1, at: "\(path).items[\($0)]") }))
            }
            return schema(.list(try child(object["items"], "items"), itemLimits(object)))
        case "map":
            return schema(.map(keys: try child(object["keys"], "keys"), values: try child(object["values"], "values"), itemLimits(object)))
        case "constructor":
            guard let index = object["index"] as? Int else { throw BlueprintError.notABlueprint("\(path) is a constructor with no index.") }
            let fields = object["fields"] as? [Any] ?? []
            return schema(.constructor(index: index, fields: try fields.enumerated().map { try parse($1, at: "\(path).fields[\($0)]") }))
        case "#unit": return schema(.builtin(.unit))
        case "#boolean": return schema(.builtin(.boolean))
        case "#integer": return schema(.builtin(.integer))
        case "#bytes": return schema(.builtin(.bytes))
        case "#string": return schema(.builtin(.string))
        case "#pair": return schema(.builtin(.pair(try child(object["left"], "left"), try child(object["right"], "right"))))
        case "#list": return schema(.builtin(.list(try child(object["items"], "items"))))
        default:
            throw BlueprintError.notABlueprint("\(path) has the unknown dataType \"\(dataType)\".")
        }
    }

    /// `#/definitions/market~1Order` → `market/Order` (a JSON pointer's escapes undone).
    static func definitionName(_ reference: String) throws -> String {
        let prefix = "#/definitions/"
        guard reference.hasPrefix(prefix) else {
            throw BlueprintError.notABlueprint("The reference \(reference) is not to the blueprint's definitions.")
        }
        return String(reference.dropFirst(prefix.count))
            .replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        (value as? NSNumber).map { $0.decimalValue }
    }

    private static func itemLimits(_ object: [String: Any]) -> ItemLimits {
        ItemLimits(minItems: object["minItems"] as? Int, maxItems: object["maxItems"] as? Int, uniqueItems: object["uniqueItems"] as? Bool ?? false)
    }
}
