import Foundation
import OrderedCollections
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import TxWorkshopCore

extension TransactionComposer {
    /// What the recipe's certificates and proposals lock up and give back.
    struct Deposits {
        var paid: Int64 = 0
        var refunded: Int64 = 0
    }

    /// Adds the recipe's certificates, withdrawals, votes, proposals and
    /// treasury donation to `builder`.
    static func addGovernance(_ recipe: BuildRecipe, to builder: TxBuilder, parameters: ProtocolParameters) throws -> Deposits {
        var deposits = Deposits()
        let stakeDeposit = parameters.stakeAddressDeposit
        let drepDeposit = parameters.dRepDeposit

        var certificates: [Certificate] = []
        for item in recipe.certificates {
            switch item.certificate {
            case .registerStake(let address):
                certificates.append(.register(Register(stakeCredential: try stakeCredential(address), coin: Coin(stakeDeposit))))
                deposits.paid += stakeDeposit
            case .deregisterStake(let address):
                certificates.append(.unregister(Unregister(stakeCredential: try stakeCredential(address), coin: Coin(stakeDeposit))))
                deposits.refunded += stakeDeposit
            case .delegateStake(let address, let pool):
                certificates.append(.stakeDelegation(StakeDelegation(stakeCredential: try stakeCredential(address), poolKeyHash: try poolKeyHash(pool))))
            case .delegateVote(let address, let drep):
                certificates.append(.voteDelegate(VoteDelegate(stakeCredential: try stakeCredential(address), drep: try Self.drep(drep))))
            case .registerDRep(let keyHash, let url, let hash):
                certificates.append(.registerDRep(RegisterDRep(
                    drepCredential: try drepCredential(keyHash), coin: Coin(drepDeposit), anchor: try anchor(url, hash)
                )))
                deposits.paid += drepDeposit
            case .unregisterDRep(let keyHash):
                certificates.append(.unRegisterDRep(UnregisterDRep(drepCredential: try drepCredential(keyHash), coin: Coin(drepDeposit))))
                deposits.refunded += drepDeposit
            case .updateDRep(let keyHash, let url, let hash):
                certificates.append(.updateDRep(UpdateDRep(drepCredential: try drepCredential(keyHash), anchor: try anchor(url, hash))))
            }
        }
        if !certificates.isEmpty { builder.certificates = certificates }

        if !recipe.withdrawals.isEmpty {
            var accounts = OrderedDictionary<RewardAccount, Coin>()
            for withdrawal in recipe.withdrawals {
                accounts[try rewardAccount(withdrawal.stakeAddress)] = Coin(withdrawal.lovelace)
            }
            builder.withdrawals = Withdrawals(accounts)
        }

        for vote in recipe.votes {
            let voter: VoterType = switch vote.voter {
            case .drep: .drepKeyhash(try keyHash(vote.voterID))
            case .committee: .constitutionalCommitteeHotKeyhash(try keyHash(vote.voterID))
            case .stakePool: .stakePoolKeyhash(VerificationKeyHash(payload: try poolKeyHash(vote.voterID).payload))
            }
            let choice: Vote = switch vote.choice {
            case .yes: .yes
            case .no: .no
            case .abstain: .abstain
            }
            do {
                try builder.addVote(
                    voter: Voter(credential: voter), govActionId: try govActionID(vote.action), vote: choice,
                    anchor: vote.anchorURL.isEmpty ? nil : try anchor(vote.anchorURL, vote.anchorHash)
                )
            } catch let error as ComposeError {
                throw error
            } catch {
                throw ComposeError.builder(String(describing: error))
            }
        }

        for proposal in recipe.proposals {
            let action: GovAction = switch proposal.kind {
            case .info:
                .infoAction(InfoAction())
            case .treasuryWithdrawal(let address, let lovelace):
                .treasuryWithdrawalsAction(TreasuryWithdrawalsAction(withdrawals: [try rewardAccount(address): Coin(lovelace)], policyHash: nil))
            }
            guard let proposalAnchor = try anchor(proposal.anchorURL, proposal.anchorHash) else {
                throw ComposeError.badGovernance("A proposal needs an anchor: its URL and the Blake2b-256 hash of its content.")
            }
            do {
                try builder.addProposal(
                    deposit: Int(parameters.govActionDeposit), rewardAccount: try rewardAccount(proposal.returnAddress),
                    govAction: action, anchor: proposalAnchor
                )
            } catch let error as ComposeError {
                throw error
            } catch {
                throw ComposeError.builder(String(describing: error))
            }
            deposits.paid += parameters.govActionDeposit
        }

        if let donation = recipe.donation, donation > 0 {
            do {
                try builder.addTreasuryDonation(Int(donation))
            } catch {
                throw ComposeError.builder(String(describing: error))
            }
        }
        return deposits
    }

    // MARK: Credentials and ids

    static func stakeAddress(_ text: String) throws -> Address {
        let address = try address(text)
        guard address.stakingPart != nil else { throw ComposeError.badGovernance("\(text) has no stake credential.") }
        return address
    }

    static func stakeCredential(_ text: String) throws -> StakeCredential {
        switch try stakeAddress(text).stakingPart {
        case .verificationKeyHash(let hash)?: StakeCredential(credential: .verificationKeyHash(hash))
        case .scriptHash(let hash)?: StakeCredential(credential: .scriptHash(hash))
        default: throw ComposeError.badGovernance("\(text) has no stake credential.")
        }
    }

    /// The reward account a stake address names, as the ledger writes it.
    static func rewardAccount(_ text: String) throws -> RewardAccount {
        let address = try stakeAddress(text)
        guard address.paymentPart == nil else {
            throw ComposeError.badGovernance("\(text) is a payment address; use its stake address (stake…).")
        }
        return address.toBytes()
    }

    static func keyHash(_ hex: String) throws -> VerificationKeyHash {
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), bytes.count == 28 else { throw ComposeError.badKeyHash(hex) }
        return VerificationKeyHash(payload: bytes)
    }

    static func drepCredential(_ hex: String) throws -> DRepCredential {
        DRepCredential(credential: .verificationKeyHash(try keyHash(hex)))
    }

    static func poolKeyHash(_ text: String) throws -> PoolKeyHash {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("pool") {
            guard let pool = try? PoolOperator(from: trimmed) else { throw ComposeError.badGovernance("\(text) is not a pool id.") }
            return pool.poolKeyHash
        }
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: trimmed), bytes.count == 28 else {
            throw ComposeError.badGovernance("\(text) is not a pool id.")
        }
        return PoolKeyHash(payload: bytes)
    }

    static func drep(_ text: String) throws -> DRep {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "abstain": return DRep(credential: .alwaysAbstain)
        case "no-confidence", "noconfidence": return DRep(credential: .alwaysNoConfidence)
        default:
            if trimmed.hasPrefix("drep") {
                guard let drep = try? DRep(from: trimmed) else { throw ComposeError.badGovernance("\(text) is not a DRep id.") }
                return drep
            }
            return DRep(credential: .verificationKeyHash(try keyHash(trimmed)))
        }
    }

    static func govActionID(_ text: String) throws -> GovActionID {
        let parts = text.split(separator: "#")
        guard parts.count == 2, let index = UInt16(parts[1]), let id = try? TxDocumentCodec.bytes(fromHex: String(parts[0])), id.count == 32 else {
            throw ComposeError.badGovernance("\(text) is not a governance action id (transaction id#index).")
        }
        return GovActionID(transactionID: TransactionId(payload: id), govActionIndex: index)
    }

    /// An anchor from its URL and hash; `nil` when both are empty.
    static func anchor(_ url: String, _ hash: String) throws -> Anchor? {
        let url = url.trimmingCharacters(in: .whitespaces)
        let hash = hash.trimmingCharacters(in: .whitespaces)
        if url.isEmpty, hash.isEmpty { return nil }
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hash), bytes.count == 32 else {
            throw ComposeError.badGovernance("An anchor hash is the 32-byte Blake2b-256 of the anchor's content, in hex.")
        }
        guard let anchorURL = try? Url(url) else { throw ComposeError.badGovernance("\(url) is not an anchor URL.") }
        return Anchor(anchorUrl: anchorURL, anchorDataHash: AnchorDataHash(payload: bytes))
    }
}
