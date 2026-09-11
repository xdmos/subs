import Foundation
import Testing
@testable import SubsCore

/// Wraps the real file system and can be told to fail individual moves or
/// directory creation, recording every move attempted through it.
final class FaultyFileSystem: StoreFileSystem {
    enum Fault: Error, Equatable {
        case move
        case createDirectory
    }

    let real = LocalFileSystem()
    var failMoveWhen: (URL, URL) -> Bool   // (source, destination) -> should the move throw?
    var failCreateDirectory = false
    private(set) var moves: [(URL, URL)] = []

    init(
        failMoveWhen: @escaping (URL, URL) -> Bool = { _, _ in false },
        failCreateDirectory: Bool = false
    ) {
        self.failMoveWhen = failMoveWhen
        self.failCreateDirectory = failCreateDirectory
    }

    func fileExists(at url: URL) -> Bool {
        real.fileExists(at: url)
    }

    func createDirectory(at url: URL) throws {
        if failCreateDirectory {
            throw Fault.createDirectory
        }
        try real.createDirectory(at: url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moves.append((source, destination))
        if failMoveWhen(source, destination) {
            throw Fault.move
        }
        try real.moveItem(at: source, to: destination)
    }
}

struct StoreBackupTests {
    private let utc = TimeZone(identifier: "UTC")!

    // 2026-03-11 09:30:00 UTC, so the expected directory is "subs-backup-20260311-093000".
    private let fixedDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 9, minute: 30))!
    }()

    private var expectedBackupName: String {
        "subs-backup-20260311-093000"
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ bytes: [UInt8], to url: URL) throws {
        try Data(bytes).write(to: url)
    }

    private func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    @Test func movesAllFilesIntoTimestampedBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try write([0xA0], to: storeURL)
        try write([0xA1], to: directory.appendingPathComponent("default.store-wal"))
        try write([0xA2], to: directory.appendingPathComponent("default.store-shm"))
        let fileSystem = LocalFileSystem()

        let backup = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)

        #expect(backup == directory.appendingPathComponent(expectedBackupName, isDirectory: true))
        #expect(try read(backup.appendingPathComponent("default.store")) == Data([0xA0]))
        #expect(try read(backup.appendingPathComponent("default.store-wal")) == Data([0xA1]))
        #expect(try read(backup.appendingPathComponent("default.store-shm")) == Data([0xA2]))
        #expect(!fileSystem.fileExists(at: storeURL))
        #expect(!fileSystem.fileExists(at: directory.appendingPathComponent("default.store-wal")))
        #expect(!fileSystem.fileExists(at: directory.appendingPathComponent("default.store-shm")))
    }

    @Test func skipsMissingSidecars() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try write([0xB0], to: storeURL)
        let fileSystem = LocalFileSystem()

        let backup = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)

        #expect(backup == directory.appendingPathComponent(expectedBackupName, isDirectory: true))
        #expect(try read(backup.appendingPathComponent("default.store")) == Data([0xB0]))
        #expect(!fileSystem.fileExists(at: storeURL))
    }

    @Test func collisionAppendsNumericSuffix() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try write([0xC0], to: storeURL)
        let fileSystem = LocalFileSystem()
        try fileSystem.createDirectory(at: directory.appendingPathComponent(expectedBackupName))
        try fileSystem.createDirectory(at: directory.appendingPathComponent(expectedBackupName + "-2"))

        let backup = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)

        #expect(backup.lastPathComponent == expectedBackupName + "-3")
        #expect(try read(backup.appendingPathComponent("default.store")) == Data([0xC0]))
    }

    @Test func failureOnWalMoveRollsBackStore() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let walURL = directory.appendingPathComponent("default.store-wal")
        let shmURL = directory.appendingPathComponent("default.store-shm")
        try write([0xD0], to: storeURL)
        try write([0xD1], to: walURL)
        try write([0xD2], to: shmURL)
        let fileSystem = FaultyFileSystem { source, _ in
            source.lastPathComponent == "default.store-wal" && source.deletingLastPathComponent() == directory
        }

        do {
            _ = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)
            Issue.record("Expected moving the -wal file to fail")
        } catch let error as StoreBackupError {
            guard case let .moveFailed(underlying) = error else {
                Issue.record("Expected moveFailed, got \(error)")
                return
            }
            #expect(underlying is FaultyFileSystem.Fault)
        }
        #expect(try read(storeURL) == Data([0xD0]))
        #expect(try read(walURL) == Data([0xD1]))
        #expect(try read(shmURL) == Data([0xD2]))
    }

    @Test func failureOnShmMoveRollsBackStoreAndWal() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let walURL = directory.appendingPathComponent("default.store-wal")
        let shmURL = directory.appendingPathComponent("default.store-shm")
        try write([0xE0], to: storeURL)
        try write([0xE1], to: walURL)
        try write([0xE2], to: shmURL)
        let fileSystem = FaultyFileSystem { source, _ in
            source.lastPathComponent == "default.store-shm" && source.deletingLastPathComponent() == directory
        }

        do {
            _ = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)
            Issue.record("Expected moving the -shm file to fail")
        } catch let error as StoreBackupError {
            guard case .moveFailed = error else {
                Issue.record("Expected moveFailed, got \(error)")
                return
            }
        }
        #expect(try read(storeURL) == Data([0xE0]))
        #expect(try read(walURL) == Data([0xE1]))
        #expect(try read(shmURL) == Data([0xE2]))
    }

    @Test func rollbackFailureLeavesStoreInBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let shmURL = directory.appendingPathComponent("default.store-shm")
        try write([0xF0], to: storeURL)
        try write([0xF1], to: directory.appendingPathComponent("default.store-wal"))
        try write([0xF2], to: shmURL)
        // Fail moving the -shm file into the backup AND moving the -wal file back out,
        // so the rollback stops between them: store and -wal stay in the backup.
        let fileSystem = FaultyFileSystem { source, _ in
            let isInBackup = source.deletingLastPathComponent().lastPathComponent.hasPrefix(StoreBackup.directoryPrefix)
            if source.lastPathComponent == "default.store-shm" && !isInBackup { return true }
            if source.lastPathComponent == "default.store-wal" && isInBackup { return true }
            return false
        }

        do {
            _ = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)
            Issue.record("Expected the rollback to fail")
        } catch let error as StoreBackupError {
            guard case let .rollbackFailed(underlying, backupDirectory) = error else {
                Issue.record("Expected rollbackFailed, got \(error)")
                return
            }
            #expect(underlying is FaultyFileSystem.Fault)
            #expect(backupDirectory == directory.appendingPathComponent(expectedBackupName, isDirectory: true))
        }

        let backup = directory.appendingPathComponent(expectedBackupName, isDirectory: true)
        #expect(try read(backup.appendingPathComponent("default.store")) == Data([0xF0]))
        #expect(try read(backup.appendingPathComponent("default.store-wal")) == Data([0xF1]))
        #expect(try read(shmURL) == Data([0xF2]))
        #expect(StoreBackup.hasOrphanedSidecars(storeURL: storeURL, fileSystem: fileSystem))
    }

    @Test func directoryCreationFailureMovesNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try write([0xA0], to: storeURL)
        try write([0xA1], to: directory.appendingPathComponent("default.store-wal"))
        let fileSystem = FaultyFileSystem(failCreateDirectory: true)

        do {
            _ = try StoreBackup.moveToBackup(storeURL: storeURL, date: fixedDate, timeZone: utc, fileSystem: fileSystem)
            Issue.record("Expected creating the backup directory to fail")
        } catch {
            #expect(error as? FaultyFileSystem.Fault == .createDirectory)
        }
        #expect(try read(storeURL) == Data([0xA0]))
        #expect(try read(directory.appendingPathComponent("default.store-wal")) == Data([0xA1]))
        #expect(fileSystem.moves.isEmpty)
    }

    @Test func orphanDetection() throws {
        let directory = try makeTemporaryDirectory()
        defer { cleanup(directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let walURL = directory.appendingPathComponent("default.store-wal")
        let shmURL = directory.appendingPathComponent("default.store-shm")
        let fileSystem = LocalFileSystem()

        try write([0xA0], to: storeURL)
        try write([0xA1], to: walURL)
        try write([0xA2], to: shmURL)
        #expect(!StoreBackup.hasOrphanedSidecars(storeURL: storeURL, fileSystem: fileSystem))

        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.removeItem(at: walURL)
        try FileManager.default.removeItem(at: shmURL)
        #expect(!StoreBackup.hasOrphanedSidecars(storeURL: storeURL, fileSystem: fileSystem))

        try write([0xA1], to: walURL)
        #expect(StoreBackup.hasOrphanedSidecars(storeURL: storeURL, fileSystem: fileSystem))

        try FileManager.default.removeItem(at: walURL)
        try write([0xA2], to: shmURL)
        #expect(StoreBackup.hasOrphanedSidecars(storeURL: storeURL, fileSystem: fileSystem))
    }
}
