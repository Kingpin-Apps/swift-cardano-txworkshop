import Foundation
import TxWorkshopCore

extension TxWorkshopDocument {
    /// A document holding a small mainnet transaction, for previews.
    static var preview: TxWorkshopDocument {
        let hex = "84a300818258200000000000000000000000000000000000000000000000000000000000000000000181825839"
            + "01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            + "0000001a000f4240021a0002a8b1a0f5f6"
        return TxWorkshopDocument(content: TxDocumentContent(
            transaction: try? TxDocumentCodec.bytes(fromHex: hex),
            notes: "A sample transaction."
        ))
    }
}

extension ProviderSettingsStore {
    /// A store with a provider per public network, for previews.
    @MainActor
    static var preview: ProviderSettingsStore {
        let store = ProviderSettingsStore(
            persistence: InMemoryProviderSettingsPersistence(),
            secrets: InMemorySecretStore()
        )
        store.save(ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet), apiKey: "mainnetPREVIEW")
        store.save(ProviderConfiguration(name: "Koios", kind: .koios, network: .preprod))
        return store
    }
}
