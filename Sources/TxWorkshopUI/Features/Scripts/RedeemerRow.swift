import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct RedeemerRow: View {
    let redeemer: RedeemerDetail
    /// Opens the debugger; `nil` when there is no chain data to run it with.
    var onDebug: (() -> Void)?

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
            if let onDebug {
                Button(action: onDebug) {
                    Label {
                        Text("Debug Script", bundle: #bundle)
                    } icon: {
                        Image(systemName: "ladybug")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
