import Foundation

extension CBORExploration {
    /// Body map keys by the validator's field names.
    static let bodyKeys: [String: UInt64] = [
        "inputs": 0, "outputs": 1, "fee": 2, "ttl": 3, "certificates": 4, "withdrawals": 5, "update": 6,
        "auxiliary_data_hash": 7, "validity_start_interval": 8, "mint": 9, "script_data_hash": 11,
        "collateral": 13, "required_signers": 14, "network_id": 15, "collateral_return": 16,
        "total_collateral": 17, "reference_inputs": 18, "voting_procedures": 19, "proposal_procedures": 20,
        "current_treasury_amount": 21, "donation": 22,
    ]
    /// Witness set map keys by the validator's field names.
    static let witnessKeys: [String: UInt64] = [
        "vkeyWitnesses": 0, "nativeScripts": 1, "bootstrapWitness": 2, "plutusV1Scripts": 3,
        "plutusData": 4, "redeemers": 5, "plutusV2Scripts": 6, "plutusV3Scripts": 7,
    ]
    /// An output's fields, by map key or, for a legacy array output, by
    /// position.
    static let outputFields: [String: UInt64] = ["address": 0, "amount": 1, "datum": 2, "datum_hash": 2, "script_ref": 3]

    /// The tree path of the item a validator field path
    /// (`transaction_body.outputs[1].address`) is about: as deep as the
    /// path can be followed, so an unknown last step leads to its parent.
    /// `nil` when not even the first step is found.
    public func path(forFieldPath fieldPath: String) -> [Int]? {
        guard !entries.isEmpty else { return nil }
        var path: [Int] = []
        var index = 0
        var keys: [String: UInt64] = [:]
        var found = false

        for segment in Self.segments(fieldPath) {
            switch segment {
            case .name(let name):
                if path.isEmpty {
                    switch name {
                    case "transaction_body": keys = Self.bodyKeys; step(&path, &index, to: 0)
                    case "transaction_witness_set": keys = Self.witnessKeys; step(&path, &index, to: 1)
                    case "auxiliary_data": keys = [:]; step(&path, &index, to: 3)
                    default: return found ? path : nil
                    }
                    found = true
                    continue
                }
                guard let key = keys[name] else { return path }
                skipTags(&path, &index)
                if entries[index].isMap {
                    guard let value = mapValue(index, key: key) else { return path }
                    step(&path, &index, to: value)
                } else if entries[index].kind == .array, entries[index].children.indices.contains(Int(key)) {
                    step(&path, &index, to: Int(key))
                } else {
                    return path
                }
                keys = Self.outputFields
            case .index(let position):
                skipTags(&path, &index)
                let entry = entries[index]
                if entry.isMap {
                    // The nth entry of a map (redeemers in map form, withdrawals).
                    let value = position * 2 + 1
                    guard entry.children.indices.contains(value) else { return path }
                    step(&path, &index, to: value)
                } else {
                    guard entry.children.indices.contains(position) else { return path }
                    step(&path, &index, to: position)
                }
            }
        }
        return found ? path : nil
    }

    private enum Segment { case name(String), index(Int) }

    private static func segments(_ fieldPath: String) -> [Segment] {
        var out: [Segment] = []
        for part in fieldPath.split(separator: ".") {
            var name = Substring(part)
            var indexes: [Int] = []
            while let open = name.lastIndex(of: "["), name.last == "]" {
                if let value = Int(name[name.index(after: open)..<name.index(before: name.endIndex)]) { indexes.insert(value, at: 0) }
                name = name[..<open]
            }
            if !name.isEmpty { out.append(.name(String(name))) }
            out += indexes.map { .index($0) }
        }
        return out
    }

    private func step(_ path: inout [Int], _ index: inout Int, to child: Int) {
        guard entries[index].children.indices.contains(child) else { return }
        path.append(child)
        index = entries[index].children[child]
    }

    /// Steps through tags, such as the 258 that marks a set.
    private func skipTags(_ path: inout [Int], _ index: inout Int) {
        while case .tag = entries[index].kind, entries[index].children.count == 1 {
            step(&path, &index, to: 0)
        }
    }

    /// The child index of the value under unsigned `key` in the map at
    /// `index`.
    private func mapValue(_ index: Int, key: UInt64) -> Int? {
        let children = entries[index].children
        return stride(from: 0, to: children.count - 1, by: 2).first { entries[children[$0]].scalar == String(key) }.map { $0 + 1 }
    }
}
