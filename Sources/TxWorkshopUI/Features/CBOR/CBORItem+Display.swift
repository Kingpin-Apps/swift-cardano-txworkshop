import SwiftUI
import TxWorkshopEngine

extension CBORItem {
    /// What the item is, with its size: "array · 4 items", "tag 258".
    var kindSummary: AttributedString {
        switch kind {
        case .unsigned: AttributedString(localized: "unsigned integer", bundle: #bundle)
        case .negative: AttributedString(localized: "negative integer", bundle: #bundle)
        case .bytes: AttributedString(localized: "bytes · ^[\(count ?? 0) byte](inflect: true)", bundle: #bundle)
        case .text: AttributedString(localized: "text · ^[\(count ?? 0) byte](inflect: true)", bundle: #bundle)
        case .array: AttributedString(localized: "array · ^[\(count ?? 0) item](inflect: true)", bundle: #bundle)
        case .map: AttributedString(localized: "map · ^[\(count ?? 0) entry](inflect: true)", bundle: #bundle)
        case .tag(let tag): AttributedString(localized: "tag \(tag)", bundle: #bundle)
        case .float: AttributedString(localized: "float", bundle: #bundle)
        case .simple: AttributedString(localized: "simple value", bundle: #bundle)
        case .bool: AttributedString(localized: "boolean", bundle: #bundle)
        case .null: AttributedString(localized: "null", bundle: #bundle)
        case .undefined: AttributedString(localized: "undefined", bundle: #bundle)
        }
    }

    /// The ids of the items from the root down to, but not including, the
    /// item at `path`.
    static func ancestorIDs(of path: [Int]) -> [String] {
        (0..<path.count).map { length in path.prefix(length).map(String.init).joined(separator: ".") }
    }

    static func path(fromID id: String) -> [Int] {
        id.isEmpty ? [] : id.split(separator: ".").compactMap { Int($0) }
    }
}

extension CBORItem.Flag {
    var title: LocalizedStringResource {
        switch self {
        case .overlongHead: LocalizedStringResource("Head longer than needed", bundle: #bundle)
        case .indefiniteLength: LocalizedStringResource("Indefinite length", bundle: #bundle)
        case .nonPreferredFloat: LocalizedStringResource("Float wider than needed", bundle: #bundle)
        case .unsortedMapKeys: LocalizedStringResource("Map keys out of order", bundle: #bundle)
        case .duplicateMapKeys: LocalizedStringResource("Map has duplicate keys", bundle: #bundle)
        case .duplicateKey: LocalizedStringResource("Key repeats an earlier key", bundle: #bundle)
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .overlongHead:
            LocalizedStringResource("The length or value is written in more bytes than it needs. Re-encoding shortens it, which changes hashes.", bundle: #bundle)
        case .indefiniteLength:
            LocalizedStringResource("Written with a break marker instead of a length. The ledger accepts it; canonical CBOR does not.", bundle: #bundle)
        case .nonPreferredFloat:
            LocalizedStringResource("The number fits a shorter float encoding.", bundle: #bundle)
        case .unsortedMapKeys:
            LocalizedStringResource("Canonical CBOR sorts map keys by their encoded bytes.", bundle: #bundle)
        case .duplicateMapKeys:
            LocalizedStringResource("Two keys in this map are written the same. Decoders disagree on which one wins.", bundle: #bundle)
        case .duplicateKey:
            LocalizedStringResource("This key is written the same as an earlier key in its map.", bundle: #bundle)
        }
    }
}

extension Binding where Value == Set<String> {
    /// Whether the set holds `id`, as a binding that inserts or removes it.
    func contains(_ id: String) -> Binding<Bool> {
        Binding<Bool> {
            wrappedValue.contains(id)
        } set: { isIn in
            if isIn { wrappedValue.insert(id) } else { wrappedValue.remove(id) }
        }
    }
}
