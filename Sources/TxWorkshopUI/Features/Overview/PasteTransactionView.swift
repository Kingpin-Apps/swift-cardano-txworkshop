import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Takes a transaction for an empty document: pasted as hex, base64 or a
/// text envelope, opened from or dropped as a file, fetched by id, or built
/// from scratch.
struct PasteTransactionView: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Form {
            TransactionSourceSection(document: document)
            FetchByHashSection(document: document, isAlternative: true)
            BuildFromScratchSection()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return TransactionSourceSection.load(url, into: document, undoManager: undoManager) == nil
        }
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .navigationTitle(Text("Overview", bundle: #bundle))
    }
}

/// Starts a new transaction in the Build form, for a document with none.
private struct BuildFromScratchSection: View {
    @Environment(WorkshopSession.self) private var session

    var body: some View {
        Section {
            Text("Make a transaction from a form: payments, minting, scripts, staking and governance. Coin selection, change and the fee are worked out for you.", bundle: #bundle)
                .foregroundStyle(TWColor.secondaryText)
            Button {
                session.selection = .build
            } label: {
                Label {
                    Text("Build a Transaction", bundle: #bundle)
                } icon: {
                    Image(systemName: "hammer")
                }
            }
            .accessibilityIdentifier("buildFromScratch")
        } header: {
            VStack(alignment: .leading, spacing: TWSpacing.m) {
                OrDivider()
                Text("Build from scratch", bundle: #bundle)
            }
        }
    }
}

/// A rule with "or" in the middle, between ways of doing the same thing.
struct OrDivider: View {
    var body: some View {
        HStack(spacing: TWSpacing.s) {
            line
            Text("or", bundle: #bundle)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(TWColor.secondaryText)
            line
        }
        .padding(.vertical, TWSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle()
            .fill(TWColor.secondaryText.opacity(0.35))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
