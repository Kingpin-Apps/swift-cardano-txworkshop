import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A file to share: its bytes and its name, extension included.
protocol ShareableFile: Transferable {
    var data: Data { get }
    var fileName: String { get }
}

/// A share asked for from a menu, waiting for the menu's button to show it.
struct PendingShare: Equatable, Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
}

/// A menu item that shares `file`. A `ShareLink` in a menu loses its anchor
/// when the menu closes, so the share sheet opens at the window's edge on a
/// Mac, and points at nothing on an iPad. Here the item only sets `pending`,
/// and the menu's own button, given `.sharePicker(_:)`, shows the share
/// sheet pointing at itself.
struct ShareFileItem<File: ShareableFile, ItemLabel: View>: View {
    let file: File
    @Binding var pending: PendingShare?
    @ViewBuilder let label: () -> ItemLabel

    var body: some View {
        Button {
            pending = PendingShare(data: file.data, fileName: file.fileName)
        } label: {
            label()
        }
    }
}

extension View {
    /// Shows the share sheet for `pending` anchored to this view, then
    /// clears it. Apply it to the menu that holds the `ShareFileItem`.
    ///
    /// In a toolbar on iPhone and iPad the menu is drawn by the toolbar
    /// itself, outside this view: there `barItemTitle`, the menu's title,
    /// finds the toolbar's button to point at.
    func sharePicker(_ pending: Binding<PendingShare?>, barItemTitle: String? = nil) -> some View {
        background(SharePickerAnchor(pending: pending, barItemTitle: barItemTitle))
    }
}

#if os(macOS)
/// An empty view behind the menu's button that the share picker points at.
private struct SharePickerAnchor: NSViewRepresentable {
    @Binding var pending: PendingShare?
    let barItemTitle: String?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let share = pending else { return }
        // After the menu has finished closing, so the picker is not
        // dismissed along with it.
        Task { @MainActor in
            pending = nil
            guard view.window != nil,
                  let url = try? TransferredFileDraft.write(share.data, named: share.fileName)
            else { return }
            NSSharingServicePicker(items: [url])
                .show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}
#else
/// An empty view behind the menu's button that the share sheet's popover
/// points at. On an iPhone the sheet rises from the bottom as usual.
private struct SharePickerAnchor: UIViewRepresentable {
    @Binding var pending: PendingShare?
    let barItemTitle: String?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let share = pending else { return }
        Task { @MainActor in
            pending = nil
            // The menu is still closing: presenting over it fails.
            try? await Task.sleep(for: .milliseconds(350))
            guard let window = view.window ?? Self.keyWindow,
                  let url = try? TransferredFileDraft.write(share.data, named: share.fileName)
            else { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = sheet.popoverPresentationController {
                // This view; or the toolbar's button it sits behind; or as a
                // last resort the top of the window, where toolbars are.
                if view.window != nil {
                    popover.sourceView = view
                    popover.sourceRect = view.bounds
                } else if let barItemTitle, let item = Self.barItem(titled: barItemTitle, from: window.rootViewController) {
                    popover.sourceItem = item
                } else {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.safeAreaInsets.top, width: 1, height: 1)
                }
            }
            var top = window.rootViewController
            while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
            top?.present(sheet, animated: true)
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// The bar button item titled `title` in any navigation bar or toolbar
    /// of `controller` or the controllers it holds or presents.
    private static func barItem(titled title: String, from controller: UIViewController?) -> UIBarButtonItem? {
        guard let controller else { return nil }
        let navigation = controller.navigationItem
        let groups = navigation.leadingItemGroups + navigation.centerItemGroups + navigation.trailingItemGroups
        let items = (navigation.leftBarButtonItems ?? []) + (navigation.rightBarButtonItems ?? [])
            + groups.flatMap { $0.barButtonItems + ($0.representativeItem.map { [$0] } ?? []) }
            + (controller.toolbarItems ?? [])
        if let item = items.first(where: { $0.title == title }) { return item }
        for child in controller.children + [controller.presentedViewController].compactMap({ $0 }) {
            if let item = barItem(titled: title, from: child) { return item }
        }
        return nil
    }
}
#endif
