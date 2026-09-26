import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// When the transaction may be included, in slots and local time.
struct ValiditySection: View {
    let validity: ValidityWindow

    var body: some View {
        Section {
            if validity.isUnbounded {
                Text("Valid in any slot.", bundle: #bundle)
            } else {
                BoundRow(title: LocalizedStringResource("Valid from", bundle: #bundle), slot: validity.startSlot, date: validity.start)
                BoundRow(title: LocalizedStringResource("Valid until", bundle: #bundle), slot: validity.endSlot, date: validity.end)
            }
        } header: {
            Text("Validity", bundle: #bundle)
        } footer: {
            if !validity.isUnbounded && validity.start == nil && validity.end == nil {
                Text("Set the document's network to see these slots as times.", bundle: #bundle)
            }
        }
    }
}

private struct BoundRow: View {
    let title: LocalizedStringResource
    let slot: UInt64?
    let date: Date?

    var body: some View {
        TWFieldRow(title) {
            if let slot {
                VStack(alignment: .trailing) {
                    Text("Slot \(slot)", bundle: #bundle).font(TWFont.figure)
                    if let date {
                        Text(date, format: .dateTime.year().month().day().hour().minute().second())
                            .foregroundStyle(TWColor.secondaryText)
                    }
                }
            } else {
                Text("No bound", bundle: #bundle).foregroundStyle(TWColor.secondaryText)
            }
        }
    }
}
