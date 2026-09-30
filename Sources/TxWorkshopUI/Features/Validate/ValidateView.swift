import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import UniformTypeIdentifiers

/// Validates the transaction against the ledger rules and runs its scripts,
/// from the chain data the document keeps.
struct ValidateView: View {
    let document: TxWorkshopDocument
    @Environment(WorkshopSession.self) private var session
    @Environment(\.undoManager) private var undoManager
    @State private var mode = TransactionValidation.Mode.now
    @State private var run: LoadState<ValidationOutcome> = .idle
    @State private var requirements: TransactionValidation.Requirements?
    @State private var isAskingWhatIf = false
    @State private var tracing: TraceRequest?
    @State private var report = ReportFile()
    @State private var isExporting = false
    @State private var isPickingFolder = false
    @State private var batchFolder: BatchFolder?

    struct BatchFolder: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var outcome: ValidationOutcome? {
        run.value ?? session.validation(for: document.content.transaction)
    }

    private struct RequirementsKey: Equatable {
        let transaction: Data?
        let snapshot: ChainContextSnapshot?
    }

    var body: some View {
        Form {
            if document.content.transaction == nil {
                Section {
                    Text("Add a transaction in Overview first.", bundle: #bundle)
                }
            } else {
                ChainDataSection(document: document, requirements: requirements)
                Section {
                    Picker(selection: $mode) {
                        Text("If submitted now", bundle: #bundle).tag(TransactionValidation.Mode.now)
                        Text("As written", bundle: #bundle).tag(TransactionValidation.Mode.asWritten)
                    } label: {
                        Text("Judge it", bundle: #bundle)
                    }
                    Button(action: validate) {
                        Text("Validate", bundle: #bundle)
                            .opacity(run.isLoading ? 0 : 1)
                            .overlay { if run.isLoading { ProgressView() } }
                    }
                    .disabled(run.isLoading || requirements?.needsProtocolParameters != false)
                    .accessibilityIdentifier("runValidation")
                } footer: {
                    switch mode {
                    case .now:
                        Text("At the chain tip the data was fetched at, with inputs spent as they were then.", bundle: #bundle)
                    case .asWritten:
                        Text("With its inputs unspent, at a slot in its validity window: for a transaction already on chain.", bundle: #bundle)
                    }
                }
                if let failure = run.failure {
                    Section {
                        Label {
                            Text(verbatim: failure)
                        } icon: {
                            Image(systemName: "xmark.octagon")
                        }
                        .labelStyle(.status(TWColor.failure))
                    }
                }
                if let outcome {
                    ValidationResultSections(outcome: outcome) { fieldPath in
                        session.show(fieldPath: fieldPath)
                    } onTrace: { position in
                        tracing = TraceRequest(position: position)
                    }
                    if !outcome.redeemers.isEmpty {
                        Section {
                            Button {
                                isAskingWhatIf = true
                            } label: {
                                Text("What If…", bundle: #bundle)
                            }
                        } footer: {
                            Text("Change a redeemer or datum and see what it does to each script.", bundle: #bundle)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Validate", bundle: #bundle))
        .sheet(isPresented: $isAskingWhatIf) {
            WhatIfSheet(document: document)
        }
        .sheet(item: $tracing) { request in
            ScriptTraceSheet(document: document, request: request)
        }
        .toolbar {
            if let outcome {
                ToolbarItem {
                    Menu {
                        Button { export(outcome, as: .markdown) } label: { Text("Markdown", bundle: #bundle) }
                        Button { export(outcome, as: .json) } label: { Text("JSON", bundle: #bundle) }
                    } label: {
                        Label {
                            Text("Export Report", bundle: #bundle)
                        } icon: {
                            Image(systemName: "doc.badge.arrow.up")
                        }
                    }
                }
            }
            #if os(macOS)
            ToolbarItem {
                Button {
                    isPickingFolder = true
                } label: {
                    Label {
                        Text("Batch Validate a Folder…", bundle: #bundle)
                    } icon: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                }
                .disabled(document.content.network == nil)
            }
            #endif
        }
        .fileExporter(
            isPresented: $isExporting, document: report, contentType: report.contentType,
            defaultFilename: String(localized: "Validation Report", bundle: #bundle)
        ) { _ in }
        #if os(macOS)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { batchFolder = BatchFolder(url: url) }
        }
        .sheet(item: $batchFolder) { folder in
            if let network = document.content.network {
                BatchValidationSheet(folder: folder.url, network: network, mode: mode)
            }
        }
        #endif
        // onChange rather than task(id:): on iOS 27 the task did not restart
        // when fetched chain data arrived, leaving Validate disabled.
        .onChange(of: RequirementsKey(transaction: document.content.transaction, snapshot: document.content.chainContext), initial: true) {
            guard let bytes = document.content.transaction else { return }
            let found = try? TransactionValidation().requirements(for: bytes, snapshot: document.content.chainContext)
            requirements = found
            // A transaction whose inputs are all spent is most likely on
            // chain already: judge it as written.
            if found?.allInputsSpent == true, run.value == nil { mode = .asWritten }
        }
    }

    private func export(_ outcome: ValidationOutcome, as type: UTType) {
        guard let bytes = document.content.transaction else { return }
        let network = document.content.network
        Task {
            let id = (try? await TransactionInspector().inspect(bytes).id) ?? ""
            let report = ValidationReport(transactionID: id, network: network, outcome: outcome)
            self.report.data = type == .json ? ((try? report.json()) ?? Data()) : Data(report.markdown().utf8)
            self.report.contentType = type
            isExporting = true
        }
    }

    private func validate() {
        guard let bytes = document.content.transaction, let snapshot = document.content.chainContext else { return }
        let network = document.content.network
        let mode = mode
        run = .loading
        Task {
            do {
                let outcome = try await TransactionValidation().validate(bytes, snapshot: snapshot, network: network, mode: mode)
                run = .loaded(outcome)
                session.record(outcome, for: bytes)
                let id = (try? await TransactionInspector().inspect(bytes).id) ?? ""
                let record = ValidationRecord(
                    ranAt: outcome.ranAt, errorCount: outcome.errors.count, warningCount: outcome.warnings.count,
                    report: try? ValidationReport(transactionID: id, network: network, outcome: outcome).json()
                )
                document.update(
                    { $0.validations.append(record) },
                    actionName: LocalizedStringResource("Validate", bundle: #bundle),
                    undoManager: undoManager
                )
            } catch {
                run = .failed(String(describing: error))
            }
        }
    }
}
