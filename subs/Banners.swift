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
