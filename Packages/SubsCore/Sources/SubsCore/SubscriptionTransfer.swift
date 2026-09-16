//
//  SubscriptionTransfer.swift
//  subs
//

import Foundation

/// One subscription as it travels through the JSON file: its identity, its
/// trimmed name and the calendar day it starts on.
public struct SubscriptionRecord: Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var startDay: CalendarDay

    public init(id: UUID, name: String, startDay: CalendarDay) {
        self.id = id
        self.name = name
        self.startDay = startDay
    }
}

/// A calendar day without a time or time zone, so a start date means the same
/// day regardless of the device's time zone.
public struct CalendarDay: Comparable, Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The year, month and day of `date` in `calendar`.
    public init?(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Midnight of this day in `calendar`, or nil when the day does not
    /// exist. The round trip matters: calendars silently roll 2026-02-30
    /// forward to March 1 instead of refusing it.
    public func date(calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        return CalendarDay(date: date, calendar: calendar) == self ? date : nil
    }

    var encoded: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public enum SubscriptionTransferError: Error, Equatable, Sendable, LocalizedError {
    public enum Field: String, Sendable {
        case id
        case name
        case startDate
    }

    case notValidJSON
    case fileTooLarge
    case notASubsExport
    case missingVersion
    case unsupportedVersion(Int)
    case missingSubscriptions
    case missingField(index: Int, field: Field)
    case invalidID(index: Int, value: String)
    case emptyName(index: Int)
    case invalidStartDate(index: Int, value: String)
    case duplicateID(first: Int, second: Int)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The file is too large to be a subs export."
        case .notValidJSON:
            "The file isn’t valid JSON."
        case .notASubsExport:
            "This file isn’t a subs export."
        case .missingVersion:
            "The file has no valid format version."
        case let .unsupportedVersion(version):
            "This file uses format version \(version), which this version of subs can’t read."
        case .missingSubscriptions:
            "The file has no subscription list."
        case let .missingField(index, field):
            "Subscription \(index) is missing a valid “\(field.rawValue)”."
        case let .invalidID(index, value):
            "Subscription \(index) has an invalid id “\(value)”."
        case let .emptyName(index):
            "Subscription \(index) has an empty name."
        case let .invalidStartDate(index, value):
            "Subscription \(index) has an invalid start date “\(value)”."
        case let .duplicateID(first, second):
            "Subscriptions \(first) and \(second) have the same id."
        }
    }
}

/// The versioned JSON format for moving the whole subscription list between
/// devices. Decoding validates the entire file and never reports partial
/// success: the first problem throws, so callers can ask the user for a
/// decision before anything is changed.
public enum SubscriptionTransfer {
    public static let format = "pl.glasek.subs"
    public static let version = 1
    /// Files larger than this are rejected before being read into memory.
    public static let maxFileSize = 5_000_000

    /// Transfer dates are always Gregorian calendar days. The time zone stays
    /// local so an existing stored midnight remains the same day for the user.
    public static func gregorianCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Encoding

    /// Encodes records as format version 1. Records are sorted by start day,
    /// then name, then id, so exporting the same data twice produces the same
    /// bytes.
    public static func encode(_ records: [SubscriptionRecord], exportedAt: Date) throws -> Data {
        let sorted = records.sorted { lhs, rhs in
            if lhs.startDay != rhs.startDay { return lhs.startDay < rhs.startDay }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let file = ExportFile(
            exportedAt: exportedAt.formatted(.iso8601),
            format: format,
            subscriptions: sorted.map { ExportRecord(id: $0.id.uuidString, name: $0.name, startDate: $0.startDay.encoded) },
            version: version
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(file)
        guard data.count <= maxFileSize else { throw SubscriptionTransferError.fileTooLarge }
        return data
    }

    private struct ExportFile: Encodable {
        let exportedAt: String
        let format: String
        let subscriptions: [ExportRecord]
        let version: Int
    }

    private struct ExportRecord: Encodable {
        let id: String
        let name: String
        let startDate: String
    }

    // MARK: - Decoding

    /// Validates the whole file and returns its records. Unknown keys are
    /// ignored, so fields added in later minor edits of version 1 keep
    /// older builds reading the file; a changed meaning of existing fields
    /// requires version 2 instead.
    public static func decode(_ data: Data) throws -> [SubscriptionRecord] {
        guard data.count <= maxFileSize else { throw SubscriptionTransferError.fileTooLarge }
        let decoder = JSONDecoder()

        // The header is validated before any record is looked at, so a file
        // from a future format version reports its version instead of the
        // first record it would fail on.
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw mapHeaderError(error)
        }

        guard header.format == format else { throw SubscriptionTransferError.notASubsExport }
        guard let version = header.version else { throw SubscriptionTransferError.missingVersion }
        guard version == Self.version else { throw SubscriptionTransferError.unsupportedVersion(version) }

        let list: RecordList
        do {
            list = try decoder.decode(RecordList.self, from: data)
        } catch {
            throw mapRecordError(error)
        }
        guard let records = list.subscriptions else {
            throw SubscriptionTransferError.missingSubscriptions
        }
        return try validated(records)
    }

    /// Reads at most one byte beyond the supported limit, so a stale or
    /// unavailable filesystem size never causes an unbounded allocation.
    public static func decode(contentsOf url: URL) throws -> [SubscriptionRecord] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxFileSize + 1) ?? Data()
        guard data.count <= maxFileSize else { throw SubscriptionTransferError.fileTooLarge }
        return try decode(data)
    }

    private struct Header: Decodable {
        var format: String?
        var version: Int?
    }

    private struct RecordList: Decodable {
        var subscriptions: [RawRecord]?
    }

    /// Fields are optional here so that missing keys become nil and are
    /// reported one field at a time; wrong-typed values still throw with a
    /// coding path that names the record and the field.
    private struct RawRecord: Decodable {
        var id: String?
        var name: String?
        var startDate: String?
    }

    private static func mapHeaderError(_ error: Error) -> SubscriptionTransferError {
        guard let decoding = error as? DecodingError, let key = decoding.codingPath.first else {
            return .notValidJSON
        }
        switch key.stringValue {
        case "format": return .notASubsExport
        case "version": return .missingVersion
        default: return .notValidJSON
        }
    }

    private static func mapRecordError(_ error: Error) -> SubscriptionTransferError {
        guard let decoding = error as? DecodingError else { return .missingSubscriptions }
        let path = decoding.codingPath
        if path.count == 1, path[0].stringValue == "subscriptions" {
            return .missingSubscriptions
        }
        var index: Int?
        var field = SubscriptionTransferError.Field.id
        for key in path {
            if let value = key.intValue {
                index = value
            } else if let value = SubscriptionTransferError.Field(rawValue: key.stringValue) {
                field = value
            }
        }
        guard let index else { return .missingSubscriptions }
        return .missingField(index: index + 1, field: field)
    }

    private static func validated(_ records: [RawRecord]) throws -> [SubscriptionRecord] {
        var result: [SubscriptionRecord] = []
        var firstOccurrence: [UUID: Int] = [:]

        for (offset, raw) in records.enumerated() {
            let index = offset + 1

            guard let idText = raw.id else { throw SubscriptionTransferError.missingField(index: index, field: .id) }
            guard let id = UUID(uuidString: idText) else {
                throw SubscriptionTransferError.invalidID(index: index, value: idText)
            }
            if let first = firstOccurrence[id] {
                throw SubscriptionTransferError.duplicateID(first: first, second: index)
            }
            firstOccurrence[id] = index

            guard let rawName = raw.name else { throw SubscriptionTransferError.missingField(index: index, field: .name) }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw SubscriptionTransferError.emptyName(index: index) }

            guard let startText = raw.startDate else {
                throw SubscriptionTransferError.missingField(index: index, field: .startDate)
            }
            guard let startDay = parseDay(startText) else {
                throw SubscriptionTransferError.invalidStartDate(index: index, value: startText)
            }

            result.append(SubscriptionRecord(id: id, name: name, startDay: startDay))
        }
        return result
    }

    /// Accepts exactly `YYYY-MM-DD` with ASCII digits and a day that really
    /// exists in the Gregorian calendar. The time-zone-independent existence
    /// check keeps "2026-02-30" out even though calendars would silently
    /// roll it forward.
    private static func parseDay(_ text: String) -> CalendarDay? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = digits(parts[0], count: 4),
              let month = digits(parts[1], count: 2),
              let day = digits(parts[2], count: 2)
        else { return nil }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let calendarDay = CalendarDay(year: year, month: month, day: day)
        return calendarDay.date(calendar: gregorian) == nil ? nil : calendarDay
    }

    private static func digits(_ part: Substring, count: Int) -> Int? {
        guard part.count == count, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(part)
    }
}

private extension DecodingError {
    var codingPath: [any CodingKey] {
        switch self {
        case .dataCorrupted(let context), .keyNotFound(_, let context),
             .typeMismatch(_, let context), .valueNotFound(_, let context):
            context.codingPath
        @unknown default:
            []
        }
    }
}
