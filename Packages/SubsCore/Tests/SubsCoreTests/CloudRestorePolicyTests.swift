import Testing
@testable import SubsCore

struct CloudRestorePolicyTests {
    @Test(arguments: [
        StoreMigrationOutcome.noLegacyStore,
        .legacyNotSubs,
        .alreadyDone,
    ])
    func newStoreWithoutMigratedDataCanRestore(outcome: StoreMigrationOutcome) {
        #expect(CloudRestorePolicy.shouldAutomaticallyRestore(hadAppStore: false, migrationOutcome: outcome))
    }

    @Test(arguments: [
        StoreMigrationOutcome.noLegacyStore,
        .legacyNotSubs,
        .alreadyDone,
        .migrated,
    ])
    func existingStoreNeverRestores(outcome: StoreMigrationOutcome) {
        #expect(!CloudRestorePolicy.shouldAutomaticallyRestore(hadAppStore: true, migrationOutcome: outcome))
    }

    @Test func migratedLegacyDataWinsOverCloudBackup() {
        #expect(!CloudRestorePolicy.shouldAutomaticallyRestore(hadAppStore: false, migrationOutcome: .migrated))
    }
}
