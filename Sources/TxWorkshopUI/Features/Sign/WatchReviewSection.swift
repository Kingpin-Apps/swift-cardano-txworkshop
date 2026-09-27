#if os(iOS)
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Hands the transaction to the Apple Watch to look over before signing,
/// and shows its answer. The watch holds no keys.
struct WatchReviewSection: View {
    let document: TxWorkshopDocument
    @State private var link = WatchLink.shared
    @State private var requestID: UUID?
    @State private var problem: String?

    var body: some View {
        Section {
            if let requestID, let reply = link.replies[requestID] {
                Label {
                    if reply.approved {
                        Text("Approved on Apple Watch \(reply.at, format: .relative(presentation: .named))", bundle: #bundle)
                    } else {
                        Text("Declined on Apple Watch \(reply.at, format: .relative(presentation: .named))", bundle: #bundle)
                    }
                } icon: {
                    Image(systemName: reply.approved ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                }
                .foregroundStyle(reply.approved ? TWColor.success : TWColor.failure)
            } else if requestID != nil {
                Label {
                    Text("Waiting for the watch", bundle: #bundle)
                } icon: {
                    Image(systemName: "applewatch")
                }
            }
            if let problem {
                Text(verbatim: problem).foregroundStyle(TWColor.failure)
            }
            Button(action: ask) {
                Label {
                    Text("Ask Apple Watch to Review", bundle: #bundle)
                } icon: {
                    Image(systemName: "applewatch")
                }
            }
            .disabled(document.content.transaction == nil)
        } header: {
            Text("Co-signer review", bundle: #bundle)
        } footer: {
            Text("Shows the transaction on your Apple Watch to approve before you sign here.", bundle: #bundle)
        }
    }

    private func ask() {
        guard let bytes = document.content.transaction else { return }
        let network = document.content.network
        problem = nil
        Task {
            do {
                let inspection = try await TransactionInspector().inspection(of: bytes, network: network)
                let request = try await WatchReviewRequest.make(
                    for: bytes, network: network, summary: TransactionDescription.sentence(for: inspection)
                )
                requestID = request.id
                link.requestReview(request)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
#endif
