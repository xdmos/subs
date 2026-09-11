//
//  SubscriptionCard.swift
//  subs
//

import SubsCore
import SwiftData
import SwiftUI

// MARK: - Card

struct SubscriptionCard: View {
    let entry: SubscriptionEntry

    @State private var displayMode = CycleDisplayMode.remaining

    private var subscription: Subscription { entry.subscription }
    private var cycle: SubscriptionCycle { entry.cycle }

    private var isRenewingSoon: Bool { cycle.phase != .upcoming && cycle.remainingDays <= 3 }

    private var highlight: Color {
        switch displayMode {
        case .remaining: isRenewingSoon ? AppColors.warning : AppColors.accent
        case .elapsed: AppColors.elapsed
        }
    }

    var body: some View {
        Button {
            withAnimation(.snappy) {
                displayMode.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(displayMode.detail(for: cycle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }

                    Spacer(minLength: 8)

                    dayCounter
                }

                CycleProgressBar(
                    fraction: cycle.phase == .upcoming ? 0 : displayMode.fraction(for: cycle),
                    color: cycle.phase == .upcoming ? AppColors.accent : highlight
                )
            }
            .padding(14)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isRenewingSoon ? AppColors.warning.opacity(0.10) : .clear).interactive(),
            in: .rect(cornerRadius: 20)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityValue(cardAccessibilityValue)
        .accessibilityHint(cardAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private var dayCounter: some View {
        let isUpcoming = cycle.phase == .upcoming
        let count = isUpcoming ? cycle.daysUntilStart : displayMode.dayCount(for: cycle)

        return VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if showsRenewalToday {
                    Text("Today")
                        .font(.system(.title, design: .rounded).weight(.bold))
                } else {
                    Text(count, format: .number)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))

                    Text(count == 1 ? "day" : "days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isUpcoming ? AppColors.accent : highlight)

            Text(dayCounterCaption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .contentTransition(.opacity)
        }
    }

    // On the renewal day the cycle has run out, so the counter says "Today"
    // instead of a zero that would read like an expired subscription.
    private var showsRenewalToday: Bool {
        cycle.phase == .renewalDay && displayMode == .remaining
    }

    private var dayCounterCaption: String {
        switch cycle.phase {
        case .upcoming: "until start"
        case .renewalDay where displayMode == .remaining: "renews"
        case .active, .renewalDay: displayMode.title.lowercased()
        }
    }

    private var cardAccessibilityLabel: String {
        if cycle.phase == .upcoming {
            return "\(subscription.name), starts \(cycle.startDate.formatted(AppFormat.shortDate))"
        }
        return "\(subscription.name), \(displayMode.title)"
    }

    private var cardAccessibilityValue: String {
        switch cycle.phase {
        case .upcoming:
            return "\(dayText(cycle.daysUntilStart)) until start"
        case .renewalDay where displayMode == .remaining:
            return "Renews today"
        default:
            return dayText(displayMode.dayCount(for: cycle))
        }
    }

    private var cardAccessibilityHint: String {
        cycle.phase == .upcoming ? "" : "Shows \(displayMode.oppositeTitle.lowercased()) days"
    }

    private func dayText(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

private struct CycleProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
                    .shadow(color: color.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

private enum CycleDisplayMode: Equatable {
    case remaining
    case elapsed

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .elapsed: "Elapsed"
        }
    }

    var oppositeTitle: String {
        switch self {
        case .remaining: "Elapsed"
        case .elapsed: "Remaining"
        }
    }

    mutating func toggle() {
        self = self == .remaining ? .elapsed : .remaining
    }

    func dayCount(for cycle: SubscriptionCycle) -> Int {
        switch self {
        case .remaining: cycle.remainingDays
        case .elapsed: cycle.elapsedDays
        }
    }

    func fraction(for cycle: SubscriptionCycle) -> Double {
        switch self {
        case .remaining: cycle.remainingFraction
        case .elapsed: cycle.elapsedFraction
        }
    }

    func detail(for cycle: SubscriptionCycle) -> String {
        if cycle.phase == .upcoming {
            return "Starts \(cycle.startDate.formatted(AppFormat.shortDate))"
        }
        if cycle.phase == .renewalDay && self == .remaining {
            return "Renews today"
        }
        switch self {
        case .remaining:
            return "Renews \(cycle.nextRenewal.formatted(AppFormat.shortDate))"
        case .elapsed:
            return "Cycle started \(cycle.cycleStart.formatted(AppFormat.shortDate))"
        }
    }
}
