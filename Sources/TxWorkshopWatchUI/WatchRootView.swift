import SwiftUI
import TxWorkshopCore

/// The watch companion's root: transactions submitted from the phone and
/// their confirmations. Filled in with submission tracking (Phase 6).
public struct WatchRootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("No Submissions", bundle: #bundle)
                } icon: {
                    Image(systemName: "shippingbox")
                }
            } description: {
                Text("Transactions you submit from your iPhone appear here until they confirm.", bundle: #bundle)
            }
            .navigationTitle(Text("Tx Workshop", bundle: #bundle))
        }
    }
}

#Preview {
    WatchRootView()
}
