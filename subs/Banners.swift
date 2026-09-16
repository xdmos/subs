//
//  Banners.swift
//  subs
//

import SwiftUI

// MARK: - Error banner

struct ErrorBanner: View {
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

// MARK: - Success banner

struct SuccessBanner: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .padding(.top, 4)
                }
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
        .glassEffect(.regular.tint(AppColors.accent.opacity(0.15)), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Import confirmation

struct ImportConfirmationBanner: View {
    let currentCount: Int
    let incomingCount: Int
    let fileName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var summary: String {
        let subscriptions = incomingCount == 1 ? "1 subscription" : "\(incomingCount) subscriptions"

        if currentCount == 0 {
            return "\(subscriptions) from “\(fileName)” will be added. A copy of the current list is saved first."
        }
        if incomingCount == 0 {
            return "Your \(currentCount) subscriptions will be removed, because “\(fileName)” has none. A copy of the current list is saved first."
        }
        return "Your \(currentCount) subscriptions will be replaced with \(incomingCount) from “\(fileName)”. A copy of the current list is saved first."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.body)
                    .foregroundStyle(AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Replace All Subscriptions?")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)

                Button("Replace", role: .destructive, action: onConfirm)
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

// MARK: - Delete confirmation

struct DeleteConfirmationBanner: View {
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
