import SwiftUI
import TxWorkshopCore

/// Chooses and enters a script: native JSON, Plutus CBOR hex, or a
/// reference script on a UTxO.
struct ScriptDraftEditor: View {
    @Binding var script: ScriptDraft
    @State private var kind = Kind.native
    @State private var text = ""

    enum Kind: Hashable { case native, plutusV1, plutusV2, plutusV3, reference }

    var body: some View {
        Group {
            controls
        }
        .onAppear {
            switch script {
            case .native(let json): kind = .native; text = json
            case .plutus(let version, let hex): kind = [1: .plutusV1, 2: .plutusV2, 3: .plutusV3][version] ?? .plutusV3; text = hex
            case .reference(let input): kind = .reference; text = input
            }
        }
        .onChange(of: kind) { sync() }
        .onChange(of: text) { sync() }
    }

    @ViewBuilder private var controls: some View {
        Picker(selection: $kind) {
            Text("Native script", bundle: #bundle).tag(Kind.native)
            Text("Plutus V1", bundle: #bundle).tag(Kind.plutusV1)
            Text("Plutus V2", bundle: #bundle).tag(Kind.plutusV2)
            Text("Plutus V3", bundle: #bundle).tag(Kind.plutusV3)
            Text("Reference script", bundle: #bundle).tag(Kind.reference)
        } label: {
            Text("Script", bundle: #bundle)
        }
        if kind == .reference {
            TextField(text: $text) {
                Text("UTxO carrying it (transaction id#index)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
        } else {
            TextEditor(text: $text)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 120)
                .autocorrectionDisabled()
                .accessibilityLabel(kind == .native ? Text("Native script JSON", bundle: #bundle) : Text("Script CBOR hex", bundle: #bundle))
        }
    }

    private func sync() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        script = switch kind {
        case .native: .native(json: text)
        case .plutusV1: .plutus(version: 1, cborHex: trimmed.filter { !$0.isWhitespace })
        case .plutusV2: .plutus(version: 2, cborHex: trimmed.filter { !$0.isWhitespace })
        case .plutusV3: .plutus(version: 3, cborHex: trimmed.filter { !$0.isWhitespace })
        case .reference: .reference(input: trimmed)
        }
    }
}
