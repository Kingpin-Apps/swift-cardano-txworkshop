import Foundation
import SwiftCDDL
import SwiftCDDLCardano

/// Checks CBOR against the ledger's CDDL schema for an era, and links each
/// mismatch to the item it is about.
public struct SchemaCheck: Sendable {
    public init() {}

    /// The eras there are schemas for, oldest first.
    public static let eras: [String] = CardanoEra.allCases.map(\.rawValue)

    /// The latest era `possibleEras` (as a transaction summary gives it, e.g.
    /// `babbage…conway`) names, or Conway.
    public static func defaultEra(possibleEras: String) -> String {
        let text = possibleEras.lowercased()
        return CardanoEra.allCases.last { text.contains($0.rawValue) }?.rawValue ?? CardanoEra.conway.rawValue
    }

    /// The names of `era`'s rules, sorted, without duplicates.
    public func ruleNames(era: String) throws -> [String] {
        let document = try CardanoSchemas.document(for: Self.era(era))
        return Array(Set(document.rules.map { $0.ruleName.description })).sorted()
    }

    /// Checks a whole transaction against `era`'s `transaction` rule. Issues
    /// the ledger accepts anyway (long Plutus byte strings written in 64-byte
    /// chunks) are marked.
    public func checkTransaction(_ bytes: Data, era: String) async throws -> SchemaReport {
        let result = try await CardanoSchemas.validate(transaction: bytes, era: Self.era(era))
        return SchemaReport(rule: "transaction", era: era, issues: result.issues.map { issue in
            SchemaIssue(
                location: issue.issue.path, reason: issue.issue.reason, kind: SchemaIssue.Kind(issue.issue.kind),
                ledgerAccepts: issue.isLedgerAccepted, itemPath: issue.itemPath
            )
        })
    }

    /// Checks the item at `path`, whose bytes are `range` of `bytes`, against
    /// `rule` of `era`'s schema. Issue locations are linked to items under
    /// `path`.
    public func check(_ bytes: Data, range: Range<Int>, path: [Int], rule: String, era: String) async throws -> SchemaReport {
        let document = try CardanoSchemas.document(for: Self.era(era))
        let slice = Data(bytes.dropFirst(range.lowerBound).prefix(range.count))
        let result = await document.validate(cbor: slice, rule: rule)
        let decoding = CBORNode.decodeAnnotated(slice)
        return SchemaReport(rule: rule, era: era, issues: result.issues.map { issue in
            SchemaIssue(
                location: issue.path, reason: issue.reason, kind: SchemaIssue.Kind(issue.kind), ledgerAccepts: false,
                itemPath: decoding.root?.path(forIssuePath: issue.path).map { path + $0 }
            )
        })
    }

    static func era(_ name: String) throws -> CardanoEra {
        guard let era = CardanoEra(rawValue: name) else { throw SchemaCheckError.unknownEra(name) }
        return era
    }
}

public enum SchemaCheckError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownEra(String)

    public var description: String {
        switch self {
        case .unknownEra(let name): "There is no schema for the \(name) era."
        }
    }
}

/// The verdict of a schema check.
public struct SchemaReport: Sendable, Equatable {
    public let rule: String
    public let era: String
    public let issues: [SchemaIssue]

    /// Whether nothing the ledger would refuse was found.
    public var isValid: Bool { issues.allSatisfy(\.ledgerAccepts) }
}

/// One way the CBOR does not match the schema.
public struct SchemaIssue: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case mismatch, malformedDocument, invalidSchema, unsupported

        init(_ kind: ValidationIssue.Kind) {
            switch kind {
            case .mismatch: self = .mismatch
            case .malformedDocument: self = .malformedDocument
            case .invalidSchema: self = .invalidSchema
            case .unsupported: self = .unsupported
            }
        }
    }

    /// Where the item is, as the validator writes it: `/0/2`, empty for the
    /// root.
    public let location: String
    public let reason: String
    public let kind: Kind
    /// Whether the ledger accepts it although the schema does not.
    public let ledgerAccepts: Bool
    /// The item's path in the explorer's tree, when it could be found.
    public let itemPath: [Int]?

    public var id: String { "\(location)|\(reason)" }
}
