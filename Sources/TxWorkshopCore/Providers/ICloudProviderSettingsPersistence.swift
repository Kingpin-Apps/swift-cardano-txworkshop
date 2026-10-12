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
/// iCloud's copy and each device's copy are always joined, never replaced:
/// a device that starts syncing with few providers, or before iCloud has
/// reached it, adds its own and takes the others', and cannot wipe them. A
/// provider leaves every device only when it is removed on purpose, which
/// is recorded and synced. Providers tied to this machine, a local node or
/// cardano-cli, stay in the local copy only: their socket paths mean nothing
/// elsewhere.
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

    /// This device's settings joined with iCloud's, iCloud's version of a
    /// provider winning. Providers only this device had go up to iCloud.
    public func load() throws -> ProviderSettings? {
        let localSettings = try local.load()
        guard let cloudSettings = try cloudSettings() else {
            // Nothing in iCloud yet: this device's settings start it off.
            if let localSettings { try saveToCloud(localSettings) }
            return localSettings
        }
        let merged = Self.join(cloudSettings, localSettings ?? ProviderSettings())
        if Self.shareable(merged) != Self.shareable(cloudSettings) { try saveToCloud(merged) }
        try local.save(merged)
        return merged
    }

    /// Saves `settings`, joined with anything another device added to iCloud
    /// since this one last read it; this device's version of a provider wins.
    public func save(_ settings: ProviderSettings) throws {
        let merged = try cloudSettings().map { Self.join(settings, $0) } ?? settings
        try local.save(merged)
        try saveToCloud(merged)
    }

    /// Adds `settings` to what is already in iCloud, when this device starts
    /// syncing, and returns the result. iCloud's choice of provider for each
    /// network stays.
    public func join(_ settings: ProviderSettings) throws -> ProviderSettings {
        cloud.synchronize()
        let joined = try cloudSettings().map { Self.join($0, settings) } ?? settings
        try local.save(joined)
        try saveToCloud(joined)
        return joined
    }

    private func cloudSettings() throws -> ProviderSettings? {
        guard let data = cloud.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(ProviderSettings.self, from: data)
    }

    /// `primary` with what `secondary` adds: its providers that `primary`
    /// lacks, and its choices for networks `primary` has none for. A provider
    /// both have under another id (the same kind, network, address and name)
    /// is not added twice, and one removed on either side is gone from both.
    static func join(_ primary: ProviderSettings, _ secondary: ProviderSettings) -> ProviderSettings {
        func same(_ a: ProviderConfiguration, _ b: ProviderConfiguration) -> Bool {
            a.id == b.id || (a.kind == b.kind && a.network == b.network && a.url == b.url && a.name == b.name)
        }
        var removed = primary.removed
        for id in secondary.removed where !removed.contains(id) { removed.append(id) }
        var providers = primary.providers
        for provider in secondary.providers where !providers.contains(where: { same($0, provider) }) {
            providers.append(provider)
        }
        providers.removeAll { removed.contains($0.id) }
        let ids = Set(providers.map(\.id))
        var selection = primary.selection.filter { ids.contains($0.value) }
        for (network, id) in secondary.selection where selection[network] == nil && ids.contains(id) {
            selection[network] = id
        }
        // This machine's own providers stay chosen here.
        for (network, id) in secondary.selection {
            if let provider = providers.first(where: { $0.id == id }), provider.kind.requiresDirectDistribution {
                selection[network] = id
            }
        }
        return ProviderSettings(providers: providers, selection: selection, removed: removed)
    }

    private func saveToCloud(_ settings: ProviderSettings) throws {
        cloud.set(try JSONEncoder().encode(Self.shareable(settings)), forKey: key)
        cloud.synchronize()
    }

    /// The part of `settings` other devices can use.
    static func shareable(_ settings: ProviderSettings) -> ProviderSettings {
        let providers = settings.providers.filter { !$0.kind.requiresDirectDistribution }
        let ids = Set(providers.map(\.id))
        return ProviderSettings(
            providers: providers, selection: settings.selection.filter { ids.contains($0.value) }, removed: settings.removed
        )
    }
}
