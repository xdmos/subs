//
//  StoreErrorView.swift
//  subs
//

import AppKit
import SwiftUI

struct StoreErrorView: View {
    enum Recovery {
        case startFresh      // the subs data file can't be used; a new empty store is offered
        case retryMigration  // copying from the previous data file failed; it hasn't been changed
    }

    let details: String
    let recovery: Recovery
    let persistence: PersistenceController

    @State private var isConfirmingStartFresh = false

    var body: some View {
        Group {
            switch recovery {
            case .startFresh:
                startFreshContent
            case .retryMigration:
                retryMigrationContent
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .frame(width: 340)
        .padding(14)
    }

    // The subs data file itself is unreadable, so starting fresh is safe: it
    // only ever moves the unreadable files into a backup folder.
    private var startFreshContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn’t Open Your Subscriptions")
                        .font(.headline)

                    Text("The data file can’t be read, so the list can’t be shown.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isConfirmingStartFresh {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Start with an empty list? The current data file will be moved to a backup folder next to it, not deleted.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Spacer()

                        Button("Cancel") {
                            withAnimation(.smooth(duration: 0.3)) { isConfirmingStartFresh = false }
                        }
                        .buttonStyle(.glass)

                        Button("Start Fresh", role: .destructive) {
                            persistence.startFresh()
                            isConfirmingStartFresh = false
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    }
                    .controlSize(.regular)
                }
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Button("Show in Finder") {
                        persistence.revealStoreInFinder()
                    }
                    .buttonStyle(.glass)

                    Button("Start Fresh") {
                        withAnimation(.smooth(duration: 0.3)) { isConfirmingStartFresh = true }
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.regular)
                .transition(.blurReplace)
            }
        }
    }

    // The previous data file is untouched, so the only useful moves are
    // looking at it and trying again. Start Fresh is deliberately missing:
    // an empty new store would make the next launch skip the migration and
    // hide the subscriptions.
    private var retryMigrationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn’t Move Your Subscriptions")
                        .font(.headline)

                    Text("Your subscriptions are still in the previous data file, which hasn’t been changed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.glass)

                Spacer()

                Button("Show in Finder") {
                    persistence.revealLegacyStoreInFinder()
                }
                .buttonStyle(.glass)

                Button("Try Again") {
                    persistence.retryMigration()
                }
                .buttonStyle(.glassProminent)
            }
            .controlSize(.regular)
        }
    }
}
