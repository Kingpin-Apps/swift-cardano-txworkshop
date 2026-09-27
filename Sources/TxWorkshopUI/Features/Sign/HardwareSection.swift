import CardanoHWKit
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Hardware wallet accounts: import one, and sign with any that holds a key
/// the transaction needs. The device shows the transaction for approval.
struct HardwareSection: View {
    let document: TxWorkshopDocument
    let missing: Set<String>
    let knownUTxOs: [String]
    @Environment(HardwareAccountStore.self) private var accounts
    @Environment(\.undoManager) private var undoManager
    @State private var isImporting = false
    @State private var signing: HardwareAccountStore.Account?
    @State private var problem: String?
    @State private var keystoneSigning: HardwareAccountStore.Account?

    var body: some View {
        Section {
            ForEach(accounts.accounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                        Text(verbatim: account.name)
                        Text(verbatim: "\(account.model.deviceKind.displayName) · \(account.model.accountPath)")
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    Spacer()
                    if !missing.isDisjoint(with: account.keyHashes) {
                        Button {
                            if account.connection.isQR { keystoneSigning = account } else { sign(with: account) }
                        } label: {
                            if signing?.id == account.id {
                                ProgressView()
                            } else {
                                Text("Sign", bundle: #bundle)
                            }
                        }
                        .disabled(signing != nil)
                    }
                    Button(role: .destructive) {
                        accounts.remove(account)
                    } label: {
                        Label {
                            Text("Forget \(account.name)", bundle: #bundle)
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .twHitTarget()
                    }
                    .buttonStyle(.borderless)
                }
            }
            if signing != nil {
                Label {
                    Text("Check the transaction on the device and approve it there.", bundle: #bundle)
                } icon: {
                    Image(systemName: "hand.point.up.left")
                }
            }
            if let problem {
                TWErrorText(problem)
            }
            Button {
                isImporting = true
            } label: {
                Label {
                    Text("Import a Hardware Account…", bundle: #bundle)
                } icon: {
                    Image(systemName: "externaldrive.badge.plus")
                }
            }
            .disabled(document.content.network == nil)
        } header: {
            Text("Hardware wallets", bundle: #bundle)
        } footer: {
            Text("Ledger over USB or Bluetooth, Trezor over USB on the Mac, and Keystone by QR code on iPhone and iPad. Payments, stake registration and delegation, vote delegation and withdrawals.", bundle: #bundle)
        }
        .sheet(isPresented: $isImporting) {
            if let network = document.content.network {
                ImportHardwareAccountSheet(network: network)
            }
        }
        #if os(iOS)
        .sheet(item: $keystoneSigning) { account in
            KeystoneSignSheet(document: document, account: account, knownUTxOs: knownUTxOs, undoManager: undoManager)
        }
        #endif
    }

    private func sign(with account: HardwareAccountStore.Account) {
        guard let bytes = document.content.transaction, let network = document.content.network else { return }
        signing = account
        problem = nil
        let utxos = knownUTxOs
        Task {
            defer { signing = nil }
            do {
                let witnesses = try await HardwareSigning().sign(
                    bytes, utxos: utxos, account: account.model, connection: account.connection, network: network
                )
                let signed = try WitnessAssembler.merge(bytes, adding: witnesses)
                let records = try witnesses.map { witness in
                    CollectedWitness(label: account.name, keyHash: try WitnessAssembler.keyHash(witness), witnessCBOR: try WitnessAssembler.cborHex(witness), addedAt: .now)
                }
                document.update({ content in
                    content.transaction = signed
                    content.envelope = nil
                    content.witnesses += records
                }, actionName: LocalizedStringResource("Sign with Hardware Wallet", bundle: #bundle), undoManager: undoManager)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

/// Reads an account's public key from a connected device.
struct ImportHardwareAccountSheet: View {
    let network: CardanoNetwork
    @Environment(HardwareAccountStore.self) var accounts
    @Environment(\.dismiss) var dismiss
    @State var name = ""
    @State private var connection = HardwareConnection.available[0]
    @State private var index = 0
    @State private var isImporting = false
    @State var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $name) { Text("Name", bundle: #bundle) }
                    Picker(selection: $connection) {
                        ForEach(HardwareConnection.available, id: \.self) { connection in
                            Text(connection.title).tag(connection)
                        }
                    } label: {
                        Text("Device", bundle: #bundle)
                    }
                    if !connection.isQR {
                        Stepper(value: $index, in: 0...20) {
                            Text("Account \(index)", bundle: #bundle)
                        }
                    }
                } footer: {
                    if connection.isQR {
                        Text("Scan the account QR code the Keystone shows.", bundle: #bundle)
                    } else {
                        Text("Connect and unlock the device, open its Cardano app, then approve exporting the public key.", bundle: #bundle)
                    }
                }
                #if os(iOS)
                if connection.isQR {
                    Section {
                        KeystoneImportView(network: network, name: name) { model in add(model, connection: .keystoneQR) }
                    }
                }
                #endif
                if let problem {
                    Section { TWErrorText(problem) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Import Hardware Account", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: importAccount) {
                        if isImporting { ProgressView() } else { Text("Import", bundle: #bundle) }
                    }
                    .disabled(isImporting || connection.isQR || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }

    private func importAccount() {
        isImporting = true
        problem = nil
        let connection = connection
        let index = index
        Task {
            defer { isImporting = false }
            do {
                let model = try await HardwareSigning().importAccount(connection, network: network, index: index)
                add(model, connection: connection)
            } catch {
                problem = String(describing: error)
            }
        }
    }
}

extension ImportHardwareAccountSheet {
    func add(_ model: HardwareAccountModel, connection: HardwareConnection) {
        do {
            let hashes = try HardwareSigning.keyHashes(of: model)
            let named = name.trimmingCharacters(in: .whitespaces)
            accounts.add(.init(name: named.isEmpty ? model.deviceKind.displayName : named, connection: connection, model: model, keyHashes: hashes.sorted()))
            dismiss()
        } catch {
            problem = String(describing: error)
        }
    }
}

extension HardwareConnection {
    var title: LocalizedStringResource {
        switch self {
        case .ledgerUSB: LocalizedStringResource("Ledger over USB", bundle: #bundle)
        case .ledgerBluetooth: LocalizedStringResource("Ledger over Bluetooth", bundle: #bundle)
        case .trezorUSB: LocalizedStringResource("Trezor over USB", bundle: #bundle)
        case .keystoneQR: LocalizedStringResource("Keystone (QR codes)", bundle: #bundle)
        }
    }
}
