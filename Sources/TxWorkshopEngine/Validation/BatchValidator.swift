import Foundation
import TxWorkshopCore

/// Validates many transaction files in turn: each is read, its chain data
/// fetched from one provider, and both phases run.
public struct BatchValidator: Sendable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let file: String
        public let transactionID: String?
        public let outcome: ValidationOutcome?
        /// Why the file could not be validated.
        public let problem: String?
        public var id: String { file }
    }

    private let fetcher: ChainDataFetcher

    public init(fetcher: ChainDataFetcher = ChainDataFetcher()) {
        self.fetcher = fetcher
    }

    /// The transaction files in `folder`: text envelopes, raw CBOR and hex.
    public static func transactionFiles(in folder: URL) throws -> [URL] {
        let extensions = Set(TxDocumentFormat.allCases.filter { $0 != .package }.flatMap(\.fileExtensions))
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Validates `data`, the contents of the file `name`.
    public func validate(
        file name: String, data: Data, provider: ProviderConfiguration, apiKey: String?, mode: TransactionValidation.Mode
    ) async -> Item {
        let format = TxDocumentFormat.allCases.first { $0.fileExtensions.contains((name as NSString).pathExtension.lowercased()) }
        guard let format, let bytes = try? TxDocumentCodec.content(fromFile: data, format: format).transaction else {
            return Item(file: name, transactionID: nil, outcome: nil, problem: "Not a transaction.")
        }
        let id = try? await TransactionInspector().inspect(bytes).id
        do {
            let snapshot = try await fetcher.fetch(transaction: bytes, provider: provider, apiKey: apiKey, keeping: nil)
            let outcome = try await TransactionValidation().validate(bytes, snapshot: snapshot, network: provider.network, mode: mode)
            return Item(file: name, transactionID: id, outcome: outcome, problem: nil)
        } catch {
            return Item(file: name, transactionID: id, outcome: nil, problem: String(describing: error))
        }
    }

    /// A Markdown table of the results.
    public static func markdown(_ items: [Item], network: CardanoNetwork, mode: TransactionValidation.Mode) -> String {
        var lines = [
            "# Batch validation", "",
            "Network: \(network.id). Judged \(mode == .now ? "as if submitted now" : "as written").", "",
            "| File | Transaction | Result | Errors | Warnings |", "| --- | --- | --- | --- | --- |",
        ]
        for item in items {
            let result = item.outcome.map { $0.isValid ? "valid" : "not valid" } ?? "not run: \(item.problem ?? "")"
            lines.append("| \(item.file) | \(item.transactionID.map { "`\($0)`" } ?? "—") | \(result) | \(item.outcome?.errors.count ?? 0) | \(item.outcome?.warnings.count ?? 0) |")
        }
        for item in items {
            guard let outcome = item.outcome, !outcome.errors.isEmpty else { continue }
            lines += ["", "## \(item.file)", ""]
            lines += outcome.errors.map { "- `\($0.kind)` at `\($0.fieldPath)`: \($0.message)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
