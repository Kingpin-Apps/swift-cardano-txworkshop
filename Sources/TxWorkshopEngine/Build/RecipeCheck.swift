import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// One thing wrong with a build recipe, and where it is.
public struct RecipeProblem: Sendable, Equatable, Identifiable, CustomStringConvertible {
    /// Where in the form: "Output 2", "Certificate 1 (Register stake address)".
    public let place: String
    /// The field, as the form labels it.
    public let field: String
    public let message: String
    /// The item the problem is in, for the form to mark it.
    public let itemID: UUID?

    public var id: String { "\(place)|\(field)|\(message)" }
    public var description: String { "\(place), \(field): \(message)" }
}

/// Checks a build recipe field by field before it is built, so each mistake
/// is named where it is rather than surfacing from deep in the builder.
public enum RecipeCheck {
    public static func problems(_ recipe: BuildRecipe, network: CardanoNetwork?) -> [RecipeProblem] {
        var check = Checker(network: network)
        check.recipe(recipe)
        return check.found
    }
}

private struct Checker {
    let network: CardanoNetwork?
    var blueprints: [StoredBlueprint] = []
    var found: [RecipeProblem] = []

    mutating func add(_ place: String, _ field: String, _ message: String, _ item: UUID? = nil) {
        found.append(RecipeProblem(place: place, field: field, message: message, itemID: item))
    }

    func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Reads `text` as `kind`; adds a problem if it is empty (when required)
    /// or does not read.
    mutating func value(
        _ kind: ValueKind, _ text: String, required: Bool = true,
        _ place: String, _ field: String, _ item: UUID? = nil
    ) {
        if blank(text) {
            if required { add(place, field, "Empty.", item) }
            return
        }
        do {
            _ = try ValueReader.read(kind, text: text.trimmingCharacters(in: .whitespacesAndNewlines), network: network)
        } catch {
            add(place, field, String(describing: error), item)
        }
    }

    /// Checks a blueprint form field by field; each problem names its field path.
    mutating func blueprint(_ form: BlueprintForm, _ role: BlueprintRole, _ place: String, _ field: String, _ item: UUID?) {
        for problem in BlueprintCatalog.problems(form, role: role, in: blueprints) {
            add(place, field, problem.description, item)
        }
    }

    func lines(_ list: [String]) -> [String] {
        list.flatMap { $0.split(whereSeparator: \.isNewline).map(String.init) }.filter { !blank($0) }
    }

    mutating func recipe(_ r: BuildRecipe) {
        blueprints = r.blueprints
        let sources = lines(r.sourceAddresses)
        for address in sources { value(.address, address, "Sources", "Source address") }
        for input in lines(r.fixedInputs) { value(.transactionInput, input, "Sources", "Inputs to spend") }
        for input in lines(r.collateral) { value(.transactionInput, input, "Options", "Collateral") }
        for signer in lines(r.requiredSigners) { value(.keyHash, signer, "Options", "Required signers") }
        value(.address, r.changeAddress, required: false, "Sources", "Change address")
        if sources.isEmpty && blank(r.changeAddress) {
            add("Sources", "Change address", "Add a source address, or a change address for the change.")
        }
        if let from = r.validFrom, let until = r.validUntil, from >= until {
            add("Options", "Validity", "Valid from (slot \(from)) must come before valid until (slot \(until)).")
        }

        if r.outputs.isEmpty && r.mints.isEmpty && r.certificates.isEmpty && r.withdrawals.isEmpty
            && r.votes.isEmpty && r.proposals.isEmpty && r.scriptInputs.isEmpty && (r.donation ?? 0) == 0 {
            add("Outputs", "Output", "Add an output, or something else for the transaction to do.")
        }

        for (i, output) in r.outputs.enumerated() {
            let place = "Output \(i + 1)"
            value(.address, output.address, place, "Address", output.id)
            assets(output.assets, place, output.id, allowNegative: false)
            switch output.datum {
            case .none: break
            case .hash(let hash):
                if blank(hash) {
                    add(place, "Datum hash", "Empty.", output.id)
                } else if (try? TxDocumentCodec.bytes(fromHex: hash.trimmingCharacters(in: .whitespaces)))?.count != 32 {
                    add(place, "Datum hash", "A datum hash is 32 bytes in hex.", output.id)
                }
            case .inline(let data):
                if let form = output.datumForm {
                    blueprint(form, .datum, place, "Inline datum", output.id)
                } else {
                    value(.plutusData, data, place, "Inline datum", output.id)
                }
            }
            if let reference = output.referenceScript, !blank(reference) {
                guard (try? TxDocumentCodec.bytes(fromHex: reference.trimmingCharacters(in: .whitespacesAndNewlines))) != nil else {
                    add(place, "Reference script", "Not CBOR hex.", output.id)
                    continue
                }
            }
        }

        for (i, mint) in r.mints.enumerated() {
            let place = "Mint or burn \(i + 1)"
            script(mint.script, place, "Policy script", mint.id)
            if mint.assets.isEmpty { add(place, "Assets", "Add an asset to mint or burn.", mint.id) }
            for asset in mint.assets {
                value(.assetName, asset.assetNameHex, required: false, place, "Asset name", mint.id)
                if asset.quantity == 0 { add(place, "Quantity", "Zero mints nothing; use a positive number to mint or negative to burn.", mint.id) }
            }
            if let parameters = mint.scriptParameters {
                for problem in BlueprintCatalog.problems(parameters, in: blueprints) { add(place, "Script parameters", problem.description, mint.id) }
            }
            if case .plutus = mint.script {
                if let form = mint.redeemerForm {
                    blueprint(form, .redeemer, place, "Redeemer", mint.id)
                } else {
                    value(.plutusData, mint.redeemer, place, "Redeemer", mint.id)
                }
            }
        }

        for (i, input) in r.scriptInputs.enumerated() {
            let place = "Script input \(i + 1)"
            value(.transactionInput, input.input, place, "UTxO", input.id)
            if let draft = input.script { script(draft, place, "Script", input.id) }
            if let parameters = input.scriptParameters {
                for problem in BlueprintCatalog.problems(parameters, in: blueprints) { add(place, "Script parameters", problem.description, input.id) }
            }
            if let form = input.datumForm {
                blueprint(form, .datum, place, "Datum", input.id)
            } else {
                value(.plutusData, input.datum, required: false, place, "Datum", input.id)
            }
            if let form = input.redeemerForm {
                blueprint(form, .redeemer, place, "Redeemer", input.id)
            } else {
                value(.plutusData, input.redeemer, place, "Redeemer", input.id)
            }
        }

        for (i, item) in r.certificates.enumerated() {
            certificate(item.certificate, number: i + 1, item.id)
        }

        for (i, withdrawal) in r.withdrawals.enumerated() {
            value(.stakeAddress, withdrawal.stakeAddress, "Withdrawal \(i + 1)", "Stake address", withdrawal.id)
        }

        for (i, vote) in r.votes.enumerated() {
            let place = "Vote \(i + 1)"
            let kind: ValueKind = switch vote.voter {
            case .drep: .drepKeyHash
            case .stakePool: .pool
            case .committee: .committeeHotKeyHash
            }
            value(kind, vote.voterID, place, "Voter", vote.id)
            value(.govActionID, vote.action, place, "Governance action", vote.id)
            anchor(vote.anchorURL, vote.anchorHash, required: false, place, vote.id)
        }

        for (i, proposal) in r.proposals.enumerated() {
            let place = "Proposal \(i + 1)"
            value(.stakeAddress, proposal.returnAddress, place, "Deposit return stake address", proposal.id)
            anchor(proposal.anchorURL, proposal.anchorHash, required: true, place, proposal.id)
            if case .treasuryWithdrawal(let address, let lovelace) = proposal.kind {
                value(.stakeAddress, address, place, "Pay to stake address", proposal.id)
                if lovelace == 0 { add(place, "Lovelace", "Zero: give the amount to withdraw from the treasury.", proposal.id) }
            }
        }
    }

    mutating func assets(_ assets: [AssetDraft], _ place: String, _ item: UUID, allowNegative: Bool) {
        for asset in assets {
            value(.policyID, asset.policyID, place, "Policy id", item)
            value(.assetName, asset.assetNameHex, required: false, place, "Asset name", item)
            if asset.quantity == 0 || (!allowNegative && asset.quantity < 0) {
                add(place, "Quantity", "An output carries a positive quantity of each asset.", item)
            }
        }
    }

    mutating func script(_ draft: ScriptDraft, _ place: String, _ field: String, _ item: UUID) {
        switch draft {
        case .native(let json):
            if blank(json) {
                add(place, field, "Empty: give the native script's JSON, or choose its file.", item)
            } else if (try? NativeScript.fromJSON(json)) == nil {
                add(place, field, "The native script JSON does not read as a script.", item)
            }
        case .plutus(let version, let text):
            value(.plutusScript(version: version), text, place, field, item)
        case .reference(let input):
            value(.transactionInput, input, place, "\(field) (reference UTxO)", item)
        }
    }

    mutating func anchor(_ url: String, _ hash: String, required: Bool, _ place: String, _ item: UUID) {
        if blank(url) && blank(hash) {
            if required { add(place, "Anchor URL", "A proposal needs an anchor: its URL and hash.", item) }
            return
        }
        if blank(url) { add(place, "Anchor URL", "Empty, but an anchor hash is given.", item) }
        else if URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme == nil { add(place, "Anchor URL", "Not a URL.", item) }
        value(.anchorHash, hash, place, "Anchor hash", item)
    }

    mutating func certificate(_ certificate: CertificateDraft, number: Int, _ item: UUID) {
        switch certificate {
        case .registerStake(let address):
            value(.stakeAddress, address, "Certificate \(number) (Register stake address)", "Stake address", item)
        case .deregisterStake(let address):
            value(.stakeAddress, address, "Certificate \(number) (Deregister stake address)", "Stake address", item)
        case .delegateStake(let address, let pool):
            let place = "Certificate \(number) (Delegate stake to a pool)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.pool, pool, place, "Pool", item)
        case .delegateVote(let address, let drep):
            let place = "Certificate \(number) (Delegate votes to a DRep)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.drep, drep, place, "DRep", item)
        case .registerDRep(let key, let url, let hash):
            let place = "Certificate \(number) (Register as a DRep)"
            value(.drepKeyHash, key, place, "DRep", item)
            anchor(url, hash, required: false, place, item)
        case .unregisterDRep(let key):
            value(.drepKeyHash, key, "Certificate \(number) (Retire as a DRep)", "DRep", item)
        case .updateDRep(let key, let url, let hash):
            let place = "Certificate \(number) (Update DRep metadata)"
            value(.drepKeyHash, key, place, "DRep", item)
            anchor(url, hash, required: false, place, item)
        case .registerStakeLegacy(let address):
            value(.stakeAddress, address, "Certificate \(number) (Register stake address, pre-Conway)", "Stake address", item)
        case .deregisterStakeLegacy(let address):
            value(.stakeAddress, address, "Certificate \(number) (Deregister stake address, pre-Conway)", "Stake address", item)
        case .delegateStakeAndVote(let address, let pool, let drep):
            let place = "Certificate \(number) (Delegate stake and votes)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.pool, pool, place, "Pool", item)
            value(.drep, drep, place, "DRep", item)
        case .registerAndDelegateStake(let address, let pool):
            let place = "Certificate \(number) (Register and delegate stake)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.pool, pool, place, "Pool", item)
        case .registerAndDelegateVote(let address, let drep):
            let place = "Certificate \(number) (Register and delegate votes)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.drep, drep, place, "DRep", item)
        case .registerAndDelegateStakeAndVote(let address, let pool, let drep):
            let place = "Certificate \(number) (Register and delegate stake and votes)"
            value(.stakeAddress, address, place, "Stake address", item)
            value(.pool, pool, place, "Pool", item)
            value(.drep, drep, place, "DRep", item)
        case .registerPool(let pool):
            poolRegistration(pool, place: "Certificate \(number) (\(pool.isUpdate ? "Update stake pool" : "Register stake pool"))", item)
        case .retirePool(let pool, let epoch):
            let place = "Certificate \(number) (Retire stake pool)"
            value(.pool, pool, place, "Pool", item)
            if epoch == nil { add(place, "Retirement epoch", "Empty: give the epoch the pool retires at.", item) }
        case .authorizeCommitteeHot(let cold, let hot):
            let place = "Certificate \(number) (Authorize committee hot key)"
            value(.committeeColdKeyHash, cold, place, "Cold key", item)
            value(.committeeHotKeyHash, hot, place, "Hot key", item)
        case .resignCommitteeCold(let cold, let url, let hash):
            let place = "Certificate \(number) (Resign from the committee)"
            value(.committeeColdKeyHash, cold, place, "Cold key", item)
            anchor(url, hash, required: false, place, item)
        }
    }

    mutating func poolRegistration(_ pool: PoolRegistrationDraft, place: String, _ item: UUID) {
        value(.pool, pool.pool, place, "Pool", item)
        value(.vrfKeyHash, pool.vrfKey, place, "VRF key", item)
        if pool.pledge == nil { add(place, "Pledge", "Empty.", item) }
        if pool.cost == nil { add(place, "Fixed cost", "Empty.", item) }
        if blank(pool.margin) {
            add(place, "Margin", "Empty.", item)
        } else if PoolMargin.parse(pool.margin) == nil {
            add(place, "Margin", "Not a number from 0 to 1, a percentage such as 5%, or a fraction such as 1/20.", item)
        }
        value(.stakeAddress, pool.rewardAccount, place, "Reward account", item)
        let owners = pool.owners.filter { !blank($0) }
        if owners.isEmpty { add(place, "Owners", "Add at least one owner's stake key.", item) }
        for owner in owners { value(.stakeAddress, owner, place, "Owner", item) }
        for (i, relay) in pool.relays.enumerated() {
            let field = "Relay \(i + 1)"
            let host = relay.host.trimmingCharacters(in: .whitespaces)
            switch relay.kind {
            case .ipv4: if IPv4Address(host) == nil { add(place, field, blank(host) ? "Empty." : "Not an IPv4 address.", item) }
            case .ipv6: if IPv6Address(host) == nil { add(place, field, blank(host) ? "Empty." : "Not an IPv6 address.", item) }
            case .dnsName, .srvName:
                if blank(host) { add(place, field, "Empty.", item) }
                else if host.utf8.count > 64 { add(place, field, "A DNS name is at most 64 bytes.", item) }
            }
            if relay.kind != .srvName, relay.port == nil { add(place, field, "Give the port.", item) }
        }
        if blank(pool.metadataURL) != blank(pool.metadataHash) {
            add(place, "Metadata", "Give both the metadata URL and its hash, or neither.", item)
        } else if !blank(pool.metadataURL) {
            if pool.metadataURL.trimmingCharacters(in: .whitespaces).utf8.count > 64 {
                add(place, "Metadata URL", "At most 64 bytes.", item)
            }
            value(.anchorHash, pool.metadataHash, place, "Metadata hash", item)
        }
    }
}
