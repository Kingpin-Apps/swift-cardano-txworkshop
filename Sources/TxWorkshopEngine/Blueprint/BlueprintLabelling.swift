import Foundation
import SwiftCardanoCore
import SwiftCardanoTxValidator
import TxWorkshopCore

extension TransactionInspection {
    /// The inspection with every datum and redeemer whose script is in
    /// `blueprints` read as its blueprint type: fields by name, constructors
    /// by their titles. Data that does not fit its type is left as it was.
    /// ``labelled(with:)`` on a thread with room for deeply nested data.
    public func labelling(with blueprints: [StoredBlueprint], applied: [String: BlueprintParameters] = [:]) async -> TransactionInspection {
        guard !blueprints.isEmpty else { return self }
        let inspection = self
        return await DeepStack.run { inspection.labelled(with: blueprints, applied: applied) }
    }

    /// `applied` names the validators of scripts made by applying parameters.
    public func labelled(with blueprints: [StoredBlueprint], applied: [String: BlueprintParameters] = [:]) -> TransactionInspection {
        guard !blueprints.isEmpty else { return self }
        var copy = self
        let label = BlueprintLabeller(blueprints: blueprints, applied: applied)

        func output(_ detail: OutputDetail) -> OutputDetail {
            guard case .inline(let hash, _, let cborHex)? = detail.datum,
                let tree = label.datum(cborHex, scriptHash: Self.scriptHash(detail.address.payment))
            else { return detail }
            var labelled = detail
            labelled.datum = .inline(hash: hash, tree: tree, cborHex: cborHex)
            return labelled
        }
        func input(_ detail: InputDetail) -> InputDetail {
            var labelled = detail
            labelled.output = detail.output.map(output)
            return labelled
        }
        copy.outputs = outputs.map(output)
        copy.collateralReturn = collateralReturn.map(output)
        copy.inputs = inputs.map(input)
        copy.referenceInputs = referenceInputs.map(input)
        copy.collateralInputs = collateralInputs.map(input)

        // A witness datum belongs to the input whose output holds its hash.
        copy.datums = datums.map { datum in
            let owner = inputs.compactMap(\.output).first { output in
                if case .hash(let hash)? = output.datum { return hash == datum.hash }
                return false
            }
            guard let owner, let tree = label.datum(datum.cborHex, scriptHash: Self.scriptHash(owner.address.payment)) else { return datum }
            var labelled = datum
            labelled.tree = tree
            return labelled
        }

        copy.redeemers = redeemers.map { redeemer in
            guard let tree = label.redeemer(
                redeemer.view.dataCBORHex, scriptHash: redeemerScriptHash(redeemer.view), purpose: Self.purpose(of: redeemer.view.tag)
            ) else { return redeemer }
            var labelled = redeemer
            labelled.tree = tree
            return labelled
        }
        return copy
    }

    /// The script a redeemer runs, from what its index points at.
    func redeemerScriptHash(_ redeemer: RedeemerView) -> String? {
        guard let purpose = redeemer.purpose else { return nil }
        switch redeemer.tag {
        case "spend":
            return Self.scriptHash(inputs.first { $0.id == purpose }?.output?.address.payment)
        case "mint":
            return purpose.lowercased()
        case "reward":
            guard let address = try? Address(from: .string(purpose)), case .scriptHash(let hash)? = address.stakingPart else { return nil }
            return hash.payload.hex
        case "cert":
            if let index = purpose.firstMatch(of: /certificate\[(\d+)\]/).flatMap({ Int($0.output.1) }),
                view.certificates.indices.contains(index) {
                return Self.scriptHash(view.certificates[index].credential)
            }
            return nil
        default:
            return purpose.firstMatch(of: /script:([0-9a-fA-F]{56})/).map { String($0.output.1).lowercased() }
        }
    }

    /// The hash in a `script:<hash>` credential.
    static func scriptHash(_ credential: String?) -> String? {
        guard let credential, credential.hasPrefix("script:") else { return nil }
        return String(credential.dropFirst("script:".count))
    }

    /// The Aiken purpose a redeemer tag runs under.
    static func purpose(of tag: String) -> String? {
        switch tag {
        case "spend": "spend"
        case "mint": "mint"
        case "reward": "withdraw"
        case "cert": "publish"
        case "voting": "vote"
        case "proposing": "propose"
        default: nil
        }
    }
}

/// Reads datums and redeemers as their validators' blueprint types.
struct BlueprintLabeller {
    let blueprints: [StoredBlueprint]
    var applied: [String: BlueprintParameters] = [:]

    func datum(_ cborHex: String, scriptHash: String?) -> DataNode? {
        tree(cborHex, scriptHash: scriptHash, role: .datum, purpose: "spend")
    }

    func redeemer(_ cborHex: String, scriptHash: String?, purpose: String?) -> DataNode? {
        tree(cborHex, scriptHash: scriptHash, role: .redeemer, purpose: purpose)
    }

    private func tree(_ cborHex: String, scriptHash: String?, role: BlueprintRole, purpose: String?) -> DataNode? {
        guard let scriptHash, let bytes = try? TxDocumentCodec.bytes(fromHex: cborHex),
            let data = try? PlutusData.fromCBOR(data: bytes)
        else { return nil }
        for choice in BlueprintCatalog.choices(blueprints, scriptHash: scriptHash, role: role, purpose: purpose, applied: applied) {
            guard let argument = role.argument(of: choice.validator),
                (try? choice.blueprint.decode(data, as: argument.schema, path: role.path)) != nil
            else { continue }
            var tree = choice.blueprint.dataNode(data, as: argument.schema)
            tree.validator = choice.validator.title
            if tree.typeName == nil { tree.typeName = choice.blueprint.typeName(argument.schema) }
            return tree
        }
        return nil
    }
}

extension Blueprint {
    /// `data` as a tree labelled by `schema`: fields by name, constructors by
    /// title. Parts that do not fit fall back to the plain tree.
    public func dataNode(_ data: PlutusData, as schema: BlueprintSchema, label: String = "", path: String = "$") -> DataNode {
        let plain = DataNode.plutus(data, label: label, path: path)
        guard let resolved = try? resolve(schema) else { return plain }
        let type = typeName(schema)

        func typed(_ node: DataNode, _ name: String?) -> DataNode {
            var node = node
            node.typeName = name
            return node
        }
        func node(kind: DataNode.Kind, children: [DataNode], name: String?) -> DataNode {
            var node = DataNode(id: path, label: label, kind: kind, value: nil, text: nil, children: children)
            node.typeName = name
            return node
        }

        switch resolved.kind {
        case .integer, .bytes:
            return typed(plain, type)
        case .list(let items, _):
            guard let elements = Self.elements(data) else { return plain }
            return node(kind: .list, children: elements.enumerated().map {
                dataNode($1, as: items, label: "\($0)", path: "\(path).\($0)")
            }, name: type)
        case .tuple(let items):
            guard let elements = Self.elements(data), elements.count == items.count else { return plain }
            return node(kind: .list, children: zip(items, elements).enumerated().map { index, pair in
                dataNode(pair.1, as: pair.0, label: "\(index)", path: "\(path).\(index)")
            }, name: type)
        case .map(_, let values, _):
            guard case .map(let pairs) = data, let keyed = plain.children, keyed.count == pairs.count else { return plain }
            return node(kind: .map, children: zip(pairs, keyed).enumerated().map { index, pair in
                dataNode(pair.0.value, as: values, label: pair.1.label, path: "\(path).\(index)")
            }, name: type)
        case .constructor(let index, let fields):
            return constructorNode(data, index: index, fields: fields, title: resolved.title, plain: plain, label: label, path: path)
        case .anyOf(let variants):
            guard case .constructor(let constr) = data, let tag = constr.tag else {
                // A sum of other forms: the first that fits.
                for variant in variants where (try? decode(data, as: variant, path: path)) != nil {
                    return dataNode(data, as: variant, label: label, path: path)
                }
                return plain
            }
            guard let variant = variants.compactMap({ try? resolve($0) }).first(where: { Self.constructorIndex($0) == Int(tag) }),
                case .constructor(let index, let fields) = variant.kind
            else { return plain }
            return constructorNode(data, index: index, fields: fields, title: variant.title, plain: plain, label: label, path: path)
        case .reference, .anyData, .unsupported, .builtin:
            return plain
        }
    }

    private func constructorNode(
        _ data: PlutusData, index: Int, fields: [BlueprintSchema], title: String?, plain: DataNode, label: String, path: String
    ) -> DataNode {
        guard case .constructor(let constr) = data, constr.tag.map(Int.init) == index, constr.fields.count == fields.count else { return plain }
        var node = DataNode(
            id: path, label: label, kind: .constructor(UInt64(index)), value: nil, text: nil,
            children: zip(fields, constr.fields).enumerated().map { position, pair in
                dataNode(pair.1, as: pair.0, label: pair.0.title ?? "\(position)", path: "\(path).\(position)")
            }
        )
        node.typeName = title
        return node
    }

    private static func elements(_ data: PlutusData) -> [PlutusData]? {
        switch data {
        case .array(let items): items
        case .indefiniteArray(let items): items.getAll()
        default: nil
        }
    }
}
