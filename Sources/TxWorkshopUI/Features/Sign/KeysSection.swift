import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The signing keys the app keeps.
struct KeysSection: View {
    let onAdd: () -> Void
    @Environment(SigningKeyStore.self) private var keys
    @State private var removing: StoredSigningKey?

    var body: some View {
        Section {
            ForEach(keys.keys) { key in
                HStack {
                    VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                        Text(verbatim: key.name)
                        Text(AttributedString(localized: key.kind == .mnemonic
                            ? "Recovery phrase · ^[\(key.keyHashes.count) key](inflect: true)"
                            : "Key file · ^[\(key.keyHashes.count) key](inflect: true)", bundle: #bundle))
                            .font(.caption)
                            .foregroundStyle(TWColor.secondaryText)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        removing = key
                    } label: {
                        Label {
                            Text("Remove \(key.name)", bundle: #bundle)
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .twHitTarget()
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button(action: onAdd) {
                Label {
                    Text("Add a Signing Key…", bundle: #bundle)
                } icon: {
                    Image(systemName: "key")
                }
            }
        } header: {
            Text("Signing keys", bundle: #bundle)
        } footer: {
            Text("Kept in the Keychain on this device only. Use test keys: this is a developer tool.", bundle: #bundle)
        }
        .confirmationDialog(String(localized: "Remove this key?", bundle: #bundle), item: $removing) { key in
            Button(role: .destructive) {
                keys.remove(key)
            } label: {
                Text("Remove \(key.name)", bundle: #bundle)
            }
        } message: { key in
            Text("\(key.name) is deleted from the Keychain. Keep a copy if you still need it.", bundle: #bundle)
        }
    }
}

/// Adds a recovery phrase or cardano-cli key file to the Keychain.
struct AddKeySheet: View {
    @Environment(SigningKeyStore.self) private var keys
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = StoredSigningKey.Kind.mnemonic
    @State private var secret = ""
    @State private var passphrase = ""
    @State private var accounts = 1
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TWLabeledField(Text("Name", bundle: #bundle), text: $name)
                    Picker(selection: $kind) {
                        Text("Recovery phrase", bundle: #bundle).tag(StoredSigningKey.Kind.mnemonic)
                        Text("Key file (.skey)", bundle: #bundle).tag(StoredSigningKey.Kind.keyFile)
                    } label: {
                        Text("Kind", bundle: #bundle)
                    }
                    TextEditor(text: $secret)
                        .font(TWFont.bytesSmall)
                        .frame(minHeight: 80, maxHeight: 180)
                        .autocorrectionDisabled()
                        .accessibilityLabel(kind == .mnemonic ? Text("Recovery phrase", bundle: #bundle) : Text("Key file contents", bundle: #bundle))
                    if kind == .mnemonic {
                        TWLabeledField(Text("Passphrase (optional)", bundle: #bundle), secret: $passphrase)
                        Stepper(value: $accounts, in: 1...5) {
                            Text("Accounts: \(accounts)", bundle: #bundle)
                        }
                    }
                } footer: {
                    Text("Keys are derived for the first 20 external and change addresses of each account, and its stake and DRep keys.", bundle: #bundle)
                }
                if let problem {
                    Section { TWErrorText(problem) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Add Signing Key", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: add) { Text("Add", bundle: #bundle) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    private func add() {
        let material: SigningKeyMaterial = kind == .mnemonic
            ? .mnemonic(words: secret.trimmingCharacters(in: .whitespacesAndNewlines), passphrase: passphrase)
            : .envelope(json: secret)
        do {
            let ring = try KeyRing(material, accounts: 0..<accounts)
            let key = StoredSigningKey(name: name.trimmingCharacters(in: .whitespaces), kind: kind, keyHashes: ring.keyHashes.sorted())
            try keys.add(key, secret: try StoredKeyMaterial.encode(material))
            secret = ""
            passphrase = ""
            dismiss()
        } catch {
            problem = String(describing: error)
        }
    }
}
