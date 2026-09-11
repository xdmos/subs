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

private struct SubscriptionEntry: Identifiable {
    let subscription: Subscription
    let cycle: SubscriptionCycle

    var id: UUID { subscription.id }
}

// MARK: - Header

private struct PanelHeader: View {
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

// MARK: - Card

private struct SubscriptionCard: View {
    let entry: SubscriptionEntry

    @State private var displayMode = CycleDisplayMode.remaining

    private var subscription: Subscription { entry.subscription }
    private var cycle: SubscriptionCycle { entry.cycle }

    private var isRenewingSoon: Bool { cycle.phase != .upcoming && cycle.remainingDays <= 3 }

    private var highlight: Color {
        switch displayMode {
        case .remaining: isRenewingSoon ? AppColors.warning : AppColors.accent
        case .elapsed: AppColors.elapsed
        }
    }

    var body: some View {
        Button {
            withAnimation(.snappy) {
                displayMode.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(displayMode.detail(for: cycle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }

                    Spacer(minLength: 8)

                    dayCounter
                }

                CycleProgressBar(
                    fraction: cycle.phase == .upcoming ? 0 : displayMode.fraction(for: cycle),
                    color: cycle.phase == .upcoming ? AppColors.accent : highlight
                )
            }
            .padding(14)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isRenewingSoon ? AppColors.warning.opacity(0.10) : .clear).interactive(),
            in: .rect(cornerRadius: 20)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityValue(cardAccessibilityValue)
        .accessibilityHint(cardAccessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private var dayCounter: some View {
        let isUpcoming = cycle.phase == .upcoming
        let count = isUpcoming ? cycle.daysUntilStart : displayMode.dayCount(for: cycle)

        return VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if showsRenewalToday {
                    Text("Today")
                        .font(.system(.title, design: .rounded).weight(.bold))
                } else {
                    Text(count, format: .number)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))

                    Text(count == 1 ? "day" : "days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isUpcoming ? AppColors.accent : highlight)

            Text(dayCounterCaption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .contentTransition(.opacity)
        }
    }

    // On the renewal day the cycle has run out, so the counter says "Today"
    // instead of a zero that would read like an expired subscription.
    private var showsRenewalToday: Bool {
        cycle.phase == .renewalDay && displayMode == .remaining
    }

    private var dayCounterCaption: String {
        switch cycle.phase {
        case .upcoming: "until start"
        case .renewalDay where displayMode == .remaining: "renews"
        case .active, .renewalDay: displayMode.title.lowercased()
        }
    }

    private var cardAccessibilityLabel: String {
        if cycle.phase == .upcoming {
            return "\(subscription.name), starts \(cycle.startDate.formatted(AppFormat.shortDate))"
        }
        return "\(subscription.name), \(displayMode.title)"
    }

    private var cardAccessibilityValue: String {
        switch cycle.phase {
        case .upcoming:
            return "\(dayText(cycle.daysUntilStart)) until start"
        case .renewalDay where displayMode == .remaining:
            return "Renews today"
        default:
            return dayText(displayMode.dayCount(for: cycle))
        }
    }

    private var cardAccessibilityHint: String {
        cycle.phase == .upcoming ? "" : "Shows \(displayMode.oppositeTitle.lowercased()) days"
    }

    private func dayText(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

private struct CycleProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
                    .shadow(color: color.opacity(0.5), radius: 4)
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: fraction)
        .accessibilityHidden(true)
    }
}

private enum CycleDisplayMode: Equatable {
    case remaining
    case elapsed

    var title: String {
        switch self {
        case .remaining: "Remaining"
        case .elapsed: "Elapsed"
        }
    }

    var oppositeTitle: String {
        switch self {
        case .remaining: "Elapsed"
        case .elapsed: "Remaining"
        }
    }

    mutating func toggle() {
        self = self == .remaining ? .elapsed : .remaining
    }

    func dayCount(for cycle: SubscriptionCycle) -> Int {
        switch self {
        case .remaining: cycle.remainingDays
        case .elapsed: cycle.elapsedDays
        }
    }

    func fraction(for cycle: SubscriptionCycle) -> Double {
        switch self {
        case .remaining: cycle.remainingFraction
        case .elapsed: cycle.elapsedFraction
        }
    }

    func detail(for cycle: SubscriptionCycle) -> String {
        if cycle.phase == .upcoming {
            return "Starts \(cycle.startDate.formatted(AppFormat.shortDate))"
        }
        if cycle.phase == .renewalDay && self == .remaining {
            return "Renews today"
        }
        switch self {
        case .remaining:
            return "Renews \(cycle.nextRenewal.formatted(AppFormat.shortDate))"
        case .elapsed:
            return "Cycle started \(cycle.cycleStart.formatted(AppFormat.shortDate))"
        }
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(AppColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .help("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppColors.warning.opacity(0.15)), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Delete confirmation

private struct DeleteConfirmationBanner: View {
    let name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "trash.fill")
                    .font(.body)
                    .foregroundStyle(AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete “\(name)”?")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text("This can’t be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)

                Button("Delete", role: .destructive, action: onConfirm)
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            }
            .controlSize(.regular)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppColors.warning.opacity(0.15)), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 64, height: 64)
                .glassEffect(.regular.tint(AppColors.accent.opacity(0.18)), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("No Subscriptions")
                    .font(.headline)

                Text("Add a name and a start date,\nand we’ll count the days to renewal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Add Subscription", systemImage: "plus", action: onAdd)
                .buttonStyle(.glassProminent)
                .tint(AppColors.accent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Add/Edit form

private enum FormMode {
    case add
    case edit(name: String, startDate: Date)
}

private struct SubscriptionFormView: View {
    @State private var name: String
    @State private var startDate: Date
    @FocusState private var isNameFocused: Bool

    let mode: FormMode
    let onCancel: () -> Void
    let onSave: (String, Date) -> Void
    let onDelete: (() -> Void)?

    init(
        mode: FormMode,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, Date) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.mode = mode
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _startDate = State(initialValue: .now)
        case .edit(let name, let startDate):
            _name = State(initialValue: name)
            _startDate = State(initialValue: startDate)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formTitle: String {
        switch mode {
        case .add: "New Subscription"
        case .edit: "Edit Subscription"
        }
    }

    private var confirmButtonTitle: String {
        switch mode {
        case .add: "Add"
        case .edit: "Save"
        }
    }

    // In edit mode saving is allowed only when something actually changed.
    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }

        guard case .edit(let originalName, let originalStartDate) = mode else { return true }
        return trimmedName != originalName
            || !Calendar.current.isDate(startDate, inSameDayAs: originalStartDate)
    }

    private var nextRenewal: Date {
        SubscriptionCycle(startDate: startDate).nextRenewal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(formTitle)
                .font(.headline)

            TextField("Name, e.g. Netflix", text: $name)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isNameFocused)
                .onSubmit(save)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isNameFocused ? AppColors.accent.opacity(0.7) : .white.opacity(0.10),
                            lineWidth: 1
                        )
                }

            HStack(spacing: 10) {
                Label("Start Date", systemImage: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                DatePicker(
                    "Start Date",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }

            Label {
                Text("Next renewal \(nextRenewal.formatted(AppFormat.longDate))")
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let onDelete {
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.glass)
                        .tint(.red)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)

                Button(confirmButtonTitle, action: save)
                    .buttonStyle(.glassProminent)
                    .tint(AppColors.accent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .defaultFocus($isNameFocused, true)
        .task {
            // Focus set during the insertion transition is dropped; wait for it to settle.
            try? await Task.sleep(for: .milliseconds(350))
            isNameFocused = true
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(trimmedName, startDate)
    }
}

// MARK: - Styling

private enum AppFormat {
    // The interface is English regardless of the system language; keep the user's region for date order.
    static let locale = Locale(languageCode: .english, languageRegion: Locale.current.region)
    static let shortDate = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
    static let longDate = Date.FormatStyle.dateTime.day().month(.wide).year().locale(locale)
}

private enum AppColors {
    static let accent = Color(red: 0.40, green: 0.66, blue: 1)
    static let elapsed = Color(red: 0.96, green: 0.70, blue: 0.18)
    static let warning = Color(red: 1.00, green: 0.45, blue: 0.35)
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
