import SwiftUI
import TxWorkshopCore

/// Schema text with line numbers, scrolled to and highlighting a range of
/// lines.
struct SourceLinesView: View {
    let text: String
    /// 1-based lines to highlight.
    let highlight: ClosedRange<Int>?
    let problemLine: Int?

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        let lines = lines
        let width = String(lines.count).count
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        let number = index + 1
                        HStack(alignment: .firstTextBaseline, spacing: TWSpacing.m) {
                            Text(verbatim: String(number).leftPadded(to: width))
                                .foregroundStyle(TWColor.secondaryText)
                            Text(verbatim: String(lines[index]))
                                .textSelection(.enabled)
                        }
                        .font(TWFont.bytesSmall)
                        .padding(.horizontal, TWSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(number))
                        .id(number)
                    }
                }
                .padding(.vertical, TWSpacing.s)
            }
            .onChange(of: highlight?.lowerBound, initial: true) { _, line in
                guard let line else { return }
                withAnimation { proxy.scrollTo(line, anchor: .top) }
            }
            .onChange(of: problemLine, initial: true) { _, line in
                guard let line, highlight == nil else { return }
                proxy.scrollTo(line, anchor: .center)
            }
        }
    }

    private func background(_ line: Int) -> Color {
        if line == problemLine { return TWColor.failure.opacity(0.18) }
        if highlight?.contains(line) == true { return Color.accentColor.opacity(0.15) }
        return .clear
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }
}
