import Foundation
import Testing
import TxWorkshopCore

@testable import TxWorkshopUI

/// A witness chosen as a file: its contents fill the sheet, and its name
/// names the witness unless one was typed.
@Suite("Witness files")
@MainActor
struct WitnessFileTests {
    /// `[vkey, signature]`: a vkey witness's CBOR.
    static let witnessHex = "825820" + String(repeating: "11", count: 32) + "5840" + String(repeating: "22", count: 64)
    /// A cardano-cli witness file: `[0, witness]` in a text envelope.
    static let cliFile = Data("""
        {
            "type": "TxWitness ConwayEra",
            "description": "Key Witness ShelleyEra",
            "cborHex": "8200\(witnessHex)"
        }
        """.utf8)

    @Test("A cardano-cli witness file is shown as written, and names the witness after the file")
    func cliWitnessFile() {
        let read = ImportWitnessSheet.read(Self.cliFile, named: "alice.payment.witness", label: "", labelFromFile: nil)
        #expect(read.isWitness)
        #expect(read.text == String(decoding: Self.cliFile, as: UTF8.self))
        #expect(read.label == "alice.payment")
    }

    @Test("Raw CBOR is shown as hex")
    func rawCBOR() throws {
        let bytes = try TxDocumentCodec.bytes(fromHex: Self.witnessHex)
        let read = ImportWitnessSheet.read(bytes, named: "bob.witness", label: "", labelFromFile: nil)
        #expect(read.isWitness)
        #expect(read.text == Self.witnessHex)
        #expect(read.label == "bob")
    }

    @Test("A typed name is kept; a name from an earlier file gives way to the next one")
    func naming() {
        #expect(ImportWitnessSheet.read(Self.cliFile, named: "a.witness", label: "Treasury signer", labelFromFile: nil).label == "Treasury signer")
        #expect(ImportWitnessSheet.read(Self.cliFile, named: "b.witness", label: "a", labelFromFile: "a").label == "b")
        #expect(ImportWitnessSheet.read(Self.cliFile, named: "c.witness", label: "   ", labelFromFile: nil).label == "c")
    }

    @Test("A file that is not a witness is shown as written, and says so")
    func notAWitness() {
        let read = ImportWitnessSheet.read(Data("hello".utf8), named: "notes.txt", label: "", labelFromFile: nil)
        #expect(!read.isWitness)
        #expect(read.text == "hello")
        #expect(read.label == "notes")
    }
}
