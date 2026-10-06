import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Values of one kind, one per line, each checked as it is typed, and more
/// added from files.
struct ValueLinesEditor: View {
    let kind: ValueKind
    @Binding var lines: [String]
    let label: Text
    @Environment(\.documentNetwork) private var network
    @Environment(BuildNetworkHints.self) private var networkHints: BuildNetworkHints?
    @State private var text = ""
    @State private var isImporting = false
    @State private var problem: String?

    var body: some View {
        TextEditor(text: $text)
            .font(TWFont.bytesSmall)
            .frame(minHeight: 44, maxHeight: 120)
            .autocorrectionDisabled()
            .accessibilityLabel(label)
            .onAppear { text = lines.joined(separator: "\n") }
            .onChange(of: text) { _, text in lines = Self.lines(text) }
            .onChange(of: lines) { _, lines in
                if Self.lines(text) != lines { text = lines.joined(separator: "\n") }
            }
        ForEach(unreadable, id: \.line) { line, reason in
            Label {
                Text(verbatim: "\(line.prefix(24))\(line.count > 24 ? "…" : ""): \(reason)")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .labelStyle(.status(TWColor.warning))
            .font(.caption)
        }
        Button {
            isImporting = true
        } label: {
            Label {
                Text("Add from Files…", bundle: #bundle)
            } icon: {
                Image(systemName: "doc.badge.plus")
            }
        }
        .buttonStyle(.borderless)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        // A file's problem goes once the lines change.
        .onChange(of: lines) { problem = nil }
        if let problem {
            TWErrorText(problem)
        }
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var unreadable: [(line: String, reason: String)] {
        lines.compactMap { line in
            do {
                _ = try ValueReader.read(kind, text: line, network: network)
                return nil
            } catch {
                return (line, String(describing: error))
            }
        }
    }

    private func add(_ urls: [URL]) {
        problem = nil
        var added: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = (try? Data(contentsOf: url)) ?? Data()
            if let named = NetworkGuess.network(inFileName: url.lastPathComponent), let text = String(data: data, encoding: .utf8),
                NetworkGuess.hint(for: kind, text: text) != nil {
                networkHints?.fromFileName = named
            }
            do {
                added.append(try ValueReader.read(kind, file: data, name: url.lastPathComponent, network: network, folder: url.deletingLastPathComponent()).value)
            } catch {
                problem = "\(url.lastPathComponent): \(error)"
            }
        }
        if !added.isEmpty { lines += added }
    }
}
