//
//  subsApp.swift
//  subs
//
//  Created by Macbook M4 Pro on 11/09/2026.
//

import SwiftUI
import SwiftData

@main
struct subsApp: App {
    @State private var persistence = PersistenceController()

    var body: some Scene {
        MenuBarExtra("Subscriptions", systemImage: "creditcard.fill") {
            Group {
                switch persistence.state {
                case .ready(let container):
                    ContentView()
                        .modelContainer(container)
                case .failed(let details):
                    StoreErrorView(details: details, recovery: .startFresh, persistence: persistence)
                case .migrationFailed(let details):
                    StoreErrorView(details: details, recovery: .retryMigration, persistence: persistence)
                }
            }
            .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
    }
}
