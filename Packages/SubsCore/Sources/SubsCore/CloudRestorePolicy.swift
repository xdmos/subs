public enum CloudRestorePolicy {
    public static func shouldAutomaticallyRestore(
        hadAppStore: Bool,
        migrationOutcome: StoreMigrationOutcome
    ) -> Bool {
        guard !hadAppStore else { return false }
        return migrationOutcome != .migrated
    }
}
