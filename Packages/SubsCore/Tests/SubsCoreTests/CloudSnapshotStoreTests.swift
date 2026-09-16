import Foundation
import Testing
@testable import SubsCore

struct CloudSnapshotStoreTests {
    @Test func writesAndReadsSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSnapshotStore(directoryURL: directory)
        let expected = Data("snapshot".utf8)

        try store.write(expected)

        #expect(try store.read() == expected)
    }

    @Test func missingSnapshotReturnsNil() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try CloudSnapshotStore(directoryURL: directory).read() == nil)
    }

    @Test func oversizedSnapshotIsRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CloudSnapshotStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: SubscriptionTransfer.maxFileSize + 1).write(to: store.snapshotURL)

        #expect(throws: SubscriptionTransferError.fileTooLarge) {
            try store.read()
        }
    }

    @Test func failedAtomicWritePreservesPreviousSnapshot() throws {
        let fileSystem = FailingWriteFileSystem(existing: Data("previous".utf8))
        let store = CloudSnapshotStore(
            directoryURL: URL(filePath: "/virtual/Backups", directoryHint: .isDirectory),
            fileSystem: fileSystem
        )

        #expect(throws: FailingWriteFileSystem.Failure.self) {
            try store.write(Data("new".utf8))
        }
        #expect(try store.read() == Data("previous".utf8))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "subs-cloud-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private final class FailingWriteFileSystem: CloudSnapshotFileSystem, @unchecked Sendable {
    enum Failure: Error { case expected }

    private var data: Data?

    init(existing: Data?) {
        data = existing
    }

    func createDirectory(at url: URL) throws {}

    func read(upToCount count: Int, from url: URL) throws -> Data? {
        data.map { Data($0.prefix(count)) }
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        throw Failure.expected
    }
}
