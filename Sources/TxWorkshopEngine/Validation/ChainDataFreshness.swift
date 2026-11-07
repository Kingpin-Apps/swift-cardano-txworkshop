import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// Whether a document's chain data can be used as it is or needs fetching:
/// fetched once, then kept until the epoch turns, since the protocol
/// parameters and the ledger state the builder reads only change then.
public enum ChainDataFreshness {
    /// Where an epoch starts and how long it lasts, for the networks whose
    /// timeline is fixed.
    private struct Epochs {
        let firstShelleyEpoch: UInt64
        let firstShelleySlot: UInt64
        let length: UInt64
        let timeline: SlotTimeline
    }

    private static func epochs(_ network: CardanoNetwork) -> Epochs? {
        switch network {
        case .mainnet: Epochs(firstShelleyEpoch: 208, firstShelleySlot: 4_492_800, length: 432_000, timeline: .mainnet)
        case .preprod: Epochs(firstShelleyEpoch: 4, firstShelleySlot: 86_400, length: 432_000, timeline: .preprod)
        case .preview: Epochs(firstShelleyEpoch: 0, firstShelleySlot: 0, length: 86_400, timeline: .preview)
        case .custom: nil
        }
    }

    /// The epoch in progress at `date` on `network`, when its timeline is known.
    public static func epoch(at date: Date, on network: CardanoNetwork) -> UInt64? {
        guard let e = epochs(network),
              let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded(.down)),
              let slot = e.timeline.slot(atMilliseconds: milliseconds),
              slot >= e.firstShelleySlot
        else { return nil }
        return e.firstShelleyEpoch + (slot - e.firstShelleySlot) / e.length
    }

    /// Whether `snapshot` should be fetched again at `now`: there is none, it
    /// lacks the protocol parameters or the tip, or it is from an earlier
    /// epoch. A network without a known timeline keeps what it has until the
    /// user fetches again.
    public static func needsFetch(_ snapshot: ChainContextSnapshot?, network: CardanoNetwork?, now: Date = .now) -> Bool {
        guard let snapshot, snapshot.protocolParameters != nil, snapshot.tipSlot != nil else { return true }
        guard let network, let current = epoch(at: now, on: network) else { return false }
        let fetched = LedgerState.decode(snapshot.ledgerState).currentEpoch ?? epoch(at: snapshot.fetchedAt, on: network)
        return fetched.map { $0 < current } ?? true
    }
}
