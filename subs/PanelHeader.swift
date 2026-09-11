//
//  PanelHeader.swift
//  subs
//

import AppKit
import SubsCore
import SwiftUI

// MARK: - Header

struct PanelHeader: View {
    let nearest: SubscriptionEntry?
    let count: Int
    let isShowingForm: Bool
    let onToggleAdd: () -> Void
    let loginItem: LoginItemController

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Subscriptions")
                    .font(.title3.weight(.bold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 8) {
                headerButtons
            }
        }
        .padding(.horizontal, 4)
    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            Button(
                isShowingForm ? "Close Form" : "Add Subscription",
                systemImage: isShowingForm ? "xmark" : "plus",
                action: onToggleAdd
            )
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .keyboardShortcut("n", modifiers: .command)
            .help(isShowingForm ? "Cancel" : "Add Subscription (⌘N)")

            Menu {
                Button("Add Subscription", systemImage: "plus", action: onToggleAdd)
                    .disabled(isShowingForm)

                Divider()

                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))

                if loginItem.requiresApproval {
                    Button("Approve in System Settings…", systemImage: "exclamationmark.triangle") {
                        loginItem.openLoginItemsSettings()
                    }
                }

                Divider()

                Button("Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("More")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }

    private var subtitle: String {
        guard let nearest else { return "Track renewals every 30 days" }

        let cycle = nearest.cycle
        let days = cycle.daysUntilNextEvent
        let name = nearest.subscription.name

        if count == 1 {
            switch cycle.phase {
            case .renewalDay:
                return "Renews today"
            case .active:
                return days == 1 ? "Renews tomorrow" : "Renews in \(days) days"
            case .upcoming:
                return days == 1 ? "Starts tomorrow" : "Starts in \(days) days"
            }
        }

        switch cycle.phase {
        case .renewalDay:
            return "Next: \(name) renews today"
        case .active:
            return "Next: \(name) \(days == 1 ? "tomorrow" : "in \(days) days")"
        case .upcoming:
            return "Next: \(name) \(days == 1 ? "starts tomorrow" : "starts in \(days) days")"
        }
    }
}
