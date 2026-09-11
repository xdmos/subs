//
//  LoginItemController.swift
//  subs
//

import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemController {
    private(set) var isEnabled = false          // status == .enabled
    private(set) var requiresApproval = false   // status == .requiresApproval
    var errorMessage: String?                   // non-nil => alert is shown

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            requiresApproval = false
        @unknown default:
            // Never claim a state the system hasn't confirmed.
            isEnabled = false
            requiresApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        let status = SMAppService.mainApp.status

        if enabled {
            if status != .enabled {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else if status != .notRegistered && status != .notFound {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Always read back the real status, even after a failure.
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
