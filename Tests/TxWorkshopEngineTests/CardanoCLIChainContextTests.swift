#if os(macOS)
import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

/// Runs the context against a stand-in cardano-cli: a shell script that
/// records its arguments and prints canned answers.
@Suite("cardano-cli provider")
struct CardanoCLIChainContextTests {
    let folder: URL
    let socket: String

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "fake-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        socket = folder.appending(path: "node.socket").path()
    }

    /// Writes a cardano-cli that prints `utxos` for `query utxo`, `tip` for
    /// `query tip`, and fails for anything else.
    func fakeCLI(utxos: String = "", tip: String = "{}") throws -> String {
        let utxoFile = folder.appending(path: "utxos.hex")
        try utxos.write(to: utxoFile, atomically: true, encoding: .utf8)
        let script = """
        #!/bin/sh
        echo "$@" > "\(folder.path())/arguments"
        case "$2 $3" in
          "query utxo") cat "\(utxoFile.path())" ;;
          "query tip") echo '\(tip)' ;;
          *) echo "unknown command" >&2; exit 1 ;;
        esac
        """
        let path = folder.appending(path: "cardano-cli").path()
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func arguments() throws -> String {
        try String(contentsOf: folder.appending(path: "arguments"), encoding: .utf8)
    }

    static func utxoHex(count: Int) throws -> (String, Address) {
        let key: PaymentVerificationKey = try PaymentSigningKey.generate().toVerificationKey()
        let address = try Address(paymentPart: .verificationKeyHash(key.hash()), network: .testnet)
        var map: [Primitive: Primitive] = [:]
        for index in 0..<count {
            let input = TransactionInput(transactionId: TransactionId(payload: Data(repeating: 7, count: 32)), index: UInt16(index))
            let output = TransactionOutput(address: address, amount: Value(coin: 1_000_000 + Int64(index)))
            map[try input.toPrimitive()] = try output.toPrimitive()
        }
        return (try Primitive.dict(map).toCBORHex(), address)
    }

    @Test("UTxOs come from the CBOR cardano-cli prints, on the document's network")
    func utxos() async throws {
        let (hex, address) = try Self.utxoHex(count: 2)
        let context = CardanoCLIChainContext(cli: try fakeCLI(utxos: hex), socketPath: socket, network: .preview)
        let utxos = try await context.utxos(address: address)
        #expect(utxos.count == 2)
        #expect(Set(utxos.map(\.output.amount.coin)) == [1_000_000, 1_000_001])
        let arguments = try arguments()
        #expect(arguments.hasPrefix("latest query utxo --address \(try address.toBech32()) --output-cbor-hex"))
        #expect(arguments.contains("--testnet-magic 2 --socket-path \(socket)"))
    }

    @Test("Output larger than a pipe holds is read in full")
    func largeOutput() async throws {
        let (hex, address) = try Self.utxoHex(count: 1500)
        #expect(hex.utf8.count > 65_536)
        let context = CardanoCLIChainContext(cli: try fakeCLI(utxos: hex), socketPath: socket, network: .mainnet)
        #expect(try await context.utxos(address: address).count == 1500)
        #expect(try arguments().contains("--mainnet"))
    }

    @Test("The tip gives the slot, epoch and era")
    func tip() async throws {
        let tip = #"{"block": 10, "epoch": 900, "era": "Conway", "hash": "ab", "slot": 12345, "slotInEpoch": 5, "slotsToEpochEnd": 6, "syncProgress": "100.00"}"#
        let context = CardanoCLIChainContext(cli: try fakeCLI(tip: tip), socketPath: socket, network: .preprod)
        #expect(try await context.lastBlockSlot() == 12345)
        #expect(try await context.epoch() == 900)
        #expect(try await context.era() == .conway)
    }

    @Test("cardano-cli's complaint is passed on")
    func failure() async throws {
        let path = folder.appending(path: "failing-cli").path()
        try "#!/bin/sh\necho 'Network.Socket.connect: does not exist' >&2\nexit 1\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let context = CardanoCLIChainContext(cli: path, socketPath: socket, network: .preview)
        await #expect(throws: CardanoCLIError.failed("Network.Socket.connect: does not exist")) {
            _ = try await context.protocolParameters()
        }
    }
}
#endif
