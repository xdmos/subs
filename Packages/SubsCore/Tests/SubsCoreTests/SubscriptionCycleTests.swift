import Foundation
import Testing
@testable import SubsCore

struct SubscriptionCycleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func cycle(start: Date, now: Date) -> SubscriptionCycle {
        SubscriptionCycle(startDate: start, now: now, calendar: calendar)
    }

    @Test func startDayBeginsAFullCycle() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 1, 1, 18))

        #expect(result.elapsedDays == 0)
        #expect(result.remainingDays == 30)
        #expect(result.cycleStart == date(2026, 1, 1, 0))
        #expect(result.nextRenewal == date(2026, 1, 31, 0))
    }

    @Test func firstDayAfterStart() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 1, 2))

        #expect(result.elapsedDays == 1)
        #expect(result.remainingDays == 29)
    }

    @Test func dayBeforeRenewal() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 1, 30))

        #expect(result.elapsedDays == 29)
        #expect(result.remainingDays == 1)
        #expect(result.nextRenewal == date(2026, 1, 31, 0))
    }

    @Test func dayAfterRenewalStartsTheNextCycle() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 2, 1))

        #expect(result.elapsedDays == 1)
        #expect(result.remainingDays == 29)
        #expect(result.cycleStart == date(2026, 1, 31, 0))
        #expect(result.nextRenewal == date(2026, 3, 2, 0))
    }

    @Test func timeOfDayIsIgnored() {
        let result = cycle(start: date(2026, 1, 1, 23, 30), now: date(2026, 1, 2, 0, 10))

        #expect(result.elapsedDays == 1)
        #expect(result.remainingDays == 29)
    }

    @Test func daylightSavingChangeDoesNotShiftTheCount() {
        // Europe/Warsaw moves clocks forward on 29 March 2026.
        let result = cycle(start: date(2026, 3, 1), now: date(2026, 3, 30))

        #expect(result.elapsedDays == 29)
        #expect(result.remainingDays == 1)
        #expect(result.nextRenewal == date(2026, 3, 31, 0))
    }

    @Test func renewalDayReportsZeroRemaining() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 1, 31, 12))

        #expect(result.phase == .renewalDay)
        #expect(result.remainingDays == 0)
        #expect(result.elapsedDays == 30)
        #expect(result.daysUntilNextEvent == 0)
        #expect(result.cycleStart == date(2026, 1, 1, 0))
        #expect(result.nextRenewal == date(2026, 1, 31, 0))
        #expect(result.remainingFraction == 0)
    }

    @Test func secondRenewalDay() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 3, 2, 8))

        #expect(result.phase == .renewalDay)
        #expect(result.cycleStart == date(2026, 1, 31, 0))
        #expect(result.nextRenewal == date(2026, 3, 2, 0))
    }

    @Test func startDayIsActiveNotRenewal() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 1, 1, 18))

        #expect(result.phase == .active)
        #expect(result.daysUntilNextEvent == 30)
    }

    @Test func dayAfterRenewalIsActive() {
        let result = cycle(start: date(2026, 1, 1), now: date(2026, 2, 1))

        #expect(result.phase == .active)
        #expect(result.daysUntilNextEvent == 29)
    }

    @Test func futureStartCountsDaysUntilStart() {
        let result = cycle(start: date(2026, 6, 1), now: date(2026, 3, 1, 9))

        #expect(result.phase == .upcoming)
        #expect(result.daysUntilStart == 92)
        #expect(result.daysUntilNextEvent == 92)
        #expect(result.startDate == date(2026, 6, 1, 0))
        #expect(result.nextRenewal == date(2026, 7, 1, 0))
    }

    @Test func startTomorrowIsOneDayAway() {
        let result = cycle(start: date(2026, 1, 2), now: date(2026, 1, 1, 23, 30))

        #expect(result.phase == .upcoming)
        #expect(result.daysUntilStart == 1)
    }

    @Test func renewalDayAcrossDaylightSaving() {
        // Europe/Warsaw moves clocks forward on 29 March 2026.
        let result = cycle(start: date(2026, 3, 1), now: date(2026, 3, 31, 12))

        #expect(result.phase == .renewalDay)
        #expect(result.nextRenewal == date(2026, 3, 31, 0))
    }
}
