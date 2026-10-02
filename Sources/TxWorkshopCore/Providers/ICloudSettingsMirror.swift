import Foundation

/// Keeps a few user-defaults settings, such as the chosen block explorer, the
/// same on every device signed in to the same iCloud account. Views keep
/// reading them with `@AppStorage`; this copies changes both ways.
@MainActor
public final class ICloudSettingsMirror {
    private let keys: [String]
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore
    private var tasks: [Task<Void, Never>] = []

    public init(keys: [String], defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore = .default) {
        self.keys = keys
        self.defaults = defaults
        self.cloud = cloud
    }

    /// Takes iCloud's values where it has them, sends this device's otherwise,
    /// then follows changes on either side.
    public func start() {
        cloud.synchronize()
        for key in keys {
            if let value = cloud.string(forKey: key) {
                defaults.set(value, forKey: key)
            } else if let value = defaults.string(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification) {
                self?.pullFromCloud()
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.pushToCloud()
            }
        })
    }

    private func pullFromCloud() {
        for key in keys {
            if let value = cloud.string(forKey: key), defaults.string(forKey: key) != value {
                defaults.set(value, forKey: key)
            }
        }
    }

    private func pushToCloud() {
        for key in keys {
            if let value = defaults.string(forKey: key), cloud.string(forKey: key) != value {
                cloud.set(value, forKey: key)
            }
        }
    }
}
