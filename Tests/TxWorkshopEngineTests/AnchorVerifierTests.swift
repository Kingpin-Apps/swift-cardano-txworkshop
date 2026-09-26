import Foundation
import Testing

@testable import TxWorkshopEngine

/// Serves canned anchors by URL.
final class AnchorURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodies[request.url!.absoluteString]
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Governance anchors", .serialized)
struct AnchorVerifierTests {
    static let document = Data(#"{"@context": {}, "body": {"title": "Raise the fee", "abstract": {"@value": "Why and how."}}}"#.utf8)

    func verifier() -> AnchorVerifier {
        AnchorURLProtocol.bodies = [
            "https://example.com/anchor.jsonld": Self.document,
            "https://ipfs.io/ipfs/bafyanchor": Self.document,
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnchorURLProtocol.self]
        return AnchorVerifier(session: URLSession(configuration: configuration))
    }

    @Test("Content that hashes to the anchor matches, and its title is read")
    func matches() async {
        let check = await verifier().check(url: "https://example.com/anchor.jsonld", expectedHash: AnchorVerifier.hash(Self.document))
        #expect(check.status == .matches)
        #expect(check.title == "Raise the fee")
        #expect(check.abstract == "Why and how.")
        #expect(check.byteCount == Self.document.count)
    }

    @Test("Other content is a mismatch, with the hash it has")
    func mismatch() async {
        let check = await verifier().check(url: "https://example.com/anchor.jsonld", expectedHash: String(repeating: "0", count: 64))
        #expect(check.status == .mismatch(computed: AnchorVerifier.hash(Self.document)))
    }

    @Test("IPFS anchors go through the gateway")
    func ipfs() async {
        let check = await verifier().check(url: "ipfs://bafyanchor", expectedHash: AnchorVerifier.hash(Self.document))
        #expect(check.status == .matches)
    }

    @Test("Missing and unsupported anchors are unreachable")
    func unreachable() async {
        guard case .unreachable = await verifier().check(url: "https://example.com/gone", expectedHash: "").status else {
            Issue.record("a 404 should be unreachable"); return
        }
        guard case .unreachable = await verifier().check(url: "ftp://example.com/x", expectedHash: "").status else {
            Issue.record("ftp should be unsupported"); return
        }
    }

    @Test("The hash is Blake2b-256 of the bytes")
    func knownHash() {
        // Blake2b-256 of the empty string.
        #expect(AnchorVerifier.hash(Data()) == "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8")
    }
}
