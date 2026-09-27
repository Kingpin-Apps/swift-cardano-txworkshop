import Foundation
import Observation
#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity
#endif

/// What the phone shows on the watch: submissions being tracked, and a
/// transaction waiting for review.
public struct WatchState: Codable, Sendable, Equatable {
    public var submissions: [WatchSubmission]
    public var review: WatchReviewRequest?

    public init(submissions: [WatchSubmission] = [], review: WatchReviewRequest? = nil) {
        self.submissions = submissions
        self.review = review
    }
}

public struct WatchSubmission: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var network: String
    public var submittedAt: Date
    public var confirmedAt: Date?

    public init(id: String, network: String, submittedAt: Date, confirmedAt: Date? = nil) {
        self.id = id
        self.network = network
        self.submittedAt = submittedAt
        self.confirmedAt = confirmedAt
    }
}

/// A transaction handed to the watch to look over before the phone signs it.
/// The watch holds no keys: approving only tells the phone.
public struct WatchReviewRequest: Codable, Sendable, Equatable, Identifiable {
    public struct Output: Codable, Sendable, Equatable, Hashable {
        public var address: String
        public var lovelace: Int64
        public var assetCount: Int

        public init(address: String, lovelace: Int64, assetCount: Int) {
            self.address = address
            self.lovelace = lovelace
            self.assetCount = assetCount
        }
    }

    public var id: UUID
    public var transactionID: String
    public var network: String
    /// The transaction in a sentence.
    public var summary: String
    public var fee: UInt64
    public var outputs: [Output]
    public var requestedAt: Date

    public init(
        id: UUID = UUID(), transactionID: String, network: String, summary: String, fee: UInt64, outputs: [Output],
        requestedAt: Date = .now
    ) {
        self.id = id
        self.transactionID = transactionID
        self.network = network
        self.summary = summary
        self.fee = fee
        self.outputs = outputs
        self.requestedAt = requestedAt
    }
}

/// The watch's answer to a review request.
public struct WatchReviewReply: Codable, Sendable, Equatable {
    public var requestID: UUID
    public var approved: Bool
    public var at: Date

    public init(requestID: UUID, approved: Bool, at: Date = .now) {
        self.requestID = requestID
        self.approved = approved
        self.at = at
    }
}

/// Carries ``WatchState`` from the phone to the watch, and review replies
/// back, over WatchConnectivity. Elsewhere it does nothing.
@MainActor
@Observable
public final class WatchLink {
    public static let shared = WatchLink()

    /// On the watch, the latest state from the phone; on the phone, what was
    /// last sent.
    public private(set) var state = WatchState()
    /// On the phone, the watch's replies by request.
    public private(set) var replies: [UUID: WatchReviewReply] = [:]
    /// Whether a watch with the app is there to talk to.
    public private(set) var isReachable = false

    private var stateKey: String { Self.stateKey }
    private var replyKey: String { Self.replyKey }
    #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
    @ObservationIgnored private var delegate: Delegate?
    #endif

    private init() {}

    /// Starts the session. Call once, early.
    public func activate() {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        guard WCSession.isSupported(), delegate == nil else { return }
        let delegate = Delegate(link: self)
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        #endif
    }

    /// Phone: sends the tracked submissions.
    public func update(submissions: [WatchSubmission]) {
        state.submissions = submissions
        push()
    }

    /// Phone: asks the watch to look over `request`.
    public func requestReview(_ request: WatchReviewRequest) {
        state.review = request
        replies[request.id] = nil
        push()
    }

    /// Watch: answers the pending review.
    public func reply(approved: Bool) {
        guard let review = state.review else { return }
        let reply = WatchReviewReply(requestID: review.id, approved: approved)
        state.review = nil
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        guard let data = try? JSONEncoder().encode(reply) else { return }
        let message = [replyKey: data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
        #endif
    }

    private func push() {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        guard WCSession.default.activationState == .activated, let data = try? JSONEncoder().encode(state) else { return }
        try? WCSession.default.updateApplicationContext([stateKey: data])
        #endif
    }

    fileprivate func received(state stateData: Data?, reply replyData: Data?) {
        if let stateData, let state = try? JSONDecoder().decode(WatchState.self, from: stateData) {
            self.state = state
        }
        if let replyData, let reply = try? JSONDecoder().decode(WatchReviewReply.self, from: replyData) {
            replies[reply.requestID] = reply
            if state.review?.id == reply.requestID { state.review = nil }
        }
    }

    fileprivate nonisolated static let stateKey = "state"
    fileprivate nonisolated static let replyKey = "reply"

    fileprivate func setReachable(_ reachable: Bool) {
        isReachable = reachable
        if reachable { push() }
    }
}

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
/// Hands WatchConnectivity's callbacks to the link on the main actor. Only
/// the `Data` inside a message crosses over.
private final class Delegate: NSObject, WCSessionDelegate, Sendable {
    /// The shared link, which lives as long as the app.
    let link: WatchLink

    init(link: WatchLink) { self.link = link }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let context = session.receivedApplicationContext
        let stateData = context[WatchLink.stateKey] as? Data
        Task { @MainActor in
            self.link.setReachable(reachable)
            self.link.received(state: stateData, reply: nil)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.link.setReachable(reachable) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }

    private func deliver(_ message: [String: Any]) {
        let stateData = message[WatchLink.stateKey] as? Data
        let replyData = message[WatchLink.replyKey] as? Data
        Task { @MainActor in self.link.received(state: stateData, reply: replyData) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
