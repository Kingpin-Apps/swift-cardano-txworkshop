import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// A built transaction: what it spends, the fee item by item, and the button
/// that makes it the document's.
struct CompositionSections: View {
    let composition: TransactionComposer.Composition
    let onUse: () -> Void

    var body: some View {
        Section {
            TWFieldRow(LocalizedStringResource("Transaction id", bundle: #bundle)) {
                CopyableBytes(composition.id)
            }
            TWFieldRow(LocalizedStringResource("In", bundle: #bundle)) {
                Text(verbatim: TWFormat.ada(composition.totalIn)).font(TWFont.figure)
            }
            TWFieldRow(LocalizedStringResource("Out", bundle: #bundle)) {
                Text(verbatim: TWFormat.ada(composition.totalOut)).font(TWFont.figure)
            }
            if let change = composition.change {
                TWFieldRow(LocalizedStringResource("Change", bundle: #bundle)) {
                    Text(verbatim: TWFormat.ada(change)).font(TWFont.figure)
                }
            }
            if composition.deposits > 0 {
                TWFieldRow(LocalizedStringResource("Deposits", bundle: #bundle)) {
                    Text(verbatim: TWFormat.ada(composition.deposits)).font(TWFont.figure)
                }
            }
            if composition.refunds > 0 {
                TWFieldRow(LocalizedStringResource("Refunds", bundle: #bundle)) {
                    Text(verbatim: TWFormat.ada(composition.refunds)).font(TWFont.figure)
                }
            }
            DisclosureGroup {
                ForEach(composition.inputs, id: \.self) { input in
                    CopyableBytes(input)
                }
            } label: {
                Text(AttributedString(localized: "^[\(composition.inputs.count) input](inflect: true) chosen", bundle: #bundle))
            }
            Button(action: onUse) {
                Text("Use as the Document's Transaction", bundle: #bundle)
            }
        } header: {
            Text("Built", bundle: #bundle)
        } footer: {
            Text("Replaces the document's transaction, to inspect, validate and sign. Undo brings the old one back.", bundle: #bundle)
        }
        FeeBreakdownSection(fee: composition.fee)
    }
}

/// The fee, item by item, as the ledger prices it.
struct FeeBreakdownSection: View {
    let fee: TransactionComposer.FeeBreakdownView

    var body: some View {
        Section {
            row(LocalizedStringResource("Size: \(fee.sizeBytes) bytes", bundle: #bundle), fee.sizeFee)
            row(LocalizedStringResource("Fixed", bundle: #bundle), fee.fixedFee)
            if fee.memory > 0 || fee.steps > 0 {
                row(LocalizedStringResource("Script memory: \(fee.memory)", bundle: #bundle), fee.memoryFee)
                row(LocalizedStringResource("Script steps: \(fee.steps)", bundle: #bundle), fee.stepsFee)
            }
            if fee.referenceScriptBytes > 0 {
                row(LocalizedStringResource("Reference scripts: \(fee.referenceScriptBytes) bytes", bundle: #bundle), fee.referenceScriptFee)
                ForEach(fee.referenceScriptTiers.indices, id: \.self) { index in
                    let tier = fee.referenceScriptTiers[index]
                    Text("Tier \(index + 1): \(tier.bytes) bytes at \(tier.pricePerByte, format: .number.precision(.fractionLength(0...3))) per byte", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
            }
            if fee.buffer > 0 {
                row(LocalizedStringResource("Buffer", bundle: #bundle), fee.buffer)
            }
            TWFieldRow(LocalizedStringResource("Fee", bundle: #bundle)) {
                Text(verbatim: TWFormat.ada(fee.total))
                    .font(TWFont.figure.bold())
            }
        } header: {
            Text("Fee", bundle: #bundle)
        }
    }

    private func row(_ title: LocalizedStringResource, _ lovelace: UInt64) -> some View {
        TWFieldRow(title) {
            Text(verbatim: TWFormat.ada(lovelace)).font(TWFont.figure)
        }
    }
}
