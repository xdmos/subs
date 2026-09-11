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
        case failed(details: String)     // error.localizedDescription of the last failure
    }

    private static let logger = Logger(subsystem: "pl.glasek.subs", category: "persistence")

    private(set) var state: State
    let storeURL: URL

    // Kept so startFresh() can reopen a store with the exact same schema and configuration.
    private let schema: Schema
    private let configuration: ModelConfiguration

    init() {
        let schema = Schema([Subscription.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.schema = schema
        self.configuration = configuration
        storeURL = configuration.url

        // A -wal or -shm file without the main store file means a previous relocation
        // never finished. Opening now could pair a fresh database with the old sidecars,
        // so report it and touch nothing instead.
        if StoreBackup.hasOrphanedSidecars(storeURL: storeURL) {
            Self.logger.error("Leftover database files without the main data file at \(self.storeURL.path, privacy: .public)")
            state = .failed(details: "Leftover database files were found without the main data file. Nothing was opened or changed.")
            return
        }

        do {
            state = .ready(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            Self.logger.error("Failed to open the store: \(String(describing: error), privacy: .public)")
            state = .failed(details: error.localizedDescription)
        }
    }

    /// Moves the unreadable store files into a backup folder next to them and opens a new
    /// empty store. Files are only ever moved, never deleted: this code must not be able to
    /// destroy user data, and the move happens only after the user confirms it. A move that
    /// fails part-way is rolled back, so the store is never left half-moved.
    func startFresh() {
        // Never touch a store that opened fine.
        guard case .failed = state else { return }

        do {
            try StoreBackup.moveToBackup(storeURL: storeURL)
        } catch {
            Self.logger.error("Failed to move the store files to the backup folder: \(String(describing: error), privacy: .public)")
            state = .failed(details: "Couldn’t move the data file to a backup folder: \(error.localizedDescription)")
            return
        }

        do {
            state = .ready(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            Self.logger.error("Failed to open a fresh store: \(String(describing: error), privacy: .public)")
            state = .failed(details: error.localizedDescription)
        }
    }

    func revealStoreInFinder() {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        } else {
            NSWorkspace.shared.open(storeURL.deletingLastPathComponent())
        }
    }
}
