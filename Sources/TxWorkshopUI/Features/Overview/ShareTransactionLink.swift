import SwiftUI
import TxWorkshopCore

/// Shares the transaction as a cardano-cli text envelope. Its own view, so the
/// envelope is only encoded again when the transaction changes.
struct ShareTransactionLink: View {
    let transaction: Data
    let envelope: TextEnvelopeInfo?

    var body: some View {
        if let file {
            ShareLink(item: file, preview: SharePreview(Text("Transaction", bundle: #bundle))) {
                Label {
                    Text("Share Transaction", bundle: #bundle)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .help(Text("Share as a cardano-cli text envelope", bundle: #bundle))
        }
    }

    /// The transaction as a `.tx` file, written by swift-cardano-core.
    private var file: TextEnvelopeFile? {
        let content = TxDocumentContent(transaction: transaction, envelope: envelope)
        guard let data = try? TxDocumentCodec.file(for: content, format: .textEnvelope) else { return nil }
        return TextEnvelopeFile(data: data, name: String(localized: "Transaction", bundle: #bundle))
    }
}
