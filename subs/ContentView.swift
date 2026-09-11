//
//  ContentView.swift
//  subs
//

import AppKit
import SubsCore
import SwiftData
import SwiftUI

private enum PanelRoute: Equatable {
    case list
    case add
    case edit(Subscription)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subscription.startDate, order: .reverse) private var subscriptions: [Subscription]

    @State private var route: PanelRoute = .list
    @State private var persistenceErrorMessage: String?
    @State private var pendingDeletion: Subscription?
    @State private var loginItem = LoginItemController()

    private var isShowingForm: Bool { route != .list }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let entries = sortedEntries(at: context.date)

            // No GlassEffectContainer around the list: the container draws glass
            // itself, which escapes the ScrollView's clipping while scrolling.
            VStack(spacing: 14) {
                PanelHeader(
                    nearest: entries.first,
                    count: entries.count,
                    isShowingForm: isShowingForm,
                    onToggleAdd: toggleForm,
                    loginItem: loginItem
                )

                // Errors are shown inside the panel: an alert opens its own window,
                // and clicking it dismisses the menu bar panel instead of the alert.
                if let message = persistenceErrorMessage {
                    ErrorBanner(title: "Couldn’t Save Changes", message: message) {
                        withAnimation(.smooth(duration: 0.3)) { persistenceErrorMessage = nil }
                    }
                    .transition(.blurReplace)
                }

                if let message = loginItem.errorMessage {
                    ErrorBanner(title: "Couldn’t Change Login Item", message: message) {
                        withAnimation(.smooth(duration: 0.3)) { loginItem.errorMessage = nil }
                    }
                    .transition(.blurReplace)
                }

                if let subscription = pendingDeletion {
                    DeleteConfirmationBanner(
                        name: subscription.name,
                        onCancel: cancelDeletion,
                        onConfirm: { confirmDeletion(subscription) }
                    )
                    .transition(.blurReplace)
                }

                switch route {
                case .add:
                    SubscriptionFormView(
                        mode: .add,
                        onCancel: hideForm,
                        onSave: addSubscription,
                        onDelete: nil
                    )
                    .id("add")
                    .transition(.blurReplace)
                case .edit(let subscription):
                    SubscriptionFormView(
                        mode: .edit(name: subscription.name, startDate: subscription.startDate),
                        onCancel: hideForm,
                        onSave: { name, startDate in
                            updateSubscription(subscription, name: name, startDate: startDate)
                        },
                        onDelete: { requestDeletion(subscription) }
                    )
                    .id(subscription.id.uuidString)
                    .transition(.blurReplace)
                case .list:
                    if entries.isEmpty {
                        EmptyStateView(onAdd: showAddForm)
                            .transition(.blurReplace)
                    } else {
                        subscriptionList(entries)
                            .transition(.blurReplace)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 340)
        .environment(\.locale, AppFormat.locale)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginItem.refresh()
        }
        .onChange(of: route) {
            persistenceErrorMessage = nil
            pendingDeletion = nil
        }
    }

    private func subscriptionList(_ entries: [SubscriptionEntry]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    SubscriptionCard(entry: entry)
                        .contextMenu {
                            Button("Edit…", systemImage: "pencil") {
                                editSubscription(entry.subscription)
                            }

                            Divider()

                            Button("Delete", systemImage: "trash", role: .destructive) {
                                requestDeletion(entry.subscription)
                            }
                        }
                        .help("Click to switch the view · Right-click to edit or delete")
                }
            }
        }
        .scrollIndicators(.never)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sortedEntries(at date: Date) -> [SubscriptionEntry] {
        subscriptions
            .map { SubscriptionEntry(subscription: $0, cycle: SubscriptionCycle(startDate: $0.startDate, now: date)) }
            .sorted { lhs, rhs in
                if lhs.cycle.daysUntilNextEvent != rhs.cycle.daysUntilNextEvent {
                    return lhs.cycle.daysUntilNextEvent < rhs.cycle.daysUntilNextEvent
                }
                return lhs.subscription.name.localizedStandardCompare(rhs.subscription.name) == .orderedAscending
            }
    }

    private func addSubscription(name: String, startDate: Date) {
        let normalizedStartDate = Calendar.current.startOfDay(for: startDate)
        modelContext.insert(Subscription(name: name, startDate: normalizedStartDate))
        if saveChanges() {
            hideForm()
        }
    }

    private func updateSubscription(_ subscription: Subscription, name: String, startDate: Date) {
        subscription.name = name
        subscription.startDate = Calendar.current.startOfDay(for: startDate)
        if saveChanges() {
            hideForm()
        }
    }

    private func toggleForm() {
        withAnimation(.smooth(duration: 0.3)) {
            route = route == .list ? .add : .list
        }
    }

    private func showAddForm() {
        withAnimation(.smooth(duration: 0.3)) {
            route = .add
        }
    }

    private func editSubscription(_ subscription: Subscription) {
        withAnimation(.smooth(duration: 0.3)) {
            route = .edit(subscription)
        }
    }

    private func hideForm() {
        withAnimation(.smooth(duration: 0.3)) {
            route = .list
        }
    }

    private func requestDeletion(_ subscription: Subscription) {
        withAnimation(.smooth(duration: 0.3)) {
            pendingDeletion = subscription
        }
    }

    private func cancelDeletion() {
        withAnimation(.smooth(duration: 0.3)) {
            pendingDeletion = nil
        }
    }

    private func confirmDeletion(_ subscription: Subscription) {
        // Clear the request first, so the banner never renders a deleted model.
        withAnimation(.smooth(duration: 0.3)) {
            pendingDeletion = nil
        }
        if route == .edit(subscription) {
            deleteEditedSubscription(subscription)
        } else {
            deleteSubscription(subscription)
        }
    }

    private func deleteSubscription(_ subscription: Subscription) {
        withAnimation(.smooth(duration: 0.3)) {
            modelContext.delete(subscription)
        }
        saveChanges()
    }

    private func deleteEditedSubscription(_ subscription: Subscription) {
        modelContext.delete(subscription)
        // Leave the form in the same update as a successful save, so it never
        // renders a deleted model; a failed save restores the model and keeps the form.
        if saveChanges() {
            hideForm()
        }
    }

    /// Saves pending changes. On failure the unsaved changes are rolled back, so the
    /// list keeps showing what is actually stored, and the error is presented.
    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            persistenceErrorMessage = nil
            return true
        } catch {
            modelContext.rollback()
            withAnimation(.smooth(duration: 0.3)) {
                persistenceErrorMessage = Self.message(for: error)
            }
            return false
        }
    }

    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        // SQLITE_FULL: the store could not grow.
        if nsError.domain == "NSSQLiteErrorDomain", nsError.code == 13 {
            return "Your disk is full. Free up some space and try again."
        }
        return error.localizedDescription
    }
}

struct SubscriptionEntry: Identifiable {
    let subscription: Subscription
    let cycle: SubscriptionCycle

    var id: UUID { subscription.id }
}

#Preview("List") {
    let container = try! ModelContainer(
        for: Subscription.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let starts = [-4, -17, -28]
    let names = ["Netflix", "Spotify", "iCloud+"]

    for (name, offset) in zip(names, starts) {
        let startDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        container.mainContext.insert(Subscription(name: name, startDate: startDate))
    }

    return ContentView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}

#Preview("Empty List") {
    ContentView()
        .modelContainer(for: Subscription.self, inMemory: true)
        .preferredColorScheme(.dark)
}
