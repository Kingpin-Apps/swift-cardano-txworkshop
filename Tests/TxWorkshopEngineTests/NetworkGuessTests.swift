import Foundation
import SwiftCardanoCore
import Testing
import TxWorkshopCore

@testable import TxWorkshopEngine

@Suite("Guessing the network")
struct NetworkGuessTests {
    static func address(_ network: NetworkId) throws -> String {
        let key: PaymentVerificationKey = try PaymentSigningKey.generate().toVerificationKey()
        return try Address(paymentPart: .verificationKeyHash(key.hash()), network: network).toBech32()
    }

    @Test("Addresses tell mainnet from testnet, file names tell which testnet")
    func addresses() throws {
        #expect(NetworkGuess.hint(for: .address, text: try Self.address(.mainnet)) == .network(.mainnet))
        let testnet = try Self.address(.testnet)
        #expect(NetworkGuess.hint(for: .address, text: testnet) == .testnet)
        #expect(NetworkGuess.hint(for: .address, text: testnet, fileName: "alice.preview.addr") == .network(.preview))
        #expect(NetworkGuess.hint(for: .address, text: testnet, fileName: "mainnet.addr") == .testnet)
        #expect(NetworkGuess.hint(for: .address, text: "not an address") == nil)
        #expect(NetworkGuess.hint(for: .pool, text: testnet) == nil)
    }

    @Test("Hints allow the networks they name")
    func allows() {
        #expect(NetworkHint.testnet.allows(.preview))
        #expect(!NetworkHint.testnet.allows(.mainnet))
        #expect(NetworkHint.network(.preprod).candidates == [.preprod])
        #expect(NetworkGuess.network(inFileName: "Payment-PREPROD.addr") == .preprod)
        #expect(NetworkGuess.network(inFileName: "payment.addr") == nil)
        #expect(NetworkHint.testnet.fits(.preview))
        #expect(!NetworkHint.testnet.fits(.mainnet))
        #expect(!NetworkHint.network(.mainnet).fits(nil))
    }

    @Test("A transaction's network comes from its outputs")
    func transaction() throws {
        let input = TransactionInput(transactionId: TransactionId(payload: Data(repeating: 1, count: 32)), index: 0)
        let output = TransactionOutput(address: try Address(from: .string(try Self.address(.mainnet))), amount: Value(coin: 2_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 200_000)
        let bytes = try Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet()).toCBORData()
        #expect(NetworkGuess.hint(forTransaction: bytes) == .network(.mainnet))
        #expect(NetworkGuess.hint(forTransaction: Data([0x00])) == nil)
    }
}
