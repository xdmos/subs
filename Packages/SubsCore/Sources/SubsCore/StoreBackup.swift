//
//  StoreBackup.swift
//  subs
//

import Foundation

/// The handful of file operations the store relocation needs, so tests can
/// inject faults. Every implementation must only move and create: there is no
/// way to delete or overwrite a store file through this protocol.
public protocol StoreFileSystem {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
}

/// The real file system, backed by `FileManager.default`.
public struct LocalFileSystem: StoreFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

public enum StoreBackupError: Error, LocalizedError {
    /// A move failed and every file already moved was moved back. The (empty)
    /// backup directory may remain.
    case moveFailed(underlying: any Error)
    /// A move failed and moving files back also failed. Some files remain in
    /// `backupDirectory`.
    case rollbackFailed(underlying: any Error, backupDirectory: URL)

    public var errorDescription: String? {
        switch self {
        case let .moveFailed(underlying):
            underlying.localizedDescription
        case let .rollbackFailed(underlying, backupDirectory):
            "Some files couldn’t be moved back and are in “\(backupDirectory.lastPathComponent)”: \(underlying.localizedDescription)"
        }
    }
}

public enum StoreBackup {
    public static let directoryPrefix = "subs-backup-"

    /// [store, store + "-wal", store + "-shm"] in the store's directory, in this order.
    public static func storeFileURLs(for storeURL: URL) -> [URL] {
        let directory = storeURL.deletingLastPathComponent()
        let fileName = storeURL.lastPathComponent
        return ["", "-wal", "-shm"].map { directory.appendingPathComponent(fileName + $0) }
    }

    /// true when the main store file is missing but its -wal or -shm file exists.
    /// Opening a store in that state could pair a new database with the old
    /// sidecars, so callers must refuse instead.
    public static func hasOrphanedSidecars(
        storeURL: URL,
        fileSystem: any StoreFileSystem = LocalFileSystem()
    ) -> Bool {
        guard !fileSystem.fileExists(at: storeURL) else { return false }
        return storeFileURLs(for: storeURL).dropFirst().contains { fileSystem.fileExists(at: $0) }
    }

    /// "<store directory>/subs-backup-yyyyMMdd-HHmmss", then "-2", "-3", ... while that
    /// name exists.
    public static func makeBackupDirectoryURL(
        for storeURL: URL,
        date: Date,
        timeZone: TimeZone,
        fileSystem: any StoreFileSystem
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)

        let directory = storeURL.deletingLastPathComponent()
        var backupDirectory = directory.appendingPathComponent(directoryPrefix + stamp, isDirectory: true)
        var suffix = 2
        while fileSystem.fileExists(at: backupDirectory) {
            backupDirectory = directory.appendingPathComponent("\(directoryPrefix)\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return backupDirectory
    }

    /// Creates the backup directory and moves every EXISTING file of
    /// `storeFileURLs(for:)` into it (same file names), in order store, -wal, -shm.
    /// Returns the backup directory.
    ///
    /// Files are only ever moved, never deleted: a failed move is rolled back
    /// in reverse order, so the store is never left half-moved. If
    /// `rollbackFailed` is thrown, the main store file is not back at its
    /// original path while a sidecar moved after it is still there — the
    /// rollback stops at the first failure — so the original location shows up
    /// as `hasOrphanedSidecars(...)` (unless the failing file was the store
    /// itself, but then nothing had been moved before it and the error is
    /// `moveFailed`).
    @discardableResult
    public static func moveToBackup(
        storeURL: URL,
        date: Date = .now,
        timeZone: TimeZone = .current,
        fileSystem: any StoreFileSystem = LocalFileSystem()
    ) throws -> URL {
        let backup = makeBackupDirectoryURL(for: storeURL, date: date, timeZone: timeZone, fileSystem: fileSystem)
        // Nothing has been moved yet, so a failure here is rethrown unchanged.
        try fileSystem.createDirectory(at: backup)

        var moved: [(original: URL, backup: URL)] = []
        for url in storeFileURLs(for: storeURL) where fileSystem.fileExists(at: url) {
            do {
                let destination = backup.appendingPathComponent(url.lastPathComponent)
                try fileSystem.moveItem(at: url, to: destination)
                moved.append((original: url, backup: destination))
            } catch let moveError {
                // Roll back in reverse order. Stop at the FIRST rollback failure: never
                // move the main store file back while a sidecar that belongs to it is
                // still in the backup, so the store is never left beside mismatched
                // sidecars (see the invariant in the doc comment above).
                for pair in moved.reversed() {
                    do {
                        try fileSystem.moveItem(at: pair.backup, to: pair.original)
                    } catch {
                        throw StoreBackupError.rollbackFailed(underlying: moveError, backupDirectory: backup)
                    }
                }
                throw StoreBackupError.moveFailed(underlying: moveError)
            }
        }
        return backup
    }
}
