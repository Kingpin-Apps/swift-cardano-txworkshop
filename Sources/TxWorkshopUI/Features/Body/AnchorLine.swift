import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A governance anchor: its URL, the hash its content must have, and a check
/// that fetches the content and compares.
struct AnchorLine: View {
    let url: String
    let hash: String?
    @State private var check: LoadState<AnchorCheck> = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            if let link = URL(string: url), link.scheme == "https" || link.scheme == "http" {
                Link(destination: link) { TWBytesText(url, font: TWFont.bytesSmall) }
                    .buttonStyle(.borderless)
            } else {
                TWBytesText(url, font: TWFont.bytesSmall)
            }
            if let hash {
                HStack {
                    TWBytesText(hash, font: TWFont.bytesSmall)
                        .foregroundStyle(TWColor.secondaryText)
                    Spacer()
                    switch check {
                    case .idle:
                        Button { verify(hash) } label: { Text("Verify", bundle: #bundle) }
                            .buttonStyle(.borderless)
                    case .loading:
                        ProgressView().controlSize(.small)
                    case .failed, .loaded:
                        EmptyView()
                    }
                }
                if case .loaded(let result) = check {
                    AnchorResult(check: result)
                }
            }
        }
    }

    private func verify(_ hash: String) {
        check = .loading
        Task {
            check = .loaded(await AnchorVerifier().check(url: url, expectedHash: hash))
        }
    }
}

private struct AnchorResult: View {
    let check: AnchorCheck

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            switch check.status {
            case .matches:
                Label {
                    Text("The content matches its hash.", bundle: #bundle)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .labelStyle(.status(TWColor.success))
            case .mismatch(let computed):
                Label {
                    Text("The content does not match: it hashes to \(computed).", bundle: #bundle)
                } icon: {
                    Image(systemName: "xmark.seal.fill")
                }
                .labelStyle(.status(TWColor.failure))
            case .unreachable(let reason):
                Label {
                    Text("Could not fetch the content: \(reason)", bundle: #bundle)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.warning))
            }
            if let title = check.title {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
            }
            if let abstract = check.abstract {
                Text(verbatim: abstract).font(.caption).foregroundStyle(TWColor.secondaryText).lineLimit(6)
            }
        }
        .font(.caption)
    }
}
