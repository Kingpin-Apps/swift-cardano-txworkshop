import Foundation

/// A small key-value store in iCloud: `NSUbiquitousKeyValueStore`, or a
/// stand-in for tests.
public protocol CloudKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {
    public func set(_ data: Data?, forKey key: String) {
        if let data { set(data as Any, forKey: key) } else { removeObject(forKey: key) }
    }
}

/// Provider settings kept on the device and in iCloud, so a provider set up
/// on one device is there on the others signed in to the same account.
///
/// iCloud holds the providers any device can use. Ones tied to this machine,
/// a local node or cardano-cli, stay in the local copy only: their socket
/// paths mean nothing elsewhere. When the two disagree, iCloud's copy wins,
/// with this machine's own providers added back.
public final class ICloudProviderSettingsPersistence: ProviderSettingsPersistence, @unchecked Sendable {
    // @unchecked: NSUbiquitousKeyValueStore is documented as thread-safe, and
    // the local persistence is a value type holding only a key and a suite name.
    private let local: UserDefaultsProviderSettingsPersistence
    private let cloud: any CloudKeyValueStore
    private let key: String

    public init(
        key: String = "providerSettings",
        local: UserDefaultsProviderSettingsPersistence = UserDefaultsProviderSettingsPersistence(),
        cloud: any CloudKeyValueStore = NSUbiquitousKeyValueStore.default
    ) {
        self.key = key
        self.local = local
        self.cloud = cloud
        cloud.synchronize()
    }

    public func load() throws -> ProviderSettings? {
        let localSettings = try local.load()
        guard let data = cloud.data(forKey: key) else {
            // Nothing in iCloud yet: this device's settings start it off.
            if let localSettings { try saveToCloud(localSettings) }
            return localSettings
        }
        let merged = Self.merge(cloud: try JSONDecoder().decode(ProviderSettings.self, from: data), local: localSettings)
        try local.save(merged)
        return merged
    }

    public func save(_ settings: ProviderSettings) throws {
        try local.save(settings)
        try saveToCloud(settings)
    }

    private func saveToCloud(_ settings: ProviderSettings) throws {
        cloud.set(try JSONEncoder().encode(Self.shareable(settings)), forKey: key)
        cloud.synchronize()
    }

    /// The part of `settings` other devices can use.
    static func shareable(_ settings: ProviderSettings) -> ProviderSettings {
        let providers = settings.providers.filter { !$0.kind.requiresDirectDistribution }
        let ids = Set(providers.map(\.id))
        return ProviderSettings(providers: providers, selection: settings.selection.filter { ids.contains($0.value) })
    }

    /// iCloud's settings, with this machine's own providers, and its choice
    /// of them, kept.
    static func merge(cloud: ProviderSettings, local: ProviderSettings?) -> ProviderSettings {
        guard let local else { return cloud }
        let machineOnly = local.providers.filter(\.kind.requiresDirectDistribution)
        var merged = ProviderSettings(providers: cloud.providers + machineOnly, selection: cloud.selection)
        let machineIDs = Set(machineOnly.map(\.id))
        for (network, id) in local.selection where machineIDs.contains(id) {
            merged.selection[network] = id
        }
        return merged
    }
}
