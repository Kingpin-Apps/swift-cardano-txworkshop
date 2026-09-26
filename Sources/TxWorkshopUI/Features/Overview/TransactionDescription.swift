import Foundation
import TxWorkshopEngine

/// A plain-English sentence saying what a transaction does.
enum TransactionDescription {
    /// A localized clause with its counts inflected. `String(localized:)`
    /// leaves the `^[…](inflect: true)` markup as it is; an attributed string
    /// applies it.
    private static func inflected(_ value: String.LocalizationValue) -> String {
        String(AttributedString(localized: value, bundle: #bundle).characters)
    }

    static func sentence(for inspection: TransactionInspection) -> String {
        let view = inspection.view
        var parts: [String] = []
        parts.append(inflected("Spends ^[\(inspection.inputs.count) input](inflect: true)"))
        parts.append(inflected("creates ^[\(inspection.outputs.count) output](inflect: true)"))
        let minted = inspection.mint.filter { $0.quantity > 0 }.count
        let burned = inspection.mint.filter { $0.quantity < 0 }.count
        if minted > 0 { parts.append(inflected("mints ^[\(minted) asset](inflect: true)")) }
        if burned > 0 { parts.append(inflected("burns ^[\(burned) asset](inflect: true)")) }
        if !inspection.redeemers.isEmpty {
            parts.append(inflected("runs ^[\(inspection.redeemers.count) script](inflect: true)"))
        }
        if !view.certificates.isEmpty {
            parts.append(inflected("carries ^[\(view.certificates.count) certificate](inflect: true)"))
        }
        if !view.votes.isEmpty { parts.append(inflected("casts ^[\(view.votes.count) vote](inflect: true)")) }
        if !view.proposals.isEmpty {
            parts.append(inflected("makes ^[\(view.proposals.count) proposal](inflect: true)"))
        }
        if !view.withdrawals.isEmpty {
            parts.append(inflected("withdraws rewards from ^[\(view.withdrawals.count) account](inflect: true)"))
        }
        let list = parts.formatted(.list(type: .and))
        return list.prefix(1).uppercased() + list.dropFirst() + "."
    }
}
