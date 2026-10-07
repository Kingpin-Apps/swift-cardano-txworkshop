import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A native asset: its readable name, fingerprint and quantity.
struct AssetRow: View {
    let asset: AssetDetail

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                Text(verbatim: title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
                if let fingerprint = asset.fingerprint {
                    CopyableBytes(fingerprint)
                        .foregroundStyle(TWColor.secondaryText)
                }
                CopyableBytes(asset.policyID)
                    .foregroundStyle(TWColor.secondaryText)
            }
            Spacer()
            ExplorerLinkButton(item: ExplorerItem.asset(policy: asset.policyID, name: asset.assetNameHex))
            quantity
                .font(TWFont.figure)
                .foregroundStyle(asset.quantity < 0 ? TWColor.failure : Color.primary)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        asset.displayName ?? asset.assetName ?? (asset.assetNameHex.isEmpty ? "—" : asset.assetNameHex)
    }

    /// Where the name came from, and what a CIP-67 label says the asset is.
    private var caption: AttributedString? {
        var parts: [String] = []
        if let label = asset.cip67Label { parts.append(Self.meaning(ofLabel: label)) }
        switch asset.nameSource {
        case .cip25?: parts.append(String(localized: "Named in the transaction (CIP-25)", bundle: #bundle))
        case .registry?: parts.append(String(localized: "Named by the token registry", bundle: #bundle))
        case nil: break
        }
        return parts.isEmpty ? nil : AttributedString(parts.joined(separator: " · "))
    }

    @ViewBuilder private var quantity: some View {
        let ticker = asset.ticker.map { " \($0)" } ?? ""
        if let decimals = asset.decimals, decimals > 0 {
            let value = Decimal(sign: asset.quantity < 0 ? .minus : .plus, exponent: -decimals, significand: Decimal(asset.quantity.magnitude))
            Text("\(value, format: .number.precision(.fractionLength(decimals)))\(ticker)", bundle: #bundle)
        } else {
            Text("\(asset.quantity, format: .number)\(ticker)", bundle: #bundle)
        }
    }

    /// What CIP-68 says an asset with this CIP-67 label is.
    static func meaning(ofLabel label: Int) -> String {
        switch label {
        case 100: String(localized: "Reference NFT (CIP-68)", bundle: #bundle)
        case 222: String(localized: "NFT (CIP-68)", bundle: #bundle)
        case 333: String(localized: "Fungible token (CIP-68)", bundle: #bundle)
        case 444: String(localized: "Rich fungible token (CIP-68)", bundle: #bundle)
        default: String(localized: "CIP-67 label \(label)", bundle: #bundle)
        }
    }
}
