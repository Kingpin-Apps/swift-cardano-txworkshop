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

    /// How deep indentation goes; deeper code is printed at this depth.
    static let maxIndent = 10

    private mutating func open(_ text: String, indent: Int, inline: Bool = false) {
        if multiline, written > 0, !inline {
            emit("\n" + String(repeating: "  ", count: min(indent, Self.maxIndent)))
        } else if written > 0 {
            emit(" ")
        }
        emit(text)
    }

    private mutating func print(_ term: Term<NamedDeBruijn>, indent: Int, inline: Bool = false) {
        guard !full else {
            truncated = true
            return
        }
        switch term {
        case .var(let name):
            open(Self.name(name), indent: indent, inline: inline)
        case .lambda(_, let body):
            // A chain of lambdas stays on one line: (lam (lam (lam …
            open("(lam", indent: indent, inline: inline)
            if case .lambda = body { print(body, indent: indent, inline: true) } else { print(body, indent: indent + 1) }
            emit(")")
        case .apply(let function, let argument):
            // The function follows the bracket; a short argument stays beside it.
            open("[", indent: indent, inline: inline)
            print(function, indent: indent + 1, inline: true)
            print(argument, indent: indent + 1, inline: Self.isAtom(argument))
            emit("]")
        case .delay(let body):
            open("(delay", indent: indent, inline: inline)
            print(body, indent: indent + 1, inline: true)
            emit(")")
        case .force(let body):
            open("(force", indent: indent, inline: inline)
            print(body, indent: indent + 1, inline: true)
            emit(")")
        case .constant(let constant):
            open("(con \(Self.constant(constant)))", indent: indent, inline: inline)
        case .builtin(let function):
            open("(builtin \(function))", indent: indent, inline: inline)
        case .error:
            open("(error)", indent: indent, inline: inline)
        case .constr(let tag, let fields):
            open("(constr \(tag)", indent: indent, inline: inline)
            for field in fields where !full { print(field, indent: indent + 1, inline: Self.isAtom(field)) }
            emit(")")
        case .case(let scrutinee, let branches):
            open("(case", indent: indent, inline: inline)
            print(scrutinee, indent: indent + 1)
            for branch in branches where !full { print(branch, indent: indent + 1) }
            emit(")")
        }
    }

    /// A term short enough to print beside what holds it.
    static func isAtom(_ term: Term<NamedDeBruijn>) -> Bool {
        switch term {
        case .var, .builtin, .error: true
        case .constant(.data), .constant(.list), .constant(.pair): false
        case .constant: true
        default: false
        }
    }

    /// A variable by its De Bruijn index, as the debugger's variables list
    /// numbers them: `#1` is the nearest binding.
    static func name(_ name: NamedDeBruijn) -> String {
        "#\(name.index.index)"
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
