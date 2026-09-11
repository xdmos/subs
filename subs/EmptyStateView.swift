//
//  EmptyStateView.swift
//  subs
//

import SwiftUI

// MARK: - Empty state

struct EmptyStateView: View {
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
