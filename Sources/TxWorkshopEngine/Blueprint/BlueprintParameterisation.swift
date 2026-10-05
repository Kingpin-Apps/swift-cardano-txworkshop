import BigInt
import Foundation
import SwiftCardanoCore
import SwiftCardanoUPLC
import TxWorkshopCore

/// A validator made into a script by applying its parameters.
public struct AppliedValidator: Sendable, Equatable {
    /// The script's flat bytes in CBOR, as hex: what a blueprint's
    /// `compiledCode` holds.
    public let compiledCode: String
    public let hash: String
    public let plutusVersion: Int
}

extension Blueprint {
    /// Problems with parameter values, named `parameters.owner` and so on.
    public func parameterProblems(_ values: [BlueprintValue], for validator: Validator) -> [BlueprintProblem] {
        guard values.count == validator.parameters.count else {
            return [BlueprintProblem(path: "parameters", message: "\(validator.parameters.count) parameters expected, not \(values.count).")]
        }
        return zip(validator.parameters, values).enumerated().flatMap { index, pair in
            let path = Self.parameterPath(pair.0, index)
            if case .builtin = (try? resolve(pair.0.schema))?.kind {
                do {
                    _ = try constant(pair.1, as: pair.0.schema, path: path)
                    return [BlueprintProblem]()
                } catch BlueprintError.invalid(let problems) {
                    return problems
                } catch {
                    return [BlueprintProblem(path: path, message: String(describing: error))]
                }
            }
            return problems(pair.1, as: pair.0.schema, path: path)
        }
    }

    /// `validator`'s code with `values` applied, in order, as Aiken's
    /// `blueprint apply` does: Plutus data as data constants, builtin types as
    /// constants of their own type.
    public func apply(_ values: [BlueprintValue], to validator: Validator) throws -> AppliedValidator {
        let problems = parameterProblems(values, for: validator)
        guard problems.isEmpty else { throw BlueprintError.invalid(problems) }
        guard let code = validator.compiledCode, let bytes = try? TxDocumentCodec.bytes(fromHex: code) else {
            throw BlueprintError.notABlueprint("\(validator.title) has no compiled code.")
        }
        let named = try FlatDecoder().decode(try extractFlatBytes(from: bytes))
        let program = try DeBruijnConverter().convertFromNamed(named)
        var term = program.term
        for (index, pair) in zip(validator.parameters, values).enumerated() {
            term = .apply(function: term, argument: .constant(try constant(pair.1, as: pair.0.schema, path: Self.parameterPath(pair.0, index))))
        }
        let flat = try FlatEncoder().encode(DeBruijnProgram(version: program.version, term: term))
        let compiled = Self.cborBytes(flat).hex
        let script = try TransactionComposer.plutusScript(version: validator.plutusVersion, hex: compiled)
        return AppliedValidator(
            compiledCode: compiled, hash: try scriptHash(script: script).payload.hex, plutusVersion: validator.plutusVersion
        )
    }

    /// `bytes` as one definite CBOR byte string, as `compiledCode` wraps a script.
    static func cborBytes(_ bytes: Data) -> Data {
        let count = bytes.count
        var header: [UInt8]
        switch count {
        case 0..<24: header = [0x40 | UInt8(count)]
        case 24..<0x100: header = [0x58, UInt8(count)]
        case 0x100..<0x10000: header = [0x59, UInt8(count >> 8), UInt8(count & 0xFF)]
        default: header = [0x5a, UInt8(count >> 24 & 0xFF), UInt8(count >> 16 & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)]
        }
        return Data(header) + bytes
    }

    /// A parameter's path: `parameters.owner`, or by position when untitled.
    static func parameterPath(_ parameter: Argument, _ index: Int) -> String {
        "parameters.\(parameter.title ?? "\(index)")"
    }

    /// `value` as a UPLC constant of `schema`'s type.
    func constant(_ value: BlueprintValue, as schema: BlueprintSchema, path: String) throws -> UPLCConstant {
        let resolved = try resolve(schema)
        func invalid(_ message: String) -> BlueprintError { .invalid([BlueprintProblem(path: path, message: message)]) }
        guard case .builtin(let builtin) = resolved.kind else {
            return .data(try encode(value, as: schema, path: path))
        }
        switch (builtin, value) {
        case (.integer, .integer(let text)):
            guard let integer = Self.integer(text) else { throw invalid(text.isEmpty ? "Enter a whole number." : "\"\(text)\" is not a whole number.") }
            return .integer(integer)
        case (.bytes, .bytes(let text)):
            guard let bytes = Self.bytes(text) else { throw invalid("Bytes are written in hex: two digits 0–9, a–f a byte.") }
            return .byteString(bytes)
        case (.string, .text(let text)):
            return .string(text)
        case (.unit, _):
            return .unit
        case (.boolean, .boolean(let flag)):
            return .bool(flag)
        case (.pair(let left, let right), .pair(let first, let second)):
            return .pair(
                try type(of: left), try type(of: right),
                try constant(first, as: left, path: "\(path)[0]"), try constant(second, as: right, path: "\(path)[1]")
            )
        case (.list(let items), .list(let elements)):
            return .list(try type(of: items), try elements.enumerated().map { try constant($1, as: items, path: "\(path)[\($0)]") })
        default:
            throw invalid("This value does not fit the parameter's type.")
        }
    }

    /// The UPLC type a schema's values take as constants.
    private func type(of schema: BlueprintSchema) throws -> UPLCType {
        guard case .builtin(let builtin) = try resolve(schema).kind else { return .data }
        switch builtin {
        case .integer: return .integer
        case .bytes: return .byteString
        case .string: return .string
        case .unit: return .unit
        case .boolean: return .bool
        case .pair(let left, let right): return .pair(try type(of: left), try type(of: right))
        case .list(let items): return .list(try type(of: items))
        }
    }
}
