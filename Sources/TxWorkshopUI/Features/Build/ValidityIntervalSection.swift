import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The transaction's validity interval, picked as times rather than slots:
/// whether it has a start and an end, a few common windows, and a slider for
/// how long it stays valid, drawn as a timeline. The exact slots stay
/// editable below.
struct ValidityIntervalSection: View {
    @Binding var recipe: BuildRecipe
    let document: TxWorkshopDocument

    /// How long a new end lasts when nothing else says.
    static let defaultDuration: TimeInterval = 2 * 86_400

    private var clock: ValidityClock? {
        ValidityClock(network: document.content.network, snapshot: document.content.chainContext)
    }

    var body: some View {
        Section {
            Toggle(isOn: includesStart) {
                Text("Valid from a slot", bundle: #bundle)
            }
            .accessibilityIdentifier("validityIncludesStart")
            Toggle(isOn: includesEnd) {
                Text("Valid until a slot", bundle: #bundle)
            }
            .accessibilityIdentifier("validityIncludesEnd")
            if let clock {
                if recipe.validFrom != nil || recipe.validUntil != nil {
                    presets(clock)
                    if recipe.validUntil != nil {
                        durationSlider(clock)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ValidityTimeline(clock: clock, from: recipe.validFrom, until: recipe.validUntil, now: context.date)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: TWSpacing.s) {
                    Text("Fetch chain data to pick times instead of slots. Adding a source address fetches it too.", bundle: #bundle)
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                    FetchChainDataButton(document: document) {}
                }
            }
            TWLabeledField(Text("Valid from slot", bundle: #bundle), value: $recipe.validFrom, format: .number)
                .font(TWFont.figure)
            TWLabeledField(Text("Valid until slot", bundle: #bundle), value: $recipe.validUntil, format: .number)
                .font(TWFont.figure)
        } header: {
            Text("Validity interval", bundle: #bundle)
        } footer: {
            if clock?.isEstimate == true {
                Text("This network's slots are counted from the fetched tip at one per second, so the times are estimates. Fetch again for a fresh tip.", bundle: #bundle)
            } else {
                Text("Outside this interval the chain rejects the transaction. Leave both off for one valid at any time.", bundle: #bundle)
            }
        }
    }

    // MARK: Start and end

    private var includesStart: Binding<Bool> {
        Binding {
            recipe.validFrom != nil
        } set: { on in
            recipe.validFrom = on ? (clock?.slot(at: .now) ?? document.content.chainContext?.tipSlot ?? 0) : nil
        }
    }

    private var includesEnd: Binding<Bool> {
        Binding {
            recipe.validUntil != nil
        } set: { on in
            guard on else { recipe.validUntil = nil; return }
            if let clock {
                recipe.validUntil = clock.slot(at: anchor(clock).addingTimeInterval(Self.defaultDuration))
            } else {
                recipe.validUntil = (recipe.validFrom ?? document.content.chainContext?.tipSlot).map { $0 + UInt64(Self.defaultDuration) } ?? 0
            }
        }
    }

    /// Where the window opens: its start when it has one, otherwise now.
    private func anchor(_ clock: ValidityClock) -> Date {
        recipe.validFrom.flatMap(clock.date(of:)) ?? .now
    }

    // MARK: Presets

    private struct Preset: Identifiable {
        let id: String
        let label: Text
        let duration: TimeInterval
    }

    private var presetList: [Preset] {
        [
            Preset(id: "2h", label: Text("2 hours", bundle: #bundle), duration: 2 * 3_600),
            Preset(id: "1d", label: Text("Until tomorrow", bundle: #bundle), duration: 86_400),
            Preset(id: "2d", label: Text("48 hours", bundle: #bundle), duration: 2 * 86_400),
            Preset(id: "7d", label: Text("A week", bundle: #bundle), duration: 7 * 86_400),
        ]
    }

    private func presets(_ clock: ValidityClock) -> some View {
        VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Text("From now", bundle: #bundle)
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TWSpacing.s) {
                    ForEach(presetList) { preset in
                        Button {
                            apply(preset.duration, clock)
                        } label: {
                            preset.label
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("validityPreset-\(preset.id)")
                    }
                }
            }
        }
    }

    /// Opens the window now, when it has a start, and ends it `duration` later.
    private func apply(_ duration: TimeInterval, _ clock: ValidityClock) {
        let now = Date.now
        if recipe.validFrom != nil { recipe.validFrom = clock.slot(at: now) }
        recipe.validUntil = clock.slot(at: now.addingTimeInterval(duration))
    }

    // MARK: Slider

    /// Ten minutes to thirty days, on a log scale so short windows can be set
    /// as finely as long ones.
    private static let shortest: TimeInterval = 600
    private static let longest: TimeInterval = 30 * 86_400

    private func durationSlider(_ clock: ValidityClock) -> some View {
        let position = Binding<Double> {
            let start = anchor(clock)
            let end = recipe.validUntil.flatMap(clock.date(of:)) ?? start.addingTimeInterval(Self.defaultDuration)
            let seconds = min(max(end.timeIntervalSince(start), Self.shortest), Self.longest)
            return log(seconds / Self.shortest) / log(Self.longest / Self.shortest)
        } set: { fraction in
            let seconds = Self.shortest * pow(Self.longest / Self.shortest, fraction)
            // Whole minutes below a day, whole hours above, so the end lands
            // on a time people name.
            let step: TimeInterval = seconds < 86_400 ? 60 : 3_600
            let rounded = (seconds / step).rounded() * step
            recipe.validUntil = clock.slot(at: anchor(clock).addingTimeInterval(rounded))
        }
        return VStack(alignment: .leading, spacing: TWSpacing.xs) {
            Slider(value: position, in: 0...1) {
                Text("How long it stays valid", bundle: #bundle)
            } minimumValueLabel: {
                Text("10 min", bundle: #bundle).font(.caption)
            } maximumValueLabel: {
                Text("30 days", bundle: #bundle).font(.caption)
            }
            .accessibilityIdentifier("validityDuration")
        }
    }
}

/// The validity window on a line: when it opens and closes, the slots, and
/// where now falls.
struct ValidityTimeline: View {
    let clock: ValidityClock
    let from: UInt64?
    let until: UInt64?
    let now: Date

    private var start: Date? { from.flatMap(clock.date(of:)) }
    private var end: Date? { until.flatMap(clock.date(of:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.s) {
            bar
                .frame(height: 28)
                .accessibilityHidden(true)
            HStack(alignment: .top) {
                endpoint(Text("Opens", bundle: #bundle), date: start, slot: from, open: Text("Any time before", bundle: #bundle))
                Spacer(minLength: TWSpacing.l)
                endpoint(Text("Closes", bundle: #bundle), date: end, slot: until, open: Text("Never", bundle: #bundle))
                    .multilineTextAlignment(.trailing)
            }
            status
        }
        .padding(.vertical, TWSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("validityTimeline")
    }

    // MARK: Bar

    /// The span drawn: now and both ends, with a margin so each shows.
    private var span: (lower: Date, upper: Date) {
        let points = [now, start, end].compactMap(\.self)
        var lower = points.min()!
        var upper = points.max()!
        let width = max(upper.timeIntervalSince(lower), 3_600)
        if start == nil { lower = lower.addingTimeInterval(-width * 0.25) }
        if end == nil { upper = upper.addingTimeInterval(width * 0.25) }
        let margin = max(upper.timeIntervalSince(lower), 3_600) * 0.06
        return (lower.addingTimeInterval(-margin), upper.addingTimeInterval(margin))
    }

    private var bar: some View {
        GeometryReader { geometry in
            let (lower, upper) = span
            let total = upper.timeIntervalSince(lower)
            let x = { (date: Date) in CGFloat(date.timeIntervalSince(lower) / total) * geometry.size.width }
            let left = start.map(x) ?? 0
            let right = end.map(x) ?? geometry.size.width
            let mid = geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(TWColor.divider)
                    .frame(height: 6)
                    .offset(y: mid - 3)
                Capsule()
                    .fill(windowColor.gradient)
                    .frame(width: max(right - left, 6), height: 12)
                    .offset(x: left, y: mid - 6)
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: geometry.size.height)
                    .offset(x: x(now) - 1)
                Text("Now", bundle: #bundle)
                    .font(.caption2.weight(.semibold))
                    .fixedSize()
                    .offset(x: min(max(x(now) + 4, 0), geometry.size.width - 28), y: -2)
            }
            .animation(.snappy, value: from)
            .animation(.snappy, value: until)
        }
    }

    private var windowColor: Color {
        if let end, end <= now { return TWColor.failure }
        if let start, start > now { return TWColor.warning }
        return TWColor.accent
    }

    // MARK: Labels

    private func endpoint(_ title: Text, date: Date?, slot: UInt64?, open: Text) -> some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            title
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
            if let date {
                Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.callout.weight(.medium))
            } else {
                open.font(.callout.weight(.medium))
            }
            if let slot {
                Text("Slot \(slot, format: .number.grouping(.never))", bundle: #bundle)
                    .font(TWFont.bytesSmall)
                    .foregroundStyle(TWColor.secondaryText)
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let end, end <= now {
            Label {
                Text("Already closed. The chain rejects it; pick a later end.", bundle: #bundle)
            } icon: {
                Image(systemName: "xmark.octagon")
            }
            .labelStyle(.status(TWColor.failure))
            .font(.caption)
        } else if let start, let end, start >= end {
            Label {
                Text("It closes before it opens.", bundle: #bundle)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .labelStyle(.status(TWColor.failure))
            .font(.caption)
        } else if let start, start > now {
            Label {
                Text("Not valid until \(start, format: .relative(presentation: .named)).", bundle: #bundle)
            } icon: {
                Image(systemName: "clock")
            }
            .labelStyle(.status(TWColor.warning))
            .font(.caption)
        } else if let end {
            Text("Valid for \(Self.duration(end.timeIntervalSince(max(start ?? now, now)))) from now.", bundle: #bundle)
                .font(.caption.weight(.medium))
                .foregroundStyle(TWColor.secondaryText)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
    }
}
