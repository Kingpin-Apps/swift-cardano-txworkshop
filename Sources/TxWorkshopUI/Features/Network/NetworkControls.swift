import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

extension TxWorkshopDocument {
    /// Sets the network, as one undoable change.
    func setNetwork(_ network: CardanoNetwork?, undoManager: UndoManager?) {
        guard network != content.network else { return }
        update(
            { $0.network = network },
            actionName: LocalizedStringResource("Change Network", bundle: #bundle),
            undoManager: undoManager
        )
    }
}

/// The document's network as a picker.
struct NetworkPicker: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Picker(selection: Binding(
            get: { document.content.network },
            set: { document.setNetwork($0, undoManager: undoManager) }
        )) {
            Text("Unknown", bundle: #bundle).tag(CardanoNetwork?.none)
            ForEach(CardanoNetwork.allCases) { network in
                Text(network.name).tag(Optional(network))
            }
        } label: {
            Text("Network", bundle: #bundle)
        }
    }
}

/// The document's network in the toolbar, on every section.
struct NetworkToolbarMenu: View {
    let document: TxWorkshopDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Menu {
            Picker(selection: Binding(
                get: { document.content.network },
                set: { document.setNetwork($0, undoManager: undoManager) }
            )) {
                ForEach(CardanoNetwork.allCases) { network in
                    Text(network.name).tag(Optional(network))
                }
                Text("Unknown", bundle: #bundle).tag(CardanoNetwork?.none)
            } label: {
                Text("Network", bundle: #bundle)
            }
            .pickerStyle(.inline)
        } label: {
            // A stack rather than a Label, so toolbars show the name too
            // and not the icon alone.
            HStack(spacing: TWSpacing.xs) {
                Image(systemName: "network")
                if let network = document.content.network {
                    Text(network.name)
                } else {
                    Text("No Network", bundle: #bundle)
                }
            }
            .fixedSize()
        }
        .help(Text("The network this transaction is for", bundle: #bundle))
    }
}

/// Offers the networks a hint points to when the document's network is
/// unknown or does not fit.
struct NetworkSuggestion: View {
    let document: TxWorkshopDocument
    let hint: NetworkHint
    /// What the hint came from, as in "The addresses here".
    let source: Text
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let current = document.content.network
        if current == nil || !hint.allows(current!) {
            VStack(alignment: .leading, spacing: TWSpacing.s) {
                Label {
                    message(current: current)
                } icon: {
                    Image(systemName: current == nil ? "questionmark.circle" : "exclamationmark.triangle")
                }
                .labelStyle(.status(current == nil ? Color.accentColor : TWColor.warning))
                HStack {
                    ForEach(hint.candidates, id: \.self) { network in
                        Button {
                            document.setNetwork(network, undoManager: undoManager)
                        } label: {
                            Text("Use \(Text(network.name))", bundle: #bundle)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func message(current: CardanoNetwork?) -> Text {
        let found: Text = switch hint {
        case .network(let network): Text(network.name)
        case .testnet: Text("a testnet", bundle: #bundle)
        }
        if let current {
            return Text("\(source) are on \(found), but the document is on \(Text(current.name)).", bundle: #bundle)
        }
        return Text("\(source) are on \(found).", bundle: #bundle)
    }
}
