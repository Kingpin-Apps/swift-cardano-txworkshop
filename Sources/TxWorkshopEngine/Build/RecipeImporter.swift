import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import TxWorkshopCore

/// A transaction read back into the Build form, so it can be changed and
/// built again: coin selection, change, min-ADA, the fee and script budgets
/// are then worked out anew, not patched.
///
/// The inputs it spends are kept, as Always Use, with the addresses they come
/// from as sources, so an edit that needs more can take more. The output that
/// is plainly the change becomes the change address. What a form cannot hold
/// is either refused, when building without it would spend or authorise
/// something else, or left out with a note.
public enum RecipeImporter {
    public struct Result: Sendable, Equatable {
        public let recipe: BuildRecipe
        public let notes: [ImportNote]
    }

    /// Something the form does not carry over as it was.
    public struct ImportNote: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            /// Worked out again when the form is built.
            case recomputed
            /// Not in the form, so not in what it builds.
            case dropped
        }

        public let kind: Kind
        public let message: String
        public var id: String { message }
    }

    /// The form behind the transaction `bytes`. The UTxOs it spends come from
    /// `snapshot`; `blueprints` are kept from the form it replaces.
    public static func recipe(
        from bytes: Data, snapshot: ChainContextSnapshot?, network: CardanoNetwork?, keeping blueprints: [StoredBlueprint] = []
    ) throws -> Result {
        let transaction = try TransactionValidation.decode(bytes)
        let view = try TxValidator().inspect(transaction: transaction)
        var result = try recipe(
            from: transaction, redeemers: view.redeemers, utxos: TransactionValidation.utxos(snapshot),
            parameters: TransactionValidation.protocolParameters(snapshot), network: network
        )
        var recipe = result.recipe
        recipe.blueprints = blueprints
        recipe.cip21Compatible = (try? CIP21Check.report(bytes))?.isCompatible ?? false
        result = Result(recipe: recipe, notes: result.notes)
        return result
    }

    static func recipe(
        from transaction: Transaction, redeemers: [RedeemerView], utxos: [UTxO], parameters: ProtocolParameters?,
        network: CardanoNetwork?
    ) throws -> Result {
        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        var recipe = BuildRecipe()
        var notes: [ImportNote] = []
        var unsupported: [String] = []

        let known = Dictionary(utxos.map { (InputResolver.id($0.input), $0) }, uniquingKeysWith: { first, _ in first })
        let inputs = body.inputs.asArray
        let missing = inputs.map(InputResolver.id).filter { known[$0] == nil }
        guard missing.isEmpty else { throw ImportError.missingInputs(missing) }
        let spent = inputs.compactMap { known[InputResolver.id($0)] }

        // Scripts the witnesses carry, and those reference inputs carry.
        let witnessScripts: [ScriptType] =
            (witnesses.nativeScripts?.asList ?? []).map { .nativeScript($0) }
            + (witnesses.plutusV1Script?.asList ?? []).map { .plutusV1Script($0) }
            + (witnesses.plutusV2Script?.asList ?? []).map { .plutusV2Script($0) }
            + (witnesses.plutusV3Script?.asList ?? []).map { .plutusV3Script($0) }
        let referenceInputs = body.referenceInputs?.asList ?? []
        var usedReferences: Set<String> = []
        func script(hash: ScriptHash, what: String) throws -> ScriptDraft? {
            if let script = witnessScripts.first(where: { (try? scriptHash(script: $0)) == hash }) {
                return try draft(script)
            }
            for input in referenceInputs {
                let id = InputResolver.id(input)
                guard let utxo = known[id] else { continue }
                if let carried = utxo.output.script, (try? scriptHash(script: carried)) == hash {
                    usedReferences.insert(id)
                    return .reference(input: id)
                }
            }
            unsupported.append("the script for \(what) is neither in the transaction nor in a reference input whose UTxO is known")
            return nil
        }
        let spendRedeemers = Dictionary(
            redeemers.filter { $0.tag == "spend" }.compactMap { r in r.purpose.map { ($0, r) } }, uniquingKeysWith: { first, _ in first }
        )
        let mintRedeemers = Dictionary(
            redeemers.filter { $0.tag == "mint" }.compactMap { r in r.purpose.map { ($0, r) } }, uniquingKeysWith: { first, _ in first }
        )
        for tag in Set(redeemers.map(\.tag)).subtracting(["spend", "mint"]).sorted() {
            unsupported.append("a script runs for its \(Self.redeemerPurpose(tag)), which the form cannot give a redeemer")
        }

        // Inputs: key-locked ones are kept as they are; script-locked ones
        // carry their script, datum and redeemer.
        var sources: [String] = []
        for utxo in spent {
            let id = InputResolver.id(utxo.input)
            switch utxo.output.address.paymentPart {
            case .scriptHash(let hash)?:
                guard let redeemer = spendRedeemers[id] else {
                    unsupported.append("\(id) is locked by a native script, which the form spends only from a Plutus script")
                    continue
                }
                var input = ScriptInputDraft(input: id, redeemer: redeemer.dataCBORHex)
                input.script = try script(hash: hash, what: id)
                if let hash = Self.datumHash(of: utxo.output) {
                    let datum = witnesses.plutusData?.asList.first { data in
                        (try? data.toCBORData()).map { InspectionBuilder.blake2b256($0) == hash.payload } ?? false
                    }
                    if let datum {
                        input.datum = TxDocumentCodec.hex(try datum.toCBORData())
                    } else {
                        unsupported.append("the datum \(id) is locked with is not in the transaction")
                    }
                }
                recipe.scriptInputs.append(input)
            default:
                recipe.fixedInputs.append(id)
                recipe.utxos.append(TxDocumentCodec.hex(try utxo.toCBORData()))
                let address = try utxo.output.address.toBech32()
                if !sources.contains(address) { sources.append(address) }
            }
        }
        recipe.sourceAddresses = sources

        // The change: the last output paying the one source address any
        // output pays. The builder makes it again.
        let paysSource = CIP21Rebuild.changeOutput(of: body, spending: spent)
        // Otherwise the last output to a key address: where the builder,
        // and cardano-cli, put the change.
        let changeIndex = paysSource ?? body.outputs.lastIndex { output in
            if case .verificationKeyHash? = output.address.paymentPart { true } else { false }
        }
        if let changeIndex {
            recipe.changeAddress = try body.outputs[changeIndex].address.toBech32()
            notes.append(ImportNote(
                kind: .recomputed,
                message: paysSource != nil
                    ? "Output \(changeIndex) is taken as the change, and is worked out again."
                    : "Output \(changeIndex), the last to a key address, is taken as the change, and is worked out again. If it is a payment, add it back as an output."
            ))
        } else {
            recipe.changeAddress = sources.first ?? ""
            notes.append(ImportNote(
                kind: .recomputed,
                message: "No output is plainly the change, so every output is kept, and the change is a new output to \(sources.first ?? "the change address")."
            ))
        }
        for (index, output) in body.outputs.enumerated() where index != changeIndex {
            recipe.outputs.append(try draft(output, datums: witnesses.plutusData?.asList ?? []))
        }

        // Mints, by policy.
        if let mint = body.mint {
            for (policy, assets) in mint.data.sorted(by: { $0.key.payload.hex < $1.key.payload.hex }) {
                let policyHex = policy.payload.hex
                var draft = MintDraft(
                    assets: assets.data.map { AssetDraft(assetNameHex: $0.key.payload.hex, quantity: $0.value) },
                    redeemer: mintRedeemers[policyHex]?.dataCBORHex ?? ""
                )
                guard let found = try script(hash: policy, what: "the policy \(policyHex)") else { continue }
                draft.script = found
                recipe.mints.append(draft)
            }
        }

        // Certificates, withdrawals, votes and proposals.
        for certificate in body.certificates?.asList ?? [] {
            do {
                var item = try CertificateFile.draft(certificate, network: network)
                if case .registerPool(var pool) = item {
                    if let parameters {
                        pool.isUpdate = CIP21Rebuild.lovelaceLeftOver(body, spending: spent) < parameters.stakePoolDeposit
                        notes.append(ImportNote(
                            kind: .recomputed,
                            message: pool.isUpdate
                                ? "The pool registration pays no deposit, so it is taken as an update."
                                : "The pool registration pays the deposit, so it is taken as a first registration."
                        ))
                    }
                    item = .registerPool(pool)
                }
                if Self.stakeAddresses(in: item).contains(where: Self.isScript) {
                    unsupported.append("a certificate is for a script stake credential, which the form cannot witness")
                }
                recipe.certificates.append(CertificateItem(certificate: item))
            } catch {
                unsupported.append(String(describing: error))
            }
        }
        for (account, lovelace) in body.withdrawals?.data ?? [:] {
            let address = try Address(from: .bytes(account)).toBech32()
            if Self.isScript(address) { unsupported.append("it withdraws from a script stake address, which the form cannot witness") }
            recipe.withdrawals.append(WithdrawalDraft(stakeAddress: address, lovelace: UInt64(lovelace)))
        }
        if let procedures = body.votingProcedures {
            for voter in procedures.voters {
                let (role, id): (VoteDraft.Voter?, String) = switch voter.credential {
                case .drepKeyhash(let hash): (.drep, hash.payload.hex)
                case .constitutionalCommitteeHotKeyhash(let hash): (.committee, hash.payload.hex)
                case .stakePoolKeyhash(let hash): (.stakePool, hash.payload.hex)
                case .drepScriptHash, .constitutionalCommitteeHotScriptHash: (nil, "")
                }
                guard let role else {
                    unsupported.append("a script votes, which the form cannot witness")
                    continue
                }
                for (action, procedure) in (procedures[voter] ?? [:]).sorted(by: { Self.id($0.key) < Self.id($1.key) }) {
                    let anchor = CertificateFile.anchor(procedure.anchor)
                    let choice: VoteDraft.Choice = switch procedure.vote {
                    case .yes: .yes
                    case .no: .no
                    case .abstain: .abstain
                    }
                    recipe.votes.append(VoteDraft(
                        voter: role, voterID: id, action: Self.id(action), choice: choice, anchorURL: anchor.url, anchorHash: anchor.hash
                    ))
                }
            }
        }
        for proposal in body.proposalProcedures?.elementsOrdered ?? [] {
            let kind: ProposalDraft.Kind
            switch proposal.govAction {
            case .infoAction:
                kind = .info
            case .treasuryWithdrawalsAction(let action) where action.withdrawals.count == 1 && action.policyHash == nil:
                let (account, lovelace) = action.withdrawals.first!
                kind = .treasuryWithdrawal(stakeAddress: try Address(from: .bytes(account)).toBech32(), lovelace: UInt64(lovelace))
            default:
                unsupported.append("it proposes a governance action the form does not offer")
                continue
            }
            let anchor = CertificateFile.anchor(proposal.anchor)
            recipe.proposals.append(ProposalDraft(
                kind: kind, returnAddress: try Address(from: .bytes(proposal.rewardAccount)).toBech32(),
                anchorURL: anchor.url, anchorHash: anchor.hash
            ))
        }

        // Reference inputs not added for a script they carry are listed;
        // building needs their UTxOs too.
        let readReferences = referenceInputs.map(InputResolver.id).filter { !usedReferences.contains($0) }
        let unknownReferences = readReferences.filter { known[$0] == nil }
        guard unknownReferences.isEmpty else { throw ImportError.missingInputs(unknownReferences) }
        recipe.referenceInputs = readReferences
        if body.update != nil { unsupported.append("it carries a pre-Conway protocol update") }
        guard unsupported.isEmpty else { throw ImportError.unsupported(unsupported) }

        // Everything else in the body.
        recipe.validFrom = body.validityStart.map { UInt64($0) }
        recipe.validUntil = body.ttl.map { UInt64($0) }
        recipe.requiredSigners = body.requiredSigners?.asList.map(\.payload.hex) ?? []
        recipe.donation = body.treasuryDonation.map { UInt64($0.value) }
        let metadata = InspectionBuilder.metadataEntries(of: transaction)
        recipe.message = metadata[674].flatMap(InspectionBuilder.message) ?? ""
        let otherLabels = metadata.keys.filter { $0 != 674 || recipe.message.isEmpty }.sorted()
        if !otherLabels.isEmpty {
            notes.append(ImportNote(
                kind: .dropped,
                message: "Metadata under \(otherLabels.map(String.init).joined(separator: ", ")) is left out: the form holds only a CIP-20 message."
            ))
        }
        let hasPlutus = !recipe.scriptInputs.isEmpty || recipe.mints.contains { !$0.redeemer.isEmpty }
        if hasPlutus {
            recipe.collateral = body.collateral?.asList.map(InputResolver.id) ?? []
            notes.append(ImportNote(
                kind: .recomputed,
                message: "Script budgets, the script data hash and the collateral return are worked out again."
            ))
        }
        if body.currentTreasuryAmount != nil {
            notes.append(ImportNote(kind: .dropped, message: "The treasury amount it stated is left out."))
        }
        let signatures = witnesses.vkeyWitnesses?.count ?? 0
        if signatures > 0 {
            notes.append(ImportNote(
                kind: .dropped,
                message: "Its \(signatures) signature\(signatures == 1 ? "" : "s") signed the old transaction, so building gives one to sign again."
            ))
        }
        notes.insert(ImportNote(kind: .recomputed, message: "The fee and min-ADA are worked out again when it is built."), at: 0)
        return Result(recipe: recipe, notes: notes)
    }

    // MARK: Ledger values to drafts

    /// An output as the form gives it. A datum hash whose datum is among
    /// `datums`, the transaction's witnesses, keeps the datum with it.
    static func draft(_ output: TransactionOutput, datums: [PlutusData] = []) throws -> OutputDraft {
        var draft = OutputDraft(address: try output.address.toBech32(), lovelace: UInt64(output.amount.coin))
        for (policy, assets) in output.amount.multiAsset.data.sorted(by: { $0.key.payload.hex < $1.key.payload.hex }) {
            for (name, quantity) in assets.data {
                draft.assets.append(AssetDraft(policyID: policy.payload.hex, assetNameHex: name.payload.hex, quantity: quantity))
            }
        }
        if case .data(let data)? = output.datumOption?.datum {
            draft.datum = .inline(TxDocumentCodec.hex(try data.toCBORData()))
        } else if let hash = datumHash(of: output) {
            let datum = datums.first { data in
                (try? data.toCBORData()).map { InspectionBuilder.blake2b256($0) == hash.payload } ?? false
            }
            draft.datum = try datum.map { .hashed(TxDocumentCodec.hex(try $0.toCBORData())) } ?? .hash(hash.payload.hex)
        }
        if let script = output.script {
            draft.referenceScript = try TransactionComposer.referenceScriptHex(script)
        }
        return draft
    }

    /// The datum hash an output holds, written either way the ledger allows.
    static func datumHash(of output: TransactionOutput) -> DatumHash? {
        if case .datumHash(let hash)? = output.datumOption?.datum { return hash }
        return output.datumHash
    }

    static func draft(_ script: ScriptType) throws -> ScriptDraft {
        switch script {
        case .nativeScript(let native):
            guard let json = try native.toJSON() else { throw ImportError.malformed("A native script does not convert to JSON.") }
            return .native(json: json)
        case .plutusV1Script(let plutus): return .plutus(version: 1, cborHex: plutus.data.hex)
        case .plutusV2Script(let plutus): return .plutus(version: 2, cborHex: plutus.data.hex)
        case .plutusV3Script(let plutus): return .plutus(version: 3, cborHex: plutus.data.hex)
        }
    }

    static func id(_ action: GovActionID) -> String {
        "\(action.transactionID.payload.hex)#\(action.govActionIndex)"
    }

    static func stakeAddresses(in certificate: CertificateDraft) -> [String] {
        switch certificate {
        case .registerStake(let a), .deregisterStake(let a), .registerStakeLegacy(let a), .deregisterStakeLegacy(let a),
            .delegateStake(let a, _), .delegateVote(let a, _), .delegateStakeAndVote(let a, _, _), .registerAndDelegateStake(let a, _),
            .registerAndDelegateVote(let a, _), .registerAndDelegateStakeAndVote(let a, _, _):
            [a]
        default:
            []
        }
    }

    static func isScript(_ stakeAddress: String) -> Bool {
        guard let address = try? Address(from: .string(stakeAddress)), case .scriptHash? = address.stakingPart else { return false }
        return true
    }

    static func redeemerPurpose(_ tag: String) -> String {
        switch tag {
        case "cert": "certificate"
        case "reward": "withdrawal"
        case "voting": "vote"
        case "proposing": "proposal"
        default: tag
        }
    }
}

public enum ImportError: Error, Sendable, Equatable, CustomStringConvertible {
    case malformed(String)
    case missingInputs([String])
    case unsupported([String])

    public var description: String {
        switch self {
        case .malformed(let message):
            message
        case .missingInputs(let inputs):
            "Editing needs the UTxOs the transaction spends and reads: fetch chain data first. Missing: \(inputs.joined(separator: ", "))."
        case .unsupported(let reasons):
            "The Build form cannot hold this transaction as it is: \(reasons.joined(separator: "; "))."
        }
    }
}
