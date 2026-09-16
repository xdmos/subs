import Foundation
import Testing
@testable import SubsCore

struct CloudBackupArchiveTests {
    @Test func backupAndRestoreRoundTrip() throws {
        let fileSystem = MemorySnapshotFileSystem()
        let archive = CloudBackupArchive(
            store: CloudSnapshotStore(directoryURL: URL(filePath: "/cloud"), fileSystem: fileSystem)
        )
        let records = [sampleRecord]

        try archive.backup(records, at: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(try archive.restoreRecords() == records)
    }

    @Test func noSnapshotReturnsNil() throws {
        let archive = CloudBackupArchive(
            store: CloudSnapshotStore(
                directoryURL: URL(filePath: "/cloud"),
                fileSystem: MemorySnapshotFileSystem()
            )
        )

        #expect(try archive.restoreRecords() == nil)
    }

    @Test func corruptSnapshotIsRejected() throws {
        let fileSystem = MemorySnapshotFileSystem(data: Data("broken".utf8))
        let archive = CloudBackupArchive(
            store: CloudSnapshotStore(directoryURL: URL(filePath: "/cloud"), fileSystem: fileSystem)
        )

        #expect(throws: SubscriptionTransferError.notValidJSON) {
            try archive.restoreRecords()
        }
    }

    private var sampleRecord: SubscriptionRecord {
        SubscriptionRecord(
            id: UUID(uuidString: "3F2C9A1E-6B7D-4C1A-9E0B-2D5F8A7C6B41")!,
            name: "Netflix",
            startDay: CalendarDay(year: 2026, month: 8, day: 22)
        )
    }
}

private final class MemorySnapshotFileSystem: CloudSnapshotFileSystem, @unchecked Sendable {
    private var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func createDirectory(at url: URL) throws {}

    func read(upToCount count: Int, from url: URL) throws -> Data? {
        data.map { Data($0.prefix(count)) }
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        self.data = data
    }
}
