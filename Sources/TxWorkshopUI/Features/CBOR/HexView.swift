import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The bytes, sixteen to a row, with the selected item's head and payload
/// highlighted. Tapping a byte selects the item it belongs to.
struct HexView: View {
    let bytes: Data
    let selection: CBORItem?
    /// Where decoding stopped, when it did.
    let problemOffset: Int?
    let onSelectByte: (Int) -> Void

    static let bytesPerRow = 16

    private var rowCount: Int { (bytes.count + Self.bytesPerRow - 1) / Self.bytesPerRow }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HexRow(
                            bytes: bytes, row: row, selection: selection,
                            problemOffset: problemOffset, onSelectByte: onSelectByte
                        )
                        .id(row)
                    }
                }
                .padding(TWSpacing.s)
            }
            .onChange(of: selection?.start, initial: true) { _, start in
                guard let start else { return }
                withAnimation { proxy.scrollTo(start / Self.bytesPerRow, anchor: .center) }
            }
        }
        .font(TWFont.bytesSmall)
    }
}

private struct HexRow: View {
    let bytes: Data
    let row: Int
    let selection: CBORItem?
    let problemOffset: Int?
    let onSelectByte: (Int) -> Void

    private var offsets: Range<Int> {
        let start = row * HexView.bytesPerRow
        return start..<min(start + HexView.bytesPerRow, bytes.count)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: String(format: "%06x", offsets.lowerBound))
                .foregroundStyle(TWColor.secondaryText)
                .padding(.trailing, TWSpacing.m)
            ForEach(offsets, id: \.self) { offset in
                Text(verbatim: String(format: "%02x", bytes[bytes.startIndex + offset]))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(background(offset), in: .rect(cornerRadius: 2))
                    // The whole cell, padding included, takes the tap.
                    .contentShape(.rect)
                    .onTapGesture { onSelectByte(offset) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Offset \(offsets.lowerBound): \(offsets.map { String(format: "%02x", bytes[bytes.startIndex + $0]) }.joined(separator: " "))", bundle: #bundle))
        .accessibilityAction(named: Text("Select", bundle: #bundle)) { onSelectByte(offsets.lowerBound) }
    }

    private func background(_ offset: Int) -> Color {
        if offset == problemOffset { return TWColor.failure.opacity(0.5) }
        guard let selection else { return .clear }
        if selection.headerRange.contains(offset) { return Color.accentColor.opacity(0.45) }
        if selection.range.contains(offset) { return Color.accentColor.opacity(0.18) }
        if selection.keyRange?.contains(offset) == true { return TWColor.warning.opacity(0.3) }
        return .clear
    }
}
