import Foundation
import SwiftCardanoCore
import Testing

@testable import TxWorkshopUI

/// A signing key chosen as a file: its contents fill the sheet, and its name
/// names the key unless one was typed.
@Suite("Signing key files")
@MainActor
struct SigningKeyFileTests {
    /// A fresh cardano-cli key file for each run; never a real one.
    static func keyFile() throws -> Data {
        Data(try #require(try PaymentSigningKey.generate().toTextEnvelope()).utf8)
    }

    @Test("A cardano-cli key file is shown as written, and names the key after the file")
    func cliKeyFile() throws {
        let file = try Self.keyFile()
        let read = AddKeySheet.read(file, named: "payment.skey", name: "", nameFromFile: nil)
        #expect(read.isSigningKey)
        #expect(read.text == String(decoding: file, as: UTF8.self))
        #expect(read.name == "payment")
    }

    @Test("A typed name is kept; a name from an earlier file gives way to the next one")
    func naming() throws {
        let file = try Self.keyFile()
        #expect(AddKeySheet.read(file, named: "a.skey", name: "Treasury", nameFromFile: nil).name == "Treasury")
        #expect(AddKeySheet.read(file, named: "b.skey", name: "a", nameFromFile: "a").name == "b")
        #expect(AddKeySheet.read(file, named: "c.skey", name: "   ", nameFromFile: nil).name == "c")
    }

    @Test("A file that is not a signing key is shown as written, and says so")
    func notASigningKey() {
        let read = AddKeySheet.read(Data("hello".utf8), named: "notes.txt", name: "", nameFromFile: nil)
        #expect(!read.isSigningKey)
        #expect(read.text == "hello")
        #expect(read.name == "notes")
    }
}
