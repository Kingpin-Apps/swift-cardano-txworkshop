import Foundation
import SwiftCDDL
import SwiftCDDLCardano

/// A CDDL schema's text, parsed: its rules with where they are written and
/// which rules each one uses, or why the text does not parse.
public struct CDDLSource: Sendable {
    public let text: String
    public let rules: [Rule]
    public let problem: Problem?
    let document: CDDLDocument?

    public struct Rule: Sendable, Equatable, Identifiable {
        public let name: String
        /// 1-based.
        public let line: Int
        /// The rules this one names, in the order it first names them.
        public let uses: [String]
        /// Whether it extends an earlier rule of the same name (`/=`, `//=`).
        public let isAlternate: Bool
        public var id: String { "\(name)@\(line)" }
    }

    public struct Problem: Sendable, Equatable {
        public let line: Int
        public let column: Int
        public let message: String
    }

    /// The bundled schema for `era`.
    public static func bundled(era: String) throws -> String {
        guard let text = bundledTexts[era] else { throw SchemaCheckError.unknownEra(era) }
        return text
    }

    /// Every era's schema text, read once.
    private static let bundledTexts: [String: String] = Dictionary(uniqueKeysWithValues: CardanoEra.allCases.compactMap { era in
        (try? CardanoSchemas.source(for: era)).map { (era.rawValue, $0) }
    })

    /// Parses `text` off the caller's actor. A bundled era's schema comes
    /// from swift-cddl's cache.
    @concurrent
    public static func parse(_ text: String, bundledEra: String? = nil) async -> CDDLSource {
        if let bundledEra, let era = try? SchemaCheck.era(bundledEra), let document = try? CardanoSchemas.document(for: era) {
            return CDDLSource(text: text, document: document)
        }
        do {
            return CDDLSource(text: text, document: try CDDLDocument(text))
        } catch {
            return CDDLSource(text: text, problem: Problem(line: error.line, column: error.column, message: error.message))
        }
    }

    init(text: String, document: CDDLDocument) {
        self.text = text
        self.document = document
        problem = nil
        let bytes = Array(text.utf8)
        let names = Set(document.rules.map { $0.ruleName.description })
        rules = document.rules.map { rule in
            let name = rule.ruleName.description
            let span = rule.span
            let body = span.start < span.end && span.end <= bytes.count
                ? String(decoding: bytes[span.start..<span.end], as: UTF8.self) : ""
            var seen = Set<String>()
            let uses = Self.identifiers(in: body).filter { $0 != name && names.contains($0) && seen.insert($0).inserted }
            let alternate = rule.typeRule?.isTypeChoiceAlternate ?? rule.groupRule?.isGroupChoiceAlternate ?? false
            return Rule(name: name, line: span.line, uses: uses, isAlternate: alternate)
        }
    }

    init(text: String, problem: Problem) {
        self.text = text
        self.document = nil
        self.problem = problem
        rules = []
    }

    /// The rules that name `name`.
    public func usedBy(_ name: String) -> [Rule] {
        rules.filter { $0.uses.contains(name) }
    }

    /// The first rule written for `name`.
    public func definition(of name: String) -> Rule? {
        rules.first { $0.name == name }
    }

    /// The schema written out the formatter's way, with comments kept.
    public var formatted: String? { document?.formatted() }

    /// CDDL identifiers in `text` (RFC 8610 Section 3.1): a letter, `@`, `_`
    /// or `$` first, then those, digits, `-` and `.`; comments skipped.
    static func identifiers(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inComment = false
        var inString = false
        func flush() {
            // An identifier cannot end in "-" or ".".
            while let last = current.last, last == "-" || last == "." { current.removeLast() }
            if !current.isEmpty { out.append(current) }
            current = ""
        }
        for character in text {
            if inComment {
                if character == "\n" { inComment = false }
                continue
            }
            if inString {
                if character == "\"" { inString = false }
                continue
            }
            if character == ";" { flush(); inComment = true; continue }
            if character == "\"" { flush(); inString = true; continue }
            let isStart = character.isLetter || character == "@" || character == "_" || character == "$"
            if current.isEmpty {
                if isStart { current.append(character) }
            } else if isStart || character.isNumber || character == "-" || character == "." {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return out
    }
}

extension SchemaCheck {
    /// Checks the item at `path` (bytes `range` of `bytes`) against `rule` of
    /// a parsed schema, such as a document's own.
    public func check(_ bytes: Data, range: Range<Int>, path: [Int], rule: String, schema: CDDLSource) async throws -> SchemaReport {
        guard let document = schema.document else { throw SchemaCheckError.schemaDoesNotParse }
        let slice = Data(bytes.dropFirst(range.lowerBound).prefix(range.count))
        let result = await document.validate(cbor: slice, rule: rule)
        let decoding = CBORNode.decodeAnnotated(slice)
        return SchemaReport(rule: rule, era: "custom", issues: result.issues.map { issue in
            SchemaIssue(
                location: issue.path, reason: issue.reason, kind: SchemaIssue.Kind(issue.kind), ledgerAccepts: false,
                itemPath: decoding.root?.path(forIssuePath: issue.path).map { path + $0 }
            )
        })
    }
}
