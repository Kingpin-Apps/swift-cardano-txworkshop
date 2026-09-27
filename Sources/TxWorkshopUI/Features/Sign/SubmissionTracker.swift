import Foundation
import Observation
import TxWorkshopCore
import TxWorkshopEngine
import UserNotifications

/// Watches submitted transactions until they are on chain, for every open
/// document, and posts a notification when one confirms. The list is kept in
/// user defaults, so tracking resumes when the app opens again.
@MainActor
@Observable
final class SubmissionTracker {
    struct Tracked: Codable, Equatable, Identifiable {
        var transactionID: String
        var provider: ProviderConfiguration
        var submittedAt: Date
        var confirmedAt: Date?
        var id: String { transactionID }
    }

    private(set) var tracked: [Tracked]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "trackedSubmissions"
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// How long to keep asking about a transaction.
    static let giveUpAfter: TimeInterval = 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tracked = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Tracked].self, from: $0) } ?? []
    }

    func track(_ id: String, provider: ProviderConfiguration) {
        guard !tracked.contains(where: { $0.transactionID == id }) else { return }
        tracked.append(Tracked(transactionID: id, provider: provider, submittedAt: .now))
        persist()
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        start()
    }

    func confirmedAt(_ id: String) -> Date? {
        tracked.first { $0.transactionID == id }?.confirmedAt
    }

    /// Checks pending transactions every 20 seconds while any are pending.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                let pending = self.tracked.filter { $0.confirmedAt == nil && Date.now.timeIntervalSince($0.submittedAt) < Self.giveUpAfter }
                if pending.isEmpty { break }
                for item in pending {
                    await self.check(item)
                }
                try? await Task.sleep(for: .seconds(20))
            }
            self?.loop = nil
        }
    }

    func check(_ item: Tracked) async {
        let apiKey = try? KeychainSecretStore().secret(for: item.provider.secretAccount)
        guard (try? await TransactionSubmitter().isOnChain(item.transactionID, provider: item.provider, apiKey: apiKey)) == true,
            let index = tracked.firstIndex(where: { $0.transactionID == item.transactionID })
        else { return }
        tracked[index].confirmedAt = .now
        persist()
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Transaction confirmed", bundle: #bundle)
        content.body = String(localized: "\(String(item.transactionID.prefix(16)))… is on \(item.provider.network.id).", bundle: #bundle)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.transactionID, content: content, trigger: nil))
    }

    private func persist() {
        // Keep the last 50.
        tracked = Array(tracked.suffix(50))
        defaults.set(try? JSONEncoder().encode(tracked), forKey: key)
        syncWatch()
    }

    /// Shows the tracked submissions on the watch.
    func syncWatch() {
        WatchLink.shared.update(submissions: tracked.map {
            WatchSubmission(id: $0.transactionID, network: $0.provider.network.id, submittedAt: $0.submittedAt, confirmedAt: $0.confirmedAt)
        })
    }
}
