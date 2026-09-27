#if os(iOS)
import CardanoHWKit
import CardanoHWWalletKeystone
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine
import VisionKit

/// Scans QR codes with the camera, reporting each code's text.
struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .fast,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: true, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            report(items)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            report(items)
        }

        private func report(_ items: [RecognizedItem]) {
            for case .barcode(let code) in items {
                if let text = code.payloadStringValue { onScan(text) }
            }
        }
    }
}

/// Signs with a Keystone: shows the transaction as an animated QR code for
/// the Keystone to scan, then scans the signature it shows back.
struct KeystoneSignSheet: View {
    let document: TxWorkshopDocument
    let account: HardwareAccountStore.Account
    let knownUTxOs: [String]
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var session: KeystoneQRSession?
    @State private var frame = ""
    @State private var isScanning = false
    @State private var progress = 0
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TWSpacing.l) {
                    if let problem {
                        TWErrorText(problem)
                    }
                    if isScanning {
                        if QRScanner.isAvailable {
                            QRScanner(onScan: ingest)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: 360)
                                .clipShape(.rect(cornerRadius: 12))
                            ProgressView(value: Double(progress), total: 100) {
                                Text("Scan the signature the Keystone shows", bundle: #bundle)
                            }
                        } else {
                            Text("This device has no camera the scanner can use.", bundle: #bundle)
                        }
                    } else if !frame.isEmpty {
                        QRCodeImage(text: frame)
                            .accessibilityLabel(Text("Animated QR code with the transaction for the Keystone", bundle: #bundle))
                            .padding(TWSpacing.m)
                            .background(Color.white, in: .rect(cornerRadius: 12))
                            .frame(maxWidth: 360)
                        Text("Scan this with the Keystone and approve the transaction on it.", bundle: #bundle)
                            .multilineTextAlignment(.center)
                        Button {
                            isScanning = true
                        } label: {
                            Text("Scan the Keystone's Signature", bundle: #bundle)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(TWSpacing.l)
            }
            .navigationTitle(Text("Sign with Keystone", bundle: #bundle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
            }
            .task(id: isScanning) {
                guard !isScanning else { return }
                do {
                    guard let bytes = document.content.transaction else { return }
                    let request = try HardwareSigning.request(for: bytes, utxos: knownUTxOs, account: account.model)
                    let session = try KeystoneQRSession(request: request)
                    self.session = session
                    // Cycle the frames of the animated code until the person
                    // moves on to scanning.
                    while !Task.isCancelled {
                        frame = session.nextFrame()
                        try await Task.sleep(for: .milliseconds(200))
                    }
                } catch is CancellationError {
                } catch {
                    problem = String(describing: error)
                }
            }
        }
    }

    private func ingest(_ scanned: String) {
        guard let session, let bytes = document.content.transaction else { return }
        do {
            switch try session.ingest(scanned: scanned) {
            case .needMore:
                progress = session.progress
            case .complete(let witnessSet):
                let witnesses = try WitnessAssembler.witnesses(from: witnessSet)
                let signed = try WitnessAssembler.merge(bytes, adding: witnesses)
                let records = try witnesses.map { witness in
                    CollectedWitness(label: account.name, keyHash: try WitnessAssembler.keyHash(witness), witnessCBOR: try WitnessAssembler.cborHex(witness), addedAt: .now)
                }
                document.update({ content in
                    content.transaction = signed
                    content.envelope = nil
                    content.witnesses += records
                }, actionName: LocalizedStringResource("Sign with Keystone", bundle: #bundle), undoManager: undoManager)
                dismiss()
            }
        } catch {
            problem = String(describing: error)
            session.resetScan()
        }
    }
}

/// Imports a Keystone account by scanning the account QR it shows.
struct KeystoneImportView: View {
    let network: CardanoNetwork
    let name: String
    let onImport: (HardwareAccountModel) -> Void
    @State private var session: KeystoneAccountImportSession?
    @State private var progress = 0
    @State private var problem: String?

    var body: some View {
        VStack(spacing: TWSpacing.m) {
            if QRScanner.isAvailable {
                QRScanner(onScan: ingest)
                    .frame(minHeight: 280)
                    .clipShape(.rect(cornerRadius: 12))
                ProgressView(value: Double(progress), total: 100) {
                    Text("On the Keystone, open Connect Software Wallet and show the account QR code.", bundle: #bundle)
                }
            } else {
                Text("This device has no camera the scanner can use.", bundle: #bundle)
            }
            if let problem {
                TWErrorText(problem)
            }
        }
        .onAppear { session = KeystoneAccountImportSession(network: HardwareSigning.networkID(network)) }
    }

    private func ingest(_ scanned: String) {
        guard let session else { return }
        do {
            if let model = try session.ingest(scanned: scanned) {
                onImport(model)
            } else {
                progress = session.progress
            }
        } catch {
            problem = String(describing: error)
            session.reset()
        }
    }
}
#endif
