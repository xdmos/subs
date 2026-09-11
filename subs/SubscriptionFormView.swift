//
//  SubscriptionFormView.swift
//  subs
//

import SubsCore
import SwiftUI

// MARK: - Add/Edit form

enum FormMode {
    case add
    case edit(name: String, startDate: Date)
}

struct SubscriptionFormView: View {
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
