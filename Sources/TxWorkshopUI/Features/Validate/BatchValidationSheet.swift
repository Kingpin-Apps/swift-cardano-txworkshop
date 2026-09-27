#if os(macOS)
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Validates every transaction file in a folder with one network's
/// provider, one after another, and exports a summary.
struct BatchValidationSheet: View {
    let folder: URL
    let network: CardanoNetwork
    let mode: TransactionValidation.Mode
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(\.dismiss) private var dismiss
    @State private var items: [BatchValidator.Item] = []
    @State private var total = 0
    @State private var problem: String?
    @State private var isExporting = false
    @State private var summary = ReportFile(contentType: .markdown)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let problem {
                        TWErrorText(problem)
                    } else if items.count < total {
                        ProgressView(value: Double(items.count), total: Double(total)) {
                            Text("Validating \(items.count + 1) of \(total)", bundle: #bundle)
                        }
                    } else {
                        Text(AttributedString(localized: "Validated ^[\(total) file](inflect: true).", bundle: #bundle))
                    }
                } header: {
                    Text(verbatim: folder.lastPathComponent)
                }
                Section {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.outcome.map { $0.isValid ? "checkmark.circle" : "xmark.circle" } ?? "questionmark.circle")
                                .foregroundStyle(item.outcome.map { $0.isValid ? TWColor.success : TWColor.failure } ?? TWColor.warning)
                                .accessibilityLabel(item.outcome.map { $0.isValid ? Text("Valid", bundle: #bundle) : Text("Not valid", bundle: #bundle) } ?? Text("Not checked", bundle: #bundle))
                            VStack(alignment: .leading) {
                                Text(verbatim: item.file)
                                if let problem = item.problem {
                                    Text(verbatim: problem).font(.caption).foregroundStyle(TWColor.secondaryText)
                                } else if let outcome = item.outcome {
                                    Text("\(outcome.errors.count) errors, \(outcome.warnings.count) warnings", bundle: #bundle)
                                        .font(.caption).foregroundStyle(TWColor.secondaryText)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle(Text("Batch Validation", bundle: #bundle))
            .toolbar {
                ToolbarItem {
                    Button {
                        summary.data = Data(BatchValidator.markdown(items, network: network, mode: mode).utf8)
                        isExporting = true
                    } label: {
                        Text("Export Summary…", bundle: #bundle)
                    }
                    .disabled(items.isEmpty || items.count < total)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
            .fileExporter(isPresented: $isExporting, document: summary, contentType: .markdown, defaultFilename: String(localized: "Batch Validation", bundle: #bundle)) { _ in }
            .task { await run() }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 420, idealHeight: 560)
    }

    private func run() async {
        guard let provider = providers.selectedProvider(for: network) else {
            problem = String(localized: "Add a provider for this network in Settings first.", bundle: #bundle)
            return
        }
        let apiKey = providers.apiKey(for: provider)
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let files: [URL]
        do {
            files = try BatchValidator.transactionFiles(in: folder)
        } catch {
            problem = String(describing: error)
            return
        }
        total = files.count
        for file in files {
            guard !Task.isCancelled else { return }
            let data = (try? Data(contentsOf: file)) ?? Data()
            items.append(await BatchValidator().validate(file: file.lastPathComponent, data: data, provider: provider, apiKey: apiKey, mode: mode))
        }
    }
}
#endif
