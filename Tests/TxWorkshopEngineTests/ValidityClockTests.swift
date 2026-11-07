import Foundation
import Testing
import TxWorkshopCore
@testable import TxWorkshopEngine

@Suite("Turning validity times into slots")
struct ValidityClockTests {
    let address = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    @Test("Preview slots follow its one-second timeline from system start")
    func previewTimeline() throws {
        let clock = try #require(ValidityClock(network: .preview, snapshot: nil))
        #expect(!clock.isEstimate)
        // Preview's system start is 2022-10-25T00:00:00Z, with one-second slots.
        let start = Date(timeIntervalSince1970: 1_666_656_000)
        #expect(clock.slot(at: start) == 0)
        #expect(clock.slot(at: start.addingTimeInterval(86_400)) == 86_400)
        #expect(clock.date(of: 86_400) == start.addingTimeInterval(86_400))
    }

    @Test("A 48-hour window spans 172,800 slots on a one-second network")
    func window() throws {
        let clock = try #require(ValidityClock(network: .preprod, snapshot: nil))
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let (from, until) = clock.window(from: now, lasting: 2 * 86_400)
        let opens = try #require(from)
        let closes = try #require(until)
        #expect(closes - opens == 172_800)
    }

    @Test("A custom network needs a fetched tip, and counts from it as an estimate")
    func customFromTip() throws {
        #expect(ValidityClock(network: .custom(magic: 42), snapshot: nil) == nil)
        let fetched = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = ChainContextSnapshot(fetchedAt: fetched, utxos: [], tipSlot: 5_000)
        let clock = try #require(ValidityClock(network: .custom(magic: 42), snapshot: snapshot))
        #expect(clock.isEstimate)
        #expect(clock.slot(at: fetched.addingTimeInterval(3_600)) == 8_600)
        #expect(clock.slot(at: fetched.addingTimeInterval(-6_000)) == nil)
        #expect(clock.date(of: 5_060) == fetched.addingTimeInterval(60))
    }

    @Test("Only whole addresses count as ready to fetch from")
    func addressesReady() {
        #expect(TransactionComposer.areAddresses([address]))
        #expect(!TransactionComposer.areAddresses([]))
        #expect(!TransactionComposer.areAddresses([address, String(address.dropLast(4))]))
    }
}
