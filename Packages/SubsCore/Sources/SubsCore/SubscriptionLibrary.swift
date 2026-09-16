//
//  SubscriptionLibrary.swift
//  subs
//

import Foundation
import SwiftData

public enum SubscriptionLibraryError: Error, LocalizedError, Sendable {
    /// Writing the pre-import copy of the current list failed; nothing was
    /// changed.
    case backupFailed(underlying: any Error)
    /// Saving the replacement failed and was rolled back; the store keeps its
    /// previous content.
    case replaceFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case let .backupFailed(underlying):
            underlying.localizedDescription
        case let .replaceFailed(underlying):
            underlying.localizedDescription
        }
    }
}

/// Whole-list operations on the SwiftData store: reading every subscription
/// as a transfer record, replacing the entire content in one save, and the
/// import flow that backs up the current list before touching anything.
public enum SubscriptionLibrary {
    public struct ImportResult: Equatable, Sendable {
        public let importedCount: Int
        public let previousCount: Int
        public let backupURL: URL

        public init(importedCount: Int, previousCount: Int, backupURL: URL) {
            self.importedCount = importedCount
            self.previousCount = previousCount
            self.backupURL = backupURL
        }
    }

    /// Every subscription in the store as a transfer record, in fetch order.
    public static func records(
        in container: ModelContainer,
        calendar: Calendar = SubscriptionTransfer.gregorianCalendar()
    ) throws -> [SubscriptionRecord] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try context.fetch(FetchDescriptor<Subscription>()).compactMap { subscription in
            guard let startDay = CalendarDay(date: subscription.startDate, calendar: calendar) else {
                return nil
            }
            return SubscriptionRecord(id: subscription.id, name: subscription.name, startDay: startDay)
        }
    }

    /// Replaces the whole store content with `records` in a single save.
    /// Every existing object is deleted explicitly first — inserting a record
    /// with an already stored unique id would silently overwrite instead of
    /// failing — then the new records are inserted with their original ids
    /// and start-of-day start dates. A failed save is rolled back and
    /// rethrown, so the store keeps its previous content.
    public static func replaceAll(
        in container: ModelContainer,
        with records: [SubscriptionRecord],
        calendar: Calendar = SubscriptionTransfer.gregorianCalendar(),
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        // Validate before deleting anything, so an impossible day in the
        // caller's records can never leave the store half-cleared.
        for record in records where record.startDay.date(calendar: calendar) == nil {
            throw SubscriptionLibraryError.replaceFailed(
                underlying: SubscriptionTransferError.invalidStartDate(index: 0, value: record.startDay.encoded)
            )
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        for existing in try context.fetch(FetchDescriptor<Subscription>()) {
            context.delete(existing)
        }
        for record in records {
            context.insert(
                Subscription(
                    name: record.name,
                    startDate: calendar.startOfDay(for: record.startDay.date(calendar: calendar)!),
                    id: record.id
                )
            )
        }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw SubscriptionLibraryError.replaceFailed(underlying: error)
        }
    }

    /// Writes `data` into `directory` as `subs-before-import-yyyyMMdd-HHmmss.json`
    /// (collisions get "-2", "-3", …). Existing files are never overwritten or
    /// removed: the copy is the user's only way back, so this code must not be
    /// able to destroy one.
    @discardableResult
    public static func writeImportBackup(
        _ data: Data,
        directory: URL,
        date: Date,
        timeZone: TimeZone = .current
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)

        var url = directory.appendingPathComponent("subs-before-import-\(stamp).json")
        var suffix = 2
        while true {
            do {
                // The exclusive create closes the race between choosing a
                // suffix and writing it. A concurrent import can never replace
                // an existing recovery file.
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                url = directory.appendingPathComponent("subs-before-import-\(stamp)-\(suffix).json")
                suffix += 1
            }
        }
    }

    /// The whole import, in the only safe order: read the current list,
    /// write a copy of it to disk, and only then replace the store. A backup
    /// failure aborts before any change; a failed save keeps the (harmless)
    /// copy on disk and leaves the store untouched through the rollback.
    @discardableResult
    public static func importReplacingAll(
        _ incoming: [SubscriptionRecord],
        in container: ModelContainer,
        backupDirectory: URL,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = SubscriptionTransfer.gregorianCalendar(),
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> ImportResult {
        let previous = try records(in: container, calendar: calendar)

        let backupURL: URL
        do {
            let backupData = try SubscriptionTransfer.encode(previous, exportedAt: now)
            backupURL = try writeImportBackup(backupData, directory: backupDirectory, date: now, timeZone: timeZone)
        } catch {
            throw SubscriptionLibraryError.backupFailed(underlying: error)
        }

        try replaceAll(in: container, with: incoming, calendar: calendar, save: save)
        return ImportResult(importedCount: incoming.count, previousCount: previous.count, backupURL: backupURL)
    }
}
