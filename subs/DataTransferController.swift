//
//  DataTransferController.swift
//  subs
//

import AppKit
import Observation
import SubsCore
import SwiftData
import UniformTypeIdentifiers

/// Drives the JSON export/import for the app instance. It lives at the app
/// level because opening a file panel can close the menu bar panel: the
/// result must still be there when the user reopens it.
@MainActor
@Observable
final class DataTransferController {
    struct BannerAction: Equatable {
        let title: String
        let url: URL
    }

    enum Banner: Equatable {
        case success(title: String, message: String, action: BannerAction?)
        case failure(title: String, message: String)
    }

    struct PendingImport: Equatable {
        let fileName: String
        let records: [SubscriptionRecord]
        let currentCount: Int
    }

    var pendingImport: PendingImport?
    var banner: Banner?

    func exportJSON(container: ModelContainer) {
        do {
            let records = try SubscriptionLibrary.records(in: container)
            let data = try SubscriptionTransfer.encode(records, exportedAt: .now)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "subs-\(fileStamp()).json"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.title = "Export Subscriptions"
            panel.prompt = "Export"
            NSApp.activate()
            guard panel.runModal() == .OK, let url = panel.url else { return }

            try data.write(to: url, options: .atomic)
            banner = .success(
                title: countTitle("Exported", count: records.count),
                message: "Saved to “\(url.lastPathComponent)”.",
                action: BannerAction(title: "Show in Finder", url: url)
            )
        } catch {
            banner = .failure(title: "Couldn’t Export Subscriptions", message: error.localizedDescription)
        }
    }

    func chooseImportFile(container: ModelContainer) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Subscriptions"
        panel.prompt = "Choose"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            // The whole file is validated here, before any confirmation or
            // change, so a rejected file never reaches the store.
            let records = try SubscriptionTransfer.decode(contentsOf: url)
            let currentCount = try SubscriptionLibrary.records(in: container).count
            pendingImport = PendingImport(fileName: url.lastPathComponent, records: records, currentCount: currentCount)
        } catch {
            banner = .failure(title: "Couldn’t Import Subscriptions", message: error.localizedDescription)
        }
    }

    func chooseCloudRestore(container: ModelContainer, cloudBackup: CloudBackupController) {
        Task {
            do {
                guard let records = try await cloudBackup.loadRestoreRecords() else {
                    banner = .failure(title: "No iCloud Backup", message: "No subscriptions backup was found in iCloud.")
                    return
                }
                let currentCount = try SubscriptionLibrary.records(in: container).count
                pendingImport = PendingImport(
                    fileName: "iCloud backup",
                    records: records,
                    currentCount: currentCount
                )
            } catch {
                banner = .failure(title: "Couldn’t Restore from iCloud", message: error.localizedDescription)
            }
        }
    }

    @discardableResult
    func confirmImport(container: ModelContainer, backupDirectory: URL) -> Bool {
        guard let pending = pendingImport else { return false }
        do {
            let result = try SubscriptionLibrary.importReplacingAll(
                pending.records, in: container, backupDirectory: backupDirectory
            )
            pendingImport = nil
            banner = .success(
                title: countTitle("Imported", count: result.importedCount),
                message: "The previous list was saved to “\(result.backupURL.lastPathComponent)”.",
                action: BannerAction(title: "Show Backup", url: result.backupURL)
            )
            return true
        } catch let error as SubscriptionLibraryError {
            switch error {
            case let .backupFailed(underlying):
                failImport("Couldn’t save a copy of the current list, so nothing was changed. \(underlying.localizedDescription)")
            case let .replaceFailed(underlying):
                failImport("Nothing was changed. \(Self.saveMessage(for: underlying))")
            }
        } catch {
            failImport("Nothing was changed. \(Self.saveMessage(for: error))")
        }
        return false
    }

    func cancelImport() {
        pendingImport = nil
    }

    func dismissBanner() {
        banner = nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Same wording as save failures elsewhere in the panel.
    static func saveMessage(for error: Error) -> String {
        let nsError = error as NSError
        // SQLITE_FULL: the store could not grow.
        if nsError.domain == "NSSQLiteErrorDomain", nsError.code == 13 {
            return "Your disk is full. Free up some space and try again."
        }
        return error.localizedDescription
    }

    private func failImport(_ message: String) {
        pendingImport = nil
        banner = .failure(title: "Couldn’t Import Subscriptions", message: message)
    }

    private func countTitle(_ verb: String, count: Int) -> String {
        count == 1 ? "\(verb) 1 Subscription" : "\(verb) \(count) Subscriptions"
    }

    private func fileStamp() -> String {
        Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}
