import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A testnet named in the file an address was read from, such as
/// `alice.preview.addr`, to tell preprod from preview.
@MainActor @Observable
final class BuildNetworkHints {
    var fromFileName: CardanoNetwork?
}

extension EnvironmentValues {
    /// The network of the document being edited, for reading keys and key
    /// hashes as addresses and refusing addresses from another network.
    @Entry var documentNetwork: CardanoNetwork? = nil
}

/// A field for a value that can be given in several forms: pasted as
/// bech32, hex or a key file's JSON, or read from a file (`.addr`, `.vkey`,
/// `.skey`, id files, `pool.json`, scripts, datums). The line below says
/// what it was read as, or why it can't be.
struct ValueField: View {
    let kind: ValueKind
    @Binding var text: String
    let prompt: Text
    var axis: Axis = .horizontal
    @Environment(\.documentNetwork) private var network
    @Environment(BuildNetworkHints.self) private var networkHints: BuildNetworkHints?
    @State private var isImporting = false
    /// The form of the last file read, while the field still holds its value.
    @State private var loaded: ReadValue?
    @State private var fileProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                TextField(text: $text, axis: axis) { prompt }
                    .font(TWFont.bytesSmall)
                    .autocorrectionDisabled()
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button {
                    isImporting = true
                } label: {
                    Label {
                        Text("Choose File…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                    .twHitTarget()
                }
                .buttonStyle(.borderless)
                .help(Text("Read it from a file", bundle: #bundle))
            }
            status
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { load(url) }
        }
        // A file that couldn't be read says so only until the field changes:
        // a value typed or pasted after it is judged on its own.
        .onChange(of: text) { fileProblem = nil }
    }

    @ViewBuilder private var status: some View {
        if let fileProblem {
            caption(fileProblem, systemImage: "exclamationmark.triangle", color: TWColor.warning)
        } else if let loaded, loaded.value == text {
            caption(loaded.form, systemImage: "checkmark.circle", color: TWColor.success)
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch Result(catching: { try ValueReader.read(kind, text: text, network: network) }) {
            case .success(let read):
                caption(read.form, systemImage: "checkmark.circle", color: TWColor.success)
            case .failure(let error):
                caption(String(describing: error), systemImage: "exclamationmark.triangle", color: TWColor.warning)
            }
        }
    }

    private func caption(_ message: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.status(color))
        .font(.caption)
        .foregroundStyle(TWColor.secondaryText)
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = (try? Data(contentsOf: url)) ?? Data()
        if let named = NetworkGuess.network(inFileName: url.lastPathComponent), let text = String(data: data, encoding: .utf8),
            NetworkGuess.hint(for: kind, text: text) != nil {
            networkHints?.fromFileName = named
        }
        do {
            let read = try ValueReader.read(kind, file: data, name: url.lastPathComponent, network: network, folder: url.deletingLastPathComponent())
            loaded = read
            fileProblem = nil
            text = read.value
        } catch {
            fileProblem = "\(url.lastPathComponent): \(error)"
        }
    }
}

/// An anchor hash: typed, read from the anchor's file, or computed by
/// downloading the anchor URL.
struct AnchorHashField: View {
    @Binding var hash: String
    let url: String
    let prompt: Text
    @State private var isHashing = false
    @State private var problem: String?

    var body: some View {
        ValueField(kind: .anchorHash, text: $hash, prompt: prompt)
        if !url.trimmingCharacters(in: .whitespaces).isEmpty {
            Button(action: hashURL) {
                Text("Hash the Anchor URL", bundle: #bundle)
                    .opacity(isHashing ? 0 : 1)
                    .overlay { if isHashing { ProgressView() } }
            }
            .buttonStyle(.borderless)
            .disabled(isHashing)
            if let problem {
                TWErrorText(problem)
            }
        }
    }

    private func hashURL() {
        isHashing = true
        problem = nil
        let url = url
        Task {
            defer { isHashing = false }
            do {
                hash = try await ValueReader.anchorHash(downloading: url).value
            } catch {
                problem = String(describing: error)
            }
        }
    }
}
