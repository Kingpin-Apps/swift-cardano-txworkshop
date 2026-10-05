import Foundation

/// Rewrites a transaction so hardware wallets can sign it (CIP-21), as far as
/// that can be done without changing what it does: the body in canonical
/// CBOR, with empty optional collections left out and sets tagged one way
/// throughout. Datums, scripts and metadata are written as they were, so
/// their hashes still hold. A new body is a new transaction id, so its
/// signatures are dropped; it must be signed again.
public enum CIP21Transform {
    public struct Result: Sendable, Equatable {
        public let bytes: Data
        /// What changed, in words.
        public let changes: [String]
        /// Signatures dropped because the body changed.
        public let droppedSignatures: Int
        /// What is still in the way: what a rewrite cannot fix.
        public let remaining: [CIP21Finding]
        public var changed: Bool { !changes.isEmpty }
    }

    public static func compatible(_ bytes: Data) throws -> Result {
        let before = try CIP21Check.report(bytes)
        let transaction = try RawCBOR.read(bytes)
        guard var parts = transaction.array, parts.count >= 2, var body = Optional(parts[0]), body.entries != nil else {
            throw RawCBOR.ReadError(description: "That is not a transaction.")
        }
        var changes: [String] = []

        // Empty optional collections out.
        if case .map(var entries) = body.kind {
            let emptied = entries.filter { entry in
                guard let key = entry.key.unsigned, CIP21Check.optionalCollections[key] != nil else { return false }
                return (entry.value.array?.isEmpty ?? false) || (entry.value.entries?.isEmpty ?? false)
            }
            if !emptied.isEmpty {
                entries.removeAll { entry in emptied.contains { $0.key == entry.key } }
                changes.append("Left out empty " + emptied.compactMap { $0.key.unsigned.flatMap { CIP21Check.fieldNames[$0] } }.joined(separator: ", ") + ".")
                body.kind = .map(entries)
            }
        }

        // Sets tagged one way: with 258 throughout if any already are.
        if before.findings.contains(where: { $0.rule == "set-tags" }) {
            body = tagSets(body)
            changes.append("Tagged every set with 258.")
        }

        let canonicalBody = body.canonical()
        let originalBody = Data(bytes[parts[0].range])
        if before.fixable.contains(where: { $0.rule.hasPrefix("canonical") }) {
            changes.append("Wrote the body in canonical CBOR: shortest lengths, definite lengths, sorted map keys.")
        }
        guard canonicalBody != originalBody else {
            return Result(bytes: bytes, changes: [], droppedSignatures: 0, remaining: before.findings)
        }

        // The witness set as it was, less the signatures over the old body.
        var dropped = 0
        var witnessBytes = Data(bytes[parts[1].range])
        if let entries = parts[1].entries {
            let kept = entries.filter { entry in
                let signs = entry.key.unsigned == 0 || entry.key.unsigned == 2
                if signs { dropped += entry.value.array?.count ?? 0 }
                return !signs
            }
            if dropped > 0 {
                witnessBytes = Data()
                RawCBOR.head(5, UInt64(kept.count), into: &witnessBytes)
                for entry in kept {
                    witnessBytes += bytes[entry.key.range]
                    witnessBytes += bytes[entry.value.range]
                }
            }
        }

        var rebuilt = Data()
        RawCBOR.head(4, UInt64(parts.count), into: &rebuilt)
        rebuilt += canonicalBody
        rebuilt += witnessBytes
        for part in parts.dropFirst(2) { rebuilt += bytes[part.range] }
        parts.removeAll()

        let after = try CIP21Check.report(rebuilt)
        return Result(bytes: rebuilt, changes: changes, droppedSignatures: dropped, remaining: after.findings)
    }

    /// Every non-empty set in the body wrapped in tag 258.
    static func tagSets(_ body: RawCBOR) -> RawCBOR {
        guard case .map(var entries) = body.kind else { return body }
        func tagged(_ item: RawCBOR) -> RawCBOR {
            if case .array(let items) = item.kind, !items.isEmpty {
                return RawCBOR(kind: .tag(258, item), range: item.range)
            }
            return item
        }
        for index in entries.indices {
            guard let key = entries[index].key.unsigned else { continue }
            if CIP21Check.setFields.contains(key) { entries[index].value = tagged(entries[index].value) }
            if key == 4, let certificates = entries[index].value.array {
                let rewritten = certificates.map { certificate -> RawCBOR in
                    guard case .array(var fields) = certificate.kind, fields.first?.unsigned == 3, fields.count > 7 else { return certificate }
                    fields[7] = tagged(fields[7])
                    return RawCBOR(kind: .array(fields), range: certificate.range)
                }
                let list = RawCBOR(kind: .array(rewritten), range: entries[index].value.range)
                entries[index].value = entries[index].value.isTaggedSet ? RawCBOR(kind: .tag(258, list), range: list.range) : tagged(list)
            }
        }
        return RawCBOR(kind: .map(entries), range: body.range)
    }
}
