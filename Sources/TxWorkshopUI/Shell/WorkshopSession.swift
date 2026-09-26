import Foundation
import Observation
import TxWorkshopEngine

/// What one document window shares between its sections: which section is
/// showing, a request to show an item in the CBOR explorer, and the latest
/// validation, whose findings the explorer marks.
@MainActor
@Observable
final class WorkshopSession {
    var selection: WorkshopSection? = .overview
    /// A tree path the CBOR explorer should select next.
    var cborFocus: [Int]?
    /// A field path the CBOR explorer should select next, as validation
    /// writes it.
    var cborFieldFocus: String?
    private(set) var validation: ValidationOutcome?
    /// The bytes ``validation`` judged; its findings are shown only while the
    /// document still holds them.
    private(set) var validatedTransaction: Data?

    func record(_ outcome: ValidationOutcome, for transaction: Data) {
        validation = outcome
        validatedTransaction = transaction
    }

    /// The latest validation, if it judged `transaction`.
    func validation(for transaction: Data?) -> ValidationOutcome? {
        transaction != nil && transaction == validatedTransaction ? validation : nil
    }

    /// Opens the CBOR explorer at the item a validation finding is about.
    func show(fieldPath: String) {
        cborFieldFocus = fieldPath
        selection = .cbor
    }
}
