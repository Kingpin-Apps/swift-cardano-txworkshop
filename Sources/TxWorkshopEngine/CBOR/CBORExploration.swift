import Foundation
import SwiftCDDL

/// Bytes decoded as CBOR for exploring: every item with where it was written,
/// how its encoding departs from the preferred serialization, and, when the
/// bytes break off, the items read up to there.
///
/// The decoded items are kept in a flat table rather than as nested values,
/// so data nested thousands of levels deep is freed without deep recursion.
public struct CBORExploration: Sendable, Identifiable {
    /// Unique to this decoding, so views keyed on it refresh when the bytes
    /// change even where an item's path does not.
    public let id = UUID()
    public let bytes: Data
    /// The outermost item, if one was begun. The tree stops at
    /// ``CBORItem/maxDepth``.
    public let root: CBORItem?
    /// Why decoding stopped early, and at which byte.
    public let problem: Problem?
    /// Every item, in the order written; the root is entry 0.
    let entries: [Entry]

    public struct Problem: Sendable, Equatable {
        public let message: String
        public let offset: Int?
    }

    struct Entry: Sendable {
        let start: Int
        let headerEnd: Int
        let end: Int
        let flags: [CBORItem.Flag]
        let kind: CBORItem.Kind
        let isComplete: Bool
        /// The full diagnostic notation of a scalar.
        let scalar: String?
        let stringLength: Int?
        /// Indexes into ``CBORExploration/entries``, in encoding order.
        var children: [Int] = []

        var range: Range<Int> { start..<end }
        /// Major type 5.
        var isMap: Bool { kind == .map }
    }

    /// Explores `bytes` off the caller's actor, on a thread with a stack deep
    /// enough for data nested thousands of levels.
    @concurrent
    public static func explore(_ bytes: Data) async -> CBORExploration {
        await DeepStack.run { CBORExploration(bytes: bytes) }
    }

    /// Decodes `bytes` on the calling thread. Freeing swift-cddl's annotated
    /// tree recurses once per level, so call this only on a deep stack for
    /// untrusted input; ``explore(_:)`` does.
    init(bytes: Data) {
        self.bytes = bytes
        let raw = [UInt8](bytes)
        let decoding = CBORNode.decodeAnnotated(raw)
        problem = decoding.error.map { Problem(message: String(describing: $0), offset: decoding.errorOffset) }
        entries = decoding.root.map { Self.flatten($0, bytes: raw) } ?? []
        let naming = CardanoNaming(root: decoding.root, bytes: raw)
        root = entries.isEmpty ? nil : CBORItem(entries: entries, index: 0, path: [], label: nil, naming: naming)
    }

    private static func flatten(_ root: CBORAnnotatedItem, bytes: [UInt8]) -> [Entry] {
        var entries: [Entry] = []
        // Items still to add, each with the entry of its parent.
        var pending: [(item: CBORAnnotatedItem, parent: Int?)] = [(root, nil)]
        while let (item, parent) = pending.popLast() {
            let index = entries.count
            entries.append(Entry(
                start: item.span.start, headerEnd: item.span.headerEnd, end: item.span.end,
                flags: CBORItem.Flag.allCases.filter { item.flags.contains($0.option) },
                kind: CBORItem.kind(of: item, bytes: bytes),
                isComplete: item.isComplete,
                scalar: DiagnosticWriter.scalar(item),
                stringLength: CBORItem.stringLength(item)
            ))
            if let parent { entries[parent].children.append(index) }
            for child in item.children.reversed() { pending.append((child, index)) }
        }
        return entries
    }

    /// The entry at `path`.
    func entry(at path: [Int]) -> Int? {
        guard !entries.isEmpty else { return nil }
        var index = 0
        for step in path {
            guard entries[index].children.indices.contains(step) else { return nil }
            index = entries[index].children[step]
        }
        return index
    }

    /// The path of the innermost item the byte at `offset` belongs to. A map
    /// key's bytes lead to its entry's value, which is where the tree shows
    /// the pair.
    public func path(toByte offset: Int) -> [Int]? {
        guard let first = entries.first, first.range.contains(offset) else { return nil }
        var path: [Int] = []
        var index = 0
        while let step = entries[index].children.firstIndex(where: { entries[$0].range.contains(offset) }) {
            if entries[index].isMap, step.isMultiple(of: 2), entries[index].children.indices.contains(step + 1) {
                return path + [step + 1]
            }
            path.append(step)
            index = entries[index].children[step]
        }
        return path
    }

    /// The item at `path`, if the tree goes that deep.
    public func item(at path: [Int]) -> CBORItem? {
        var item = root
        for index in path {
            item = item?.children?.first { $0.path.last == index }
        }
        return item
    }

    /// The item as CBOR diagnostic notation (RFC 8949 Section 8).
    func diagnostic(at path: [Int], limit: Int = 200_000) -> String? {
        guard let index = entry(at: path) else { return nil }
        var writer = DiagnosticWriter(entries: entries, limit: limit)
        writer.write(index, indent: 0)
        return writer.finish()
    }

    /// The item's diagnostic notation, written off the caller's actor on a
    /// deep stack.
    @concurrent
    public func diagnosticText(at path: [Int], limit: Int = 200_000) async -> String? {
        await DeepStack.run { diagnostic(at: path, limit: limit) }
    }
}

/// One item in the explorer's tree. A map's entries are shown as their values,
/// labelled with the key.
public struct CBORItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case unsigned, negative, bytes, text, array, map, tag(UInt64), float, simple, bool, null, undefined
    }

    public enum Flag: String, Sendable, Equatable, CaseIterable {
        case overlongHead, indefiniteLength, nonPreferredFloat, unsortedMapKeys, duplicateMapKeys, duplicateKey
    }

    public var id: String { path.map(String.init).joined(separator: ".") }
    /// Child indexes from the root, as the encoding orders them.
    public let path: [Int]
    /// The map key or array index this item sits at.
    public let label: String?
    /// What the Cardano ledger calls the item, when the bytes are a
    /// transaction.
    public let name: String?
    public let kind: Kind
    /// Items in an array, entries in a map, bytes in a string; `nil` for
    /// other kinds.
    public let count: Int?
    /// The item's value in diagnostic notation, shortened, for scalars.
    public let preview: String?
    public let start: Int
    public let headerEnd: Int
    public let end: Int
    /// The span of the map key, for an entry's value.
    public let keyRange: Range<Int>?
    public let flags: [Flag]
    public let isComplete: Bool
    /// `nil` for scalars, so an outline shows no disclosure for them, and
    /// for items at ``maxDepth``.
    public let children: [CBORItem]?
    /// Whether the item has children the tree leaves out because it is
    /// nested ``maxDepth`` deep; its diagnostic notation shows them.
    public let childrenOmitted: Bool

    /// How deep the tree goes. Deeper data is rare on chain.
    public static let maxDepth = 256

    public var range: Range<Int> { start..<end }
    public var headerRange: Range<Int> { start..<headerEnd }
    public var byteCount: Int { end - start }

    init(
        entries: [CBORExploration.Entry], index: Int, path: [Int], label: String?,
        keyRange: Range<Int>? = nil, naming: CardanoNaming
    ) {
        let entry = entries[index]
        self.path = path
        self.label = label
        name = naming.name(at: path)
        kind = entry.kind
        start = entry.start
        headerEnd = entry.headerEnd
        end = entry.end
        self.keyRange = keyRange
        flags = entry.flags
        isComplete = entry.isComplete
        childrenOmitted = path.count >= Self.maxDepth && !entry.children.isEmpty
        let short = DiagnosticWriter.short(entry)

        func child(_ step: Int, label: String?, keyRange: Range<Int>? = nil) -> CBORItem {
            CBORItem(entries: entries, index: entry.children[step], path: path + [step], label: label, keyRange: keyRange, naming: naming)
        }

        if childrenOmitted {
            count = entry.kind == .map ? entry.children.count / 2 : entry.children.count
            children = nil
            preview = short
            return
        }
        switch entry.kind {
        case .array:
            count = entry.children.count
            children = entry.children.indices.map { child($0, label: "[\($0)]") }
            preview = nil
        case .map:
            count = entry.children.count / 2
            children = stride(from: 0, to: entry.children.count, by: 2).map { step in
                let key = entries[entry.children[step]]
                let keyText = DiagnosticWriter.short(key)
                guard step + 1 < entry.children.count else {
                    // The bytes broke off after the key.
                    return child(step, label: "key \(keyText)")
                }
                return child(step + 1, label: keyText, keyRange: key.range)
            }
            preview = nil
        case .tag:
            count = nil
            children = entry.children.indices.map { child($0, label: nil) }
            preview = nil
        case .bytes, .text:
            count = entry.stringLength
            // The chunks of an indefinite-length string are its children.
            children = entry.children.isEmpty ? nil : entry.children.indices.map { child($0, label: "chunk \($0)") }
            preview = short
        default:
            count = nil
            children = nil
            preview = short
        }
    }

    static func kind(of item: CBORAnnotatedItem, bytes: [UInt8]) -> Kind {
        switch item.node {
        case .unsigned?: return .unsigned
        case .negative?: return .negative
        case .byteString?: return .bytes
        case .textString?: return .text
        case .array?: return .array
        case .map?: return .map
        case .tagged(let tagged)?: return .tag(tagged.tag)
        case .float?: return .float
        case .simple?: return .simple
        case .bool?: return .bool
        case .null?: return .null
        case .undefined?: return .undefined
        case nil:
            // Incomplete: read the major type from the head.
            guard bytes.indices.contains(item.span.start) else { return .undefined }
            switch bytes[item.span.start] >> 5 {
            case 0: return .unsigned
            case 1: return .negative
            case 2: return .bytes
            case 3: return .text
            case 4: return .array
            case 5: return .map
            case 6: return .tag(DiagnosticWriter.argument(bytes, item.span) ?? 0)
            default: return .simple
            }
        }
    }

    static func stringLength(_ item: CBORAnnotatedItem) -> Int? {
        switch item.node {
        case .byteString(let bytes, _)?: bytes.count
        case .textString(let text, _)?: text.utf8.count
        default: nil
        }
    }
}

extension CBORItem.Flag {
    var option: CBORNonCanonicalFlags {
        switch self {
        case .overlongHead: .overlongHead
        case .indefiniteLength: .indefiniteLength
        case .nonPreferredFloat: .nonPreferredFloat
        case .unsortedMapKeys: .unsortedMapKeys
        case .duplicateMapKeys: .duplicateMapKeys
        case .duplicateKey: .duplicateKey
        }
    }
}
