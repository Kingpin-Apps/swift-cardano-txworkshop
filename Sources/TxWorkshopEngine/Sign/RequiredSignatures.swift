import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import TxWorkshopCore

/// Whose signatures a transaction needs, why, and which it has.
public struct RequiredSignatures: Sendable, Equatable {
    public struct Signer: Sendable, Equatable, Identifiable {
        /// Key hash, hex.
        public let keyHash: String
        /// What needs it: "input …#0", "required signer", "certificate 1", ….
        public let reasons: [String]
        public let isSigned: Bool
        public var id: String { keyHash }
    }

    public let signers: [Signer]
    /// Witnesses for keys nothing in the transaction asks for.
    public let extraWitnesses: [String]
    /// Inputs whose address could not be read because their UTxO is not
    /// known; their payment keys are missing from ``signers``.
    public let unresolvedInputs: [String]

    public var isComplete: Bool { unresolvedInputs.isEmpty && signers.allSatisfy(\.isSigned) }

    /// Reads what `bytes` needs signed. Input UTxOs come from `utxos` (CBOR
    /// hex, as the chain snapshot and recipe keep them).
    public static func analyze(_ bytes: Data, utxos: [String]) throws -> RequiredSignatures {
        let transaction = try TransactionValidation.decode(bytes)
        let view = try TxValidator().inspect(transaction: transaction)
        let known = Dictionary(
            utxos.compactMap { hex in (try? TransactionComposer.utxo(hex)).map { (InputResolver.id($0.input), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var reasons: [String: [String]] = [:]
        func need(_ hash: String, _ reason: String) {
            reasons[hash.lowercased(), default: []].append(reason)
        }

        var unresolved: [String] = []
        let body = transaction.transactionBody
        for (kind, inputs) in [("input", body.inputs.asArray), ("collateral", body.collateral?.asList ?? [])] {
            for input in inputs {
                let id = InputResolver.id(input)
                guard let utxo = known[id] else {
                    unresolved.append(id)
                    continue
                }
                if case .verificationKeyHash(let hash)? = utxo.output.address.paymentPart {
                    need(hash.payload.hex, "\(kind) \(id)")
                }
            }
        }
        for signer in body.requiredSigners?.asList ?? [] {
            need(signer.payload.hex, "required signer")
        }
        for withdrawal in view.withdrawals where withdrawal.credentialKind == "key" {
            if let address = try? Address(from: .string(withdrawal.rewardAddress)),
                case .verificationKeyHash(let hash)? = address.stakingPart
            {
                need(hash.payload.hex, "withdrawal from \(withdrawal.rewardAddress)")
            }
        }
        for certificate in view.certificates {
            if let credential = certificate.credential, credential.hasPrefix("key:"),
                !["stakeRegistration"].contains(certificate.kind)
            {
                need(String(credential.dropFirst(4)), "certificate \(certificate.index): \(certificate.kind)")
            }
        }
        // Pool certificates carry no stake credential: the cold key signs,
        // and for a registration every owner too.
        for (index, certificate) in (body.certificates?.asList ?? []).enumerated() {
            switch certificate {
            case .poolRegistration(let registration):
                need(registration.poolParams.poolOperator.payload.hex, "certificate \(index): pool registration (cold key)")
                for owner in registration.poolParams.poolOwners.asArray {
                    need(owner.payload.hex, "certificate \(index): pool registration (owner)")
                }
            case .poolRetirement(let retirement):
                need(retirement.poolKeyHash.payload.hex, "certificate \(index): pool retirement (cold key)")
            default:
                break
            }
        }
        for vote in view.votes where !vote.voter.hasPrefix("script") {
            let hash = vote.voter.split(separator: ":").last.map(String.init) ?? vote.voter
            if hash.count == 56 { need(hash, "vote on \(vote.govActionId)") }
        }
        for script in transaction.transactionWitnessSet.nativeScripts?.asList ?? [] {
            for hash in keyHashes(in: script) { need(hash, "native script") }
        }

        let signed = Set(try (transaction.transactionWitnessSet.vkeyWitnesses?.asList ?? []).map(WitnessAssembler.keyHash))
        let signers = reasons.keys.sorted().map { Signer(keyHash: $0, reasons: reasons[$0]!, isSigned: signed.contains($0)) }
        return RequiredSignatures(
            signers: signers,
            extraWitnesses: signed.subtracting(reasons.keys).sorted(),
            unresolvedInputs: unresolved
        )
    }

    /// The key hashes a native script names, at any depth.
    static func keyHashes(in script: NativeScript) -> [String] {
        guard let json = try? script.toJSON(), let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
        var hashes: [String] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if dict["type"] as? String == "sig", let hash = dict["keyHash"] as? String { hashes.append(hash.lowercased()) }
                dict.values.forEach(walk)
            } else if let list = value as? [Any] {
                list.forEach(walk)
            }
        }
        walk(object)
        return hashes
    }
}
