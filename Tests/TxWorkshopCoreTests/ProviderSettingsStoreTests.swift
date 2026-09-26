import Foundation
import Testing

@testable import TxWorkshopCore

@MainActor
@Suite("Provider settings")
struct ProviderSettingsStoreTests {
    func store(directDistribution: Bool = false) -> (ProviderSettingsStore, InMemoryProviderSettingsPersistence, InMemorySecretStore) {
        let persistence = InMemoryProviderSettingsPersistence()
        let secrets = InMemorySecretStore()
        return (ProviderSettingsStore(persistence: persistence, secrets: secrets, directDistribution: directDistribution), persistence, secrets)
    }

    @Test("The first provider for a network becomes its selection")
    func firstProviderIsSelected() {
        let (store, _, _) = store()
        let koios = ProviderConfiguration(name: "Koios", kind: .koios, network: .preprod)
        store.save(koios)
        store.save(ProviderConfiguration(name: "Other", kind: .koios, network: .preprod))
        #expect(store.selectedProvider(for: .preprod) == koios)
        #expect(store.selectedProvider(for: .mainnet) == nil)
    }

    @Test("API keys go to the secret store, never to the settings")
    func apiKeysStaySecret() throws {
        let (store, persistence, secrets) = store()
        let provider = ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet)
        store.save(provider, apiKey: "mainnetSECRET")
        #expect(try secrets.secret(for: provider.secretAccount) == "mainnetSECRET")
        let saved = try JSONEncoder().encode(try #require(try persistence.load()))
        #expect(!String(decoding: saved, as: UTF8.self).contains("mainnetSECRET"))
        #expect(store.hasAPIKey(provider))

        store.save(provider, apiKey: "")
        #expect(!store.hasAPIKey(provider))
    }

    @Test("Settings survive a new store")
    func persistence() {
        let (store, persistence, secrets) = store()
        let provider = ProviderConfiguration(name: "Koios", kind: .koios, network: .preview)
        store.save(provider)
        let reopened = ProviderSettingsStore(persistence: persistence, secrets: secrets)
        #expect(reopened.providers == [provider])
        #expect(reopened.selectedProvider(for: .preview) == provider)
    }

    @Test("Removing the selected provider selects another and forgets its key")
    func removal() throws {
        let (store, _, secrets) = store()
        let first = ProviderConfiguration(name: "A", kind: .blockfrost, network: .mainnet)
        let second = ProviderConfiguration(name: "B", kind: .koios, network: .mainnet)
        store.save(first, apiKey: "key")
        store.save(second)
        store.remove(first)
        #expect(store.selectedProvider(for: .mainnet) == second)
        #expect(try secrets.secret(for: first.secretAccount) == nil)
    }

    @Test("The local node is offered only in the Developer ID build")
    func directOnlyKinds() {
        #expect(!store().0.availableKinds.contains(.localNode))
        #expect(store(directDistribution: true).0.availableKinds.contains(.localNode))
    }

    @Test("A configuration says what it still needs")
    func problems() {
        #expect(ProviderConfiguration(name: "", kind: .koios, network: .mainnet).problem(hasAPIKey: false) != nil)
        #expect(ProviderConfiguration(name: "B", kind: .blockfrost, network: .mainnet).problem(hasAPIKey: false) != nil)
        #expect(ProviderConfiguration(name: "B", kind: .blockfrost, network: .mainnet).problem(hasAPIKey: true) == nil)
        #expect(ProviderConfiguration(name: "O", kind: .ogmios, network: .mainnet).problem(hasAPIKey: false) != nil)
        #expect(ProviderConfiguration(name: "O", kind: .ogmios, network: .mainnet, url: URL(string: "ws://localhost:1337")).problem(hasAPIKey: false) == nil)
    }
}
