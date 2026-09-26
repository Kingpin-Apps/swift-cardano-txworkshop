import TxWorkshopEngine

/// Where the latest validation's findings sit in the CBOR tree.
struct CBORMarkers: Equatable {
    /// Whether each marked item has an error (`true`) or only warnings.
    private var severity: [String: Bool] = [:]
    /// The items holding a marked item, so a collapsed branch shows it.
    private var containers: Set<String> = []
    /// Each marked item's bytes, with whether it has an error.
    private(set) var ranges: [(range: Range<Int>, isError: Bool)] = []
    /// The findings for each marked item.
    private var findings: [String: [ValidationFinding]] = [:]

    static let none = CBORMarkers()

    init() {}

    init(outcome: ValidationOutcome?, exploration: CBORExploration) {
        guard let outcome else { return }
        for finding in outcome.issues {
            guard let path = exploration.path(forFieldPath: finding.fieldPath) else { continue }
            let id = path.map(String.init).joined(separator: ".")
            severity[id] = (severity[id] ?? false) || !finding.isWarning
            findings[id, default: []].append(finding)
            containers.formUnion(CBORItem.ancestorIDs(of: path))
        }
        ranges = severity.compactMap { id, isError in
            exploration.item(at: CBORItem.path(fromID: id)).map { ($0.range, isError) }
        }
    }

    /// `true` for an error, `false` for warnings only, `nil` when unmarked.
    func mark(_ id: String) -> Bool? { severity[id] }
    func contains(_ id: String) -> Bool { containers.contains(id) }
    func findings(_ id: String) -> [ValidationFinding] { findings[id] ?? [] }

    static func == (lhs: CBORMarkers, rhs: CBORMarkers) -> Bool {
        lhs.severity == rhs.severity && lhs.containers == rhs.containers
    }
}
