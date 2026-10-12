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

    @Test("A device that starts syncing before iCloud reaches it cannot wipe the others' providers")
    func lateDeviceDoesNotWipe() throws {
        let cloud = MemoryCloud()
        let blockfrost = ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet)
        let preprod = ProviderConfiguration(name: "Koios Preprod", kind: .koios, network: .preprod)
        let macLocal = local()
        let mac = ICloudProviderSettingsPersistence(local: macLocal, cloud: cloud)
        try mac.save(ProviderSettings(providers: [blockfrost, preprod], selection: ["mainnet": blockfrost.id, "preprod": preprod.id]))

        // The headset's first download has not arrived: iCloud looks empty to
        // it, so it starts iCloud off with its one provider.
        let early = MemoryCloud()
        let headset = ICloudProviderSettingsPersistence(local: local(), cloud: early)
        _ = try headset.join(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id]))
        cloud.values = early.values

        // The Mac keeps its providers, adds the headset's, and puts them all back in iCloud.
        let onMac = try #require(try mac.load())
        #expect(Set(onMac.providers.map(\.id)) == [blockfrost.id, preprod.id, koios.id])
        #expect(onMac.selection["preprod"] == preprod.id)
        let inCloud = try #require(try ICloudProviderSettingsPersistence(local: local(), cloud: cloud).load())
        #expect(Set(inCloud.providers.map(\.id)) == [blockfrost.id, preprod.id, koios.id])
    }

    @Test("A provider removed on one device is removed on the others, and not added back")
    func removalSyncs() throws {
        let cloud = MemoryCloud()
        let blockfrost = ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet)
        let mac = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        let phone = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        try mac.save(ProviderSettings(providers: [koios, blockfrost], selection: ["mainnet": blockfrost.id]))
        #expect(try phone.load()?.providers.count == 2)

        try mac.save(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id], removed: [blockfrost.id]))
        let onPhone = try #require(try phone.load())
        #expect(onPhone.providers == [koios])
        #expect(onPhone.selection["mainnet"] == koios.id)
        // The phone still had Blockfrost; saving there does not bring it back.
        try phone.save(onPhone)
        #expect(try mac.load()?.providers == [koios])
    }

    @Test("Saving keeps a provider another device added meanwhile")
    func saveKeepsOthersAdditions() throws {
        let cloud = MemoryCloud()
        let blockfrost = ProviderConfiguration(name: "Blockfrost", kind: .blockfrost, network: .mainnet)
        let mac = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        let phone = ICloudProviderSettingsPersistence(local: local(), cloud: cloud)
        try mac.save(ProviderSettings(providers: [koios], selection: ["mainnet": koios.id]))
        let stale = try #require(try phone.load())
        try mac.save(ProviderSettings(providers: [koios, blockfrost], selection: ["mainnet": koios.id]))

        // The phone, not yet told, renames Koios from its stale copy.
        var renamed = stale
        renamed.providers[0].name = "Koios (mine)"
        try phone.save(renamed)
        let after = try #require(try mac.load())
        #expect(after.providers.map(\.name).sorted() == ["Blockfrost", "Koios (mine)"])
    }

    @Test("Settings saved before removals were recorded still read")
    func readsOldSettings() throws {
        let old = Data(#"{"providers":[],"selection":{}}"#.utf8)
        let settings = try JSONDecoder().decode(ProviderSettings.self, from: old)
        #expect(settings.removed.isEmpty)
    }
}
