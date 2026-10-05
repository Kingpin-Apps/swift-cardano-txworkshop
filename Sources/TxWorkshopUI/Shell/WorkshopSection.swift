import SwiftUI

/// The sections of a document, in sidebar order.
enum WorkshopSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case inputsOutputs
    case body
    case scripts
    case metadata
    case cbor
    case cddl
    case chainData
    case validate
    case build
    case sign

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .overview: LocalizedStringResource("Overview", bundle: #bundle)
        case .inputsOutputs: LocalizedStringResource("Inputs & Outputs", bundle: #bundle)
        case .body: LocalizedStringResource("Certificates & Governance", bundle: #bundle)
        case .scripts: LocalizedStringResource("Scripts & Datums", bundle: #bundle)
        case .metadata: LocalizedStringResource("Metadata", bundle: #bundle)
        case .cbor: LocalizedStringResource("CBOR", bundle: #bundle)
        case .cddl: LocalizedStringResource("CDDL", bundle: #bundle)
        case .chainData: LocalizedStringResource("Chain Data", bundle: #bundle)
        case .validate: LocalizedStringResource("Validate", bundle: #bundle)
        case .build: LocalizedStringResource("Build", bundle: #bundle)
        case .sign: LocalizedStringResource("Sign & Submit", bundle: #bundle)
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "doc.text.magnifyingglass"
        case .inputsOutputs: "arrow.left.arrow.right"
        case .body: "checkmark.seal"
        case .scripts: "curlybraces"
        case .metadata: "tag"
        case .cbor: "chevron.left.forwardslash.chevron.right"
        case .cddl: "text.book.closed"
        case .chainData: "cube.transparent"
        case .validate: "checklist"
        case .build: "hammer"
        case .sign: "signature"
        }
    }

    static let inspect: [WorkshopSection] = [.overview, .inputsOutputs, .body, .scripts, .metadata, .cbor, .cddl]
    static let act: [WorkshopSection] = [.chainData, .validate, .build, .sign]
}
