import Testing
import Foundation
import SwiftCardanoCore
@testable import TxWorkshopEngine

@Suite("TEMP depth probe") struct DepthProbeTEMP {
    @Test func probe() async throws {
        guard let n = Int(ProcessInfo.processInfo.environment["PROBE_N"] ?? ""),
              let stage = ProcessInfo.processInfo.environment["PROBE_STAGE"] else { return }
        let ok = await Task.detached {
            // n nested one-element CBOR arrays around the integer 0
            let bytes = Data(repeating: 0x81, count: n) + Data([0x00])
            let data = try! PlutusData.fromCBOR(data: bytes)
            if stage == "decode" { return true }
            let node = DataNode.plutus(data)
            return node.id == "$"
        }.value
        FileHandle.standardError.write(Data("PROBE \(stage) \(n) ok=\(ok)\n".utf8))
    }
}
