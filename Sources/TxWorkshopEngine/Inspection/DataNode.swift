import Foundation
import SwiftCardanoCore

/// A node of Plutus data or transaction metadata, flattened for display as a
/// tree.
public struct DataNode: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case constructor(UInt64)
        case map
        case list
        case integer
        case bytes
        case text
    }

    /// The node's path from the root, e.g. `1.fields.0`; unique within a tree.
    public let id: String
    /// How the node is reached from its parent: an index, a key, or a label.
    public let label: String
    public let kind: Kind
    /// The value of a leaf: an integer, text, or bytes as hex.
    public let value: String?
    /// Bytes that read as printable UTF-8, shown beside the hex.
    public let text: String?
    public let children: [DataNode]?
    /// The blueprint type or constructor the node was read as: `Order`, `Update`.
    public internal(set) var typeName: String? = nil
    /// For a root read through a blueprint, the validator it is for.
    public internal(set) var validator: String? = nil
    /// Whether the node has children the tree leaves out because it is nested
    /// ``maxDepth`` deep: data can nest as deep as a transaction's size allows,
    /// and a tree that deep could not be shown or even freed safely.
    public internal(set) var childrenOmitted = false

    /// How deep the tree goes, as the CBOR outline does. Deeper data is rare on chain.
    public static let maxDepth = 256

    /// How deep the node at `path` is: its path's steps after the root.
    static func depth(of path: String) -> Int {
        path.reduce(0) { $1 == "." ? $0 + 1 : $0 }
    }

    /// A container left without its children, at ``maxDepth``.
    static func omitted(_ kind: Kind, label: String, path: String) -> DataNode {
        var node = DataNode(id: path, label: label, kind: kind, value: nil, text: nil, children: nil)
        node.childrenOmitted = true
        return node
    }

    /// A one-line summary: the leaf value, or the node's kind and size.
    public var summary: String {
        if childrenOmitted {
            let what = switch kind {
            case .constructor(let tag): typeName ?? "Constr \(tag)"
            case .map: typeName ?? "map"
            default: typeName ?? "list"
            }
            return "\(what) · nested deeper than \(Self.maxDepth) levels"
        }
        let count = children?.count ?? 0
        let fields = count == 1 ? "1 field" : "\(count) fields"
        switch kind {
        case .constructor(let tag):
            if let typeName { return count == 0 ? typeName : "\(typeName) · \(fields)" }
            return "Constr \(tag) · \(fields)"
        case .map: return "\(typeName ?? "map") · \(count)"
        case .list: return "\(typeName ?? "list") · \(count)"
        case .integer, .text: return value ?? ""
        case .bytes:
            if let text { return "\"\(text)\"" }
            return value.map { $0.isEmpty ? "#<empty>" : "#\($0)" } ?? ""
        }
    }
}

extension DataNode {
    /// The tree of Plutus data.
    public static func plutus(_ data: PlutusData, label: String = "", path: String = "$") -> DataNode {
        if depth(of: path) >= maxDepth {
            switch data {
            case .constructor(let constr): return omitted(.constructor(UInt64(constr.tag ?? 0)), label: label, path: path)
            case .map, .indefiniteMap: return omitted(.map, label: label, path: path)
            case .array, .indefiniteArray: return omitted(.list, label: label, path: path)
            case .bigInt, .bytes: break
            }
        }
        switch data {
        case .constructor(let constr):
            let tag = UInt64(constr.tag ?? 0)
            return DataNode(
                id: path, label: label, kind: .constructor(tag), value: nil, text: nil,
                children: constr.fields.enumerated().map { plutus($1, label: "\($0)", path: "\(path).\($0)") }
            )
        case .map(let pairs), .indefiniteMap(let pairs):
            return DataNode(
                id: path, label: label, kind: .map, value: nil, text: nil,
                children: pairs.enumerated().map { index, pair in
                    plutus(pair.value, label: keyLabel(pair.key), path: "\(path).\(index)")
                }
            )
        case .array(let items):
            return list(items.array, label: label, path: path)
        case .indefiniteArray(let items):
            return list(items.getAll(), label: label, path: path)
        case .bigInt(let integer):
            return DataNode(id: path, label: label, kind: .integer, value: integerText(integer), text: nil, children: nil)
        case .bytes(let bytes):
            return bytesNode(bytes.data, label: label, path: path)
        }
    }

    private static func list(_ items: [PlutusData], label: String, path: String) -> DataNode {
        DataNode(
            id: path, label: label, kind: .list, value: nil, text: nil,
            children: items.enumerated().map { plutus($1, label: "\($0)", path: "\(path).\($0)") }
        )
    }

    private static func keyLabel(_ key: PlutusData) -> String {
        switch key {
        case .bytes(let bytes): printableText(bytes.data).map { "\"\($0)\"" } ?? "#\(hex(bytes.data))"
        case .bigInt(let integer): integerText(integer)
        default: plutus(key).summary
        }
    }

    private static func integerText(_ integer: BigInteger) -> String {
        switch integer {
        case .int(let value): String(value)
        case .bigUInt(let value): String(value)
        case .bigNInt(let value): String(value)
        }
    }

    /// The tree of a transaction metadatum.
    public static func metadatum(_ value: TransactionMetadatum, label: String = "", path: String = "$") -> DataNode {
        if depth(of: path) >= maxDepth {
            switch value {
            case .map: return omitted(.map, label: label, path: path)
            case .list: return omitted(.list, label: label, path: path)
            case .int, .bigInt, .bytes, .text: break
            }
        }
        switch value {
        case .map(let pairs):
            return DataNode(
                id: path, label: label, kind: .map, value: nil, text: nil,
                children: pairs.enumerated().map { index, pair in
                    metadatum(pair.value, label: metadatumKey(pair.key), path: "\(path).\(index)")
                }
            )
        case .list(let items):
            return DataNode(
                id: path, label: label, kind: .list, value: nil, text: nil,
                children: items.enumerated().map { metadatum($1, label: "\($0)", path: "\(path).\($0)") }
            )
        case .int(let integer):
            return DataNode(id: path, label: label, kind: .integer, value: String(integer), text: nil, children: nil)
        case .bigInt(let integer):
            return DataNode(id: path, label: label, kind: .integer, value: integer.description, text: nil, children: nil)
        case .bytes(let data):
            return bytesNode(data, label: label, path: path)
        case .text(let text):
            return DataNode(id: path, label: label, kind: .text, value: text, text: nil, children: nil)
        }
    }

    private static func metadatumKey(_ key: TransactionMetadatum) -> String {
        switch key {
        case .text(let text): text
        case .int(let integer): String(integer)
        case .bigInt(let integer): integer.description
        case .bytes(let data): "#\(hex(data))"
        default: metadatum(key).summary
        }
    }

    private static func bytesNode(_ data: Data, label: String, path: String) -> DataNode {
        DataNode(id: path, label: label, kind: .bytes, value: hex(data), text: printableText(data), children: nil)
    }

    /// `data` as text, when it is valid UTF-8 made of printable characters.
    static func printableText(_ data: Data) -> String? {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        let printable = text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        return printable ? text : nil
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
