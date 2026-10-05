import Foundation
import SwiftCardanoCore
import SwiftCardanoUPLC

/// Prints a UPLC term only as far as a limit, so a debugger can show any term
/// (a whole script, a closure over the script context) in time proportional
/// to what it shows, not to the term's size.
struct BoundedTermPrinter {
    let limit: Int
    /// Indented, one construct a line; otherwise all on one line.
    let multiline: Bool
    private var output = ""
    private var written = 0
    private var truncated = false

    init(limit: Int, multiline: Bool) {
        self.limit = limit
        self.multiline = multiline
    }

    static func text(_ term: Term<NamedDeBruijn>, limit: Int, multiline: Bool) -> String {
        var printer = BoundedTermPrinter(limit: limit, multiline: multiline)
        printer.print(term, indent: 0)
        return printer.truncated ? printer.output + " …" : printer.output
    }

    private var full: Bool { truncated || written >= limit }

    private mutating func emit(_ text: String) {
        guard !full else {
            truncated = true
            return
        }
        let room = limit - written
        let count = text.count
        if count > room {
            output += text.prefix(room)
            written = limit
            truncated = true
        } else {
            output += text
            written += count
        }
    }

    private mutating func open(_ text: String, indent: Int) {
        if multiline, written > 0 { emit("\n" + String(repeating: "  ", count: indent)) } else if written > 0 { emit(" ") }
        emit(text)
    }

    private mutating func print(_ term: Term<NamedDeBruijn>, indent: Int) {
        guard !full else {
            truncated = true
            return
        }
        switch term {
        case .var(let name):
            open(Self.name(name), indent: indent)
        case .lambda(let name, let body):
            open("(lam \(Self.name(name))", indent: indent)
            print(body, indent: indent + 1)
            emit(")")
        case .apply(let function, let argument):
            open("[", indent: indent)
            print(function, indent: indent + 1)
            print(argument, indent: indent + 1)
            emit("]")
        case .delay(let body):
            open("(delay", indent: indent)
            print(body, indent: indent + 1)
            emit(")")
        case .force(let body):
            open("(force", indent: indent)
            print(body, indent: indent + 1)
            emit(")")
        case .constant(let constant):
            open("(con \(Self.constant(constant)))", indent: indent)
        case .builtin(let function):
            open("(builtin \(function))", indent: indent)
        case .error:
            open("(error)", indent: indent)
        case .constr(let tag, let fields):
            open("(constr \(tag)", indent: indent)
            for field in fields where !full { print(field, indent: indent + 1) }
            emit(")")
        case .case(let scrutinee, let branches):
            open("(case", indent: indent)
            print(scrutinee, indent: indent + 1)
            for branch in branches where !full { print(branch, indent: indent + 1) }
            emit(")")
        }
    }

    static func name(_ name: NamedDeBruijn) -> String {
        name.text.isEmpty ? "i\(name.index.index)" : "\(name.text)_\(name.index.index)"
    }

    /// A constant, with data shown by its shape rather than in full.
    static func constant(_ constant: UPLCConstant) -> String {
        switch constant {
        case .data(let data): return "data \(DataNode.shape(data))"
        case .byteString(let bytes): return "bytestring #" + (bytes.count > 32 ? bytes.prefix(32).hex + "…" : bytes.hex)
        case .string(let text): return "string \"" + (text.count > 64 ? text.prefix(64) + "…" : text) + "\""
        default:
            let printed = PrettyPrinter().printConstant(constant)
            return printed.count > 120 ? String(printed.prefix(120)) + "…" : printed
        }
    }
}

extension DataNode {
    /// One line naming a piece of data's shape: `constr 0 · 3 fields`.
    static func shape(_ data: PlutusData) -> String {
        switch data {
        case .constructor(let constr): "constr \(constr.tag ?? 0) · \(constr.fields.count) fields"
        case .map(let pairs): "map · \(pairs.count)"
        case .array(let items): "list · \(items.count)"
        case .indefiniteArray(let items): "list · \(items.getAll().count)"
        case .bigInt(let integer): "\(integer.value)"
        case .bytes(let bytes): bytes.data.count > 32 ? "#" + bytes.data.prefix(32).hex + "…" : "#" + bytes.data.hex
        }
    }
}
