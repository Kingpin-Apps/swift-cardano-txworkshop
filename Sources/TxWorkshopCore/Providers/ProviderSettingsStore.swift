import Foundation
import Observation
import Synchronization

/// Where provider configurations are persisted. Secrets never go here.
public protocol ProviderSettingsPersistence: Sendable {
    func load() throws -> ProviderSettings?
    func save(_ settings: ProviderSettings) throws
}

/// The configured providers and which one each network uses.
public struct ProviderSettings: Codable, Sendable, Equatable {
    public var providers: [ProviderConfiguration]
    /// The provider chosen for each network, by network id.
    public var selection: [String: UUID]

    public init(providers: [ProviderConfiguration] = [], selection: [String: UUID] = [:]) {
        self.providers = providers
        self.selection = selection
    }
}

/// Provider settings kept in user defaults, as JSON.
public struct UserDefaultsProviderSettingsPersistence: ProviderSettingsPersistence {
    public let key: String
    private let suiteName: String?

    public init(key: String = "providerSettings", suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func load() throws -> ProviderSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(ProviderSettings.self, from: data)
    }

    public func save(_ settings: ProviderSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }
}

/// The app's provider settings: what is configured, which provider each
/// network uses, and their API keys (in the Keychain).
@MainActor
@Observable
public final class ProviderSettingsStore {
    public private(set) var settings: ProviderSettings
    /// The last error saving or loading, for the settings screen to show.
    public private(set) var lastError: String?

    /// Whether this is the Developer ID build, which may use providers the
    /// App Sandbox rules out.
    public let directDistribution: Bool

    /// Whether this build can sync through iCloud: the App Store build can;
    /// the Developer ID build has no iCloud.
    public let canSyncWithICloud: Bool
    /// Whether providers, their API keys and the explorer sync through iCloud,
    /// as the person chose. See ``setSyncsWithICloud(_:)``.
    public private(set) var syncsWithICloud: Bool

    @ObservationIgnored private let local: UserDefaultsProviderSettingsPersistence?
    @ObservationIgnored private let cloud: ICloudProviderSettingsPersistence?
    @ObservationIgnored private let mirror: ICloudSettingsMirror?
    @ObservationIgnored private var persistence: any ProviderSettingsPersistence
    @ObservationIgnored private var secrets: any SecretStore
    @ObservationIgnored private var cloudChanges: Task<Void, Never>?

    /// Where the person's choice to sync is kept, on this device.
    static let syncPreferenceKey = "syncSettingsWithICloud"

    public init(
        persistence: any ProviderSettingsPersistence = UserDefaultsProviderSettingsPersistence(),
        secrets: any SecretStore = KeychainSecretStore(),
        directDistribution: Bool = false
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.directDistribution = directDistribution
        canSyncWithICloud = false
        syncsWithICloud = false
        local = nil
        cloud = nil
        mirror = nil
        settings = ProviderSettings()
        load()
    }

    private init(local: UserDefaultsProviderSettingsPersistence, cloud: ICloudProviderSettingsPersistence, mirror: ICloudSettingsMirror, syncs: Bool) {
        self.local = local
        self.cloud = cloud
        self.mirror = mirror
        directDistribution = false
        canSyncWithICloud = true
        syncsWithICloud = syncs
        persistence = syncs ? cloud : local
        secrets = KeychainSecretStore(synchronizable: syncs)
        settings = ProviderSettings()
        load()
    }

    /// The App Store build's settings: synced through iCloud unless the person
    /// turned that off, with API keys in iCloud Keychain and the chosen
    /// explorer (`explorerKey`) kept the same everywhere.
    public static func appStore(explorerKey: String) -> ProviderSettingsStore {
        let syncs = UserDefaults.standard.object(forKey: syncPreferenceKey) as? Bool ?? true
        let store = ProviderSettingsStore(
            local: UserDefaultsProviderSettingsPersistence(),
            cloud: ICloudProviderSettingsPersistence(),
            mirror: ICloudSettingsMirror(keys: [explorerKey]),
            syncs: syncs
        )
        if syncs {
            store.moveAPIKeysToICloudKeychainOnce()
            store.startSyncing()
        }
        return store
    }

    /// Saves each API key again, once, so keys added before this version,
    /// which synced nothing, move to iCloud Keychain.
    private func moveAPIKeysToICloudKeychainOnce() {
        let flag = "providerKeysInICloudKeychain"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        for (account, key) in apiKeys() { try? secrets.setSecret(key, for: account) }
        UserDefaults.standard.set(true, forKey: flag)
    }

    /// Whether the person is signed in to iCloud on this device.
    public var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Turns iCloud sync on or off, for this device.
    ///
    /// On: this device's providers join those already in iCloud, and its API
    /// keys move to iCloud Keychain. Off: this device keeps its own copy of
    /// everything, and the other devices keep theirs; nothing is deleted from
    /// iCloud.
    public func setSyncsWithICloud(_ on: Bool) {
        guard canSyncWithICloud, on != syncsWithICloud, let local, let cloud else { return }
        let keys = apiKeys()
        syncsWithICloud = on
        UserDefaults.standard.set(on, forKey: Self.syncPreferenceKey)
        secrets = KeychainSecretStore(synchronizable: on)
        if on {
            persistence = cloud
            do {
                settings = try cloud.join(settings)
            } catch {
                lastError = String(describing: error)
            }
            startSyncing()
        } else {
            persistence = local
            cloudChanges?.cancel()
            cloudChanges = nil
            mirror?.stop()
            persist()
        }
        // Each key is saved again in the new place: iCloud Keychain when on,
        // this device's own copy when off.
        for (account, key) in keys {
            try? secrets.setSecret(key, for: account)
        }
    }

    private func startSyncing() {
        mirror?.start()
        cloudChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
                self?.load()
            }
        }
    }

    /// The API key of every provider that has one, by Keychain account.
    private func apiKeys() -> [String: String] {
        var keys: [String: String] = [:]
        for provider in settings.providers where !provider.kind.requiresDirectDistribution {
            if let key = apiKey(for: provider), !key.isEmpty { keys[provider.secretAccount] = key }
        }
        return keys
    }

    /// Reads the settings again, as when another device changes them.
    public func load() {
        do {
            if let loaded = try persistence.load(), loaded != settings { settings = loaded }
        } catch {
            lastError = String(describing: error)
        }
    }

    public var providers: [ProviderConfiguration] { settings.providers }

    public var availableKinds: [ProviderKind] { ProviderKind.available(directDistribution: directDistribution) }

    /// The providers configured for `network`.
    public func providers(for network: CardanoNetwork) -> [ProviderConfiguration] {
        settings.providers.filter { $0.network == network }
    }

    /// The provider `network` uses, if one is chosen and still exists.
    public func selectedProvider(for network: CardanoNetwork) -> ProviderConfiguration? {
        guard let id = settings.selection[network.id] else { return nil }
        return settings.providers.first { $0.id == id }
    }

    public func select(_ provider: ProviderConfiguration) {
        settings.selection[provider.network.id] = provider.id
        persist()
    }

    /// Adds or replaces `provider`, and stores its API key when one is given.
    /// An empty key removes the stored one.
    public func save(_ provider: ProviderConfiguration, apiKey: String? = nil) {
        if let index = settings.providers.firstIndex(where: { $0.id == provider.id }) {
            settings.providers[index] = provider
        } else {
            settings.providers.append(provider)
            if settings.selection[provider.network.id] == nil {
                settings.selection[provider.network.id] = provider.id
            }
        }
        if let apiKey {
            do {
                if apiKey.isEmpty {
                    try secrets.removeSecret(for: provider.secretAccount)
                } else {
                    try secrets.setSecret(apiKey, for: provider.secretAccount)
                }
            } catch {
                lastError = String(describing: error)
            }
        }
        persist()
    }

    public func remove(_ provider: ProviderConfiguration) {
        settings.providers.removeAll { $0.id == provider.id }
        if settings.selection[provider.network.id] == provider.id {
            settings.selection[provider.network.id] = providers(for: provider.network).first?.id
        }
        try? secrets.removeSecret(for: provider.secretAccount)
        persist()
    }

    /// The provider's API key, if one is stored.
    public func apiKey(for provider: ProviderConfiguration) -> String? {
        try? secrets.secret(for: provider.secretAccount)
    }

    public func hasAPIKey(_ provider: ProviderConfiguration) -> Bool {
        !(apiKey(for: provider) ?? "").isEmpty
    }

    private func persist() {
        do {
            try persistence.save(settings)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }
}

/// Settings kept in memory, for previews and tests.
public final class InMemoryProviderSettingsPersistence: ProviderSettingsPersistence {
    private let storage: Mutex<ProviderSettings?>

    public init(_ settings: ProviderSettings? = nil) {
        storage = Mutex(settings)
    }

    public func load() throws -> ProviderSettings? { storage.withLock { $0 } }
    public func save(_ settings: ProviderSettings) throws { storage.withLock { $0 = settings } }
}
