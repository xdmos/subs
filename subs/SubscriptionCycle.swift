//
//  SubscriptionCycle.swift
//  subs
//

import Foundation

struct SubscriptionCycle: Equatable {
    static let lengthInDays = 30

    let cycleStart: Date
    let nextRenewal: Date
    let elapsedDays: Int
    let remainingDays: Int

    var elapsedFraction: Double {
        Double(elapsedDays) / Double(Self.lengthInDays)
    }

    var remainingFraction: Double {
        Double(remainingDays) / Double(Self.lengthInDays)
    }

    init(startDate: Date, now: Date = .now, calendar: Calendar = .current) {
        let startOfSubscription = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)

        guard today >= startOfSubscription else {
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
