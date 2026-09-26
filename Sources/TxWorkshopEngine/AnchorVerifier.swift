import Foundation
import SwiftNaCl

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What fetching a governance anchor found.
public struct AnchorCheck: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// The content hashes to the anchor's hash.
        case matches
        /// The content hashes to something else.
        case mismatch(computed: String)
        /// The content could not be fetched.
        case unreachable(String)
    }

    public let status: Status
    public let byteCount: Int?
    /// The CIP-108 title, or the CIP-119 DRep name.
    public let title: String?
    /// The CIP-108 abstract, or the CIP-119 objectives.
    public let abstract: String?
}

/// Fetches governance anchors (CIP-100) and checks their content against the
/// hash the chain records: Blake2b-256 of the bytes, exactly as served.
public struct AnchorVerifier: Sendable {
    /// Where `ipfs://` anchors are fetched from.
    public static let ipfsGateway = URL(string: "https://ipfs.io/ipfs/")!
    /// Anchors larger than this are not fetched in full.
    public static let maximumSize = 5 * 1024 * 1024

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func check(url: String, expectedHash: String) async -> AnchorCheck {
        guard let resolved = Self.resolve(url) else {
            return AnchorCheck(status: .unreachable("Not a web or IPFS address."), byteCount: nil, title: nil, abstract: nil)
        }
        let data: Data
        do {
            let (body, response) = try await session.data(from: resolved)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return AnchorCheck(status: .unreachable("HTTP \(http.statusCode)"), byteCount: nil, title: nil, abstract: nil)
            }
            guard body.count <= Self.maximumSize else {
                return AnchorCheck(status: .unreachable("Larger than 5 MB."), byteCount: body.count, title: nil, abstract: nil)
            }
            data = body
        } catch {
            return AnchorCheck(status: .unreachable(error.localizedDescription), byteCount: nil, title: nil, abstract: nil)
        }
        let computed = Self.hash(data)
        let (title, abstract) = Self.describe(data)
        return AnchorCheck(
            status: computed == expectedHash.lowercased() ? .matches : .mismatch(computed: computed),
            byteCount: data.count, title: title, abstract: abstract
        )
    }

    /// `https` and `http` addresses as they are; `ipfs://<cid>` through the gateway.
    static func resolve(_ url: String) -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("ipfs://") {
            return URL(string: String(trimmed.dropFirst("ipfs://".count)), relativeTo: ipfsGateway)?.absoluteURL
        }
        guard let parsed = URL(string: trimmed), ["https", "http"].contains(parsed.scheme?.lowercased()) else { return nil }
        return parsed
    }

    static func hash(_ data: Data) -> String {
        let digest = (try? Hash().blake2b(data: data, digestSize: 32, encoder: RawEncoder.self)) ?? Data()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The title and abstract of a CIP-108 governance action, or the name and
    /// objectives of a CIP-119 DRep, from the anchor's JSON-LD `body`.
    static func describe(_ data: Data) -> (title: String?, abstract: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let body = object["body"] as? [String: Any]
        else { return (nil, nil) }
        func text(_ key: String) -> String? {
            if let value = body[key] as? String { return value }
            if let value = body[key] as? [String: Any], let inner = value["@value"] as? String { return inner }
            return nil
        }
        return (text("title") ?? text("givenName"), text("abstract") ?? text("objectives"))
    }
}
