import Foundation
import Testing

@testable import TxWorkshopCore

@Suite("Watch state")
struct WatchStateTests {
    @Test("What the phone sends survives the trip")
    func roundTrip() throws {
        let state = WatchState(
            submissions: [WatchSubmission(id: "ab", network: "preprod", submittedAt: Date(timeIntervalSince1970: 1), confirmedAt: nil)],
            review: WatchReviewRequest(
                transactionID: "cd", network: "preprod", summary: "Sends ₳10.", fee: 170_000,
                outputs: [.init(address: "addr_test1…", lovelace: 10_000_000, assetCount: 0)], requestedAt: Date(timeIntervalSince1970: 2)
            )
        )
        #expect(try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(state)) == state)
        let reply = WatchReviewReply(requestID: state.review!.id, approved: true, at: Date(timeIntervalSince1970: 3))
        #expect(try JSONDecoder().decode(WatchReviewReply.self, from: JSONEncoder().encode(reply)) == reply)
    }
}
