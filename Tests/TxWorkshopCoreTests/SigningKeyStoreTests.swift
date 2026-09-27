import Foundation
import Testing

@testable import TxWorkshopCore

@Suite("Signing key store")
@MainActor
struct SigningKeyStoreTests {
    @Test("Keys are listed without their secrets, and removed with them")
    func store() throws {
        let secrets = InMemorySecretStore()
        let defaults = UserDefaults(suiteName: "signing-key-test-\(UUID().uuidString)")!
        let store = SigningKeyStore(defaults: defaults, secrets: secrets)
        let key = StoredSigningKey(name: "Test", kind: .mnemonic, keyHashes: ["aa", "bb"])
        try store.add(key, secret: "words")

        let reloaded = SigningKeyStore(defaults: defaults, secrets: secrets)
        #expect(reloaded.keys == [key])
        #expect(try reloaded.secret(for: key) == "words")
        // The list in defaults never holds the secret.
        let listed = String(decoding: defaults.data(forKey: "signingKeys") ?? Data(), as: UTF8.self)
        #expect(!listed.contains("words"))
        #expect(reloaded.keys(signingFor: ["bb", "cc"]).map(\.id) == [key.id])
        #expect(reloaded.keys(signingFor: ["cc"]).isEmpty)

        reloaded.remove(key)
        #expect(reloaded.keys.isEmpty)
        #expect(try secrets.secret(for: key.secretAccount) == nil)
    }
}
