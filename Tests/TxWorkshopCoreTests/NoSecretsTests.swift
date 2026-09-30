import Foundation
import Testing

/// Keys and secrets never go in the repository: API keys live in the Keychain,
/// signing keys on the device. This fails if one is committed by mistake.
@Suite("No secrets in the repository")
struct NoSecretsTests {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let skippedDirectories: Set<String> = [".build", "build", ".git", ".swiftpm", "DerivedData", "Packages", "xcuserdata"]
    static let forbiddenExtensions: Set<String> = ["skey", "p8", "p12", "pem", "env", "mnemonic"]
    static let forbiddenPatterns = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        // Blockfrost project ids: the network name and 32 alphanumerics.
        #"\b(mainnet|preprod|preview)[A-Za-z0-9]{32}\b"#,
        // cardano-cli signing key envelopes.
        #""type": *"[A-Za-z]*SigningKey[A-Za-z_]*""#,
    ]

    static func files() -> [URL] {
        var found: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL {
            if skippedDirectories.contains(url.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                found.append(url)
            }
        }
        return found
    }

    @Test("The scan finds the repository")
    func scansTheRepository() {
        #expect(Self.files().contains { $0.lastPathComponent == "Package.swift" })
    }

    @Test("No key files")
    func noKeyFiles() {
        let keyFiles = Self.files().filter { Self.forbiddenExtensions.contains($0.pathExtension.lowercased()) }
        #expect(keyFiles.isEmpty, "\(keyFiles.map(\.lastPathComponent))")
    }

    @Test("No keys written into files")
    func noKeysInFiles() throws {
        let patterns = try Self.forbiddenPatterns.map { try Regex($0) }
        var offenders: [String] = []
        for file in Self.files() where file.lastPathComponent != "NoSecretsTests.swift" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if patterns.contains(where: { text.contains($0) }) {
                offenders.append(file.path.replacingOccurrences(of: Self.root.path, with: ""))
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
