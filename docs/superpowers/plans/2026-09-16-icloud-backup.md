# iCloud Backup and Restore Implementation Plan

> **Status (2026-09-18):** Implemented and verified locally. The backup feature landed
> through commits ending in `69f1fcd`; the follow-up fix keeping SwiftData local while
> iCloud is used only for JSON recovery landed in `cc7a5d5`. The original checkboxes
> below are preserved as an execution record and are not a current product-status list.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically preserve a validated snapshot of subscriptions in the user's private iCloud Drive container and restore it after a genuine fresh installation.

**Architecture:** Keep SwiftData local and authoritative. Add a testable snapshot file store to `SubsCore`, an app-level iCloud controller that serializes operations and exposes recovery state, and a launch coordinator that only restores when the app-specific store did not exist before launch.

**Tech Stack:** Swift 6, SwiftData, SwiftUI Observation, Foundation `NSFileCoordinator`, iCloud Documents, Swift Testing, Xcode 27/macOS 27.

**Spec:** `docs/superpowers/specs/2026-09-16-icloud-backup-design.md`

## Global Constraints

- This is backup and restore, not multi-device synchronization.
- Existing local or migrated data must never be automatically replaced.
- Cloud failures must never turn a successful local save into a failed local save.
- Every cloud document is decoded with `SubscriptionTransfer` before restore.
- Tests and Debug overrides must not touch the user's real iCloud container.

---

### Task 1: Safe snapshot file store

**Files:**
- Create: `Packages/SubsCore/Sources/SubsCore/CloudSnapshotStore.swift`
- Create: `Packages/SubsCore/Tests/SubsCoreTests/CloudSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `SubscriptionTransfer.maxFileSize` and encoded `Data`.
- Produces: `CloudSnapshotFileSystem`, `LocalCloudSnapshotFileSystem`, and `CloudSnapshotStore` with `write(_:)` and `read()`.

- [ ] Write tests using a temporary directory and an injected failing filesystem. Assert round-trip data, missing-file result, maximum-size read enforcement, and that a failed replacement preserves the previous snapshot.
- [ ] Run `swift test --package-path Packages/SubsCore --filter CloudSnapshotStoreTests` and confirm failures because the types do not exist.
- [ ] Implement a focused store that creates its directory, writes a sibling temporary file, coordinates replacement, and removes only its own temporary file after failure. Bound reads to `SubscriptionTransfer.maxFileSize + 1` and throw `fileTooLarge` when exceeded.
- [ ] Re-run the focused tests and the full `swift test --package-path Packages/SubsCore` suite.
- [ ] Commit the production and test files.

### Task 2: Fresh-install restore decision

**Files:**
- Create: `Packages/SubsCore/Sources/SubsCore/CloudRestorePolicy.swift`
- Create: `Packages/SubsCore/Tests/SubsCoreTests/CloudRestorePolicyTests.swift`
- Modify: `Packages/SubsCore/Sources/SubsCore/StoreMigration.swift`

**Interfaces:**
- Consumes: pre-launch existence of the app store family and `StoreMigration.Outcome`.
- Produces: `CloudRestorePolicy.shouldAutomaticallyRestore(hadAppStore:migrationOutcome:) -> Bool`.

- [ ] Write table-driven tests proving that only a missing app store plus a no-data migration outcome permits restore; existing empty/non-empty store and successful legacy migration reject restore.
- [ ] Run the focused tests and confirm the missing policy failure.
- [ ] Add the pure policy type and expose enough migration outcome information to distinguish copied legacy data from no migration without changing migration behavior.
- [ ] Run focused and full package tests.
- [ ] Commit the policy and tests.

### Task 3: App-level iCloud backup controller

**Files:**
- Create: `subs/CloudBackupController.swift`
- Create: `subsTests/CloudBackupControllerTests.swift` if an app unit-test target is present; otherwise keep scheduling logic in `SubsCore` and test it there.
- Modify: `subs.xcodeproj/project.pbxproj` only if a test file must be registered.

**Interfaces:**
- Consumes: `ModelContainer`, `SubscriptionLibrary.records`, `SubscriptionTransfer.encode/decode`, and `CloudSnapshotStore`.
- Produces: `@MainActor @Observable CloudBackupController`, `backup(container:)`, `loadRestoreRecords()`, and user-facing `errorMessage`.

- [ ] Write failing tests for a successful snapshot, failure that leaves local state successful, validated restore loading, and two requests during an active write producing a final snapshot of the newest records.
- [ ] Run the focused tests and verify the expected missing-controller/scheduler failure.
- [ ] Implement serialized/coalesced backup work. Resolve the production root with `FileManager.url(forUbiquityContainerIdentifier:)`; in Debug accept `-SubsICloudDirectory <path>` so checks never use real iCloud.
- [ ] Run focused and full tests.
- [ ] Commit the controller and tests.

### Task 4: Launch restore and mutation hooks

**Files:**
- Modify: `subs/PersistenceController.swift`
- Modify: `subs/subsApp.swift`
- Modify: `subs/ContentView.swift`
- Modify: `subs/DataTransferController.swift`

**Interfaces:**
- Consumes: `CloudBackupController`, `CloudRestorePolicy`, and the existing safe whole-library replacement APIs.
- Produces: launch-time automatic restoration plus backup requests after each successful local mutation/import.

- [ ] Add failing integration-level policy/service tests proving a fresh store imports valid cloud records, an existing store is untouched, and invalid cloud data is non-destructive.
- [ ] Run the focused tests and verify their expected failure.
- [ ] Inject one app-owned `CloudBackupController`. Record store existence before opening SwiftData, preserve legacy migration priority, restore only when the policy allows it, and request the initial upload after launch finishes.
- [ ] Pass the controller to `ContentView`; call `backup(container:)` only after successful saves and successful confirmed imports. Display cloud errors as a dismissible non-blocking banner.
- [ ] Run focused tests, the complete package suite, and an app build.
- [ ] Commit the integration.

### Task 5: Manual restore and capability configuration

**Files:**
- Modify: `subs/PanelHeader.swift`
- Modify: `subs/DataTransferController.swift`
- Create: `subs/subs.entitlements`
- Modify: `subs.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CloudBackupController.loadRestoreRecords()` and existing `PendingImport`/`confirmImport` flow.
- Produces: `Restore from iCloud…` command, the iCloud Documents entitlement, and Remote notifications capability only if required by the chosen Documents setup.

- [ ] Add failing controller/UI-state tests showing that a valid cloud snapshot becomes a pending import and invalid/unavailable data leaves the store unchanged with an error.
- [ ] Run the focused tests and confirm failure.
- [ ] Add the menu action, reuse the existing confirmation banner and `importReplacingAll`, and trigger a new cloud backup after successful replacement.
- [ ] Add `CODE_SIGN_ENTITLEMENTS = subs/subs.entitlements` to Debug and Release and configure `com.apple.developer.ubiquity-container-identifiers` plus `com.apple.developer.icloud-services = CloudDocuments` for the app-specific container.
- [ ] Run tests and build with code signing disabled first, then inspect expanded entitlements in the signed product when signing is available.
- [ ] Commit the UI and capability changes.

### Task 6: Documentation and end-to-end verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: completed backup behavior and verified limitations.
- Produces: accurate setup, privacy, and recovery documentation.

- [ ] Update Features, Build, and Privacy to describe automatic private iCloud recovery, required Signing & Capabilities setup, and conditions that make recovery unavailable.
- [ ] Run `swift test --package-path Packages/SubsCore`.
- [ ] Run `xcodebuild -project subs.xcodeproj -scheme subs -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
- [ ] Launch with disposable `-SubsDataDirectory` and `-SubsICloudDirectory`, add data, remove only the disposable local store, relaunch, and verify restoration from the disposable cloud snapshot.
- [ ] Run `git diff --check`, inspect the complete diff, and confirm no unrelated user files changed.
- [ ] Commit documentation and any final verified corrections.
