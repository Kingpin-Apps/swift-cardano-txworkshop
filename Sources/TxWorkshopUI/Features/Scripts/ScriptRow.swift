import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A script with its UPLC listing behind a disclosure.
struct ScriptRow: View {
    let script: ScriptDetail
    @State private var showsListing = false

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack {
                Text(verbatim: script.language)
                Spacer()
                Text(Int64(script.size), format: .byteCount(style: .memory))
                    .font(TWFont.figure)
                    .foregroundStyle(TWColor.secondaryText)
            }
            TWBytesText(script.hash, font: TWFont.bytesSmall)
            if let listing = script.listing {
                DisclosureGroup(isExpanded: $showsListing) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: listing)
                            .font(TWFont.bytesSmall)
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(.vertical, TWSpacing.xs)
                    }
                    .frame(maxHeight: 420)
                } label: {
                    Text("Listing", bundle: #bundle)
                }
            }
        }
    }
}
