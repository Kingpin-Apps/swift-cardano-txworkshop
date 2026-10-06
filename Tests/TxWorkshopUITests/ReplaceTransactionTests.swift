import Foundation
import Testing
import TxWorkshopCore
import TxWorkshopEngine
@testable import TxWorkshopUI

/// Replacing a document's transaction keeps only the witness records the new
/// transaction carries, and can be undone.
@MainActor
@Suite("Replace transaction")
struct ReplaceTransactionTests {
    static func bytes() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "conway-tx", withExtension: "hex", subdirectory: "Fixtures"))
        return try TxDocumentCodec.bytes(fromHex: try String(contentsOf: url, encoding: .utf8))
    }

    @Test("Witness records the new transaction doesn't carry are dropped")
    func prunesWitnesses() throws {
        let bytes = try Self.bytes()
        let carried = try #require(try WitnessAssembler.existing(in: bytes).first)
        let kept = CollectedWitness(label: "Kept", keyHash: try WitnessAssembler.keyHash(carried), witnessCBOR: "", addedAt: .now)
        let stale = CollectedWitness(label: "Stale", keyHash: String(repeating: "ab", count: 28), witnessCBOR: "", addedAt: .now)
        let document = TxWorkshopDocument(content: TxDocumentContent(transaction: Data([0x80]), network: .preprod, witnesses: [kept, stale]))
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        document.replaceTransaction(TxDocumentContent(transaction: bytes), actionName: "Replace", undoManager: undo)
        undo.endUndoGrouping()
        #expect(document.content.transaction == bytes)
        #expect(document.content.witnesses.map(\.label) == ["Kept"])
        // The document's network stays.
        #expect(document.content.network == .preprod)
        undo.undo()
        #expect(document.content.witnesses.count == 2)
    }
}
