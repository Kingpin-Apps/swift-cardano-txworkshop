import SwiftUI
import TxWorkshopCore

/// The window of an open document: a sidebar of sections beside the selected
/// section. Collapses to a navigation stack on iPhone.
struct DocumentShell: View {
    let document: TxWorkshopDocument
    @State private var selection: WorkshopSection? = .overview
    @State private var showsSettings = false

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
            SectionDetail(section: selection ?? .overview, document: document)
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
