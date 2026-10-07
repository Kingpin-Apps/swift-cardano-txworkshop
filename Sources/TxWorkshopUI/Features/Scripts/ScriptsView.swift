import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The scripts the transaction runs, the redeemers it gives them, and the
/// datums it supplies.
struct ScriptsView: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>
    @State private var debugging: DebugRequest?

    var body: some View {
        InspectionContainer(inspection: inspection, title: LocalizedStringResource("Scripts & Datums", bundle: #bundle)) { inspection in
            if inspection.redeemers.isEmpty && inspection.scripts.isEmpty && inspection.datums.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Scripts", bundle: #bundle)
                    } icon: {
                        Image(systemName: "curlybraces")
                    }
                } description: {
                    Text("This transaction runs no scripts and supplies no datums.", bundle: #bundle)
                }
            } else {
                Form {
                    if !inspection.redeemers.isEmpty {
                        Section {
                            ForEach(inspection.redeemers) { redeemer in
                                RedeemerRow(redeemer: redeemer, onDebug: document.content.chainContext == nil ? nil : {
                                    debugging = DebugRequest(position: redeemer.view.position)
                                })
                            }
                        } header: {
                            Text("Redeemers", bundle: #bundle)
                        }
                    }
                    if !inspection.scripts.isEmpty {
                        Section {
                            ForEach(inspection.scripts) { script in
                                ScriptRow(script: script)
                            }
                        } header: {
                            Text("Scripts in the witness set", bundle: #bundle)
                        } footer: {
                            Text("Scripts used by reference are listed with the outputs that carry them.", bundle: #bundle)
                        }
                    }
                    if !inspection.datums.isEmpty {
                        Section {
                            ForEach(inspection.datums) { datum in
                                VStack(alignment: .leading, spacing: TWSpacing.xs) {
                                    CopyableBytes(datum.hash)
                                    DataTreeView(node: datum.tree)
                                }
                            }
                        } header: {
                            Text("Datums", bundle: #bundle)
                        }
                    }
                }
                .formStyle(.grouped)
                .scriptDebugger(item: $debugging, document: document)
            }
        }
    }
}
