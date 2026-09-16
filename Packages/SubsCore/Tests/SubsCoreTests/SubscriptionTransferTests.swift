//
//  SubscriptionTransferTests.swift
//  subs
//

import Foundation
import Testing
@testable import SubsCore

struct SubscriptionTransferTests {
    // 2026-09-16 15:55:00 UTC.
    private let exportedAt: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 15, minute: 55))!
    }()

    private var netflix: SubscriptionRecord {
        SubscriptionRecord(
            id: UUID(uuidString: "3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41")!,
            name: "Netflix",
            startDay: CalendarDay(year: 2026, month: 8, day: 22)
        )
    }

    private var spotify: SubscriptionRecord {
        SubscriptionRecord(
            id: UUID(uuidString: "0A0B0C0D-0E0F-4A1B-8C2D-3E4F5A6B7C8D")!,
            name: "Spotify",
            startDay: CalendarDay(year: 2026, month: 9, day: 1)
        )
    }

    // MARK: - Encoding

    @Test func encodeProducesTheExactVersionOneJSON() throws {
        let data = try SubscriptionTransfer.encode([spotify, netflix], exportedAt: exportedAt)

        #expect(String(data: data, encoding: .utf8)! == """
        {
          "exportedAt" : "2026-09-16T15:55:00Z",
          "format" : "pl.glasek.subs",
          "subscriptions" : [
            {
              "id" : "3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41",
              "name" : "Netflix",
              "startDate" : "2026-08-22"
            },
            {
              "id" : "0A0B0C0D-0E0F-4A1B-8C2D-3E4F5A6B7C8D",
              "name" : "Spotify",
              "startDate" : "2026-09-01"
            }
          ],
          "version" : 1
        }
        """)
    }

    @Test func recordsAreSortedByStartDayThenNameThenID() throws {
        let late = SubscriptionRecord(id: UUID(), name: "Zeta", startDay: CalendarDay(year: 2026, month: 12, day: 1))
        let sameDayA = SubscriptionRecord(id: netflix.id, name: "beta", startDay: CalendarDay(year: 2026, month: 9, day: 1))
        let sameDayB = SubscriptionRecord(id: UUID(), name: "Alpha", startDay: CalendarDay(year: 2026, month: 9, day: 1))

        let data = try SubscriptionTransfer.encode([late, spotify, sameDayA, sameDayB], exportedAt: exportedAt)
        let decoded = try SubscriptionTransfer.decode(data)

        #expect(decoded.map(\.id) == [sameDayB.id, sameDayA.id, spotify.id, late.id])
    }

    @Test func roundTripPreservesRecords() throws {
        let quotedEmoji = SubscriptionRecord(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            name: "Na “Netflixa” 👪 & \\",
            startDay: CalendarDay(year: 2028, month: 2, day: 29)
        )
        let records = [quotedEmoji, netflix, spotify]

        // Encode sorts records, so both sides are compared in a canonical order.
        let decoded = try SubscriptionTransfer.decode(try SubscriptionTransfer.encode(records, exportedAt: exportedAt))

        #expect(byID(decoded) == byID(records))
    }

    @Test func rejectsOversizedDataAndFiles() throws {
        let oversized = Data(repeating: 0x20, count: SubscriptionTransfer.maxFileSize + 1)
        #expect(throws: SubscriptionTransferError.fileTooLarge) {
            try SubscriptionTransfer.decode(oversized)
        }

        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try oversized.write(to: url)
        #expect(throws: SubscriptionTransferError.fileTooLarge) {
            try SubscriptionTransfer.decode(contentsOf: url)
        }
    }

    @Test func refusesToCreateAnExportThatCannotBeImported() throws {
        let huge = SubscriptionRecord(
            id: UUID(),
            name: String(repeating: "x", count: SubscriptionTransfer.maxFileSize),
            startDay: CalendarDay(year: 2026, month: 1, day: 1)
        )
        #expect(throws: SubscriptionTransferError.fileTooLarge) {
            try SubscriptionTransfer.encode([huge], exportedAt: exportedAt)
        }
    }

    private func byID(_ records: [SubscriptionRecord]) -> [SubscriptionRecord] {
        records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    // MARK: - Validation

    @Test func rejectsBrokenJSON() throws {
        for json in ["", "not json", "[1, 2]", "null", "\"text\""] {
            #expect(throws: SubscriptionTransferError.notValidJSON) {
                try SubscriptionTransfer.decode(Data(json.utf8))
            }
        }
    }

    @Test func rejectsFilesWithoutTheSubsFormatMarker() throws {
        #expect(throws: SubscriptionTransferError.notASubsExport) {
            try SubscriptionTransfer.decode(Data(#"{"format":"someone.else","version":1,"subscriptions":[]}"#.utf8))
        }
        #expect(throws: SubscriptionTransferError.notASubsExport) {
            try SubscriptionTransfer.decode(Data(#"{"version":1,"subscriptions":[]}"#.utf8))
        }
    }

    @Test func rejectsFilesWithoutAnIntegerVersion() throws {
        #expect(throws: SubscriptionTransferError.missingVersion) {
            try SubscriptionTransfer.decode(Data(#"{"format":"pl.glasek.subs","subscriptions":[]}"#.utf8))
        }
        #expect(throws: SubscriptionTransferError.missingVersion) {
            try SubscriptionTransfer.decode(Data(#"{"format":"pl.glasek.subs","version":"1","subscriptions":[]}"#.utf8))
        }
    }

    @Test func rejectsFutureVersionsWithTheirNumber() throws {
        let json = #"{"format":"pl.glasek.subs","version":2,"subscriptions":[]}"#
        do {
            _ = try SubscriptionTransfer.decode(Data(json.utf8))
            Issue.record("Expected version 2 to be rejected")
        } catch let error as SubscriptionTransferError {
            #expect(error == .unsupportedVersion(2))
            #expect(error.errorDescription == "This file uses format version 2, which this version of subs can’t read.")
        }
        // The version is reported instead of the first broken record.
        #expect(throws: SubscriptionTransferError.unsupportedVersion(3)) {
            try SubscriptionTransfer.decode(
                Data(#"{"format":"pl.glasek.subs","version":3,"subscriptions":[{"id":5}]}"#.utf8)
            )
        }
    }

    @Test func rejectsFilesWithoutARecordList() throws {
        #expect(throws: SubscriptionTransferError.missingSubscriptions) {
            try SubscriptionTransfer.decode(Data(#"{"format":"pl.glasek.subs","version":1}"#.utf8))
        }
        #expect(throws: SubscriptionTransferError.missingSubscriptions) {
            try SubscriptionTransfer.decode(Data(#"{"format":"pl.glasek.subs","version":1,"subscriptions":5}"#.utf8))
        }
    }

    @Test func rejectsRecordsThatAreNotObjects() throws {
        // The first record is not an object; decoding stops there.
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .id)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[5, {"id":"x"}]"#).utf8))
        }
    }

    @Test func rejectsRecordsWithMissingOrWrongTypedFields() throws {
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .id)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"name":"N","startDate":"2026-01-02"}]"#).utf8))
        }
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .id)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"id":5,"name":"N","startDate":"2026-01-02"}]"#).utf8))
        }
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .name)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","startDate":"2026-01-02"}]"#).utf8))
        }
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .name)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":7,"startDate":"2026-01-02"}]"#).utf8))
        }
        #expect(throws: SubscriptionTransferError.missingField(index: 2, field: .startDate)) {
            try SubscriptionTransfer.decode(Data(self.file(
                #"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"N","startDate":"2026-01-02"},{"id":"0A0B0C0D-0E0F-4A1B-8C2D-3E4F5A6B7C8D","name":"S"}]"#
            ).utf8))
        }
        #expect(throws: SubscriptionTransferError.missingField(index: 1, field: .startDate)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"N","startDate":false}]"#).utf8))
        }
    }

    @Test func rejectsUnparsableIDsWithExactMessage() throws {
        let json = file(#"[{"id":"not-a-uuid","name":"N","startDate":"2026-01-02"}]"#)
        do {
            _ = try SubscriptionTransfer.decode(Data(json.utf8))
            Issue.record("Expected the id to be rejected")
        } catch let error as SubscriptionTransferError {
            #expect(error == .invalidID(index: 1, value: "not-a-uuid"))
            #expect(error.errorDescription == "Subscription 1 has an invalid id “not-a-uuid”.")
        }
    }

    @Test func rejectsEmptyNames() throws {
        #expect(throws: SubscriptionTransferError.emptyName(index: 1)) {
            try SubscriptionTransfer.decode(Data(self.file(#"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"   ","startDate":"2026-01-02"}]"#).utf8))
        }
    }

    @Test func rejectsStartDatesThatAreNotCalendarDays() throws {
        for date in ["2026-9-1", "26-09-01", "2026-09-1", "2026-02-30", "2026-09-31", "2026-13-01", "2026-00-10", "2026-09-00", "٢٠٢٦-٠٩-٠١", "2026-09-01T00:00:00Z"] {
            #expect(throws: SubscriptionTransferError.invalidStartDate(index: 1, value: date)) {
                try SubscriptionTransfer.decode(Data(self.file(
                    "[{\"id\":\"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41\",\"name\":\"N\",\"startDate\":\"\(date)\"}]"
                ).utf8))
            }
        }
    }

    @Test func rejectsDuplicateIDsRegardlessOfCase() throws {
        let json = file(
            #"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"First","startDate":"2026-01-02"},"#
            + #"{"id":"3f2c9a1e-6b7d-4c1a-9e0b-2d5f8a7c6b41","name":"Second","startDate":"2026-03-04"}]"#
        )
        do {
            _ = try SubscriptionTransfer.decode(Data(json.utf8))
            Issue.record("Expected the duplicate id to be rejected")
        } catch let error as SubscriptionTransferError {
            #expect(error == .duplicateID(first: 1, second: 2))
            #expect(error.errorDescription == "Subscriptions 1 and 2 have the same id.")
        }
    }

    @Test func stopsAtTheFirstBadRecord() throws {
        let json = file(
            #"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"Good","startDate":"2026-01-02"},"#
            + #"{"id":"0A0B0C0D-0E0F-4A1B-8C2D-3E4F5A6B7C8D","name":"","startDate":"2026-03-04"},"#
            + #"{"id":"nope","name":"Bad","startDate":"2026-05-06"}]"#
        )
        #expect(throws: SubscriptionTransferError.emptyName(index: 2)) {
            try SubscriptionTransfer.decode(Data(json.utf8))
        }
    }

    // MARK: - Lenient corners

    @Test func acceptsAnEmptyList() throws {
        let json = file("[]")
        #expect(try SubscriptionTransfer.decode(Data(json.utf8)) == [])
    }

    @Test func ignoresUnknownKeys() throws {
        let json = """
        {"format":"pl.glasek.subs","version":1,"color":"blue","subscriptions":[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"Netflix","startDate":"2026-08-22","color":"red"}]}
        """
        #expect(try SubscriptionTransfer.decode(Data(json.utf8)) == [netflix])
    }

    @Test func trimsRecordNames() throws {
        let json = file(#"[{"id":"3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41","name":"  Netflix \n","startDate":"2026-08-22"}]"#)
        #expect(try SubscriptionTransfer.decode(Data(json.utf8)) == [netflix])
    }

    @Test func dayRoundTripsThroughRealDates() throws {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!

        let day = CalendarDay(year: 2028, month: 2, day: 29)
        let date = try #require(day.date(calendar: warsaw))
        #expect(CalendarDay(date: date, calendar: warsaw) == day)
        // Midnight in the calendar's time zone, not an arbitrary hour.
        #expect(warsaw.isDate(date, equalTo: try #require(warsaw.date(from: DateComponents(year: 2028, month: 2, day: 29))), toGranularity: .second))
    }

    // MARK: - Helpers

    private func file(_ recordsJSON: String) -> String {
        #"{"format":"pl.glasek.subs","version":1,"subscriptions":\#(recordsJSON)}"#
    }
}
