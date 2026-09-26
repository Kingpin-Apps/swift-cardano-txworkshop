import SwiftUI
import TxWorkshopCore

/// Shares the transaction as a cardano-cli text envelope. Its own view, so the
/// envelope is only encoded again when the transaction changes.
struct ShareTransactionLink: View {
    let transaction: Data
    let envelope: TextEnvelopeInfo?

    var body: some View {
        if let text = envelopeText {
            ShareLink(item: text, preview: SharePreview(Text("Transaction", bundle: #bundle))) {
                Label {
                    Text("Share Transaction", bundle: #bundle)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var envelopeText: String? {
        let content = TxDocumentContent(transaction: transaction, envelope: envelope)
        return (try? TxDocumentCodec.file(for: content, format: .textEnvelope)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
