//
//  StoreMigration.swift
//  subs
//

import Foundation
import SQLite3

/// What `StoreMigration.migrateIfNeeded` decided.
public enum StoreMigrationOutcome: Equatable, Sendable {
    case alreadyDone     // the new store or the marker already exists; nothing touched
    case noLegacyStore   // no legacy file; marker written
    case legacyNotSubs   // legacy file has no ZSUBSCRIPTION table; marker written
    case migrated        // rows copied into the new store; marker written
}

public enum StoreMigrationError: Error, LocalizedError, Equatable {
    case sqlite(operation: String, message: String)
    case verificationFailed(expectedRows: Int, copiedRows: Int)
    case sourceChangedDuringCopy(attempts: Int)

    public var errorDescription: String? {
        switch self {
        case let .sqlite(operation, message):
            "\(operation) failed: \(message)"
        case let .verificationFailed(expectedRows, copiedRows):
            "The copy has \(copiedRows) subscriptions instead of \(expectedRows)."
        case let .sourceChangedDuringCopy(attempts):
            "The previous data file kept changing while it was being copied (\(attempts) attempts). Close other apps that might use it and try again."
        }
    }
}

/// Copies the subscriptions from the legacy shared SwiftData store
/// ("default.store", which every non-sandboxed SwiftData app that sticks to
/// the defaults uses) into subs' own store file, exactly once. The legacy
/// files are first copied byte for byte into a private snapshot directory and
/// every SQLite operation (table check, row count, `VACUUM INTO`) runs on
/// that snapshot, so rows still living only in the -wal file come along and
/// the copy is a single consistent database.
///
/// Copying the database and its -wal are two separate operations, so the
/// snapshot is only trusted after a consistency check: the source files are
/// fingerprinted (existence, size, modification date) before and after the
/// copy, the copy is retried while the fingerprint keeps changing, and a
/// source that keeps changing fails with `.sourceChangedDuringCopy` without
/// recording anything. The -shm file is not copied at all: the snapshot is
/// opened by a single private connection, so SQLite rebuilds the WAL index
/// from the -wal alone.
///
/// Three guarantees:
/// 1. The legacy files (default.store, -wal, -shm) are only ever read
///    (default.store and -wal by `FileManager.copyItem` and for the
///    fingerprint): SQLite never opens them at all, and they are never
///    written to, moved, renamed or removed. Even `SQLITE_OPEN_READONLY`
///    would not be enough, because SQLite may update or rebuild the -shm WAL
///    index of a database it merely reads.
/// 2. `removeItem` is only ever applied to the snapshot directory and the
///    temporary copy this call created in the store directory
///    ("legacy-snapshot-<UUID>", "subs.store.migrating-<UUID>").
/// 3. Every marker write (.noLegacyStore, .legacyNotSubs, .migrated) throws
///    on failure, so the decision is retried on the next launch instead of
///    being remembered wrongly. The marker of a successful migration is
///    written after the rename, so subs.store already exists then: a retry
///    finds `.alreadyDone` and opens the migrated data — nothing is hidden.
public enum StoreMigration {
    public static let markerFileName = ".migrated-from-default-store"
    public static let subscriptionTable = "ZSUBSCRIPTION"

    @discardableResult
    public static func migrateIfNeeded(
        legacyStoreURL: URL,
        storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> StoreMigrationOutcome {
        // Every argument spelled out: a three-argument call would resolve
        // back to this overload instead of the testable one below.
        try migrateIfNeeded(
            legacyStoreURL: legacyStoreURL,
            storeURL: storeURL,
            fileManager: fileManager,
            maxCopyAttempts: 3,
            writeMarker: { try Data().write(to: $0, options: .atomic) },
            afterSnapshotCopy: { _ in }
        )
    }

    /// The testable core of `migrateIfNeeded`: `writeMarker` can be made to
    /// throw so a marker failure is observable, and `afterSnapshotCopy` runs
    /// after the legacy files were copied but before the source fingerprint
    /// is compared again, so a test can change the source in between.
    static func migrateIfNeeded(
        legacyStoreURL: URL,
        storeURL: URL,
        fileManager: FileManager,
        maxCopyAttempts: Int = 3,
        writeMarker: (URL) throws -> Void = { try Data().write(to: $0, options: .atomic) },
        afterSnapshotCopy: (Int) throws -> Void = { _ in }
    ) throws -> StoreMigrationOutcome {
        let directory = storeURL.deletingLastPathComponent()
        let marker = directory.appendingPathComponent(markerFileName)

        if fileManager.fileExists(atPath: marker.path) || fileManager.fileExists(atPath: storeURL.path) {
            return .alreadyDone
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            // A failed marker write must throw: with no marker, the next
            // launch simply re-examines the (absent) legacy file.
            try writeMarker(marker)
            return .noLegacyStore
        }

        // Byte-copy the legacy files and only ever let SQLite touch the copy:
        // even opened read-only, a WAL database can make SQLite write to its
        // -shm index, and the legacy files must not change at all. The -wal
        // is copied after the database, so the two copies are separate
        // operations; only a source whose fingerprint (see SourceGeneration)
        // did not change between the copy and the second comparison proves
        // the snapshot is one consistent instant. The -shm is never copied:
        // the snapshot gets a single private connection, so SQLite rebuilds
        // the WAL index from the -wal alone.
        let legacyDirectory = legacyStoreURL.deletingLastPathComponent()
        let legacyFileName = legacyStoreURL.lastPathComponent
        let legacyFiles = [
            legacyStoreURL,
            legacyDirectory.appendingPathComponent(legacyFileName + "-wal"),
        ]

        var snapshot: URL?
        defer {
            if let snapshot {
                try? fileManager.removeItem(at: snapshot)
            }
        }
        for attempt in 1...maxCopyAttempts {
            let candidate = directory.appendingPathComponent("legacy-snapshot-\(UUID().uuidString)", isDirectory: true)
            let generation = SourceGeneration(legacyStoreURL: legacyStoreURL, fileManager: fileManager)
            if let previous = snapshot {
                try? fileManager.removeItem(at: previous)
            }
            try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
            snapshot = candidate
            for legacyFile in legacyFiles where fileManager.fileExists(atPath: legacyFile.path) {
                try fileManager.copyItem(
                    at: legacyFile,
                    to: candidate.appendingPathComponent(legacyFile.lastPathComponent)
                )
            }
            try afterSnapshotCopy(attempt)
            if generation == SourceGeneration(legacyStoreURL: legacyStoreURL, fileManager: fileManager) {
                break
            }
            // The snapshot may be stale: drop it, so nothing below can use
            // it and the next attempt starts clean.
            try? fileManager.removeItem(at: candidate)
            snapshot = nil
        }
        guard let snapshot else {
            // The source kept changing for every attempt, so no snapshot was
            // ever consistent. Nothing is recorded — no marker, no store —
            // and the defer above removed the last attempt's snapshot.
            throw StoreMigrationError.sourceChangedDuringCopy(attempts: maxCopyAttempts)
        }

        // The snapshot is a private copy, so WAL recovery may write to it.
        var snapshotDatabase: OpaquePointer? = try openReadWrite(
            snapshot.appendingPathComponent(legacyFileName),
            operation: "Opening the previous data file"
        )
        defer { sqlite3_close_v2(snapshotDatabase) }

        // A file that is not a database fails here; a database without the
        // subscriptions table is somebody else's default store.
        let tableCount = try scalarInt(
            snapshotDatabase,
            sql: "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = '\(subscriptionTable)'",
            operation: "Reading the previous data file"
        )
        guard tableCount > 0 else {
            // Close first, then remember the decision — but only if the
            // marker write succeeds; otherwise retry on the next launch.
            sqlite3_close_v2(snapshotDatabase)
            snapshotDatabase = nil
            try writeMarker(marker)
            return .legacyNotSubs
        }

        let expectedRows = try scalarInt(
            snapshotDatabase,
            sql: "SELECT count(*) FROM \(subscriptionTable)",
            operation: "Reading the previous data file"
        )

        let temporary = directory.appendingPathComponent("subs.store.migrating-\(UUID().uuidString)")
        do {
            try run(snapshotDatabase, sql: "VACUUM INTO ?", operation: "Copying the previous data file") { statement in
                // SQLITE_TRANSIENT: SQLite copies the path bytes during the bind.
                sqlite3_bind_text(
                    statement, 1, temporary.path, Int32(temporary.path.utf8.count),
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        do {
            let copy = try openReadOnly(temporary, operation: "Verifying the copied data file")
            defer { sqlite3_close_v2(copy) }
            let copiedRows = try scalarInt(
                copy,
                sql: "SELECT count(*) FROM \(subscriptionTable)",
                operation: "Verifying the copied data file"
            )
            guard copiedRows == expectedRows else {
                throw StoreMigrationError.verificationFailed(expectedRows: Int(expectedRows), copiedRows: Int(copiedRows))
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        do {
            try fileManager.moveItem(at: temporary, to: storeURL)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        // Throwing here costs nothing: subs.store already exists, so the next
        // launch (or Try Again) returns .alreadyDone and opens the migrated
        // data. A silently missing marker would be just as harmless, but the
        // migration is only "remembered" once the marker is really on disk.
        try writeMarker(marker)
        return .migrated
    }

    // MARK: - Snapshot consistency

    /// What the legacy source looked like at one moment: existence, size and
    /// modification date of the database and its -wal, straight from
    /// `FileManager.attributesOfItem`. A missing -wal is a valid, comparable
    /// state. Two equal generations around a copy prove that no other process
    /// changed the source while it was being copied.
    private struct SourceGeneration: Equatable {
        private struct FileFingerprint: Equatable {
            let exists: Bool
            let size: Int?
            let modified: Date?

            init(_ url: URL, fileManager: FileManager) {
                if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
                    exists = true
                    size = attributes[.size] as? Int
                    modified = attributes[.modificationDate] as? Date
                } else {
                    exists = false
                    size = nil
                    modified = nil
                }
            }
        }

        private let database: FileFingerprint
        private let wal: FileFingerprint

        init(legacyStoreURL: URL, fileManager: FileManager) {
            database = FileFingerprint(legacyStoreURL, fileManager: fileManager)
            wal = FileFingerprint(
                legacyStoreURL.deletingLastPathComponent()
                    .appendingPathComponent(legacyStoreURL.lastPathComponent + "-wal"),
                fileManager: fileManager
            )
        }
    }

    // MARK: - SQLite helpers

    private static func openReadWrite(_ url: URL, operation: String) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "the file could not be opened"
            sqlite3_close_v2(database)
            throw StoreMigrationError.sqlite(operation: operation, message: message)
        }
        return database
    }

    private static func openReadOnly(_ url: URL, operation: String) throws -> OpaquePointer {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "the file could not be opened"
            sqlite3_close_v2(database)
            throw StoreMigrationError.sqlite(operation: operation, message: message)
        }
        return database
    }

    private static func scalarInt(_ database: OpaquePointer?, sql: String, operation: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError(operation, database)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(operation, database)
        }
        return sqlite3_column_int64(statement, 0)
    }

    private static func run(
        _ database: OpaquePointer?,
        sql: String,
        operation: String,
        bind: (OpaquePointer) -> Int32 = { _ in SQLITE_OK }
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError(operation, database)
        }
        defer { sqlite3_finalize(statement) }
        guard bind(statement) == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(operation, database)
        }
    }

    private static func sqliteError(_ operation: String, _ database: OpaquePointer?) -> StoreMigrationError {
        .sqlite(operation: operation, message: String(cString: sqlite3_errmsg(database)))
    }
}
