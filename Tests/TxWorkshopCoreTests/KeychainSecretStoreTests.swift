import Foundation
import Security
import Synchronization
import Testing

@testable import TxWorkshopCore

/// The Keychain's choices: an API key is never lost, wherever the build may
/// or may not keep it.
@Suite("Keychain secrets")
struct KeychainSecretStoreTests {
    /// A Keychain in memory that can refuse a place, as a build not entitled
    /// to it is refused.
    final class FakeKeychain: KeychainBackend {
        struct State {
            var items: [KeychainPlace: [String: Data]] = [:]
            /// Status every call at a place returns instead of succeeding.
            var refused: [KeychainPlace: OSStatus] = [:]
            /// Status writes at a place return; reads and deletes still work.
            var refusedWrites: [KeychainPlace: OSStatus] = [:]
        }
        let state: Mutex<State>

        init(_ configure: (inout State) -> Void = { _ in }) {
            var initial = State()
            configure(&initial)
            state = Mutex(initial)
        }

        func value(_ place: KeychainPlace, _ account: String = "blockfrost") -> String? {
            state.withLock { $0.items[place]?[account] }.map { String(decoding: $0, as: UTF8.self) }
        }

        func read(account: String, service: String, place: KeychainPlace) -> Result<Data?, SecretStoreError> {
            state.withLock { state in
                if let status = state.refused[place] { return .failure(SecretStoreError(status: status)) }
                return .success(state.items[place]?[account])
            }
        }

        func write(_ data: Data, account: String, service: String, place: KeychainPlace) -> OSStatus {
            state.withLock { state in
                if let status = state.refused[place] ?? state.refusedWrites[place] { return status }
                state.items[place, default: [:]][account] = data
                return errSecSuccess
            }
        }

        func delete(account: String, service: String, place: KeychainPlace) -> OSStatus {
            state.withLock { state in
                if let status = state.refused[place] { return status }
                return state.items[place]?.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
            }
        }
    }

    func store(_ keychain: FakeKeychain, syncing: Bool) -> KeychainSecretStore {
        KeychainSecretStore(synchronizable: syncing, keychain: keychain)
    }

    @Test("Syncing, a key goes in iCloud Keychain, and this device's copy is replaced by it")
    func syncedWhenAllowed() throws {
        let keychain = FakeKeychain { $0.items[.local] = ["blockfrost": Data("old".utf8)] }
        try store(keychain, syncing: true).setSecret("key", for: "blockfrost")
        #expect(keychain.value(.synced) == "key")
        #expect(keychain.value(.local) == nil)
        #expect(try store(keychain, syncing: true).secret(for: "blockfrost") == "key")
    }

    @Test("When iCloud Keychain refuses it, a key stays on this device, and is read again and again")
    func keptWhenICloudRefuses() throws {
        let keychain = FakeKeychain { $0.refused[.synced] = errSecMissingEntitlement }
        let syncing = store(keychain, syncing: true)
        try syncing.setSecret("key", for: "blockfrost")
        #expect(keychain.value(.local) == "key")
        #expect(keychain.value(.login) == nil, "Not the login keychain: this build may use the data-protection one.")
        for _ in 0..<3 {
            #expect(try syncing.secret(for: "blockfrost") == "key")
        }
    }

    @Test("Turning sync on keeps a key whatever iCloud Keychain says")
    func turningSyncOn() throws {
        for refusal in [errSecMissingEntitlement, errSecNotAvailable, errSecInteractionNotAllowed] {
            let keychain = FakeKeychain {
                $0.items[.local] = ["blockfrost": Data("key".utf8)]
                $0.refusedWrites[.synced] = refusal
            }
            // What turning sync on does: read with the old store, save with the new.
            let key = try #require(try store(keychain, syncing: false).secret(for: "blockfrost"))
            try store(keychain, syncing: true).setSecret(key, for: "blockfrost")
            #expect(try store(keychain, syncing: true).secret(for: "blockfrost") == "key", "Refused with \(refusal).")
        }
    }

    @Test("A key an earlier build kept in the login keychain moves, and is not lost when iCloud Keychain refuses it")
    func movesFromLoginKeychain() throws {
        let keychain = FakeKeychain {
            $0.items[.login] = ["blockfrost": Data("key".utf8)]
            $0.refused[.synced] = errSecMissingEntitlement
        }
        let syncing = store(keychain, syncing: true)
        #expect(try syncing.secret(for: "blockfrost") == "key")
        #if os(macOS)
        #expect(keychain.value(.local) == "key")
        #expect(keychain.value(.login) == nil, "Removed once the new copy is stored.")
        #endif
        #expect(try syncing.secret(for: "blockfrost") == "key")
    }

    @Test("A login keychain copy stays when the move cannot be stored")
    func loginCopyStaysWhenMoveFails() throws {
        let keychain = FakeKeychain {
            $0.items[.login] = ["blockfrost": Data("key".utf8)]
            $0.refusedWrites[.local] = errSecInteractionNotAllowed
            $0.refusedWrites[.synced] = errSecInteractionNotAllowed
        }
        let syncing = store(keychain, syncing: true)
        #expect(try syncing.secret(for: "blockfrost") == "key")
        #if os(macOS)
        #expect(keychain.value(.login) == "key")
        #endif
        #expect(try syncing.secret(for: "blockfrost") == "key")
    }

    @Test("A build signed without a team keeps its keys in the login keychain, and never removes them")
    func unsignedBuild() throws {
        #if os(macOS)
        let keychain = FakeKeychain {
            $0.refused[.local] = errSecMissingEntitlement
            $0.refused[.synced] = errSecMissingEntitlement
        }
        for syncing in [false, true] {
            try store(keychain, syncing: syncing).setSecret("key", for: "blockfrost")
            #expect(keychain.value(.login) == "key")
            #expect(try store(keychain, syncing: syncing).secret(for: "blockfrost") == "key")
            #expect(try store(keychain, syncing: syncing).secret(for: "blockfrost") == "key")
        }
        #endif
    }

    @Test("A failed save leaves the key that was there")
    func failedSaveKeepsOldKey() throws {
        let keychain = FakeKeychain {
            $0.items[.local] = ["blockfrost": Data("old".utf8)]
            $0.refusedWrites[.local] = errSecInteractionNotAllowed
        }
        #expect(throws: SecretStoreError.self) { try store(keychain, syncing: false).setSecret("new", for: "blockfrost") }
        #expect(try store(keychain, syncing: false).secret(for: "blockfrost") == "old")
    }

    @Test("Not syncing, a key synced from another device is still read, and never removed from iCloud")
    func notSyncingLeavesICloudAlone() throws {
        let keychain = FakeKeychain { $0.items[.synced] = ["blockfrost": Data("synced".utf8)] }
        let local = store(keychain, syncing: false)
        #expect(try local.secret(for: "blockfrost") == "synced")
        try local.setSecret("mine", for: "blockfrost")
        #expect(keychain.value(.local) == "mine")
        #expect(keychain.value(.synced) == "synced")
        #expect(try local.secret(for: "blockfrost") == "mine", "This device's own copy comes first.")
        try local.removeSecret(for: "blockfrost")
        #expect(keychain.value(.local) == nil)
        #expect(keychain.value(.synced) == "synced")
    }

    @Test("Syncing, removing a key removes it everywhere")
    func syncingRemovesEverywhere() throws {
        let keychain = FakeKeychain {
            $0.items[.synced] = ["blockfrost": Data("a".utf8)]
            $0.items[.local] = ["blockfrost": Data("b".utf8)]
        }
        try store(keychain, syncing: true).removeSecret(for: "blockfrost")
        #expect(keychain.value(.synced) == nil)
        #expect(keychain.value(.local) == nil)
        #expect(try store(keychain, syncing: true).secret(for: "blockfrost") == nil)
    }
}
