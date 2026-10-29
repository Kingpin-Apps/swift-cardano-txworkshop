import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// Where the build form asks the chain about what is being entered: the
/// provider, when Build may use it, and the document's chain snapshot.
struct BuildChainSource: Equatable {
    var provider: ProviderConfiguration?
    var snapshot: ChainContextSnapshot?
}

extension EnvironmentValues {
    @Entry var buildChainSource = BuildChainSource()
}

/// What the ledger holds for a stake address, looked up as it is entered:
/// whether it is registered, its rewards and its delegations. The provider is
/// asked when there is one; otherwise the chain snapshot, when it has the
/// address.
struct StakeAccountStatus: View {
    let stakeAddress: String
    /// What the form needs the address to be, to warn when it is not.
    var expects: Expectation = .none
    /// Called with each account found.
    var onAccount: (ChainLookup.Account) -> Void = { _ in }
    @Environment(\.buildChainSource) private var source
    @Environment(\.documentNetwork) private var network
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var lookup: LoadState<ChainLookup.Account> = .idle

    enum Expectation {
        case none
        /// Registered, for delegating, withdrawing or a deposit returned to it.
        case registered
        /// Not yet registered, for registering it.
        case unregistered
    }

    private struct Key: Equatable {
        let address: String
        let network: CardanoNetwork?
        let source: BuildChainSource
    }

    var body: some View {
        Group {
            switch lookup {
            case .idle:
                EmptyView()
            case .loading:
                Label {
                    Text("Looking up the stake address…", bundle: #bundle)
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(TWColor.secondaryText)
            case .failed(let message):
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .foregroundStyle(TWColor.secondaryText)
            case .loaded(let account):
                summary(account)
                warning(account)
            }
        }
        .font(.caption)
        .task(id: Key(address: stakeAddress, network: network, source: source)) { await look() }
    }

    @ViewBuilder private func summary(_ account: ChainLookup.Account) -> some View {
        if account.isRegistered {
            Label {
                VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                    Text("Registered · \(TWFormat.ada(account.rewards)) in rewards", bundle: #bundle)
                    if let pool = account.pool {
                        Text("Delegates stake to \(pool)", bundle: #bundle).lineLimit(1).truncationMode(.middle)
                    }
                    if let drep = account.drep {
                        Text("Delegates votes to \(drep)", bundle: #bundle).lineLimit(1).truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .labelStyle(.status(TWColor.success))
        } else {
            Label {
                Text("Not registered", bundle: #bundle)
            } icon: {
                Image(systemName: "circle.dashed")
            }
            .foregroundStyle(TWColor.secondaryText)
        }
    }

    @ViewBuilder private func warning(_ account: ChainLookup.Account) -> some View {
        switch expects {
        case .registered where !account.isRegistered:
            Label {
                Text("The ledger refuses this for a stake address that is not registered. Register it first, in this transaction or an earlier one.", bundle: #bundle)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .labelStyle(.status(TWColor.warning))
        case .unregistered where account.isRegistered:
            Label {
                Text("Already registered: the ledger refuses registering it again.", bundle: #bundle)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .labelStyle(.status(TWColor.warning))
        default:
            EmptyView()
        }
    }

    private func look() async {
        guard let address = try? ChainLookup.stakeAddress(stakeAddress, network: network) else {
            lookup = .idle
            return
        }
        if let provider = source.provider {
            lookup = .loading
            // Waits for typing to stop before asking the provider.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let account = try await ChainLookup().account(address, network: network, provider: provider, apiKey: providers.apiKey(for: provider))
                guard !Task.isCancelled else { return }
                lookup = .loaded(account)
                onAccount(account)
            } catch {
                guard !Task.isCancelled else { return }
                lookup = .failed(String(describing: error))
            }
        } else if let account = ChainLookup.account(address, network: network, snapshot: source.snapshot) {
            lookup = .loaded(account)
            onAccount(account)
        } else {
            lookup = .idle
        }
    }
}

/// The epoch a pool retiring now may name, from the provider or the chain
/// snapshot. The epoch is filled in with the earliest one when it is empty.
/// When neither can say, it says why.
struct RetirementEpochHint: View {
    @Binding var epoch: UInt64?
    @Environment(\.buildChainSource) private var source
    @Environment(\.documentNetwork) private var network
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var lookup: LoadState<Found> = .idle

    struct Found: Equatable {
        let window: ChainLookup.RetirementWindow
        /// Why the provider was not used, when the snapshot answered instead.
        let providerProblem: String?
    }

    var body: some View {
        Group {
            switch lookup {
            case .idle:
                Label {
                    if network == nil {
                        Text("Set the network to fill in the next epoch.", bundle: #bundle)
                    } else {
                        Text("Fetch chain data, or let Build use a provider, to fill in the next epoch.", bundle: #bundle)
                    }
                } icon: {
                    Image(systemName: "info.circle")
                }
            case .loading:
                Label {
                    Text("Looking up the current epoch…", bundle: #bundle)
                } icon: {
                    ProgressView().controlSize(.small)
                }
            case .failed(let message):
                Label {
                    Text("The current epoch could not be looked up. \(message)", bundle: #bundle)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .labelStyle(.status(TWColor.warning))
            case .loaded(let found):
                VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline) {
                        if let latest = found.window.latest {
                            Text("Current epoch \(found.window.currentEpoch, format: .number.grouping(.never)): retire at \(found.window.earliest, format: .number.grouping(.never)) to \(latest, format: .number.grouping(.never)).", bundle: #bundle)
                        } else {
                            Text("Current epoch \(found.window.currentEpoch, format: .number.grouping(.never)): retire at \(found.window.earliest, format: .number.grouping(.never)) or later.", bundle: #bundle)
                        }
                        Spacer()
                        if epoch != found.window.earliest {
                            Button {
                                epoch = found.window.earliest
                            } label: {
                                Text("Use Next Epoch", bundle: #bundle)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if let problem = found.providerProblem {
                        Text("From the document's chain data: the provider could not answer. \(problem)", bundle: #bundle)
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(TWColor.secondaryText)
        .task(id: source) { await look() }
    }

    private func look() async {
        let saved = ChainLookup.retirementWindow(source.snapshot)
        var found = saved.map { Found(window: $0, providerProblem: nil) }
        if let provider = source.provider {
            if found == nil { lookup = .loading }
            do {
                let live = try await ChainLookup().retirementWindow(provider: provider, apiKey: providers.apiKey(for: provider))
                found = Found(window: live, providerProblem: nil)
            } catch {
                guard !Task.isCancelled else { return }
                guard let saved else {
                    lookup = .failed(String(describing: error))
                    return
                }
                found = Found(window: saved, providerProblem: String(describing: error))
            }
        }
        guard !Task.isCancelled else { return }
        guard let found else {
            lookup = .idle
            return
        }
        lookup = .loaded(found)
        if epoch == nil { epoch = found.window.earliest }
    }
}

/// What a governance action is and whether it can still be voted on, from
/// the provider.
struct GovernanceActionStatus: View {
    let action: String
    @Environment(\.buildChainSource) private var source
    @Environment(ProviderSettingsStore.self) private var providers
    @State private var lookup: LoadState<ChainLookup.GovernanceAction> = .idle

    private struct Key: Equatable {
        let action: String
        let provider: ProviderConfiguration?
    }

    var body: some View {
        Group {
            switch lookup {
            case .idle:
                EmptyView()
            case .loading:
                Label {
                    Text("Looking up the action…", bundle: #bundle)
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(TWColor.secondaryText)
            case .failed(let message):
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .foregroundStyle(TWColor.secondaryText)
            case .loaded(let found):
                if found.status == .open {
                    Label {
                        if let expiry = found.expiresAfter {
                            Text("\(found.kind) · open for votes until the end of epoch \(expiry, format: .number.grouping(.never))", bundle: #bundle)
                        } else {
                            Text("\(found.kind) · open for votes", bundle: #bundle)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal")
                    }
                    .labelStyle(.status(TWColor.success))
                } else {
                    Label {
                        Text("\(found.kind) · \(closed(found.status)): the ledger refuses votes on it.", bundle: #bundle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .labelStyle(.status(TWColor.warning))
                }
            }
        }
        .font(.caption)
        .task(id: Key(action: action, provider: source.provider)) { await look() }
    }

    private func closed(_ status: ChainLookup.GovernanceAction.Status) -> String {
        switch status {
        case .open: String(localized: "open", bundle: #bundle)
        case .ratified: String(localized: "ratified", bundle: #bundle)
        case .enacted: String(localized: "enacted", bundle: #bundle)
        case .dropped: String(localized: "dropped", bundle: #bundle)
        case .expired: String(localized: "expired", bundle: #bundle)
        }
    }

    private func look() async {
        guard let provider = source.provider, (try? ValueReader.read(.govActionID, text: action, network: nil)) != nil else {
            lookup = .idle
            return
        }
        lookup = .loading
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            let found = try await ChainLookup().governanceAction(action, provider: provider, apiKey: providers.apiKey(for: provider))
            guard !Task.isCancelled else { return }
            lookup = .loaded(found)
        } catch {
            guard !Task.isCancelled else { return }
            lookup = .failed(String(describing: error))
        }
    }
}

/// The governance actions open for votes, fetched when a voter asks to
/// choose one and kept for a few minutes, so choosing again does not ask the
/// provider again.
@MainActor
@Observable
final class OpenActionsCache {
    private(set) var state: LoadState<[ChainLookup.OpenAction]> = .idle
    @ObservationIgnored private var loaded: (provider: UUID, at: Date)?

    /// How long a list is kept before it is fetched again.
    static let lifetime: TimeInterval = 5 * 60

    func load(provider: ProviderConfiguration, apiKey: String?, force: Bool = false) async {
        guard !state.isLoading else { return }
        if !force, let loaded, loaded.provider == provider.id, Date.now.timeIntervalSince(loaded.at) < Self.lifetime, state.value != nil {
            return
        }
        state = .loading
        do {
            state = .loaded(try await ChainLookup().openGovernanceActions(provider: provider, apiKey: apiKey))
            loaded = (provider.id, .now)
        } catch {
            state = .failed(String(describing: error))
            loaded = nil
        }
    }
}

/// A list of the governance actions open for votes, to choose the one voted
/// on.
struct OpenActionPicker: View {
    let selected: String
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.buildChainSource) private var source
    @Environment(ProviderSettingsStore.self) private var providers
    @Environment(OpenActionsCache.self) private var cache

    var body: some View {
        NavigationStack {
            Form {
                switch cache.state {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .failed(let message):
                    TWErrorText(message)
                case .loaded(let actions) where actions.isEmpty:
                    Text("No governance actions are open for votes.", bundle: #bundle)
                        .foregroundStyle(TWColor.secondaryText)
                case .loaded(let actions):
                    Section {
                        ForEach(actions) { action in
                            Button {
                                onChoose(action.id)
                                dismiss()
                            } label: {
                                row(action)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("openAction")
                        }
                    } footer: {
                        Text("Actions not yet ratified, enacted, dropped or expired, newest first.", bundle: #bundle)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Open Actions", bundle: #bundle))
            .twSheetRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Label {
                            Text("Refresh", bundle: #bundle)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(cache.state.isLoading)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 520)
        #endif
        .task { await load(force: false) }
    }

    private func row(_ action: ChainLookup.OpenAction) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: TWSpacing.xxs) {
                Text(verbatim: action.kind).font(.body.weight(.semibold))
                TWBytesText(action.id, font: TWFont.bytesSmall)
                if let expiry = action.expiresAfter {
                    Text("Open until the end of epoch \(expiry, format: .number.grouping(.never))", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
                if let url = action.anchorURL {
                    Text(verbatim: url)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if action.id == selected {
                Image(systemName: "checkmark").foregroundStyle(TWColor.success)
            }
        }
        .contentShape(.rect)
    }

    private func load(force: Bool) async {
        guard let provider = source.provider else { return }
        await cache.load(provider: provider, apiKey: providers.apiKey(for: provider), force: force)
    }
}
