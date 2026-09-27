import SwiftUI
import TxWorkshopCore

/// The watch companion: a transaction waiting for review, and transactions
/// submitted from the phone with their confirmations.
public struct WatchRootView: View {
    @State private var link = WatchLink.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if let review = link.state.review {
                    Section {
                        NavigationLink {
                            WatchReviewView(review: review)
                        } label: {
                            VStack(alignment: .leading) {
                                Text("Review a transaction", bundle: #bundle)
                                    .font(.headline)
                                Text(verbatim: review.summary)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                Section {
                    if link.state.submissions.isEmpty {
                        Text("Transactions you submit from your iPhone appear here until they confirm.", bundle: #bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(link.state.submissions.reversed()) { submission in
                        HStack {
                            Image(systemName: submission.confirmedAt == nil ? "clock" : "checkmark.circle.fill")
                                .foregroundStyle(submission.confirmedAt == nil ? Color.orange : Color.green)
                            VStack(alignment: .leading) {
                                Text(verbatim: String(submission.id.prefix(12)) + "…")
                                    .font(.system(.footnote, design: .monospaced))
                                if let confirmed = submission.confirmedAt {
                                    Text("On chain \(confirmed, format: .relative(presentation: .named))", bundle: #bundle)
                                        .font(.caption2)
                                } else {
                                    Text("Waiting on \(submission.network)", bundle: #bundle)
                                        .font(.caption2)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Submitted", bundle: #bundle)
                }
            }
            .navigationTitle(Text("Tx Workshop", bundle: #bundle))
        }
        .task { link.activate() }
    }
}

/// A transaction to look over: what it does, its fee and where it pays.
/// Approving tells the phone; the watch signs nothing.
struct WatchReviewView: View {
    let review: WatchReviewRequest
    @State private var link = WatchLink.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(verbatim: review.summary)
                LabeledContent {
                    Text(verbatim: TWFormat.ada(review.fee))
                } label: {
                    Text("Fee", bundle: #bundle)
                }
                Text(verbatim: review.network)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(review.outputs, id: \.self) { output in
                    VStack(alignment: .leading) {
                        Text(verbatim: TWFormat.ada(output.lovelace))
                        Text(verbatim: String(output.address.prefix(14)) + "…" + String(output.address.suffix(6)))
                            .font(.system(.caption2, design: .monospaced))
                        if output.assetCount > 0 {
                            Text("^[\(output.assetCount) native asset](inflect: true)", bundle: #bundle)
                                .font(.caption2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Pays", bundle: #bundle)
            }
            Section {
                Button {
                    link.reply(approved: true)
                    dismiss()
                } label: {
                    Label {
                        Text("Approve", bundle: #bundle)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                }
                .tint(.green)
                Button(role: .destructive) {
                    link.reply(approved: false)
                    dismiss()
                } label: {
                    Label {
                        Text("Decline", bundle: #bundle)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .navigationTitle(Text("Review", bundle: #bundle))
    }
}

#Preview {
    WatchRootView()
}
