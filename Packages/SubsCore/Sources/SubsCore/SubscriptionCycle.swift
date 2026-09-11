//
//  SubscriptionCycle.swift
//  subs
//

import Foundation

public struct SubscriptionCycle: Equatable, Sendable {
    public static let lengthInDays = 30

    public enum Phase: Equatable, Sendable {
        case upcoming     // today < start of the start date
        case active       // any other day that is not a renewal day (includes the start day)
        case renewalDay   // total days since start >= 30 and total % 30 == 0
    }

    public let cycleStart: Date
    public let nextRenewal: Date
    public let elapsedDays: Int
    public let remainingDays: Int
    public let phase: Phase
    public let startDate: Date
    public let daysUntilStart: Int

    public var elapsedFraction: Double {
        Double(elapsedDays) / Double(Self.lengthInDays)
    }

    public var remainingFraction: Double {
        Double(remainingDays) / Double(Self.lengthInDays)
    }

    // The next day the card reacts to: the start itself for a future
    // subscription, today on the renewal day, otherwise the next renewal.
    public var daysUntilNextEvent: Int {
        switch phase {
        case .upcoming: daysUntilStart
        case .renewalDay: 0
        case .active: remainingDays
        }
    }

    public init(startDate: Date, now: Date = .now, calendar: Calendar = .current) {
        let startOfSubscription = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)

        self.startDate = startOfSubscription

        guard today >= startOfSubscription else {
            phase = .upcoming
            daysUntilStart = calendar.dateComponents([.day], from: today, to: startOfSubscription).day ?? 0
            cycleStart = startOfSubscription
            nextRenewal = calendar.date(
                byAdding: .day,
                value: Self.lengthInDays,
                to: startOfSubscription
            ) ?? startOfSubscription
            elapsedDays = 0
            remainingDays = Self.lengthInDays
            return
        }

        let totalElapsedDays = max(
            0,
            calendar.dateComponents([.day], from: startOfSubscription, to: today).day ?? 0
        )

        // The start day itself is day 0 of the first cycle, not a renewal. A
        // renewal day is a positive multiple of the cycle length; its cycle is
        // the one ending today so the card can say "renews today" instead of
        // jumping straight to the next cycle.
        if totalElapsedDays >= Self.lengthInDays, totalElapsedDays % Self.lengthInDays == 0 {
            phase = .renewalDay
            daysUntilStart = 0
            cycleStart = calendar.date(byAdding: .day, value: -Self.lengthInDays, to: today) ?? today
            nextRenewal = today
            elapsedDays = Self.lengthInDays
            remainingDays = 0
            return
        }

        phase = .active
        daysUntilStart = 0
        let completedCycles = totalElapsedDays / Self.lengthInDays
        let daysIntoCycle = totalElapsedDays % Self.lengthInDays
        let currentCycleStart = calendar.date(
            byAdding: .day,
            value: completedCycles * Self.lengthInDays,
            to: startOfSubscription
        ) ?? startOfSubscription

        cycleStart = currentCycleStart
        nextRenewal = calendar.date(
            byAdding: .day,
            value: Self.lengthInDays,
            to: currentCycleStart
        ) ?? currentCycleStart
        elapsedDays = daysIntoCycle
        remainingDays = Self.lengthInDays - daysIntoCycle
    }
}
