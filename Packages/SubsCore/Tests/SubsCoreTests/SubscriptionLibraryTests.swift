//
//  SubscriptionLibraryTests.swift
//  subs
//

import Foundation
import SwiftData
import Testing
@testable import SubsCore

@MainActor
struct SubscriptionLibraryTests {
    private struct SaveFault: Error, Equatable {
        let message: String
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    // 2026-09-16 17:55:00 UTC.
    private let fixedNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 17, minute: 55))!
    }()

    private var utc = TimeZone(identifier: "UTC")!

    private let alpha = SubscriptionRecord(
        id: UUID(uuidString: "3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41")!,
        name: "Alpha",
        startDay: CalendarDay(year: 2026, month: 1, day: 5)
    )
    private let beta = SubscriptionRecord(
        id: UUID(uuidString: "0A0B0C0D-0E0F-4A1B-8C2D-3E4F5A6B7C8D")!,
        name: "Beta",
        startDay: CalendarDay(year: 2026, month: 2, day: 10)
    )

    // MARK: - Replacement

    @Test func replacesWholeStoreIncludingSameIDRecords() throws {
        let (directory, container, storeURL) = try makeStore()
        defer { cleanup(directory) }
        try insert(alpha, into: container)
        try insert(beta, into: container)
        #expect(Set(try SubscriptionLibrary.records(in: container, calendar: calendar)) == [alpha, beta])

        // Beta keeps its UUID but changes name and day; Gamma is new.
        let betaPrime = SubscriptionRecord(id: beta.id, name: "Beta Prime", startDay: CalendarDay(year: 2026, month: 3, day: 15))
        let gamma = SubscriptionRecord(id: UUID(), name: "Gamma", startDay: CalendarDay(year: 2026, month: 4, day: 2))

        let result = try SubscriptionLibrary.importReplacingAll(
            [betaPrime, gamma], in: container, backupDirectory: directory.appending(path: "Import Backups"), calendar: calendar
        )

        #expect(result.importedCount == 2)
        #expect(result.previousCount == 2)

        // A second container on the same file proves what is really stored,
        // not what a shared cache might still be holding.
        let reopened = try ModelContainer(for: Subscription.self, configurations: ModelConfiguration(url: storeURL))
        let stored = try SubscriptionLibrary.records(in: reopened, calendar: calendar)
        #expect(stored.count == 2)
        #expect(Set(stored) == [betaPrime, gamma])
        // Start dates are start-of-day in the import calendar.
        #expect(stored.allSatisfy { record in
            record.startDay.date(calendar: calendar) == calendar.startOfDay(for: record.startDay.date(calendar: calendar)!)
        })
    }

    @Test func exportImportRoundTripBetweenTwoStores() throws {
        let (directoryA, containerA, urlA) = try makeStore()
        defer { cleanup(directoryA) }
        let fancy = SubscriptionRecord(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            name: "Na “Netflixa” 👪",
            startDay: CalendarDay(year: 2028, month: 2, day: 29)
        )
        let sameName = SubscriptionRecord(id: UUID(), name: "Alpha", startDay: CalendarDay(year: 2026, month: 6, day: 30))
        try insert(alpha, into: containerA)
        try insert(fancy, into: containerA)
        try insert(sameName, into: containerA)

        let records = try SubscriptionLibrary.records(in: containerA, calendar: calendar)
        let data = try SubscriptionTransfer.encode(records, exportedAt: fixedNow)
        let decoded = try SubscriptionTransfer.decode(data)

        let (directoryB, containerB, urlB) = try makeStore()
        defer { cleanup(directoryB) }
        try SubscriptionLibrary.importReplacingAll(decoded, in: containerB, backupDirectory: directoryB.appending(path: "Import Backups"), calendar: calendar)

        let reopened = try ModelContainer(for: Subscription.self, configurations: ModelConfiguration(url: urlB))
        let stored = try SubscriptionLibrary.records(in: reopened, calendar: calendar)
        #expect(byID(stored) == byID(records))
        #expect(urlB != urlA)
    }

    @Test func failedSaveLeavesTheStoreUnchanged() throws {
        let (directory, container, storeURL) = try makeStore()
        defer { cleanup(directory) }
        try insert(alpha, into: container)
        try insert(beta, into: container)
        // Prove the store really holds {alpha, beta} first: an empty result
        // would pass the assertions below without any rollback being tested.
        #expect(Set(try SubscriptionLibrary.records(in: container, calendar: calendar)) == [alpha, beta])

        let replacement = SubscriptionRecord(id: UUID(), name: "Gamma", startDay: CalendarDay(year: 2026, month: 5, day: 5))
        do {
            _ = try SubscriptionLibrary.importReplacingAll(
                [replacement], in: container,
                backupDirectory: directory.appending(path: "Import Backups"),
                calendar: calendar,
                save: { _ in throw SaveFault(message: "disk full") }
            )
            Issue.record("Expected the save to fail")
        } catch let error as SubscriptionLibraryError {
            guard case let .replaceFailed(underlying) = error else {
                Issue.record("Expected replaceFailed, got \(error)")
                return
            }
            #expect(underlying as? SaveFault == SaveFault(message: "disk full"))
        }

        let reopened = try ModelContainer(for: Subscription.self, configurations: ModelConfiguration(url: storeURL))
        #expect(Set(try SubscriptionLibrary.records(in: reopened, calendar: calendar)) == [alpha, beta])
    }

    // MARK: - The pre-import copy

    @Test func importWritesRecoverableBackupAndSuffixesCollisions() throws {
        let (directory, container, _) = try makeStore()
        defer { cleanup(directory) }
        try insert(alpha, into: container)
        try insert(beta, into: container)
        let backups = directory.appending(path: "Import Backups")

        let gamma = SubscriptionRecord(id: UUID(), name: "Gamma", startDay: CalendarDay(year: 2026, month: 5, day: 5))
        let first = try SubscriptionLibrary.importReplacingAll(
            [gamma],
            in: container, backupDirectory: backups, now: fixedNow, timeZone: utc, calendar: calendar
        )

        #expect(first.backupURL == backups.appending(path: "subs-before-import-20260916-175500.json"))
        let firstData = try Data(contentsOf: first.backupURL)
        #expect(try SubscriptionTransfer.decode(firstData).sorted { $0.id.uuidString < $1.id.uuidString } == [alpha, beta].sorted { $0.id.uuidString < $1.id.uuidString })

        let delta = SubscriptionRecord(id: UUID(), name: "Delta", startDay: CalendarDay(year: 2026, month: 6, day: 6))
        let second = try SubscriptionLibrary.importReplacingAll(
            [delta],
            in: container, backupDirectory: backups, now: fixedNow, timeZone: utc, calendar: calendar
        )

        // Same second: the new copy gets "-2" and the first copy is untouched.
        #expect(second.backupURL == backups.appending(path: "subs-before-import-20260916-175500-2.json"))
        #expect(try Data(contentsOf: first.backupURL) == firstData)
        // The second copy holds the state before the second import.
        #expect(try SubscriptionTransfer.decode(try Data(contentsOf: second.backupURL)) == [gamma])
    }

    @Test func failedBackupChangesNothing() throws {
        let (directory, container, storeURL) = try makeStore()
        defer { cleanup(directory) }
        try insert(alpha, into: container)
        try insert(beta, into: container)
        #expect(Set(try SubscriptionLibrary.records(in: container, calendar: calendar)) == [alpha, beta])

        // An existing file instead of a directory: creating the copy must fail.
        let blocker = directory.appending(path: "blocker")
        try Data("x".utf8).write(to: blocker)

        var replaceCalls = 0
        do {
            _ = try SubscriptionLibrary.importReplacingAll(
                [SubscriptionRecord(id: UUID(), name: "Gamma", startDay: CalendarDay(year: 2026, month: 5, day: 5))],
                in: container, backupDirectory: blocker, calendar: calendar,
                save: { context in replaceCalls += 1; try context.save() }
            )
            Issue.record("Expected the backup to fail")
        } catch let error as SubscriptionLibraryError {
            guard case .backupFailed = error else {
                Issue.record("Expected backupFailed, got \(error)")
                return
            }
        }

        #expect(replaceCalls == 0)
        let reopened = try ModelContainer(for: Subscription.self, configurations: ModelConfiguration(url: storeURL))
        #expect(Set(try SubscriptionLibrary.records(in: reopened, calendar: calendar)) == [alpha, beta])
    }

    @Test func backupIsCreatedEvenForAnEmptyStore() throws {
        let (directory, container, _) = try makeStore()
        defer { cleanup(directory) }
        let backups = directory.appending(path: "Import Backups")

        let result = try SubscriptionLibrary.importReplacingAll(
            [alpha], in: container, backupDirectory: backups, now: fixedNow, timeZone: utc, calendar: calendar
        )

        #expect(result.previousCount == 0)
        let backupData = try Data(contentsOf: result.backupURL)
        #expect(try SubscriptionTransfer.decode(backupData) == [])
        #expect(Set(try SubscriptionLibrary.records(in: container, calendar: calendar)) == [alpha])
    }

    // MARK: - Helpers

    private func makeStore() throws -> (directory: URL, container: ModelContainer, storeURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let storeURL = directory.appendingPathComponent("subs.store")
        let container = try ModelContainer(for: Subscription.self, configurations: ModelConfiguration(url: storeURL))
        return (directory, container, storeURL)
    }

    private func insert(_ record: SubscriptionRecord, into container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(Subscription(name: record.name, startDate: record.startDay.date(calendar: calendar)!, id: record.id))
        try context.save()
    }

    private func byID(_ records: [SubscriptionRecord]) -> [SubscriptionRecord] {
        records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
