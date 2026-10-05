import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// What a document's chain snapshot says, readably: the tip, the epoch and
/// era, and the protocol parameters that matter most when building and
/// validating.
public struct ChainSummary: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let name: String
        public let value: String
        public var id: String { name }
    }

    public let fetchedAt: Date
    public let tipSlot: UInt64?
    public let epoch: UInt64?
    public let era: String?
    /// `10.0`
    public let protocolVersion: String?
    /// Fees, limits, deposits and prices, in that order.
    public let parameters: [Row]
    /// How many cost model entries each Plutus version has; empty versions are left out.
    public let costModels: [Row]
    /// Every parameter, as pretty-printed JSON.
    public let parametersJSON: String
    /// How many UTxOs the snapshot holds.
    public let utxoCount: Int

    public init(_ snapshot: ChainContextSnapshot) {
        let ledger = LedgerState.decode(snapshot.ledgerState)
        fetchedAt = snapshot.fetchedAt
        tipSlot = snapshot.tipSlot
        epoch = ledger.currentEpoch
        era = ledger.era
        utxoCount = snapshot.utxos.count
        parametersJSON = ManualChainData.protocolParametersText(snapshot.protocolParameters)
        guard let p = TransactionValidation.protocolParameters(snapshot) else {
            protocolVersion = nil
            parameters = []
            costModels = []
            return
        }
        protocolVersion = "\(p.protocolVersion.major).\(p.protocolVersion.minor)"
        func ada(_ lovelace: Int64) -> String { Self.ada(lovelace) }
        func number(_ value: Int64) -> String { value.formatted() }
        var rows: [Row] = [
            Row(name: "Fee per byte", value: "\(number(p.txFeePerByte)) lovelace"),
            Row(name: "Fixed fee", value: "\(number(p.txFeeFixed)) lovelace"),
            Row(name: "Max transaction size", value: "\(number(p.maxTxSize)) bytes"),
            Row(name: "Max execution units per transaction", value: "\(number(p.maxTxExecutionUnits.memory)) memory · \(number(p.maxTxExecutionUnits.steps)) steps"),
            Row(name: "Execution prices", value: "\(p.executionUnitPrices.priceMemory) per memory · \(p.executionUnitPrices.priceSteps) per step"),
            Row(name: "Max value size", value: "\(number(p.maxValueSize)) bytes"),
            Row(name: "Coins per UTxO byte", value: "\(number(p.utxoCostPerByte)) lovelace"),
            Row(name: "Collateral", value: "\(p.collateralPercentage)% · at most \(p.maxCollateralInputs) inputs"),
            Row(name: "Stake address deposit", value: ada(p.stakeAddressDeposit)),
            Row(name: "Pool deposit", value: ada(p.stakePoolDeposit)),
            Row(name: "Minimum pool cost", value: ada(p.minPoolCost)),
            Row(name: "DRep deposit", value: ada(p.dRepDeposit)),
            Row(name: "Governance action deposit", value: ada(p.govActionDeposit)),
            Row(name: "Pool retirement", value: "at most \(p.poolRetireMaxEpoch) epochs ahead"),
        ]
        if let perByte = p.minFeeRefScriptCostPerByte {
            rows.insert(Row(name: "Reference script fee", value: "\(number(perByte)) lovelace per byte"), at: 2)
        }
        parameters = rows
        costModels = [
            ("Plutus V1", p.costModels.PlutusV1), ("Plutus V2", p.costModels.PlutusV2), ("Plutus V3", p.costModels.PlutusV3),
        ].filter { !$0.1.isEmpty }.map { Row(name: $0.0, value: "\($0.1.count) entries") }
    }

    static func ada(_ lovelace: Int64) -> String {
        let value = Decimal(lovelace) / 1_000_000
        return "₳ \(value.formatted())"
    }
}
