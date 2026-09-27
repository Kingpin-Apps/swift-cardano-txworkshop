import SwiftUI

/// The Tx Workshop design system: dense and developer-tool-like, monospaced
/// where the data is bytes or hashes. Liquid Glass belongs to window chrome
/// only, never to rows of data.
public enum TWSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum TWFont {
    /// Hashes, hex and CBOR.
    public static let bytes = Font.system(.body, design: .monospaced)
    public static let bytesSmall = Font.system(.caption, design: .monospaced)
    /// Figures such as lovelace amounts, aligned in columns.
    public static let figure = Font.body.monospacedDigit()
    public static let sectionTitle = Font.headline
}

/// Semantic colours. System colours adapt to light, dark and increased
/// contrast on every platform.
public enum TWColor {
    public static let success = Color.green
    public static let warning = Color.orange
    public static let failure = Color.red
    public static let secondaryText = Color.secondary
}

/// A label whose icon carries the status colour. The text stays in the
/// primary colour: green, orange and red text fail contrast on the system
/// backgrounds.
public struct TWStatusLabelStyle: LabelStyle {
    let color: Color

    public func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            configuration.icon.foregroundStyle(color)
        }
    }
}

extension LabelStyle where Self == TWStatusLabelStyle {
    /// Colours only the icon.
    public static func status(_ color: Color) -> TWStatusLabelStyle { TWStatusLabelStyle(color: color) }
}

/// An error message, with a red icon so it does not rely on colour alone.
public struct TWErrorText: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        let label = Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .labelStyle(.status(TWColor.failure))
        #if os(watchOS)
        label
        #else
        label.textSelection(.enabled)
        #endif
    }
}

/// A hash, id or hex string: monospaced, middle-truncated, selectable.
/// At accessibility text sizes it wraps instead of truncating.
public struct TWBytesText: View {
    private let value: String
    private let font: Font
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ value: String, font: Font = TWFont.bytes) {
        self.value = value
        self.font = font
    }

    public var body: some View {
        let text = Text(verbatim: value)
            .font(font)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .truncationMode(.middle)
        #if os(watchOS)
        text
        #else
        text.textSelection(.enabled)
        #endif
    }
}

/// A label and value on one row, the value monospaced when it is bytes.
public struct TWFieldRow<Value: View>: View {
    private let title: LocalizedStringResource
    private let value: Value

    public init(_ title: LocalizedStringResource, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    public var body: some View {
        LabeledContent {
            value
        } label: {
            Text(title)
                .foregroundStyle(TWColor.secondaryText)
        }
    }
}

extension View {
    /// Grows a small control to the 44-point touch target on touch
    /// platforms; the pointer platforms keep their dense layout.
    public func twHitTarget() -> some View {
        #if os(iOS) || os(visionOS)
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
        self
        #endif
    }
}
