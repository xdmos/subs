import Foundation
import SQLite3
import Testing
@testable import SubsCore

private struct SQLiteFailure: Error {
    let message: String
}

struct StoreMigrationTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    // legacy/default.store and new/pl.glasek.subs/subs.store under a fresh
    // temporary directory. Only the legacy directory is pre-created; the store
    // directory is the migration's job.
    private func makeLayout() throws -> (legacy: URL, store: URL, directory: URL) {
        let directory = try makeTemporaryDirectory()
        let legacy = directory.appending(path: "legacy/default.store")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = directory.appending(path: "new/pl.glasek.subs/subs.store")
        return (legacy, store, directory)
    }

    private func markerURL(for store: URL) -> URL {
        store.deletingLastPathComponent().appendingPathComponent(StoreMigration.markerFileName)
    }

    private func migratingFileLeftovers(in storeDirectory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path)
            .filter { $0.hasPrefix("subs.store.migrating-") }
    }

    private func snapshotDirectoryLeftovers(in storeDirectory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path)
            .filter { $0.hasPrefix("legacy-snapshot-") }
    }

    private func legacySidecar(of legacy: URL, suffix: String) -> URL {
        legacy.deletingLastPathComponent()
            .appendingPathComponent(legacy.lastPathComponent + suffix)
    }

    // Marks the store directory read-only; each caller restores 0o755 in its
    // own defer so cleanup can still remove the directory.
    private func makeStoreDirectoryReadOnly(_ storeDirectory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: storeDirectory.path)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - SQLite helpers

    private func openDatabase(at url: URL, readOnly: Bool = false) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags: Int32 = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw SQLiteFailure(message: "could not open \(url.path)")
        }
        return database
    }

    private func lastError(_ database: OpaquePointer) -> SQLiteFailure {
        SQLiteFailure(message: String(cString: sqlite3_errmsg(database)))
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError(database)
        }
        defer { sqlite3_finalize(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {   // e.g. PRAGMA journal_mode reports its result as a row
            code = sqlite3_step(statement)
        }
        if code != SQLITE_DONE {
            throw lastError(database)
        }
    }

    private func countRows(_ database: OpaquePointer, in table: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT count(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw lastError(database)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastError(database)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func createLegacyStore(
        at url: URL,
        subscriptionRows: Int? = nil,
        statements: [String] = []
    ) throws {
        let database = try openDatabase(at: url)
        defer { sqlite3_close_v2(database) }
        if let subscriptionRows {
            try execute(database, "CREATE TABLE \(StoreMigration.subscriptionTable)(Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)")
            for index in 1...subscriptionRows {
                try execute(
                    database,
                    "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (\(index), 'Subscription \(index)')"
                )
            }
        }
        for sql in statements {
            try execute(database, sql)
        }
    }

    // MARK: - Tests

    @Test func migratesRowsIncludingUncheckpointedWal() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        let wal = legacySidecar(of: legacy, suffix: "-wal")
        let shm = legacySidecar(of: legacy, suffix: "-shm")
        // Keep the writer open for the whole test: with autocheckpointing off,
        // the last row then lives only in the -wal file while migrating runs.
        let writer = try openDatabase(at: legacy)
        defer { sqlite3_close_v2(writer) }
        try execute(writer, "PRAGMA journal_mode = wal")
        try execute(writer, "PRAGMA wal_autocheckpoint = 0")
        try execute(writer, "CREATE TABLE \(StoreMigration.subscriptionTable)(Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)")
        try execute(writer, "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (1, 'A')")
        try execute(writer, "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (2, 'B')")
        try execute(writer, "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (3, 'C')")
        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: wal.path))
        #expect(FileManager.default.fileExists(atPath: shm.path))
        #expect((try Data(contentsOf: wal)).count > 0)
        let legacyBytes = try Data(contentsOf: legacy)
        let walBytes = try Data(contentsOf: wal)
        let shmBytes = try Data(contentsOf: shm)

        let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)

        #expect(outcome == .migrated)
        #expect(FileManager.default.fileExists(atPath: store.path))
        let copy = try openDatabase(at: store, readOnly: true)
        #expect(try countRows(copy, in: StoreMigration.subscriptionTable) == 3)
        sqlite3_close_v2(copy)
        #expect(FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try migratingFileLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try snapshotDirectoryLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        // Compare before the deferred close of the writer: closing it could
        // checkpoint the -wal file into the store file.
        #expect(try Data(contentsOf: legacy) == legacyBytes)
        #expect(try Data(contentsOf: wal) == walBytes)
        #expect(try Data(contentsOf: shm) == shmBytes)
    }

    @Test func noLegacyStoreWritesMarker() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }

        let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)

        #expect(outcome == .noLegacyStore)
        #expect(FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test func legacyWithoutSubscriptionTableIsIgnored() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try createLegacyStore(at: legacy, statements: ["CREATE TABLE ZOTHER (ID INTEGER)"])
        let legacyBytes = try Data(contentsOf: legacy)

        let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)

        #expect(outcome == .legacyNotSubs)
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try snapshotDirectoryLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try Data(contentsOf: legacy) == legacyBytes)
    }

    @Test func existingStoreSkipsMigration() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try FileManager.default.createDirectory(
            at: store.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let existingBytes = Data([0x5A])
        try existingBytes.write(to: store)
        try createLegacyStore(at: legacy, subscriptionRows: 2)
        let legacyBytes = try Data(contentsOf: legacy)

        let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)

        #expect(outcome == .alreadyDone)
        #expect(try Data(contentsOf: store) == existingBytes)
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try Data(contentsOf: legacy) == legacyBytes)
    }

    @Test func markerSkipsMigration() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try FileManager.default.createDirectory(
            at: store.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data().write(to: markerURL(for: store))
        try createLegacyStore(at: legacy, subscriptionRows: 2)

        let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)

        #expect(outcome == .alreadyDone)
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test func unreadableLegacyThrowsAndLeavesNothing() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        let garbage = Data((0 ..< 8192).map { _ in UInt8.random(in: .min ... .max) })
        try garbage.write(to: legacy)

        do {
            _ = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)
            Issue.record("Expected the migration to throw for a file that is not a database")
        } catch {
            #expect(error is StoreMigrationError)
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try migratingFileLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try snapshotDirectoryLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try Data(contentsOf: legacy) == garbage)
    }

    @Test func secondRunIsNoOp() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try createLegacyStore(at: legacy, subscriptionRows: 2)

        let first = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)
        #expect(first == .migrated)
        let copy = try openDatabase(at: store, readOnly: true)
        let rowsAfterFirst = try countRows(copy, in: StoreMigration.subscriptionTable)
        sqlite3_close_v2(copy)

        let second = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)
        #expect(second == .alreadyDone)

        let copyAgain = try openDatabase(at: store, readOnly: true)
        #expect(try countRows(copyAgain, in: StoreMigration.subscriptionTable) == rowsAfterFirst)
        sqlite3_close_v2(copyAgain)
    }

    // A marker that records "nothing to migrate" must never be written when
    // writing fails: an empty subs.store or a missing marker is recoverable,
    // but a wrongly remembered decision would hide the legacy data forever.
    @Test func markerWriteFailureThrowsWhenThereIsNoLegacyStore() throws {
        let (legacy, store, directory) = try makeLayout()
        let storeDirectory = store.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: storeDirectory.path)
            cleanup(directory)
        }
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try makeStoreDirectoryReadOnly(storeDirectory)

        do {
            _ = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)
            Issue.record("Expected the migration to throw when the marker cannot be written")
        } catch {
            // The throw is the point: without it the launch would end with a
            // marker that was never actually written.
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))
    }

    // A foreign store must be remembered as "nothing to migrate", but only
    // once the marker is really on disk: a throw here is retried on the next
    // launch, while a silently skipped marker would reclassify every time.
    @Test func markerWriteFailureThrowsForForeignLegacyStore() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try createLegacyStore(at: legacy, statements: ["CREATE TABLE ZOTHER (ID INTEGER)"])
        let legacyBytes = try Data(contentsOf: legacy)

        do {
            _ = try StoreMigration.migrateIfNeeded(
                legacyStoreURL: legacy,
                storeURL: store,
                fileManager: .default,
                writeMarker: { _ in throw SQLiteFailure(message: "marker write failed") }
            )
            Issue.record("Expected the migration to throw when the marker cannot be written")
        } catch {
            // The throw is the point: without it the launch would end with a
            // marker that was never actually written.
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try snapshotDirectoryLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try Data(contentsOf: legacy) == legacyBytes)
    }

    // After the rename the migrated store already exists, so a failed marker
    // write surfaces as an error but loses nothing: the next launch (or Try
    // Again) finds subs.store and opens the migrated data.
    @Test func markerWriteFailureAfterMigrationThrowsButKeepsStore() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        try createLegacyStore(at: legacy, subscriptionRows: 3)

        do {
            _ = try StoreMigration.migrateIfNeeded(
                legacyStoreURL: legacy,
                storeURL: store,
                fileManager: .default,
                writeMarker: { _ in throw SQLiteFailure(message: "marker write failed") }
            )
            Issue.record("Expected the migration to throw when the marker cannot be written")
        } catch {
            // The throw is the point; the migrated store below must survive.
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
        let copy = try openDatabase(at: store, readOnly: true)
        #expect(try countRows(copy, in: StoreMigration.subscriptionTable) == 3)
        sqlite3_close_v2(copy)
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))

        // A later call sees subs.store and keeps the migrated data.
        let second = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacy, storeURL: store)
        #expect(second == .alreadyDone)
    }

    // A writer that changes the source between the copy and the second
    // generation check makes the snapshot stale; the migration must notice
    // and retry with a fresh snapshot.
    @Test func sourceChangeDuringCopyRetriesAndSucceeds() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        // Keep the writer open for the whole test, like a concurrently
        // running other app would.
        let writer = try openDatabase(at: legacy)
        defer { sqlite3_close_v2(writer) }
        try execute(writer, "PRAGMA journal_mode = wal")
        try execute(writer, "PRAGMA wal_autocheckpoint = 0")
        try execute(writer, "CREATE TABLE \(StoreMigration.subscriptionTable)(Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)")
        for index in 1...3 {
            try execute(
                writer,
                "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (\(index), 'Subscription \(index)')"
            )
        }

        let outcome = try StoreMigration.migrateIfNeeded(
            legacyStoreURL: legacy,
            storeURL: store,
            fileManager: .default,
            afterSnapshotCopy: { attempt in
                // Grow the -wal only on the first attempt, after the files
                // were copied: the second generation check must fail and
                // force a retry that picks the new row up.
                if attempt == 1 {
                    try self.execute(
                        writer,
                        "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (4, 'Subscription 4')"
                    )
                }
            }
        )

        #expect(outcome == .migrated)
        let copy = try openDatabase(at: store, readOnly: true)
        #expect(try countRows(copy, in: StoreMigration.subscriptionTable) == 4)
        sqlite3_close_v2(copy)
    }

    // A source that changes during every attempt produces no consistent
    // snapshot, so nothing may be recorded: no store, no marker, no
    // leftovers — the next launch simply tries again.
    @Test func sourceThatKeepsChangingThrowsAndRecordsNothing() throws {
        let (legacy, store, directory) = try makeLayout()
        defer { cleanup(directory) }
        let writer = try openDatabase(at: legacy)
        defer { sqlite3_close_v2(writer) }
        try execute(writer, "PRAGMA journal_mode = wal")
        try execute(writer, "PRAGMA wal_autocheckpoint = 0")
        try execute(writer, "CREATE TABLE \(StoreMigration.subscriptionTable)(Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)")
        for index in 1...3 {
            try execute(
                writer,
                "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (\(index), 'Subscription \(index)')"
            )
        }

        do {
            _ = try StoreMigration.migrateIfNeeded(
                legacyStoreURL: legacy,
                storeURL: store,
                fileManager: .default,
                maxCopyAttempts: 3,
                afterSnapshotCopy: { attempt in
                    // Grow the -wal on every attempt: no snapshot is ever
                    // taken from an unchanged source.
                    try self.execute(
                        writer,
                        "INSERT INTO \(StoreMigration.subscriptionTable) (Z_PK, ZNAME) VALUES (\(3 + attempt), 'Extra \(attempt)')"
                    )
                }
            )
            Issue.record("Expected the migration to throw while the source keeps changing")
        } catch {
            #expect(error as? StoreMigrationError == .sourceChangedDuringCopy(attempts: 3))
        }
        #expect(!FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: markerURL(for: store).path))
        #expect(try migratingFileLeftovers(in: store.deletingLastPathComponent()).isEmpty)
        #expect(try snapshotDirectoryLeftovers(in: store.deletingLastPathComponent()).isEmpty)
    }
}
