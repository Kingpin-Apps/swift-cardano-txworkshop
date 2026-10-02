import Foundation
import Testing
@testable import TxWorkshopCore

/// An iCloud key-value store in memory.
private final class MemoryCloud: CloudKeyValueStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func synchronize() -> Bool { true }
}

@Suite("Provider settings in iCloud")
struct ICloudProviderSettingsTests {
    let koios = ProviderConfiguration(name: "Koios", kind: .koios, network: .mainnet)
    let node = ProviderConfiguration(name: "My node", kind: .localNode, network: .mainnet, socketPath: "~/node.socket")

    /// A fresh user-defaults suite for each test.
    func local() -> UserDefaultsProviderSettingsPersistence {
        let suite = "tw-icloud-test-\(UUID().uuidString)"
        return UserDefaultsProviderSettingsPersistence(suiteName: suite)
    }

    @Test("A provider saved on one device loads on another")
    func syncsBetweenDevices() throws {
        let cloud = MemoryCloud()
        let phone = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        try phone.save(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id]))

        let mac = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        let loaded = try #require(try mac.load())
        #expect(loaded.providers == [koios])
        #expect(loaded.selection["mainnet"] == koios.id)
    }

    @Test("A device's settings start iCloud off when it has none")
    func seedsTheCloud() throws {
        let cloud = MemoryCloud()
        let existing = local()
        try existing.save(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id]))
        _ = try ICloudProviderSettingsPersistence(local: existing, cloud: cloud).load()

        let other = try #require(try ICloudProviderSettingsPersistence(local: local(), cloud: cloud).load())
        #expect(other.providers == [koios])
    }

    @Test("A local node stays on its Mac, and stays chosen there")
    func machineProvidersStayLocal() throws {
        let cloud = MemoryCloud()
        let mac = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        try mac.save(ProviderSettings(providers: [koios, node], selection: ["mainnet": node.id]))

        // Other devices see Koios only, and no choice pointing at the node.
        let phone = try #require(try ICloudProviderSettingsPersistence(local: local(), cloud: cloud).load())
        #expect(phone.providers == [koios])
        #expect(phone.selection["mainnet"] == nil)

        // The Mac keeps its node, and its choice of it, after iCloud changes.
        let reloaded = try #require(try mac.load())
        #expect(reloaded.providers.contains(node))
        #expect(reloaded.selection["mainnet"] == node.id)
    }

    @Test("Turning sync on joins this device's providers to iCloud's, without doubles")
    func joinsWithoutDoubles() throws {
        let cloud = MemoryCloud()
        let blockfrost = ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet)
        try ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
            .save(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id]))

        // This device set up its own Koios, and Blockfrost, before syncing.
        let ownKoios = ProviderConfiguration(name: "Koios", kind: .koios, network: .mainnet)
        let joined = try ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
            .join(ProviderSettings(providers: [ownKoios, blockfrost], selection: ["mainnet": blockfrost.id]))

        #expect(joined.providers.map(\.name) == ["Koios", "Blockfrost"])
        #expect(joined.selection["mainnet"] == koios.id)  // iCloud's choice stays
    }
}
