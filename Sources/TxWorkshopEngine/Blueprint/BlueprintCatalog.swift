import Foundation
import SwiftCardanoCore
import Synchronization
import TxWorkshopCore

/// What a blueprint form fills in: a validator's datum or its redeemer.
public enum BlueprintRole: Sendable, Equatable {
    case datum, redeemer

    public func argument(of validator: Blueprint.Validator) -> Blueprint.Argument? {
        switch self {
        case .datum: validator.datum
        case .redeemer: validator.redeemer
        }
    }

    /// The root of field paths: `datum.price`.
    public var path: String {
        switch self {
        case .datum: "datum"
        case .redeemer: "redeemer"
        }
    }
}

/// A validator from a stored blueprint.
public struct BlueprintChoice: Sendable, Equatable, Identifiable {
    public let stored: StoredBlueprint
    public let blueprint: Blueprint
    public let validator: Blueprint.Validator

    public var id: String { "\(stored.id)|\(validator.title)" }
}

/// Stored blueprints, read once and looked up by script hash or by a form's
/// reference.
public enum BlueprintCatalog {
    private static let cache = Mutex<[String: Blueprint]>([:])

    /// The blueprint `stored` holds, read once per app run.
    public static func blueprint(_ stored: StoredBlueprint) throws -> Blueprint {
        if let cached = cache.withLock({ $0[stored.id] }) { return cached }
        let parsed = try Blueprint(json: Data(stored.json.utf8))
        cache.withLock { $0[stored.id] = parsed }
        return parsed
    }

    /// Every validator in `stored` that has a `role` argument, for picking from.
    public static func choices(_ stored: [StoredBlueprint], role: BlueprintRole, purpose: String? = nil) -> [BlueprintChoice] {
        stored.flatMap { item -> [BlueprintChoice] in
            guard let blueprint = try? blueprint(item) else { return [] }
            return blueprint.validators
                .filter { role.argument(of: $0) != nil && (purpose == nil || $0.purpose == nil || $0.purpose == purpose) }
                .map { BlueprintChoice(stored: item, blueprint: blueprint, validator: $0) }
        }
    }

    /// The validators for a script hash with a `role` argument, preferring
    /// `purpose` when a script has several.
    public static func choices(
        _ stored: [StoredBlueprint], scriptHash: String, role: BlueprintRole, purpose: String? = nil
    ) -> [BlueprintChoice] {
        let matching = choices(stored, role: role).filter { $0.validator.hash == scriptHash.lowercased() }
        let forPurpose = matching.filter { $0.validator.purpose == purpose }
        return forPurpose.isEmpty ? matching : forPurpose
    }

    /// The validator a form names, looked up in `stored`.
    public static func choice(for form: BlueprintForm, in stored: [StoredBlueprint]) -> BlueprintChoice? {
        guard let item = stored.first(where: { $0.id == form.blueprint }), let blueprint = try? blueprint(item),
            let validator = blueprint.validators.first(where: { $0.title == form.validator })
        else { return nil }
        return BlueprintChoice(stored: item, blueprint: blueprint, validator: validator)
    }

    /// A Plutus script draft's hash; `nil` for native and reference scripts,
    /// or code that does not read.
    public static func scriptHash(_ script: ScriptDraft?) -> String? {
        guard case .plutus(let version, let hex)? = script, !hex.isEmpty,
            let compiled = try? ValueReader.plutusScript(hex, version: version).value,
            let type = try? TransactionComposer.plutusScript(version: version, hex: compiled)
        else { return nil }
        return try? SwiftCardanoCore.scriptHash(script: type).payload.hex
    }

    /// The script hash an address is locked by; `nil` for a key's address.
    public static func scriptHash(address text: String, network: CardanoNetwork?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let read = try? ValueReader.read(.address, text: trimmed, network: network),
            let address = try? Address(from: .string(read.value)),
            case .scriptHash(let hash)? = address.paymentPart
        else { return nil }
        return hash.payload.hex
    }

    /// Problems with a form, named by field, or why it cannot be checked.
    public static func problems(_ form: BlueprintForm, role: BlueprintRole, in stored: [StoredBlueprint]) -> [BlueprintProblem] {
        guard let choice = choice(for: form, in: stored) else {
            return [BlueprintProblem(path: role.path, message: "Its blueprint (\(form.validator)) is no longer in the document. Switch to Raw, or choose the blueprint again.")]
        }
        guard let argument = role.argument(of: choice.validator) else {
            return [BlueprintProblem(path: role.path, message: "\(form.validator) takes no \(role.path).")]
        }
        return choice.blueprint.problems(form.value, as: argument.schema, path: role.path)
    }
}
