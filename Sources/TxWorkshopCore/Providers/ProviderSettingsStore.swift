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

    /// Whether providers and their API keys sync through iCloud.
    public let syncsWithICloud: Bool

    @ObservationIgnored private let persistence: any ProviderSettingsPersistence
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private var cloudChanges: Task<Void, Never>?

    public init(
        persistence: any ProviderSettingsPersistence = UserDefaultsProviderSettingsPersistence(),
        secrets: any SecretStore = KeychainSecretStore(),
        directDistribution: Bool = false,
        syncsWithICloud: Bool = false
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.directDistribution = directDistribution
        self.syncsWithICloud = syncsWithICloud
        do {
            settings = try persistence.load() ?? ProviderSettings()
        } catch {
            settings = ProviderSettings()
            lastError = String(describing: error)
        }
    }

    /// Settings that sync: in iCloud, with API keys in iCloud Keychain. For the
    /// App Store build; the Developer ID build keeps its settings on the Mac.
    public static func syncingWithICloud() -> ProviderSettingsStore {
        let store = ProviderSettingsStore(
            persistence: ICloudProviderSettingsPersistence(),
            secrets: KeychainSecretStore(synchronizable: true),
            syncsWithICloud: true
        )
        store.moveAPIKeysToICloudKeychain()
        store.followICloudChanges()
        return store
    }

    /// Reloads when another device changes the settings in iCloud.
    private func followICloudChanges() {
        cloudChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
                self?.reload()
            }
        }
    }

    /// Reads the settings again.
    public func reload() {
        do {
            if let loaded = try persistence.load(), loaded != settings { settings = loaded }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Saves each API key again, once, so keys added before syncing was on
    /// move to iCloud Keychain.
    private func moveAPIKeysToICloudKeychain() {
        let flag = "providerKeysInICloudKeychain"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        for provider in settings.providers where !provider.kind.requiresDirectDistribution {
            if let key = apiKey(for: provider), !key.isEmpty {
                try? secrets.setSecret(key, for: provider.secretAccount)
            }
        }
        UserDefaults.standard.set(true, forKey: flag)
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
