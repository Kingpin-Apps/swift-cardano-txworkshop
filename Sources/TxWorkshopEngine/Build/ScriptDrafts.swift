import Foundation
import SwiftCardanoCore
import SwiftCardanoTxBuilder
import SwiftCardanoUPLC
import TxWorkshopCore

extension TransactionComposer {
    /// The script a draft names, with the UTxO carrying it for a reference
    /// script.
    static func script(_ draft: ScriptDraft, context: WorkshopChainContext) async throws -> (script: ScriptType, source: ScriptOrUTxO) {
        switch draft {
        case .native(let json):
            do {
                let script = ScriptType.nativeScript(try NativeScript.fromJSON(json))
                return (script, .script(script))
            } catch {
                throw ComposeError.badScript("The native script JSON does not parse: \(error)")
            }
        case .plutus(let version, let hex):
            let script = try plutusScript(version: version, hex: hex)
            return (script, .script(script))
        case .reference(let id):
            guard let input = TransactionValidation.input(id), let (utxo, _) = try await context.utxo(input: input) else {
                throw ComposeError.unknownInput(id)
            }
            guard let script = utxo.output.script else { throw ComposeError.badScript("\(id) carries no reference script.") }
            return (script, .utxo(utxo))
        }
    }

    /// A Plutus script from CBOR hex. A `.plutus` file's `cborHex` wraps the
    /// script's bytes in one more CBOR byte string than a blueprint's
    /// `compiledCode`; either is accepted.
    static func plutusScript(version: Int, hex: String) throws -> ScriptType {
        guard var bytes = try? TxDocumentCodec.bytes(fromHex: hex) else { throw ComposeError.badScript("The script is not hex.") }
        if case .bytes(let inner)? = try? Primitive.fromCBOR(data: bytes), let first = inner.first, first >> 5 == 2 {
            bytes = inner
        }
        do {
            _ = try FlatDecoder().decode(try extractFlatBytes(from: bytes))
        } catch {
            throw ComposeError.badScript("The script does not decode as UPLC: \(error)")
        }
        switch version {
        case 1: return .plutusV1Script(PlutusV1Script(data: bytes))
        case 2: return .plutusV2Script(PlutusV2Script(data: bytes))
        case 3: return .plutusV3Script(PlutusV3Script(data: bytes))
        default: throw ComposeError.badScript("Plutus version \(version) does not exist.")
        }
    }

    static func plutusData(_ hex: String, what: String) throws -> PlutusData {
        guard let bytes = try? TxDocumentCodec.bytes(fromHex: hex), let data = try? PlutusData.fromCBOR(data: bytes) else {
            throw ComposeError.badPlutusData(what)
        }
        return data
    }

    static func isPlutus(_ script: ScriptType) -> Bool {
        if case .nativeScript = script { return false }
        return true
    }

    /// Adds the recipe's mints, script inputs and collateral to `builder`.
    static func addScripts(_ recipe: BuildRecipe, to builder: TxBuilder, context: WorkshopChainContext) async throws {
        var minted: [(policy: String, nameHex: String, quantity: Int64)] = []
        for draft in recipe.mints {
            let (script, source) = try await Self.script(draft.script, context: context)
            let policy = try scriptHash(script: script).payload.hex
            minted += draft.assets.map { (policy, $0.assetNameHex, $0.quantity) }
            if isPlutus(script) {
                let redeemer = Redeemer(tag: .mint, data: try plutusData(draft.redeemer, what: "the minting redeemer"))
                try builder.addMintingScript(source, redeemer: redeemer)
            } else if case .nativeScript(let native) = script, case .script = source {
                builder.nativeScripts = (builder.nativeScripts ?? []) + [native]
            } else {
                try builder.addMintingScript(source)
            }
        }
        if minted.contains(where: { $0.quantity != 0 }) {
            builder.mint = try multiAsset(minted)
        }

        for draft in recipe.scriptInputs {
            guard let input = TransactionValidation.input(draft.input), let (utxo, _) = try await context.utxo(input: input) else {
                throw ComposeError.unknownInput(draft.input)
            }
            let source = try await draft.script.asyncMap { try await Self.script($0, context: context).source }
            let datum = draft.datum.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : Datum.plutusData(try plutusData(draft.datum, what: "the datum for \(draft.input)"))
            let redeemer = Redeemer(tag: .spend, data: try plutusData(draft.redeemer, what: "the redeemer for \(draft.input)"))
            do {
                try await builder.addScriptInput(utxo, script: source, datum: datum, redeemer: redeemer)
            } catch {
                throw ComposeError.builder(String(describing: error))
            }
        }

        for id in recipe.collateral {
            guard let input = TransactionValidation.input(id), let (utxo, _) = try await context.utxo(input: input) else {
                throw ComposeError.unknownInput(id)
            }
            builder.collaterals.append(utxo)
        }
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
