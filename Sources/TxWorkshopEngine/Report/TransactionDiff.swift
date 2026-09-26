import Foundation

/// What changed from one transaction to another.
public struct TransactionDiff: Sendable, Equatable {
    public enum Relation: Sendable, Equatable {
        /// Everything the inspector reads is the same.
        case identical
        /// The same body, and so the same id; only the witnesses differ, as
        /// between an unsigned transaction and its signed copy.
        case sameBody
        /// Different transactions.
        case different
    }

    public struct Change: Sendable, Equatable, Identifiable {
        public let section: TransactionFact.Section
        public let key: String
        public let label: String
        /// The value before, or `nil` if the fact is new.
        public let old: String?
        /// The value after, or `nil` if the fact is gone.
        public let new: String?
        public var id: String { "\(section.rawValue)/\(key)" }
    }

    public let relation: Relation
    /// In section order, then the order the facts appear in.
    public let changes: [Change]
    /// The changes by section, in section order; sections without changes
    /// are left out.
    public let sections: [(section: TransactionFact.Section, changes: [Change])]

    public static func == (lhs: TransactionDiff, rhs: TransactionDiff) -> Bool {
        lhs.relation == rhs.relation && lhs.changes == rhs.changes
    }

    public init(from old: TransactionInspection, to new: TransactionInspection) {
        let before = old.facts
        let after = new.facts
        let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var changes: [Change] = []
        var seen = Set<String>()
        for fact in before + after where seen.insert(fact.id).inserted {
            let was = beforeByID[fact.id]?.value
            let now = afterByID[fact.id]?.value
            guard was != now else { continue }
            changes.append(Change(section: fact.section, key: fact.key, label: fact.label, old: was, new: now))
        }
        let order = Dictionary(uniqueKeysWithValues: TransactionFact.Section.allCases.enumerated().map { ($1, $0) })
        self.changes = changes.enumerated()
            .sorted { (order[$0.element.section]!, $0.offset) < (order[$1.element.section]!, $1.offset) }
            .map(\.element)
        let grouped = Dictionary(grouping: self.changes, by: \.section)
        self.sections = TransactionFact.Section.allCases.compactMap { section in
            grouped[section].map { (section, $0) }
        }

        if changes.isEmpty {
            relation = .identical
        } else if old.summary.id == new.summary.id {
            relation = .sameBody
        } else {
            relation = .different
        }
    }
}

private func < (lhs: (Int, Int), rhs: (Int, Int)) -> Bool {
    lhs.0 != rhs.0 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
}
