import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The window of an open document: a sidebar of sections beside the selected
/// section. Collapses to a navigation stack on iPhone.
struct DocumentShell: View {
    let document: TxWorkshopDocument
    @State private var selection: WorkshopSection? = .overview
    @State private var showsSettings = false
    @State private var inspection: LoadState<TransactionInspection> = .idle

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(WorkshopSection.inspect) { section in
                        SectionLink(section: section)
                    }
                } header: {
                    Text("Inspect", bundle: #bundle)
                }
                Section {
                    ForEach(WorkshopSection.act) { section in
                        SectionLink(section: section)
                    }
                } header: {
                    Text("Work", bundle: #bundle)
                }
            }
            .navigationTitle(Text("Tx Workshop", bundle: #bundle))
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            #if !os(macOS)
            .toolbar {
                ToolbarItem {
                    Button {
                        showsSettings = true
                    } label: {
                        Label {
                            Text("Providers", bundle: #bundle)
                        } icon: {
                            Image(systemName: "network")
                        }
                    }
                }
            }
            #endif
        } detail: {
            SectionDetail(section: selection ?? .overview, document: document, inspection: inspection)
        }
        .task(id: InspectionKey(transaction: document.content.transaction, network: document.content.network)) {
            await inspect()
        }
        #if !os(macOS)
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ProviderSettingsView()
            }
        }
        #endif
    }
}

#Preview {
    DocumentShell(document: .preview)
        .environment(ProviderSettingsStore.preview)
}

extension DocumentShell {
    /// What an inspection depends on; a change to either runs it again.
    struct InspectionKey: Equatable {
        let transaction: Data?
        let network: CardanoNetwork?
    }

    /// Decodes and inspects the document's transaction once, for every section.
    private func inspect() async {
        guard let transaction = document.content.transaction else {
            inspection = .idle
            return
        }
        inspection = .loading
        do {
            inspection = .loaded(
                try await TransactionInspector().inspection(of: transaction, network: document.content.network)
            )
        } catch {
            inspection = .failed(String(describing: error))
        }
    }
}
