import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// One output: where it pays, how much, and what it carries.
struct OutputSection: View {
    let output: OutputDetail
    let title: LocalizedStringResource

    var body: some View {
        Section {
            TWFieldRow(LocalizedStringResource("Address", bundle: #bundle)) {
                TWBytesText(output.address.text, font: TWFont.bytesSmall)
            }
            TWFieldRow(LocalizedStringResource("Pays to", bundle: #bundle)) {
                Text(output.address.paysToScript ? "A script (\(output.address.kind.rawValue))" : "A key (\(output.address.kind.rawValue))", bundle: #bundle)
            }
            if let stake = output.address.stake {
                TWFieldRow(LocalizedStringResource("Stake", bundle: #bundle)) {
                    TWBytesText(stake, font: TWFont.bytesSmall)
                }
            }
            TWFieldRow(LocalizedStringResource("Ada", bundle: #bundle)) {
                Text(verbatim: TWFormat.ada(output.lovelace)).font(TWFont.figure)
            }
            if !output.assets.isEmpty {
                DisclosureGroup {
                    ForEach(output.assets) { asset in
                        AssetRow(asset: asset)
                    }
                } label: {
                    Text("^[\(output.assets.count) native asset](inflect: true)", bundle: #bundle)
                }
            }
            switch output.datum {
            case .hash(let hash)?:
                TWFieldRow(LocalizedStringResource("Datum hash", bundle: #bundle)) {
                    TWBytesText(hash, font: TWFont.bytesSmall)
                }
            case .inline(let hash, let tree, _)?:
                TWFieldRow(LocalizedStringResource("Inline datum", bundle: #bundle)) {
                    TWBytesText(hash, font: TWFont.bytesSmall)
                }
                DataTreeView(node: tree)
            case nil:
                EmptyView()
            }
            if let script = output.referenceScript {
                TWFieldRow(LocalizedStringResource("Reference script", bundle: #bundle)) {
                    Text(verbatim: "\(script.language) · \(script.hash.prefix(12))…")
                        .font(TWFont.bytesSmall)
                }
            }
        } header: {
            Text(title)
        }
    }
}
