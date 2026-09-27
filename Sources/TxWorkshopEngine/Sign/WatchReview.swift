import Foundation
import TxWorkshopCore

extension WatchReviewRequest {
    /// A review request for `bytes`: its id, fee, outputs and a one-line
    /// summary, for the watch to show.
    public static func make(for bytes: Data, network: CardanoNetwork?, summary: String) async throws -> WatchReviewRequest {
        let inspection = try await TransactionInspector().inspection(of: bytes, network: network)
        return WatchReviewRequest(
            transactionID: inspection.summary.id,
            network: network?.id ?? "unknown",
            summary: summary,
            fee: inspection.view.fee,
            outputs: inspection.outputs.map { .init(address: $0.address.text, lovelace: $0.lovelace, assetCount: $0.assets.count) }
        )
    }
}
