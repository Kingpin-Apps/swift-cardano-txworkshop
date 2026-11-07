import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// Turns wall-clock times into slots and back, for a validity interval picked
/// as "from now, for so long" instead of as raw slot numbers.
///
/// The public networks have a fixed timeline, so no chain data is needed. Any
/// other network is placed from the tip in the document's chain data, counting
/// one slot per second from when it was fetched; that is an estimate, and
/// ``isEstimate`` says so.
public struct ValidityClock: Sendable {
    private enum Source: Sendable {
        case timeline(SlotTimeline)
        case tip(slot: UInt64, at: Date)
    }

    private let source: Source

    /// Whether slots come from the tip rather than the network's timeline.
    public var isEstimate: Bool {
        if case .tip = source { true } else { false }
    }

    /// A clock for `network`, or nil when neither its timeline nor a fetched
    /// tip can place a slot in time.
    public init?(network: CardanoNetwork?, snapshot: ChainContextSnapshot?) {
        switch network {
        case .mainnet: source = .timeline(.mainnet)
        case .preprod: source = .timeline(.preprod)
        case .preview: source = .timeline(.preview)
        case .custom, nil:
            guard let tip = snapshot?.tipSlot, let fetchedAt = snapshot?.fetchedAt else { return nil }
            source = .tip(slot: tip, at: fetchedAt)
        }
    }

    /// The slot in progress at `date`, or nil when it falls outside the chain.
    public func slot(at date: Date) -> UInt64? {
        switch source {
        case .timeline(let timeline):
            guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded(.down)) else { return nil }
            return timeline.slot(atMilliseconds: milliseconds)
        case .tip(let slot, let at):
            let seconds = date.timeIntervalSince(at).rounded(.down)
            guard let offset = Int64(exactly: seconds) else { return nil }
            if offset >= 0 {
                let (sum, overflow) = slot.addingReportingOverflow(UInt64(offset))
                return overflow ? nil : sum
            }
            let back = UInt64(offset.magnitude)
            return back > slot ? nil : slot - back
        }
    }

    /// When `slot` begins, or nil when it cannot be expressed.
    public func date(of slot: UInt64) -> Date? {
        switch source {
        case .timeline(let timeline):
            return timeline.milliseconds(forSlot: slot).map { Date(timeIntervalSince1970: Double($0) / 1000) }
        case .tip(let tip, let at):
            return at.addingTimeInterval(Double(slot) - Double(tip))
        }
    }

    /// The slots for a window that opens at `start` and lasts `duration`
    /// seconds. Either end is nil when it cannot be placed.
    public func window(from start: Date, lasting duration: TimeInterval) -> (from: UInt64?, until: UInt64?) {
        (slot(at: start), slot(at: start.addingTimeInterval(duration)))
    }
}
