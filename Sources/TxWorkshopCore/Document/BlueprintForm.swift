import Foundation

/// A CIP-57 blueprint (`plutus.json`) kept in a document or the app's
/// library, as its JSON text.
public struct StoredBlueprint: Codable, Sendable, Equatable, Identifiable {
    /// Taken from the JSON's bytes, so the same file is one blueprint wherever it is kept.
    public let id: String
    public let json: String

    public init(json: String) {
        self.id = Self.id(of: json)
        self.json = json
    }

    /// A 64-bit FNV-1a hash of the text, in hex.
    static func id(of json: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in json.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// A value being filled in against a blueprint type: what a form holds. Text
/// stays as typed, so a half-written number or hash can be shown with what is
/// wrong with it.
public indirect enum BlueprintValue: Codable, Sendable, Equatable, Hashable {
    /// A whole number, as typed (`5000000`, `5_000_000`, `-2`).
    case integer(String)
    /// Bytes, as hex; a key hash may also be given as an address or key.
    case bytes(String)
    /// A list's items, or a tuple's.
    case list([BlueprintValue])
    case map([Entry])
    /// A constructor, by its alternative index, and its fields.
    case constructor(index: Int, fields: [BlueprintValue])
    /// Any Plutus data, in any form the app reads it in (CBOR hex, JSON, a number).
    case data(String)
    /// UPLC builtin values, for parameters.
    case unit
    case boolean(Bool)
    case text(String)
    case pair(BlueprintValue, BlueprintValue)

    public struct Entry: Codable, Sendable, Equatable, Hashable {
        public var key: BlueprintValue
        public var value: BlueprintValue

        public init(key: BlueprintValue, value: BlueprintValue) {
            self.key = key
            self.value = value
        }
    }
}

/// A datum or redeemer filled in through a blueprint's form. The draft's own
/// text keeps the CBOR the form makes, so the recipe builds as before.
public struct BlueprintForm: Codable, Sendable, Equatable {
    /// The ``StoredBlueprint`` in the recipe it comes from.
    public var blueprint: String
    /// The validator's title, e.g. `market.market.spend`.
    public var validator: String
    public var value: BlueprintValue

    public init(blueprint: String, validator: String, value: BlueprintValue) {
        self.blueprint = blueprint
        self.validator = validator
        self.value = value
    }
}

/// The parameters a validator from a blueprint was made into a script with.
/// The draft's script holds the applied code; these keep the values to edit.
public struct BlueprintParameters: Codable, Sendable, Equatable {
    /// The ``StoredBlueprint`` in the recipe it comes from.
    public var blueprint: String
    /// The validator's title, e.g. `market.token.mint`.
    public var validator: String
    /// One value per parameter, in order.
    public var values: [BlueprintValue]

    public init(blueprint: String, validator: String, values: [BlueprintValue]) {
        self.blueprint = blueprint
        self.validator = validator
        self.values = values
    }
}
