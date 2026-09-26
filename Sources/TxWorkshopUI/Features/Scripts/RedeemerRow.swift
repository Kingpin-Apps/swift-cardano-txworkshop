import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct RedeemerRow: View {
    let redeemer: RedeemerDetail

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(redeemer.view.tag)[\(redeemer.view.index)]")
                    .font(TWFont.bytes)
                Spacer()
                if let units = redeemer.view.exUnits {
                    Text("\(units.memory.formatted()) mem · \(units.steps.formatted()) steps", bundle: #bundle)
                        .font(TWFont.bytesSmall)
                        .foregroundStyle(TWColor.secondaryText)
                }
            }
            if let purpose = redeemer.view.purpose {
                TWBytesText(purpose, font: TWFont.bytesSmall)
                    .foregroundStyle(TWColor.secondaryText)
            }
            DataTreeView(node: redeemer.tree)
        }
    }
}
