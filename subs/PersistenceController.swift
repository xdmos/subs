//
//  PersistenceController.swift
//  subs
//

import AppKit
import Foundation
import Observation
import OSLog
import SubsCore
import SwiftData

@MainActor
@Observable
final class PersistenceController {
    enum State {
        case ready(ModelContainer)
        case failed(details: String)            // the subs store can't be used; Start Fresh is offered
        case migrationFailed(details: String)   // copying from the legacy store failed; Start Fresh is NOT offered
    }

    private static let logger = Logger(subsystem: "pl.glasek.subs", category: "persistence")

    private(set) var state: State
    let storeURL: URL
    let legacyStoreURL: URL

    /// Where the pre-import copies of the data live: "Import Backups" next to
    /// the store file, outside the "subs-backup-*" folders of Start Fresh.
    var importBackupDirectory: URL {
        storeURL.deletingLastPathComponent()
            .appending(path: "Import Backups", directoryHint: .isDirectory)
    }

    // Kept so startFresh() can reopen a store with the exact same schema and configuration.
    private let schema: Schema
    private let configuration: ModelConfiguration

    init() {
        let schema = Schema([Subscription.self])
        // SwiftData's default configuration stores data in the shared
        // "default.store", which every non-sandboxed SwiftData app that sticks
        // to the defaults uses. Give subs its own store file instead; on first
        // launch the subscriptions are copied over from the legacy file, which
        // is left untouched.
        let applicationSupport = Self.applicationSupportDirectory()
        let storeDirectory = applicationSupport.appending(path: "pl.glasek.subs", directoryHint: .isDirectory)
        storeURL = storeDirectory.appending(path: "subs.store")
        legacyStoreURL = applicationSupport.appending(path: "default.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        self.schema = schema
        self.configuration = configuration

        // load() always replaces this synchronously before init returns.
        state = .failed(details: "")
        load()
    }

    private static func applicationSupportDirectory() -> URL {
        #if DEBUG
        // "-SubsDataDirectory <path>" on the command line (open ... --args)
        // replaces Application Support, so a debug build — and the automated
        // checks driving it — never touches the user's real data. Everything
        // (store, migration marker, legacy file, Import Backups) is derived
        // from this one root.
        if let path = UserDefaults.standard.string(forKey: "SubsDataDirectory") {
            return URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        #endif
        return URL.applicationSupportDirectory
    }

    private func load() {
        // A -wal or -shm file without the main store file means a previous relocation
        // never finished. Opening now could pair a fresh database with the old sidecars,
        // so report it and touch nothing instead.
        if StoreBackup.hasOrphanedSidecars(storeURL: storeURL) {
            Self.logger.error("Leftover database files without the main data file at \(self.storeURL.path, privacy: .public)")
            state = .failed(details: "Leftover database files were found without the main data file. Nothing was opened or changed.")
            return
        }

        do {
            let outcome = try StoreMigration.migrateIfNeeded(legacyStoreURL: legacyStoreURL, storeURL: storeURL)
            Self.logger.info("Store migration outcome: \(String(describing: outcome), privacy: .public)")
        } catch {
            // Never open a container after a failed migration: an empty new store
            // would make the next launch skip the migration and hide the user's data.
            Self.logger.error("Failed to copy the subscriptions from the previous data file: \(String(describing: error), privacy: .public)")
            state = .migrationFailed(details: "Couldn’t copy your subscriptions from the previous data file: \(error.localizedDescription)")
            return
        }

        do {
            state = .ready(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            Self.logger.error("Failed to open the store: \(String(describing: error), privacy: .public)")
            state = .failed(details: error.localizedDescription)
        }
    }

    /// Moves the unreadable store files into a backup folder next to them and runs the
    /// normal launch sequence on the emptied spot. Files are only ever moved, never
    /// deleted: this code must not be able to destroy user data, and the move happens
    /// only after the user confirms it. A move that fails part-way is rolled back, so
    /// the store is never left half-moved. The fresh start still honours the one-time
    /// migration, so it can never hide subscriptions that only exist in the legacy file.
    func startFresh() {
        // Never touch a store that opened fine, and never touch anything after
        // a failed migration: the subscriptions still live only in the legacy
        // file, and an empty new store would hide them.
        guard case .failed = state else { return }

        do {
            try StoreBackup.moveToBackup(storeURL: storeURL)
        } catch {
            Self.logger.error("Failed to move the store files to the backup folder: \(String(describing: error), privacy: .public)")
            state = .failed(details: "Couldn’t move the data file to a backup folder: \(error.localizedDescription)")
            return
        }

        // The normal launch sequence, not a directly opened container: the
        // orphan guard and the one-time migration still decide what may be
        // opened, so subscriptions that only live in the legacy file are
        // migrated instead of being left behind an empty new store.
        load()
    }

    /// Runs the launch sequence again after a failed migration. The legacy
    /// files are only ever read, so a retry can succeed or fail again — it can
    /// never lose data.
    func retryMigration() {
        guard case .migrationFailed = state else { return }
        load()
    }

    func revealStoreInFinder() {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        } else {
            NSWorkspace.shared.open(storeURL.deletingLastPathComponent())
        }
    }

    func revealLegacyStoreInFinder() {
        if FileManager.default.fileExists(atPath: legacyStoreURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([legacyStoreURL])
        } else {
            NSWorkspace.shared.open(legacyStoreURL.deletingLastPathComponent())
        }
    }
}
