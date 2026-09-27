import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The bytes, sixteen to a row (eight on a phone), with the selected item's
/// head and payload highlighted. Tapping a byte selects the item it belongs
/// to.
struct HexView: View {
    let bytes: Data
    let selection: CBORItem?
    /// Where decoding stopped, when it did.
    let problemOffset: Int?
    var markers: CBORMarkers = .none
    let onSelectByte: (Int) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bytesPerRow: Int { sizeClass == .compact ? 8 : 16 }
    private var rowCount: Int { (bytes.count + bytesPerRow - 1) / bytesPerRow }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HexRow(
                            bytes: bytes, row: row, bytesPerRow: bytesPerRow, selection: selection,
                            problemOffset: problemOffset, markers: markers, onSelectByte: onSelectByte
                        )
                        .id(row)
                    }
                }
                .padding(TWSpacing.s)
            }
            .onChange(of: selection?.start, initial: true) { _, start in
                guard let start else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(start / bytesPerRow, anchor: .center) }
            }
        }
        .font(TWFont.bytesSmall)
    }
}

private struct HexRow: View {
    let bytes: Data
    let row: Int
    let bytesPerRow: Int
    let selection: CBORItem?
    let problemOffset: Int?
    let markers: CBORMarkers
    let onSelectByte: (Int) -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    private var offsets: Range<Int> {
        let start = row * bytesPerRow
        return start..<min(start + bytesPerRow, bytes.count)
    }

    /// What a byte is part of, for the highlight and for VoiceOver.
    private enum Role { case plain, problem, header, payload, key, error, warning }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: String(format: "%06x", offsets.lowerBound))
                .foregroundStyle(TWColor.secondaryText)
                .padding(.trailing, TWSpacing.m)
            ForEach(offsets, id: \.self) { offset in
                let role = role(offset)
                let hex = String(format: "%02x", bytes[bytes.startIndex + offset])
                Text(verbatim: hex)
                    .fontWeight(withoutColor && role == .header ? .bold : nil)
                    .underline(withoutColor && role != .plain && role != .header)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    #if os(iOS) || os(visionOS)
                    .frame(minWidth: 36, minHeight: 36)
                    #endif
                    .background(background(role), in: .rect(cornerRadius: 2))
                    .overlay {
                        if withoutColor && role == .problem {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(TWColor.failure, lineWidth: 1.5)
                        }
                    }
                    // The whole cell, padding included, takes the tap.
                    .contentShape(.rect)
                    #if os(visionOS)
                    .hoverEffect()
                    #endif
                    .onTapGesture { onSelectByte(offset) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(offset: offset, hex: hex, role: role))
                    .accessibilityAddTraits(role == .header || role == .payload ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onSelectByte(offset) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func role(_ offset: Int) -> Role {
        if offset == problemOffset { return .problem }
        if let selection {
            if selection.headerRange.contains(offset) { return .header }
            if selection.range.contains(offset) { return .payload }
            if selection.keyRange?.contains(offset) == true { return .key }
        }
        // The innermost marked item holding the byte decides its colour.
        if let marked = markers.ranges.filter({ $0.range.contains(offset) }).min(by: { $0.range.count < $1.range.count }) {
            return marked.isError ? .error : .warning
        }
        return .plain
    }

    private func background(_ role: Role) -> Color {
        switch role {
        case .plain: .clear
        case .problem: TWColor.failure.opacity(0.5)
        case .header: Color.accentColor.opacity(0.45)
        case .payload: Color.accentColor.opacity(0.18)
        case .key: TWColor.warning.opacity(0.3)
        case .error: TWColor.failure.opacity(0.22)
        case .warning: TWColor.warning.opacity(0.22)
        }
    }

    private func accessibilityLabel(offset: Int, hex: String, role: Role) -> Text {
        switch role {
        case .plain: Text("Offset \(offset): \(hex)", bundle: #bundle)
        case .problem: Text("Offset \(offset): \(hex), decoding stopped here", bundle: #bundle)
        case .header: Text("Offset \(offset): \(hex), selected item's head", bundle: #bundle)
        case .payload: Text("Offset \(offset): \(hex), selected item", bundle: #bundle)
        case .key: Text("Offset \(offset): \(hex), selected item's map key", bundle: #bundle)
        case .error: Text("Offset \(offset): \(hex), in an item with a validation error", bundle: #bundle)
        case .warning: Text("Offset \(offset): \(hex), in an item with a validation warning", bundle: #bundle)
        }
    }
}
