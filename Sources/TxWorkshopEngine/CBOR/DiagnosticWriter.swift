import Foundation
import SwiftCDDL

/// Writes CBOR as diagnostic notation (RFC 8949 Section 8, with the encoding
/// indicators of RFC 8610 Appendix G): `_` for indefinite length, `_1`–`_3`
/// for a float not in its preferred width. What the bytes did not complete
/// is written as `…`.
struct DiagnosticWriter {
    let entries: [CBORExploration.Entry]
    let limit: Int
    private var out = ""
    private var truncated = false

    init(entries: [CBORExploration.Entry], limit: Int) {
        self.entries = entries
        self.limit = limit
    }

    mutating func finish() -> String {
        truncated ? out + "\n…" : out
    }

    private mutating func emit(_ text: String) {
        guard !truncated else { return }
        if out.utf8.count + text.utf8.count > limit {
            truncated = true
        } else {
            out += text
        }
    }

    mutating func write(_ index: Int, indent: Int) {
        guard !truncated else { return }
        let entry = entries[index]
        // Indentation stops growing past 64 levels, so deep data stays linear.
        let pad = String(repeating: "  ", count: min(indent + 1, 64))
        let closing = String(repeating: "  ", count: min(indent, 64))
        let indefinite = entry.flags.contains(.indefiniteLength) ? "_ " : ""
        let children = entry.children
        switch entry.kind {
        case .array:
            guard !children.isEmpty else { emit("[\(indefinite)\(entry.isComplete ? "" : "…")]"); return }
            emit("[\(indefinite)\n")
            for (position, child) in children.enumerated() {
                emit(pad)
                write(child, indent: indent + 1)
                emit(position == children.count - 1 ? "" : ",\n")
            }
            emit("\(entry.isComplete ? "" : ",\n\(pad)…")\n\(closing)]")
        case .map:
            guard !children.isEmpty else { emit("{\(indefinite)\(entry.isComplete ? "" : "…")}"); return }
            emit("{\(indefinite)\n")
            var position = 0
            while position < children.count {
                emit(pad)
                write(children[position], indent: indent + 1)
                emit(": ")
                if position + 1 < children.count {
                    write(children[position + 1], indent: indent + 1)
                } else {
                    emit("…")
                }
                position += 2
                emit(position < children.count ? ",\n" : "")
            }
            emit("\(entry.isComplete ? "" : ",\n\(pad)…")\n\(closing)}")
        case .tag(let tag):
            emit("\(tag)(")
            if let content = children.first {
                write(content, indent: indent)
            } else {
                emit("…")
            }
            emit(")")
        case .bytes, .text:
            if !children.isEmpty || entry.flags.contains(.indefiniteLength) {
                emit("(_ ")
                for (position, chunk) in children.enumerated() {
                    write(chunk, indent: indent)
                    emit(position == children.count - 1 ? "" : ", ")
                }
                emit("\(entry.isComplete ? "" : "…"))")
            } else {
                emit(entry.scalar ?? "…")
            }
        default:
            emit(entry.scalar ?? "…")
        }
    }

    /// A scalar's notation, or `nil` for a container or an incomplete item.
    static func scalar(_ item: CBORAnnotatedItem) -> String? {
        switch item.node {
        case .unsigned(let value)?: return String(value)
        case .negative(let n)?: return String(-1 - Int128(n))
        case .byteString(let data, false)?: return "h'\(data.map { String(format: "%02x", $0) }.joined())'"
        case .textString(let text, false)?: return quoted(text)
        case .float(let value, let width)?:
            let text = value.isNaN ? "NaN" : value.isInfinite ? (value < 0 ? "-Infinity" : "Infinity") : "\(value)"
            guard item.flags.contains(.nonPreferredFloat) else { return text }
            switch width {
            case .half: return text + "_1"
            case .single: return text + "_2"
            case .double: return text + "_3"
            }
        case .simple(let value)?: return "simple(\(value))"
        case .bool(let value)?: return value ? "true" : "false"
        case .null?: return "null"
        case .undefined?: return "undefined"
        default: return nil
        }
    }

    /// A one-line form for labels and previews: scalars in full up to 64
    /// characters, containers by kind.
    static func short(_ entry: CBORExploration.Entry) -> String {
        if let text = entry.scalar {
            return text.count > 64 ? String(text.prefix(30)) + "…" + String(text.suffix(30)) : text
        }
        switch entry.kind {
        case .array: return "[…]"
        case .map: return "{…}"
        case .tag(let tag): return "\(tag)(…)"
        case .bytes: return "(_ h'…')"
        case .text: return "(_ \"…\")"
        default: return "…"
        }
    }

    static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// The head's argument: the tag number, length or value it encodes.
    static func argument(_ bytes: [UInt8], _ span: CBORByteSpan) -> UInt64? {
        guard bytes.indices.contains(span.start) else { return nil }
        let info = bytes[span.start] & 0x1f
        if info < 24 { return UInt64(info) }
        let width = [24: 1, 25: 2, 26: 4, 27: 8][Int(info)]
        guard let width, span.start + width < bytes.count else { return nil }
        return bytes[(span.start + 1)...(span.start + width)].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
