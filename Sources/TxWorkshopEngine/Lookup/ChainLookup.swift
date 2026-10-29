import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import TxWorkshopCore

public enum ChainLookupError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What was entered is not a value of the kind asked for.
    case badValue(String)
    /// The provider could not answer; its reason.
    case failed(String)

    public var description: String {
        switch self {
        case .badValue(let reason): reason
        case .failed(let reason): "The provider could not answer. \(reason)"
        }
    }
}

/// Answers the questions the build form asks of the chain while a recipe is
/// filled in: the epoch a pool can retire at, what a stake address holds, and
/// whether a governance action is still open. The document's chain snapshot
/// answers what it can offline; the provider answers the rest.
public struct ChainLookup: Sendable {
    public typealias ContextMaker = TransactionFetcher.ContextMaker

    /// A stake address as the ledger sees it.
    public struct Account: Sendable, Equatable {
        public let stakeAddress: String
        public let isRegistered: Bool
        /// The reward balance, which a withdrawal must take whole.
        public let rewards: UInt64
        /// The `pool1…` id it delegates to.
        public let pool: String?
        /// The DRep id it delegates its votes to.
        public let drep: String?

        public init(stakeAddress: String, isRegistered: Bool, rewards: UInt64, pool: String? = nil, drep: String? = nil) {
            self.stakeAddress = stakeAddress
            self.isRegistered = isRegistered
            self.rewards = rewards
            self.pool = pool
            self.drep = drep
        }
    }

    /// The epochs a pool retiring now may name.
    public struct RetirementWindow: Sendable, Equatable {
        public let currentEpoch: UInt64
        /// The next epoch, the earliest a pool may retire at.
        public var earliest: UInt64 { currentEpoch + 1 }
        /// The furthest ahead the protocol parameters allow, when known.
        public let latest: UInt64?
    }

    /// A governance action, for the voter to see what they vote on.
    public struct GovernanceAction: Sendable, Equatable {
        public enum Status: Sendable, Equatable {
            case open
            case ratified, enacted, dropped, expired
        }

        /// What kind of action it is, e.g. "Treasury withdrawal".
        public let kind: String
        public let status: Status
        /// The last epoch it can be voted on.
        public let expiresAfter: UInt64?
    }

    /// A governance action open for votes, for choosing one to vote on.
    public struct OpenAction: Sendable, Equatable, Identifiable {
        /// The CIP-129 `gov_action1…` id, as the vote form takes it.
        public let id: String
        /// What kind of action it is, e.g. "Treasury withdrawal".
        public let kind: String
        /// The last epoch it can be voted on.
        public let expiresAfter: UInt64?
        /// Where its rationale is published.
        public let anchorURL: String?
    }

    private let makeContext: ContextMaker

    public init(makeContext: @escaping ContextMaker = { try await ChainContextFactory().makeContext(for: $0, apiKey: $1) }) {
        self.makeContext = makeContext
    }

    // MARK: Epochs

    /// The retirement window the snapshot's epoch and protocol parameters
    /// give, or nil when it has no epoch.
    public static func retirementWindow(_ snapshot: ChainContextSnapshot?) -> RetirementWindow? {
        guard let epoch = LedgerState.decode(snapshot?.ledgerState).currentEpoch else { return nil }
        return window(epoch: epoch, parameters: TransactionValidation.protocolParameters(snapshot))
    }

    /// The retirement window as the provider sees it now.
    public func retirementWindow(provider: ProviderConfiguration, apiKey: String?) async throws -> RetirementWindow {
        let chain = try await context(provider, apiKey)
        do {
            let epoch = try await chain.epoch()
            return Self.window(epoch: UInt64(max(epoch, 0)), parameters: try? await chain.protocolParameters())
        } catch {
            throw ChainLookupError.failed(String(describing: error))
        }
    }

    static func window(epoch: UInt64, parameters: ProtocolParameters?) -> RetirementWindow {
        let limit = parameters.map { UInt64(max($0.poolRetireMaxEpoch, 0)) }
        return RetirementWindow(currentEpoch: epoch, latest: limit.map { epoch + $0 })
    }

    // MARK: Stake addresses

    /// The stake address `text` names, read the way the form reads it.
    public static func stakeAddress(_ text: String, network: CardanoNetwork?) throws -> String {
        do {
            return try ValueReader.read(.stakeAddress, text: text, network: network).value
        } catch let error as ValueReadError {
            throw ChainLookupError.badValue(error.description)
        }
    }

    /// The account the snapshot's ledger state holds for `text`, if it was
    /// fetched for a transaction that touches it.
    public static func account(_ text: String, network: CardanoNetwork?, snapshot: ChainContextSnapshot?) -> Account? {
        guard let address = try? stakeAddress(text, network: network) else { return nil }
        let ledger = LedgerState.decode(snapshot?.ledgerState)
        guard let found = ledger.accountContexts.first(where: { $0.rewardAddress == address }), let balance = found.balance else {
            return nil
        }
        return Account(
            stakeAddress: address, isRegistered: found.isRegistered, rewards: UInt64(max(balance, 0)),
            pool: found.delegatedToPool, drep: found.delegatedToDRep
        )
    }

    /// The account the provider holds for `text`. An address the chain has
    /// never seen is unregistered, with no rewards.
    public func account(_ text: String, network: CardanoNetwork?, provider: ProviderConfiguration, apiKey: String?) async throws -> Account {
        let bech32 = try Self.stakeAddress(text, network: network)
        guard let address = try? Address(from: .string(bech32)) else { throw ChainLookupError.badValue("Not a stake address.") }
        let chain = try await context(provider, apiKey)
        let infos: [StakeAddressInfo]
        do {
            infos = try await chain.stakeAddressInfo(address: address)
        } catch {
            throw ChainLookupError.failed(String(describing: error))
        }
        guard let info = infos.first else { return Account(stakeAddress: bech32, isRegistered: false, rewards: 0) }
        return Account(
            stakeAddress: bech32, isRegistered: info.active ?? true, rewards: UInt64(max(info.rewardAccountBalance, 0)),
            pool: info.stakeDelegation.map(\.description), drep: info.voteDelegation.flatMap { try? $0.id() }
        )
    }

    // MARK: Governance actions

    /// The governance action `text` names, as the provider sees it.
    public func governanceAction(_ text: String, provider: ProviderConfiguration, apiKey: String?) async throws -> GovernanceAction {
        let id: GovActionID
        do {
            id = try TransactionComposer.govActionID(text)
        } catch {
            throw ChainLookupError.badValue(String(describing: error))
        }
        let chain = try await context(provider, apiKey)
        let info: GovActionInfo
        do {
            info = try await chain.govActionInfo(govActionID: id)
        } catch {
            throw ChainLookupError.failed(String(describing: error))
        }
        let status: GovernanceAction.Status = switch info.status {
        case .enacted?: .enacted
        case .ratified?: .ratified
        case .dropped?: .dropped
        case .expired?: .expired
        default: .open
        }
        return GovernanceAction(kind: Self.kind(of: info.govAction), status: status, expiresAfter: info.expiresAfter)
    }

    /// The governance actions open for votes, as the provider sees them. The
    /// provider is asked for these alone, without their votes.
    public func openGovernanceActions(provider: ProviderConfiguration, apiKey: String?) async throws -> [OpenAction] {
        let chain = try await context(provider, apiKey)
        let actions: [OpenGovAction]
        do {
            actions = try await chain.openGovActions()
        } catch {
            throw ChainLookupError.failed(String(describing: error))
        }
        return actions.map { action in
            OpenAction(
                id: (try? action.govActionId.id()) ?? "\(action.govActionId.transactionID.payload.toHex)#\(action.govActionId.govActionIndex)",
                kind: Self.kind(of: action.type),
                expiresAfter: action.expiresAfter,
                anchorURL: action.anchor?.anchorUrl.absoluteString
            )
        }
    }

    static func kind(of code: GovActionCode) -> String {
        switch code {
        case .parameterChangeAction: "Protocol parameter change"
        case .hardForkInitiationAction: "Hard fork"
        case .treasuryWithdrawalsAction: "Treasury withdrawal"
        case .noConfidence: "No confidence"
        case .updateCommittee: "Committee update"
        case .newConstitution: "New constitution"
        case .infoAction: "Info action"
        }
    }

    static func kind(of action: GovAction) -> String {
        let code: GovActionCode = switch action {
        case .parameterChangeAction: .parameterChangeAction
        case .hardForkInitiationAction: .hardForkInitiationAction
        case .treasuryWithdrawalsAction: .treasuryWithdrawalsAction
        case .noConfidence: .noConfidence
        case .updateCommittee: .updateCommittee
        case .newConstitution: .newConstitution
        case .infoAction: .infoAction
        }
        return kind(of: code)
    }

    private func context(_ provider: ProviderConfiguration, _ apiKey: String?) async throws -> any ChainContext {
        do {
            return try await makeContext(provider, apiKey)
        } catch {
            throw ChainLookupError.failed(String(describing: error))
        }
    }
}
