import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Cardano TxWorkshop document: a package holding a transaction and the work
    /// around it.
    public static let txWorkshopDocument = UTType(exportedAs: "com.kingpinapps.cardano-txworkshop.document")
    /// A cardano-cli text envelope holding a transaction (`.tx`, `.signed`).
    public static let cardanoTextEnvelope = UTType(exportedAs: "com.kingpinapps.cardano-txworkshop.text-envelope")
    /// A transaction's raw CBOR bytes (`.cbor`).
    public static let cardanoTransactionCBOR = UTType(exportedAs: "com.kingpinapps.cardano-txworkshop.transaction-cbor")
    /// A transaction's CBOR written as hex text (`.hex`).
    public static let cardanoTransactionHex = UTType(exportedAs: "com.kingpinapps.cardano-txworkshop.transaction-hex")
}

/// The file formats a document is read from and written to.
public enum TxDocumentFormat: Sendable, CaseIterable {
    case package
    case textEnvelope
    case rawCBOR
    case hex

    public var contentType: UTType {
        switch self {
        case .package: .txWorkshopDocument
        case .textEnvelope: .cardanoTextEnvelope
        case .rawCBOR: .cardanoTransactionCBOR
        case .hex: .cardanoTransactionHex
        }
    }

    /// The file extensions of the format, as the app's Info.plist declares them.
    public var fileExtensions: [String] {
        switch self {
        case .package: ["txworkshop"]
        case .textEnvelope: ["tx", "signed", "txsigned", "witnessed"]
        case .rawCBOR: ["cbor"]
        case .hex: ["hex", "txhex"]
        }
    }

    /// The format of `contentType`.
    ///
    /// When the system has not registered the app's declared types, it hands
    /// over a dynamic type made from the file's extension instead, which
    /// conforms to none of them; the extension still says which format it is.
    public init?(contentType: UTType) {
        if let format = Self.allCases.first(where: { contentType.conforms(to: $0.contentType) }) {
            self = format
            return
        }
        let extensions = contentType.tags[.filenameExtension] ?? []
        guard let format = Self.allCases.first(where: { format in
            extensions.contains { format.fileExtensions.contains($0.lowercased()) }
        }) else {
            return nil
        }
        self = format
    }
}

public enum TxDocumentError: Error, Sendable, Equatable {
    case missingFile(String)
    case unsupportedVersion(Int)
    case notATextEnvelope
    case notHex
    case empty
    case noTransaction
}

/// Reads and writes document content in each format. Pure: bytes in, bytes
/// out, so it can run anywhere and be tested without files.
public enum TxDocumentCodec {
    /// The package format version this build writes.
    public static let packageVersion = 1

    /// The files inside a package, by name.
    public enum PackageFile {
        public static let manifest = "manifest.json"
        public static let transaction = "transaction.cbor"
        public static let context = "chain-context.json"
        public static let schema = "schema.cddl"
        public static let recipe = "build.json"
    }

    struct Manifest: Codable {
        var version: Int
        var envelope: TextEnvelopeInfo?
        var notes: String
        var network: CardanoNetwork?
        var witnesses: [CollectedWitness]
        var validations: [ValidationRecord]
        var submissions: [SubmissionRecord]?
    }

    // MARK: Package

    /// The files of a package holding `content`.
    public static func packageFiles(for content: TxDocumentContent) throws -> [String: Data] {
        let manifest = Manifest(
            version: packageVersion, envelope: content.envelope, notes: content.notes,
            network: content.network, witnesses: content.witnesses, validations: content.validations,
            submissions: content.submissions
        )
        var files = [PackageFile.manifest: try encoder.encode(manifest)]
        if let transaction = content.transaction {
            files[PackageFile.transaction] = transaction
        }
        if let context = content.chainContext {
            files[PackageFile.context] = try encoder.encode(context)
        }
        if let schema = content.schema {
            files[PackageFile.schema] = Data(schema.utf8)
        }
        if let recipe = content.recipe {
            files[PackageFile.recipe] = try encoder.encode(recipe)
        }
        return files
    }

    /// The content of a package with these files.
    public static func content(fromPackageFiles files: [String: Data]) throws -> TxDocumentContent {
        guard let manifestData = files[PackageFile.manifest] else {
            throw TxDocumentError.missingFile(PackageFile.manifest)
        }
        let manifest = try decoder.decode(Manifest.self, from: manifestData)
        guard manifest.version <= packageVersion else {
            throw TxDocumentError.unsupportedVersion(manifest.version)
        }
        return TxDocumentContent(
            transaction: files[PackageFile.transaction],
            envelope: manifest.envelope,
            notes: manifest.notes,
            network: manifest.network,
            chainContext: try files[PackageFile.context].map { try decoder.decode(ChainContextSnapshot.self, from: $0) },
            schema: files[PackageFile.schema].map { String(decoding: $0, as: UTF8.self) },
            recipe: try files[PackageFile.recipe].map { try decoder.decode(BuildRecipe.self, from: $0) },
            witnesses: manifest.witnesses,
            validations: manifest.validations,
            submissions: manifest.submissions ?? []
        )
    }

    // MARK: Flat files

    /// The content of a single-file transaction in `format`.
    public static func content(fromFile data: Data, format: TxDocumentFormat) throws -> TxDocumentContent {
        switch format {
        case .package:
            throw TxDocumentError.missingFile(PackageFile.manifest)
        case .textEnvelope:
            let envelope = try textEnvelope(from: data)
            return TxDocumentContent(transaction: envelope.cbor, envelope: envelope.info)
        case .rawCBOR:
            // Some tools write hex into `.cbor` files; take either.
            if let hex = String(data: data, encoding: .utf8), let bytes = try? bytes(fromHex: hex) {
                return TxDocumentContent(transaction: bytes)
            }
            guard !data.isEmpty else { throw TxDocumentError.empty }
            return TxDocumentContent(transaction: data)
        case .hex:
            guard let text = String(data: data, encoding: .utf8) else { throw TxDocumentError.notHex }
            return TxDocumentContent(transaction: try bytes(fromHex: text))
        }
    }

    /// The file types a transaction can be opened from: the transaction
    /// formats, JSON (text envelopes are often saved as `.json`) and plain
    /// text.
    public static let importableContentTypes: [UTType] = [
        .cardanoTextEnvelope, .cardanoTransactionCBOR, .cardanoTransactionHex, .json, .plainText,
    ]

    /// A dropped or imported file, whatever its name. Read by its extension
    /// when that names a transaction format; a `.json` file must be a text
    /// envelope; anything else by what is in it: a text envelope, hex or
    /// base64, and last of all raw CBOR that starts like a transaction.
    public static func content(fromDroppedFile data: Data, fileExtension: String) throws -> TxDocumentContent {
        guard !data.isEmpty else { throw TxDocumentError.empty }
        if fileExtension.lowercased() == "json" {
            return try content(fromFile: data, format: .textEnvelope)
        }
        if let type = UTType(filenameExtension: fileExtension), let format = TxDocumentFormat(contentType: type),
            format != .package, let content = try? content(fromFile: data, format: format) {
            return content
        }
        if let text = String(data: data, encoding: .utf8), let content = try? content(fromPastedText: text) {
            return content
        }
        // A transaction is a CBOR array of three (Shelley to Mary) or four items.
        if data.first == 0x83 || data.first == 0x84 {
            return TxDocumentContent(transaction: data)
        }
        throw TxDocumentError.noTransaction
    }

    /// `content` as a single file in `format`.
    public static func file(for content: TxDocumentContent, format: TxDocumentFormat) throws -> Data {
        guard let transaction = content.transaction else { throw TxDocumentError.noTransaction }
        switch format {
        case .package:
            throw TxDocumentError.noTransaction
        case .textEnvelope:
            let info = content.envelope ?? TextEnvelopeInfo(type: "Tx ConwayEra", description: "")
            let envelope = ["type": info.type, "description": info.description, "cborHex": hex(transaction)]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(envelope)
        case .rawCBOR:
            return transaction
        case .hex:
            return Data((hex(transaction) + "\n").utf8)
        }
    }

    // MARK: Pasted text

    /// A transaction pasted as text: hex, base64, or a whole text envelope.
    public static func content(fromPastedText text: String) throws -> TxDocumentContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TxDocumentError.empty }
        if trimmed.hasPrefix("{") {
            let envelope = try textEnvelope(from: Data(trimmed.utf8))
            return TxDocumentContent(transaction: envelope.cbor, envelope: envelope.info)
        }
        if let bytes = try? bytes(fromHex: trimmed) {
            return TxDocumentContent(transaction: bytes)
        }
        let compact = trimmed.filter { !$0.isWhitespace }
        if let bytes = Data(base64Encoded: compact), !bytes.isEmpty {
            return TxDocumentContent(transaction: bytes)
        }
        throw TxDocumentError.notHex
    }

    // MARK: Helpers

    static func textEnvelope(from data: Data) throws -> (info: TextEnvelopeInfo, cbor: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let cborHex = object["cborHex"] as? String
        else {
            throw TxDocumentError.notATextEnvelope
        }
        let info = TextEnvelopeInfo(
            type: object["type"] as? String ?? "",
            description: object["description"] as? String ?? ""
        )
        return (info, try bytes(fromHex: cborHex))
    }

    /// Bytes from hex text, ignoring whitespace and an optional `0x` prefix.
    public static func bytes(fromHex text: String) throws -> Data {
        var digits = text.filter { !$0.isWhitespace }
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits.removeFirst(2) }
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { throw TxDocumentError.notHex }
        var bytes = Data(capacity: digits.count / 2)
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { throw TxDocumentError.notHex }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
