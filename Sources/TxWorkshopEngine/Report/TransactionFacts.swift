import Foundation
import SwiftCardanoTxValidator
import TxWorkshopCore

/// One thing a transaction says, keyed so the same thing can be found in
/// another transaction. Diffs compare facts; reports list them.
public struct TransactionFact: Sendable, Equatable, Identifiable {
    public enum Section: String, Sendable, CaseIterable, Codable {
        case transaction, inputs, referenceInputs, collateral, outputs, mint, withdrawals
        case certificates, votes, proposals, scripts, redeemers, datums, metadata, witnesses
    }

    public let section: Section
    /// Unique within the section.
    public let key: String
    public let label: String
    public let value: String
    public var id: String { "\(section.rawValue)/\(key)" }
}

extension TransactionInspection {
    /// Everything the inspection shows, as a flat list of facts in reading
    /// order.
    public var facts: [TransactionFact] {
        var facts: [TransactionFact] = []
        func add(_ section: TransactionFact.Section, _ key: String, _ label: String, _ value: String) {
            facts.append(TransactionFact(section: section, key: key, label: label, value: value))
        }

        add(.transaction, "id", "Transaction id", summary.id)
        add(.transaction, "eras", "Eras", summary.possibleEras)
        add(.transaction, "size", "Size", "\(summary.byteCount) bytes")
        add(.transaction, "fee", "Fee", TWFormat.ada(view.fee))
        add(.transaction, "isValid", "Phase-2 valid flag", view.isValid ? "true" : "false")
        if let slot = validity.startSlot { add(.transaction, "validFrom", "Valid from slot", String(slot)) }
        if let slot = validity.endSlot { add(.transaction, "validUntil", "Valid until slot", String(slot)) }
        if let total = view.totalCollateral { add(.transaction, "totalCollateral", "Total collateral", TWFormat.ada(total)) }
        if let networkID = view.networkId { add(.transaction, "networkId", "Network id", String(networkID)) }
        if let hash = view.scriptDataHash { add(.transaction, "scriptDataHash", "Script data hash", hash) }
        if let hash = view.auxiliaryDataHash { add(.transaction, "auxiliaryDataHash", "Auxiliary data hash", hash) }
        if let donation = view.treasuryDonation { add(.transaction, "treasuryDonation", "Treasury donation", TWFormat.ada(donation)) }
        if let treasury = view.currentTreasuryAmount { add(.transaction, "currentTreasury", "Current treasury", TWFormat.ada(treasury)) }

        for (section, list) in [(TransactionFact.Section.inputs, inputs), (.referenceInputs, referenceInputs), (.collateral, collateralInputs)] {
            for input in list {
                add(section, input.id, input.id, Self.describe(input))
            }
        }

        for output in outputs + (collateralReturn.map { [$0] } ?? []) {
            let name = output.index == outputs.count && collateralReturn != nil ? "Collateral return" : "Output \(output.index)"
            let key = name == "Collateral return" ? "return" : String(output.index)
            add(.outputs, "\(key).address", "\(name) address", output.address.text)
            add(.outputs, "\(key).ada", "\(name) ada", TWFormat.ada(output.lovelace))
            for asset in output.assets {
                add(.outputs, "\(key).asset.\(asset.id)", "\(name) \(Self.name(asset))", String(asset.quantity))
            }
            switch output.datum {
            case .hash(let hash)?: add(.outputs, "\(key).datum", "\(name) datum hash", hash)
            case .inline(let hash, _, _)?: add(.outputs, "\(key).datum", "\(name) inline datum", hash)
            case nil: break
            }
            if let script = output.referenceScript {
                add(.outputs, "\(key).referenceScript", "\(name) reference script", "\(script.language) \(script.hash)")
            }
        }

        for asset in mint {
            add(.mint, asset.id, Self.name(asset), String(asset.quantity))
        }
        for withdrawal in view.withdrawals {
            add(.withdrawals, withdrawal.rewardAddress, withdrawal.rewardAddress, TWFormat.ada(withdrawal.lovelace))
        }
        for certificate in view.certificates {
            add(.certificates, String(certificate.index), "\(certificate.index): \(certificate.kind)", certificate.summary)
        }
        for vote in view.votes {
            add(.votes, "\(vote.voter)|\(vote.govActionId)", "\(vote.voterRole) \(vote.voter) on \(vote.govActionId)", vote.vote)
        }
        for proposal in view.proposals {
            add(.proposals, String(proposal.index), "\(proposal.index): \(proposal.actionType)",
                "\(TWFormat.ada(proposal.deposit)) deposit · \(proposal.anchorURL)")
        }
        for script in scripts {
            add(.scripts, script.hash, script.hash, "\(script.language) · \(script.size) bytes")
        }
        for redeemer in view.redeemers {
            let units = redeemer.exUnits.map { " · \($0.memory) mem / \($0.steps) steps" } ?? ""
            add(.redeemers, "\(redeemer.tag) \(redeemer.index)", "\(redeemer.tag) \(redeemer.index)",
                "\(redeemer.purpose ?? "unknown purpose")\(units) · \(redeemer.dataCBORHex)")
        }
        for datum in datums {
            add(.datums, datum.hash, datum.hash, datum.cborHex)
        }
        for entry in metadata {
            for leaf in entry.tree.leaves {
                add(.metadata, "\(entry.label)\(leaf.id)", "\(entry.label) \(leaf.id)", leaf.value ?? leaf.summary)
            }
        }

        add(.witnesses, "count", "Signatures", String(signers.count))
        for signer in requiredSigners {
            add(.witnesses, "required.\(signer)", "Required signer \(signer)", signers.contains(signer) ? "signed" : "not signed")
        }
        for signer in signers where !requiredSigners.contains(signer) {
            add(.witnesses, "signer.\(signer)", "Signed by \(signer)", "signed")
        }
        return facts
    }

    private static func describe(_ input: InputDetail) -> String {
        let status: String? = switch input.status {
        case .unresolved: nil
        case .unspent: "unspent"
        case .spent: "spent"
        case .notFound: "not found"
        }
        let value = input.output.map { TWFormat.ada($0.lovelace) }
        return [value, status].compactMap(\.self).joined(separator: " · ")
    }

    private static func name(_ asset: AssetDetail) -> String {
        asset.displayName ?? asset.assetName ?? (asset.fingerprint ?? asset.id)
    }
}

extension DataNode {
    /// The nodes without children, depth first.
    var leaves: [DataNode] {
        guard let children, !children.isEmpty else { return [self] }
        return children.flatMap(\.leaves)
    }
}
