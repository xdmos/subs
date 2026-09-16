import Foundation
import Observation
import SubsCore
import SwiftData

private actor CloudArchiveWorker {
    private let overrideRoot: URL?
    private var archive: CloudBackupArchive?

    init(overrideRoot: URL?) {
        self.overrideRoot = overrideRoot
    }

    func backup(_ records: [SubscriptionRecord]) throws {
        guard let archive = resolveArchive() else { throw CloudBackupError.iCloudUnavailable }
        try archive.backup(records)
    }

    func restoreRecords() throws -> [SubscriptionRecord]? {
        guard let archive = resolveArchive() else { throw CloudBackupError.iCloudUnavailable }
        return try archive.restoreRecords()
    }

    private func resolveArchive() -> CloudBackupArchive? {
        if let archive { return archive }
        // This actor never runs on the main thread. Apple's FileManager API may
        // take noticeable time while it establishes access to the container.
        guard let root = overrideRoot ?? FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let directory = root
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: "Backups", directoryHint: .isDirectory)
        let resolved = CloudBackupArchive(store: CloudSnapshotStore(directoryURL: directory))
        archive = resolved
        return resolved
    }
}

@MainActor
@Observable
final class CloudBackupController {
    private(set) var errorMessage: String?

    private let worker: CloudArchiveWorker
    private var pendingRecords: [SubscriptionRecord]?
    private var backupTask: Task<Void, Never>?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let overrideRoot: URL?
        #if DEBUG
        if let index = arguments.firstIndex(of: "-SubsICloudDirectory"), arguments.indices.contains(index + 1) {
            overrideRoot = URL(filePath: (arguments[index + 1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        } else {
            overrideRoot = nil
        }
        #else
        overrideRoot = nil
        #endif
        worker = CloudArchiveWorker(overrideRoot: overrideRoot)
    }

    func backup(container: ModelContainer) {
        do {
            pendingRecords = try SubscriptionLibrary.records(in: container)
            startBackupIfNeeded()
        } catch {
            errorMessage = "Couldn’t prepare the iCloud backup: \(error.localizedDescription)"
        }
    }

    func loadRestoreRecords() async throws -> [SubscriptionRecord]? {
        do {
            let records = try await worker.restoreRecords()
            errorMessage = nil
            return records
        } catch {
            errorMessage = "Couldn’t read the iCloud backup: \(error.localizedDescription)"
            throw error
        }
    }

    func reportRestoreFailure(_ error: Error) {
        errorMessage = "Couldn’t restore the iCloud backup: \(error.localizedDescription)"
    }

    func dismissError() {
        errorMessage = nil
    }

    private func startBackupIfNeeded() {
        guard backupTask == nil else { return }
        backupTask = Task { [weak self] in
            guard let self else { return }
            while let records = pendingRecords {
                pendingRecords = nil
                do {
                    try await worker.backup(records)
                    errorMessage = nil
                } catch {
                    errorMessage = "Couldn’t save the iCloud backup: \(error.localizedDescription)"
                }
            }
            backupTask = nil
        }
    }
}

enum CloudBackupError: LocalizedError {
    case iCloudUnavailable

    var errorDescription: String? {
        "iCloud Drive is unavailable. Sign in to iCloud and enable iCloud Drive to protect your subscriptions."
    }
}
