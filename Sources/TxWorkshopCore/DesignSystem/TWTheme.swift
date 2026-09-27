import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The Tx Workshop design system, "Workbench": dense and developer-tool-like,
/// monospaced where the data is bytes or hashes, on warm paper and charcoal
/// neutrals with one amber accent. Serif is kept for document titles. Liquid
/// Glass belongs to window chrome only, never to rows of data.
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
    /// A document's title: the one serif on a screen.
    public static let displayTitle = Font.system(.title2, design: .serif).weight(.semibold)
}

/// Semantic colours, each with light, dark and increased-contrast variants.
/// Status colours are the system's; the rest come from the Workbench palette
/// in `Colors.xcassets`.
public enum TWColor {
    public static let success = Color.green
    public static let warning = Color.orange
    public static let failure = Color.red
    /// Amber: selection, links, primary actions and highlighted bytes.
    public static let accent = Color("TWAccent", bundle: .module)
    /// Warm paper in light, charcoal in dark, behind every screen.
    public static let background = Color("TWBackground", bundle: .module)
    /// Panels and cards drawn on the background.
    public static let surface = Color("TWSurface", bundle: .module)
    /// The system's, so it turns white on a selected row.
    public static let secondaryText = Color.secondary
    public static let divider = Color("TWDivider", bundle: .module)
}

/// The app's appearance: the system's, or always light or dark.
public enum TWAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let storageKey = "appearance"

    public var id: Self { self }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var title: LocalizedStringResource {
        switch self {
        case .system: LocalizedStringResource("System", bundle: #bundle)
        case .light: LocalizedStringResource("Light", bundle: #bundle)
        case .dark: LocalizedStringResource("Dark", bundle: #bundle)
        }
    }
}

extension View {
    /// Applies the chosen appearance, the accent and the Workbench
    /// background. Use once at the root of each window.
    public func twWindowStyle() -> some View {
        modifier(TWWindowStyle())
    }

    /// For the root of a sheet's navigation stack: on iPhone and iPad the
    /// document window's back-to-browser button otherwise shows in the sheet.
    public func twSheetRoot() -> some View {
        navigationBarBackButtonHidden()
    }

    /// Puts a screen's lists and forms on the Workbench background. On iOS
    /// it is the navigation container's background, so titles still track
    /// the scroll view; visionOS keeps its glass.
    public func twScreenBackground() -> some View {
        #if os(macOS)
        scrollContentBackground(.hidden)
            .background(TWColor.background)
        #elseif os(iOS)
        scrollContentBackground(.hidden)
            .containerBackground(TWColor.background, for: .navigation)
        #else
        // visionOS windows are glass; an opaque background would hide it.
        self
        #endif
    }
}

private struct TWWindowStyle: ViewModifier {
    @AppStorage(TWAppearance.storageKey) private var appearance = TWAppearance.system

    func body(content: Content) -> some View {
        #if os(macOS)
        // On macOS, clearing `preferredColorScheme` does not return a window to
        // the system appearance, so the app's appearance is set directly.
        content
            .tint(TWColor.accent)
            .onChange(of: appearance, initial: true) { _, appearance in
                NSApplication.shared.appearance = switch appearance {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
        #elseif os(iOS)
        // On iOS, `preferredColorScheme` from a sheet reaches only the sheet,
        // so every window's style is set directly.
        content
            .tint(TWColor.accent)
            .onChange(of: appearance, initial: true) { _, appearance in
                let style: UIUserInterfaceStyle = switch appearance {
                case .system: .unspecified
                case .light: .light
                case .dark: .dark
                }
                for scene in UIApplication.shared.connectedScenes {
                    for window in (scene as? UIWindowScene)?.windows ?? [] {
                        window.overrideUserInterfaceStyle = style
                    }
                }
            }
        #else
        content
            .tint(TWColor.accent)
            .preferredColorScheme(appearance.colorScheme)
        #endif
    }
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
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .labelStyle(.status(TWColor.failure))
        .textSelection(.enabled)
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
        text.textSelection(.enabled)
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
