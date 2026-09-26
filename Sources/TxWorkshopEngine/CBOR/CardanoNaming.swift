import SwiftCDDL

/// What the ledger calls the fields of a transaction, by where they sit in
/// its CBOR (the era CDDL schemas). Used only when the bytes have a
/// transaction's shape: an array of three or four items whose first is a map.
struct CardanoNaming {
    /// The number of items in the transaction array, or `nil` when the bytes
    /// are not a transaction.
    private let rootCount: Int?
    /// For each map, its unsigned-integer keys by the child index of the
    /// value they label.
    private let keys: [[Int]: [Int: UInt64]]

    init(root: CBORAnnotatedItem?, bytes: [UInt8]) {
        func majorType(_ item: CBORAnnotatedItem) -> UInt8? {
            bytes.indices.contains(item.span.start) ? bytes[item.span.start] >> 5 : nil
        }
        // Read from the heads, so a transaction cut short is still named.
        guard let root, majorType(root) == 4, let count = DiagnosticWriter.argument(bytes, root.span),
            (3...4).contains(count), let body = root.children.first, majorType(body) == 5
        else {
            rootCount = nil
            keys = [:]
            return
        }
        rootCount = Int(count)
        var keys: [[Int]: [Int: UInt64]] = [:]
        root.walk { path, item in
            guard majorType(item) == 5 else { return }
            var map: [Int: UInt64] = [:]
            for index in stride(from: 0, to: item.children.count - 1, by: 2) {
                if case .unsigned(let key)? = item.children[index].node { map[index + 1] = key }
            }
            keys[path] = map
        }
        self.keys = keys
    }

    static let body: [UInt64: String] = [
        0: "inputs", 1: "outputs", 2: "fee", 3: "time to live", 4: "certificates", 5: "withdrawals",
        6: "update", 7: "auxiliary data hash", 8: "validity start", 9: "mint", 11: "script data hash",
        13: "collateral inputs", 14: "required signers", 15: "network id", 16: "collateral return",
        17: "total collateral", 18: "reference inputs", 19: "voting procedures", 20: "proposal procedures",
        21: "current treasury value", 22: "donation",
    ]
    static let witnesses: [UInt64: String] = [
        0: "vkey witnesses", 1: "native scripts", 2: "bootstrap witnesses", 3: "Plutus V1 scripts",
        4: "Plutus data", 5: "redeemers", 6: "Plutus V2 scripts", 7: "Plutus V3 scripts",
    ]
    static let output: [UInt64: String] = [0: "address", 1: "amount", 2: "datum option", 3: "script reference"]
    /// A legacy output, written as an array.
    static let legacyOutput = ["address", "amount", "datum hash"]

    func name(at path: [Int]) -> String? {
        guard let rootCount, let last = path.last else { return nil }
        if path.count == 1 {
            // Shelley to Mary transactions have no is-valid flag.
            let names = rootCount == 3
                ? ["transaction body", "witness set", "auxiliary data"]
                : ["transaction body", "witness set", "is valid", "auxiliary data"]
            return names.indices.contains(last) ? names[last] : nil
        }
        let parent = Array(path.dropLast())
        if parent == [0] { return keys[parent]?[last].flatMap { Self.body[$0] } }
        if parent == [1] { return keys[parent]?[last].flatMap { Self.witnesses[$0] } }
        if parent.count == 2, parent[0] == 0 {
            switch bodyKey(parent[1]) {
            case 1: return "output \(last)"
            case 16: return outputField(parent, last)
            default: return nil
            }
        }
        if parent.count == 3, parent[0] == 0, bodyKey(parent[1]) == 1 {
            return outputField(parent, last)
        }
        return nil
    }

    /// A field of the output at `output`: by key in a map output, by position
    /// in a legacy array output.
    private func outputField(_ output: [Int], _ index: Int) -> String? {
        if let map = keys[output] { return map[index].flatMap { Self.output[$0] } }
        return Self.legacyOutput.indices.contains(index) ? Self.legacyOutput[index] : nil
    }

    private func bodyKey(_ index: Int) -> UInt64? { keys[[0]]?[index] }
}
