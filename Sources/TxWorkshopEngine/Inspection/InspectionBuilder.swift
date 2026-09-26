import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import SwiftCardanoUPLC
import SwiftNaCl
import TxWorkshopCore

/// Builds a ``TransactionInspection`` from a decoded transaction.
struct InspectionBuilder {
    let transaction: Transaction
    let view: TransactionView
    let network: CardanoNetwork?
    private let chainContext: ChainContextSnapshot?
    private let names: AssetNames
    /// The looked-up outputs, by `<transaction id>#<index>`.
    private let resolved: [String: UTxO]

    init(transaction: Transaction, view: TransactionView, network: CardanoNetwork?, chainContext: ChainContextSnapshot? = nil) {
        self.transaction = transaction
        self.view = view
        self.network = network
        self.chainContext = chainContext
        self.names = AssetNames(metadata: Self.metadataEntries(of: transaction), registry: chainContext?.tokens ?? [])
        var resolved: [String: UTxO] = [:]
        for hex in chainContext?.utxos ?? [] {
            guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), let utxo = try? UTxO.fromCBOR(data: bytes) else { continue }
            resolved[InputResolver.id(utxo.input)] = utxo
        }
        self.resolved = resolved
    }

    /// Script listings longer than this are cut short; the full script is
    /// still in the CBOR explorer.
    static let listingLineLimit = 4_000

    func build(summary: TransactionSummary) -> TransactionInspection {
        let body = transaction.transactionBody
        let witnesses = transaction.transactionWitnessSet
        let outputs = body.outputs.enumerated().map { output($1, index: $0) }
        let network = network ?? (outputs.contains { $0.address.isMainnet } ? .mainnet : nil)
        return TransactionInspection(
            summary: summary,
            inputs: body.inputs.asArray.map(input),
            referenceInputs: body.referenceInputs?.asList.map(input) ?? [],
            collateralInputs: body.collateral?.asList.map(input) ?? [],
            outputs: outputs,
            collateralReturn: body.collateralReturn.map { output($0, index: body.outputs.count) },
            mint: body.mint.map(assets) ?? [],
            validity: validity(start: body.validityStart, end: body.ttl, network: network),
            scripts: scripts(witnesses),
            redeemers: redeemers(),
            datums: datums(witnesses),
            metadata: metadata(),
            requiredSigners: body.requiredSigners?.asList.map { $0.payload.hex } ?? []
        )
    }

    // MARK: Inputs and outputs

    private func input(_ input: TransactionInput) -> InputDetail {
        let id = InputResolver.id(input)
        let utxo = resolved[id]
        let status: InputDetail.Status =
            if chainContext == nil { .unresolved }
            else if utxo == nil { .notFound }
            else if chainContext?.spentInputs?.contains(id) == true { .spent }
            else { .unspent }
        return InputDetail(
            transactionID: input.transactionId.payload.hex, index: input.index,
            status: status, output: utxo.map { output($0.output, index: Int(input.index)) }
        )
    }

    private func output(_ output: TransactionOutput, index: Int) -> OutputDetail {
        OutputDetail(
            index: index,
            address: address(output.address),
            lovelace: output.amount.coin,
            assets: assets(output.amount.multiAsset),
            datum: datum(output),
            referenceScript: output.script.map(script)
        )
    }

    private func address(_ address: Address) -> AddressDetail {
        let kind: AddressDetail.Kind
        switch address.addressType?.rawValue ?? -1 {
        case 0...3: kind = .base
        case 4, 5: kind = .pointer
        case 6, 7: kind = .enterprise
        case 8: kind = .byron
        case 14, 15: kind = .reward
        default: kind = .unknown
        }
        let payment: String? = address.paymentPart.map {
            switch $0 {
            case .verificationKeyHash(let hash): "key:\(hash.payload.hex)"
            case .scriptHash(let hash): "script:\(hash.payload.hex)"
            }
        }
        let stake: String? = address.stakingPart.map {
            switch $0 {
            case .verificationKeyHash(let hash): "key:\(hash.payload.hex)"
            case .scriptHash(let hash): "script:\(hash.payload.hex)"
            case .pointerAddress(let pointer): "pointer:\(pointer)"
            }
        }
        return AddressDetail(
            text: (try? address.toBech32()) ?? address.toBytes().hex,
            kind: kind, payment: payment, stake: stake,
            isMainnet: address.network == .mainnet
        )
    }

    private func assets(_ multiAsset: MultiAsset) -> [AssetDetail] {
        multiAsset.data.flatMap { policy, asset in
            asset.data.map { name, quantity in
                let policyHex = policy.payload.hex
                let nameHex = name.payload.hex
                // A CIP-67 label is a 4-byte prefix; the readable name follows it.
                let readable = AssetDetail.cip67Label(ofNameHex: nameHex) == nil ? name.payload : name.payload.dropFirst(4)
                let known = names[policyHex + nameHex]
                return AssetDetail(
                    policyID: policyHex,
                    assetNameHex: nameHex,
                    assetName: DataNode.printableText(Data(readable)),
                    fingerprint: AssetFingerprint.fingerprint(policyID: policy.payload, assetName: name.payload),
                    quantity: quantity,
                    displayName: known?.name,
                    nameSource: known?.source,
                    ticker: known?.ticker,
                    decimals: known?.decimals
                )
            }
        }
        .sorted { ($0.policyID, $0.assetNameHex) < ($1.policyID, $1.assetNameHex) }
    }

    private func datum(_ output: TransactionOutput) -> DatumReference? {
        if let option = output.datumOption {
            switch option.datum {
            case .datumHash(let hash):
                return .hash(hash.payload.hex)
            case .data(let data):
                let cbor = (try? data.toCBORData()) ?? Data()
                return .inline(hash: Self.blake2b256(cbor).hex, tree: .plutus(data), cborHex: cbor.hex)
            }
        }
        return output.datumHash.map { .hash($0.payload.hex) }
    }

    // MARK: Witnesses

    private func scripts(_ witnesses: TransactionWitnessSet) -> [ScriptDetail] {
        var scripts: [ScriptType] = []
        scripts += (witnesses.nativeScripts?.asList ?? []).map { .nativeScript($0) }
        scripts += (witnesses.plutusV1Script?.asList ?? []).map { .plutusV1Script($0) }
        scripts += (witnesses.plutusV2Script?.asList ?? []).map { .plutusV2Script($0) }
        scripts += (witnesses.plutusV3Script?.asList ?? []).map { .plutusV3Script($0) }
        return scripts.map(script)
    }

    private func script(_ script: ScriptType) -> ScriptDetail {
        let hash = (try? scriptHash(script: script))?.payload.hex ?? ""
        switch script {
        case .nativeScript(let native):
            let listing = (try? native.toJSON()) ?? String(describing: native)
            return ScriptDetail(hash: hash, language: "native", size: (try? native.toCBORData().count) ?? 0, listing: listing)
        case .plutusV1Script(let plutus):
            return ScriptDetail(hash: hash, language: "plutusV1", size: plutus.data.count, listing: Self.listing(plutus.data))
        case .plutusV2Script(let plutus):
            return ScriptDetail(hash: hash, language: "plutusV2", size: plutus.data.count, listing: Self.listing(plutus.data))
        case .plutusV3Script(let plutus):
            return ScriptDetail(hash: hash, language: "plutusV3", size: plutus.data.count, listing: Self.listing(plutus.data))
        }
    }

    /// The script as readable UPLC, cut short if it is very long.
    static func listing(_ scriptData: Data) -> String? {
        guard let flat = try? extractFlatBytes(from: scriptData),
            let program = try? FlatDecoder().decode(flat)
        else { return nil }
        let text = PrettyPrinter().print(program)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > listingLineLimit else { return text }
        return lines.prefix(listingLineLimit).joined(separator: "\n")
            + "\n… \(lines.count - listingLineLimit) more lines"
    }

    private func redeemers() -> [RedeemerDetail] {
        let data = PhaseTwo.redeemers(of: transaction).map(\.data)
        return view.redeemers.map { redeemer in
            let tree = data.indices.contains(redeemer.position)
                ? DataNode.plutus(data[redeemer.position]) : DataNode.plutus(.array([]))
            return RedeemerDetail(view: redeemer, tree: tree)
        }
    }

    private func datums(_ witnesses: TransactionWitnessSet) -> [DatumDetail] {
        (witnesses.plutusData?.asList ?? []).map { datum in
            let cbor = (try? datum.toCBORData()) ?? Data()
            return DatumDetail(hash: Self.blake2b256(cbor).hex, tree: .plutus(datum), cborHex: cbor.hex)
        }
    }

    // MARK: Metadata

    /// Metadata labels registered in CIP-10 that are common on chain.
    static let registeredLabels: [UInt64: String] = [
        20: "Token registry (CIP-26)",
        674: "Message (CIP-20)",
        721: "NFT metadata (CIP-25)",
        777: "Royalties (CIP-27)",
        61284: "Vote registration (CIP-15/36)",
        61285: "Vote registration signature (CIP-15/36)",
        61286: "Vote registration witness (CIP-36)",
    ]

    static func metadataEntries(of transaction: Transaction) -> [UInt64: TransactionMetadatum] {
        guard let auxiliary = transaction.auxiliaryData else { return [:] }
        switch auxiliary.data {
        case .metadata(let metadata): return metadata.data
        case .shelleyMaryMetadata(let metadata): return metadata.metadata.data
        case .alonzoMetadata(let metadata): return metadata.metadata?.data ?? [:]
        }
    }

    private func metadata() -> [MetadataEntry] {
        let entries = Self.metadataEntries(of: transaction)
        return entries.keys.sorted().map { label in
            let value = entries[label]!
            return MetadataEntry(
                label: label,
                registeredAs: Self.registeredLabels[label],
                tree: .metadatum(value, label: String(label)),
                message: label == 674 ? Self.message(value) : nil
            )
        }
    }

    /// The CIP-20 message: `{"msg": [line, …]}`, lines of at most 64 bytes.
    static func message(_ value: TransactionMetadatum) -> String? {
        guard case .map(let map) = value, case .list(let lines)? = map[.text("msg")] else { return nil }
        let text = lines.compactMap { line -> String? in
            if case .text(let text) = line { return text }
            return nil
        }
        return text.isEmpty ? nil : text.joined(separator: "\n")
    }

    // MARK: Validity

    private func validity(start: SlotNumber?, end: SlotNumber?, network: CardanoNetwork?) -> ValidityWindow {
        let timeline: SlotTimeline? = switch network {
        case .mainnet: .mainnet
        case .preprod: .preprod
        case .preview: .preview
        default: nil
        }
        func date(_ slot: SlotNumber?) -> Date? {
            guard let slot, let timeline else { return nil }
            return Date(timeIntervalSince1970: Double(timeline.milliseconds(forSlot: UInt64(slot))) / 1000)
        }
        return ValidityWindow(
            startSlot: start.map { UInt64($0) }, endSlot: end.map { UInt64($0) },
            start: date(start), end: date(end)
        )
    }

    static func blake2b256(_ data: Data) -> Data {
        (try? Hash().blake2b(data: data, digestSize: 32, encoder: RawEncoder.self)) ?? Data()
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private func < (lhs: (String, String), rhs: (String, String)) -> Bool {
    lhs.0 != rhs.0 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
}
