import Foundation
import Testing
import UniformTypeIdentifiers

@testable import TxWorkshopCore

@Suite("Document format")
struct TxDocumentCodecTests {
    static let transactionID = "f5cd70603aedb09e99c454f56f7afa59ad67c1def54d9022b70b8550a7b60700"

    static func transactionHex() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "conway-tx", withExtension: "hex", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fullContent() throws -> TxDocumentContent {
        TxDocumentContent(
            transaction: try TxDocumentCodec.bytes(fromHex: transactionHex()),
            envelope: TextEnvelopeInfo(type: "Tx ConwayEra", description: "Ledger Cddl Format"),
            notes: "Check the collateral return.",
            network: .mainnet,
            chainContext: ChainContextSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_790_000_000), utxos: ["82825820"], protocolParameters: Data("{}".utf8),
                tipSlot: 123
            ),
            witnesses: [CollectedWitness(label: "Alice", keyHash: "ab", witnessCBOR: "a0", addedAt: Date(timeIntervalSince1970: 1_790_000_100))],
            validations: [ValidationRecord(ranAt: Date(timeIntervalSince1970: 1_790_000_200), errorCount: 0, warningCount: 2)]
        )
    }

    @Test("A package keeps everything the document holds")
    func packageRoundTrip() throws {
        let content = try Self.fullContent()
        let files = try TxDocumentCodec.packageFiles(for: content)
        #expect(Set(files.keys) == [TxDocumentCodec.PackageFile.manifest, TxDocumentCodec.PackageFile.transaction, TxDocumentCodec.PackageFile.context])
        #expect(try TxDocumentCodec.content(fromPackageFiles: files) == content)
    }

    @Test("An empty document is a package with only a manifest")
    func emptyPackage() throws {
        let files = try TxDocumentCodec.packageFiles(for: TxDocumentContent())
        #expect(Array(files.keys) == [TxDocumentCodec.PackageFile.manifest])
        #expect(try TxDocumentCodec.content(fromPackageFiles: files).isEmpty)
    }

    @Test("A package from a newer version is refused")
    func newerPackage() throws {
        var files = try TxDocumentCodec.packageFiles(for: TxDocumentContent())
        let manifest = String(decoding: files[TxDocumentCodec.PackageFile.manifest]!, as: UTF8.self)
            .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        files[TxDocumentCodec.PackageFile.manifest] = Data(manifest.utf8)
        #expect(throws: TxDocumentError.unsupportedVersion(99)) {
            try TxDocumentCodec.content(fromPackageFiles: files)
        }
    }

    @Test("A text envelope round-trips its bytes, type and description", arguments: [TxDocumentFormat.textEnvelope, .rawCBOR, .hex])
    func flatFileRoundTrip(format: TxDocumentFormat) throws {
        let content = try Self.fullContent()
        let file = try TxDocumentCodec.file(for: content, format: format)
        let read = try TxDocumentCodec.content(fromFile: file, format: format)
        #expect(read.transaction == content.transaction)
        if format == .textEnvelope {
            #expect(read.envelope == content.envelope)
        }
    }

    @Test("A .cbor file holding hex text is read as hex")
    func hexInCBORFile() throws {
        let hex = try Self.transactionHex()
        let read = try TxDocumentCodec.content(fromFile: Data(hex.utf8), format: .rawCBOR)
        #expect(read.transaction == (try TxDocumentCodec.bytes(fromHex: hex)))
    }

    @Test("Pasted hex, base64 and envelopes all open")
    func pastedText() throws {
        let bytes = try TxDocumentCodec.bytes(fromHex: Self.transactionHex())
        let hex = try Self.transactionHex()
        #expect(try TxDocumentCodec.content(fromPastedText: "  0x\(hex)\n").transaction == bytes)
        #expect(try TxDocumentCodec.content(fromPastedText: bytes.base64EncodedString()).transaction == bytes)
        let envelope = #"{"type": "Tx ConwayEra", "description": "", "cborHex": "\#(hex)"}"#
        let fromEnvelope = try TxDocumentCodec.content(fromPastedText: envelope)
        #expect(fromEnvelope.transaction == bytes)
        #expect(fromEnvelope.envelope?.type == "Tx ConwayEra")
        #expect(throws: TxDocumentError.self) { try TxDocumentCodec.content(fromPastedText: "not a transaction") }
        #expect(throws: TxDocumentError.empty) { try TxDocumentCodec.content(fromPastedText: "  ") }
    }

    @Test("Each format maps to its content type and back")
    func contentTypes() {
        for format in TxDocumentFormat.allCases {
            #expect(TxDocumentFormat(contentType: format.contentType) == format)
        }
        #expect(TxDocumentFormat(contentType: .plainText) == nil)
    }

    @Test("A dynamic type for a known extension still maps to its format")
    func dynamicTypes() throws {
        for format in TxDocumentFormat.allCases {
            let dynamic = try #require(UTType(tag: format.fileExtensions[0], tagClass: .filenameExtension, conformingTo: nil))
            #expect(TxDocumentFormat(contentType: dynamic) == format, "\(format.fileExtensions[0]) → \(dynamic.identifier)")
        }
    }
}
