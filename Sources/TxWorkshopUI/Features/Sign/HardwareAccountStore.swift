import CardanoHWKit
import Foundation
import Observation
import TxWorkshopEngine

/// Hardware wallet accounts the app has imported: their public keys only, so
/// it can tell which signatures a device can make. Kept in user defaults.
@MainActor
@Observable
final class HardwareAccountStore {
    struct Account: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var connection: HardwareConnection
        var model: HardwareAccountModel
        var keyHashes: [String]
    }

    private(set) var accounts: [Account]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "hardwareAccounts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accounts = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Account].self, from: $0) } ?? []
    }

    func add(_ account: Account) {
        accounts.append(account)
        persist()
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: key)
    }
}
