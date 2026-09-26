import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator

/// The ledger state validation reads beyond UTxOs, as saved in a document's
/// chain snapshot (``TxWorkshopCore/ChainContextSnapshot/ledgerState``).
struct LedgerState: Codable, Sendable {
    var accountContexts: [AccountInputContext] = []
    var poolContexts: [PoolInputContext] = []
    var drepContexts: [DRepInputContext] = []
    var govActionContexts: [GovActionInputContext] = []
    var lastEnactedGovAction: [GovActionInputContext] = []
    var currentCommitteeMembers: [CommitteeInputContext] = []
    var potentialCommitteeMembers: [CommitteeInputContext] = []
    var treasuryValue: UInt64?
    var currentEpoch: UInt64?
    /// The era's name, e.g. `conway`.
    var era: String?

    init(_ context: ValidationContext) {
        accountContexts = context.accountContexts
        poolContexts = context.poolContexts
        drepContexts = context.drepContexts
        govActionContexts = context.govActionContexts
        lastEnactedGovAction = context.lastEnactedGovAction
        currentCommitteeMembers = context.currentCommitteeMembers
        potentialCommitteeMembers = context.potentialCommitteeMembers
        treasuryValue = context.treasuryValue
        currentEpoch = context.currentEpoch
        era = context.era?.rawValue
    }

    init() {}

    static func decode(_ data: Data?) -> LedgerState {
        data.flatMap { try? JSONDecoder().decode(LedgerState.self, from: $0) } ?? LedgerState()
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
