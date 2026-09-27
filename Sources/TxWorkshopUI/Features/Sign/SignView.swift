import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Who must sign, signing with stored keys, collecting co-signers'
/// witnesses, and submitting.
struct SignView: View {
    let document: TxWorkshopDocument
    @Environment(SigningKeyStore.self) private var keys
    @Environment(\.undoManager) private var undoManager
    @State private var analysis: LoadState<RequiredSignatures> = .idle
    @State private var problem: String?
    @State private var isAddingKey = false
    @State private var isImporting = false

    private struct AnalysisKey: Equatable {
        let transaction: Data?
        let utxos: [String]
    }

    private var knownUTxOs: [String] {
        (document.content.chainContext?.utxos ?? []) + (document.content.recipe?.utxos ?? [])
    }

    var body: some View {
        Form {
            if document.content.transaction == nil {
                Section { Text("Add or build a transaction first.", bundle: #bundle) }
            } else {
                switch analysis {
                case .idle, .loading:
                    Section { ProgressView() }
                case .failed(let message):
                    Section { Text(verbatim: message).foregroundStyle(TWColor.failure) }
                case .loaded(let needed):
                    SignaturesSection(needed: needed, keys: keys.keys, onSign: sign)
                    if let problem {
                        Section { Text(verbatim: problem).foregroundStyle(TWColor.failure) }
                    }
                    HardwareSection(
                        document: document, missing: Set(needed.signers.filter { !$0.isSigned }.map(\.keyHash)), knownUTxOs: knownUTxOs
                    )
                    #if os(iOS)
                    WatchReviewSection(document: document)
                    #endif
                    WitnessesSection(document: document, onImport: { isImporting = true })
                    SubmitSection(document: document, isComplete: needed.isComplete)
                }
            }
            KeysSection(onAdd: { isAddingKey = true })
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Sign & Submit", bundle: #bundle))
        .task(id: AnalysisKey(transaction: document.content.transaction, utxos: knownUTxOs)) {
            guard let bytes = document.content.transaction else { return }
            do {
                analysis = .loaded(try RequiredSignatures.analyze(bytes, utxos: knownUTxOs))
            } catch {
                analysis = .failed(String(describing: error))
            }
        }
        .sheet(isPresented: $isAddingKey) { AddKeySheet() }
        .sheet(isPresented: $isImporting) { ImportWitnessSheet(document: document, undoManager: undoManager) }
    }

    /// Signs with `key` for every unsigned signature it can make, after the
    /// person confirms who they are.
    private func sign(with key: StoredSigningKey, for needed: [String]) {
        guard let bytes = document.content.transaction else { return }
        problem = nil
        Task {
            guard await OwnerCheck.confirm(String(localized: "Sign the transaction with \(key.name)", bundle: #bundle)) else { return }
            do {
                guard let secret = try keys.secret(for: key) else { throw KeyRingError.badEnvelope("The key's secret is missing from the Keychain.") }
                let ring = try KeyRing(try StoredKeyMaterial.decode(secret, kind: key.kind))
                let witnesses = try ring.witnesses(for: bytes, needed: Set(needed))
                let signed = try WitnessAssembler.merge(bytes, adding: witnesses)
                let records = try witnesses.map { witness in
                    CollectedWitness(
                        label: key.name, keyHash: try WitnessAssembler.keyHash(witness),
                        witnessCBOR: try WitnessAssembler.cborHex(witness), addedAt: .now
                    )
                }
                document.update({ content in
                    content.transaction = signed
                    content.envelope = nil
                    content.witnesses += records
                }, actionName: LocalizedStringResource("Sign", bundle: #bundle), undoManager: undoManager)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

/// The key material a stored key's Keychain secret holds.
enum StoredKeyMaterial {
    struct Mnemonic: Codable {
        let words: String
        let passphrase: String
    }

    static func encode(_ material: SigningKeyMaterial) throws -> String {
        switch material {
        case .mnemonic(let words, let passphrase):
            String(decoding: try JSONEncoder().encode(Mnemonic(words: words, passphrase: passphrase)), as: UTF8.self)
        case .envelope(let json):
            json
        }
    }

    static func decode(_ secret: String, kind: StoredSigningKey.Kind) throws -> SigningKeyMaterial {
        switch kind {
        case .mnemonic:
            let mnemonic = try JSONDecoder().decode(Mnemonic.self, from: Data(secret.utf8))
            return .mnemonic(words: mnemonic.words, passphrase: mnemonic.passphrase)
        case .keyFile:
            return .envelope(json: secret)
        }
    }
}
