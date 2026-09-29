#if os(macOS)
import Foundation
import SwiftCardanoChain
import SwiftCardanoCore
import SystemPackage
import TxWorkshopCore

public enum CardanoCLIError: Error, Sendable, Equatable, CustomStringConvertible {
    /// cardano-cli exited with an error; its message.
    case failed(String)
    /// cardano-cli printed something that could not be read.
    case unreadable(String)

    public var description: String {
        switch self {
        case .failed(let message): "cardano-cli: \(message)"
        case .unreadable(let what): "cardano-cli printed \(what) that could not be read."
        }
    }
}

/// A chain context that asks cardano-cli, as `cardano-cli latest query …`
/// would, for UTxOs, the tip and the protocol parameters, and submits
/// through it. What cardano-cli does not answer, such as genesis parameters
/// and script evaluation, goes to the same node over its socket.
public actor CardanoCLIChainContext: ChainContext {
    private let cli: String
    private let socketPath: String
    private let network: CardanoNetwork
    private let node: NodeSocketChainContext
    private var cachedParameters: (slot: Int, value: ProtocolParameters)?

    public init(cli: String, socketPath: String, network: CardanoNetwork) {
        self.cli = cli
        self.socketPath = socketPath
        self.network = network
        node = NodeSocketChainContext(socketPath: FilePath(socketPath), network: network.cardanoCoreNetwork)
    }

    nonisolated public var name: String { "cardano-cli" }
    nonisolated public var type: ContextType { .online }
    nonisolated public var networkId: NetworkId { network == .mainnet ? .mainnet : .testnet }
    nonisolated public var description: String { "cardano-cli (\(network.name))" }
    nonisolated public var debugDescription: String { description }

    // MARK: Asked of cardano-cli

    public func chainTip() async throws -> ChainTip {
        let output = try await run(["query", "tip"])
        do {
            return try JSONDecoder().decode(ChainTip.self, from: output)
        } catch {
            throw CardanoCLIError.unreadable("a tip")
        }
    }

    public func epoch() async throws -> Int {
        guard let epoch = try await chainTip().epoch else { throw CardanoCLIError.unreadable("a tip without an epoch") }
        return Int(epoch)
    }

    public func lastBlockSlot() async throws -> Int {
        guard let slot = try await chainTip().slot else { throw CardanoCLIError.unreadable("a tip without a slot") }
        return Int(slot)
    }

    public func era() async throws -> Era? {
        try await chainTip().era.flatMap { Era(rawValue: $0.lowercased()) }
    }

    public func protocolParameters() async throws -> ProtocolParameters {
        let slot = try await lastBlockSlot()
        if let cachedParameters, cachedParameters.slot == slot { return cachedParameters.value }
        let output = try await run(["query", "protocol-parameters", "--output-json"])
        do {
            let parameters = try JSONDecoder().decode(ProtocolParameters.self, from: output)
            cachedParameters = (slot, parameters)
            return parameters
        } catch {
            throw CardanoCLIError.unreadable("protocol parameters")
        }
    }

    public func utxos(address: Address) async throws -> [UTxO] {
        try await queryUTxOs(["--address", try address.toBech32()])
    }

    public func utxo(input: TransactionInput) async throws -> (UTxO, isSpent: Bool)? {
        // The ledger forgets spent outputs: one that is not found is either
        // spent or never existed, as with the other contexts.
        try await queryUTxOs(["--tx-in", input.description]).first.map { ($0, false) }
    }

    public func submitTxCBOR(cbor: Data) async throws -> String {
        let file = FileManager.default.temporaryDirectory.appending(path: "txworkshop-\(UUID().uuidString).signed")
        let envelope: [String: String] = ["type": "Tx ConwayEra", "description": "", "cborHex": cbor.toHex]
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await run(["transaction", "submit", "--tx-file", file.path()])
        guard let id = try Transaction.fromCBOR(data: cbor).id else { throw CardanoCLIError.unreadable("a transaction id") }
        return id.payload.toHex
    }

    // MARK: Asked of the node

    public func genesisParameters() async throws -> GenesisParameters {
        try await node.genesisParameters()
    }

    public func evaluateTxCBOR(cbor: Data) async throws -> [String: ExecutionUnits] {
        try await node.evaluateTxCBOR(cbor: cbor)
    }

    // MARK: Running cardano-cli

    private func queryUTxOs(_ selection: [String]) async throws -> [UTxO] {
        let output = try await run(["query", "utxo"] + selection + ["--output-cbor-hex"])
        let hex = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(hexString: hex), let primitive = try? Primitive.fromCBOR(data: data) else {
            throw CardanoCLIError.unreadable("UTxOs")
        }
        let entries: [(Primitive, Primitive)] = switch primitive {
        case .dict(let map), .frozenDict(let map): map.map { ($0.key, $0.value) }
        case .orderedDict(let map), .indefiniteDictionary(let map): map.map { ($0.key, $0.value) }
        default: throw CardanoCLIError.unreadable("UTxOs")
        }
        return try entries.map { UTxO(input: try TransactionInput(from: $0.0), output: try TransactionOutput(from: $0.1)) }
    }

    /// Runs `cardano-cli latest <arguments>` against the node and returns what
    /// it prints.
    private func run(_ arguments: [String]) async throws -> Data {
        let networkArguments = network == .mainnet ? ["--mainnet"] : ["--testnet-magic", String(network.magic)]
        let process = Process()
        process.executableURL = URL(filePath: cli)
        process.arguments = ["latest"] + arguments + networkArguments + ["--socket-path", socketPath]
        var environment = ProcessInfo.processInfo.environment
        environment["CARDANO_NODE_SOCKET_PATH"] = socketPath
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        // Both pipes are read while it runs: output larger than a pipe holds
        // would otherwise stall cardano-cli before it exits.
        let reading = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let readingErrors = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
                continuation.resume(throwing: CardanoCLIError.failed(error.localizedDescription))
            }
        }
        let printed = await reading.value
        let complaint = await readingErrors.value
        guard status == 0 else {
            let message = String(decoding: complaint.isEmpty ? printed : complaint, as: UTF8.self)
            throw CardanoCLIError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return printed
    }
}
#endif
