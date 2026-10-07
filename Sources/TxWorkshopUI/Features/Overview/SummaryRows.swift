import SwiftCardanoExplorers
import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

struct SummaryRows: View {
    let summary: TransactionSummary

    var body: some View {
        TWFieldRow(LocalizedStringResource("ID", bundle: #bundle)) {
            HStack(alignment: .firstTextBaseline) {
                TWBytesText(summary.id)
                CopyButton(text: summary.id)
                ExplorerLinkButton(item: ExplorerItem.transaction(summary.id))
            }
        }
        TWFieldRow(LocalizedStringResource("Fee", bundle: #bundle)) {
            Text(verbatim: TWFormat.ada(summary.view.fee)).font(TWFont.figure)
        }
        TWFieldRow(LocalizedStringResource("Inputs", bundle: #bundle)) {
            Text(summary.view.inputs.count, format: .number).font(TWFont.figure)
        }
        TWFieldRow(LocalizedStringResource("Outputs", bundle: #bundle)) {
            Text(summary.view.outputs.count, format: .number).font(TWFont.figure)
        }
        TWFieldRow(LocalizedStringResource("Era", bundle: #bundle)) {
            Text(verbatim: summary.possibleEras)
        }
        TWFieldRow(LocalizedStringResource("Signatures", bundle: #bundle)) {
            Text(summary.view.witnessCount, format: .number).font(TWFont.figure)
        }
        TWFieldRow(LocalizedStringResource("Size", bundle: #bundle)) {
            Text(Int64(summary.byteCount), format: .byteCount(style: .memory)).font(TWFont.figure)
        }
    }

}
