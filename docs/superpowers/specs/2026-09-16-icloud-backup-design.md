# iCloud Backup and Restore Design

## Goal

Protect the user's subscriptions against loss when `subs` is removed or the Mac is replaced. The app keeps its existing local SwiftData store as the primary data source and maintains one recoverable snapshot in the user's private iCloud Drive container. This feature is backup and restore, not multi-device synchronization.

## User-visible behavior

- After every successful add, edit, delete, or whole-library import, the app schedules an iCloud backup of the complete subscription library.
- On launch, the app also attempts a backup. This uploads an existing library after the feature is installed and retries a backup that previously failed because iCloud was temporarily unavailable.
- A newly created local store is eligible for automatic restore. If a valid iCloud backup exists, the app restores it before presenting the normal subscription list.
- An existing local store is never automatically replaced by iCloud data, even if it is empty.
- The overflow menu contains `Restore from iCloud…`. It loads and validates the backup, shows the existing replacement confirmation, and uses the existing safe import path to preserve the current local library before replacing it.
- Backup failures never prevent local use or undo a successful local edit. A non-blocking banner explains the failure and the app retries at the next launch or local change.
- If the user is not signed into iCloud, iCloud Drive is disabled, the backup has not downloaded yet, or the network is unavailable, the app continues to use the local store.

## Storage architecture

The local SwiftData database remains authoritative while the app is running. The cloud artifact is a single versioned JSON snapshot encoded and decoded by `SubscriptionTransfer`, so backup restoration receives the same size limits, format checks, duplicate-ID checks, and field validation as manual transfer.

The production app receives an iCloud Documents container entitlement associated with bundle identifier `pl.glasek.subs`. The backup service resolves the app's ubiquitous container through `FileManager.url(forUbiquityContainerIdentifier:)` and stores the snapshot at a stable application-owned path such as `Documents/Backups/subs-latest.json`. Writes use a temporary sibling followed by coordinated atomic replacement, preventing an interrupted upload from exposing a partial backup.

Debug and automated tests inject a local directory instead of accessing the developer's real iCloud container. iCloud access is kept behind a small file-store interface so encoding, restore decisions, retries, and filesystem failures can be tested deterministically.

## Components and responsibilities

### `CloudBackupService`

The app-level observable service owns backup availability and the most recent recoverable error. It:

1. Resolves the iCloud container without blocking startup.
2. Reads all records from a supplied `ModelContainer`.
3. Encodes a complete snapshot with `SubscriptionTransfer`.
4. Writes the snapshot safely to the stable backup URL.
5. Coordinates download/read access and validates a restore file before returning records.

Only one backup operation runs at a time. If another change arrives while a write is running, the service performs one more backup afterward so the final snapshot cannot lag behind the latest successful local save.

### `PersistenceController`

Before opening SwiftData, the controller records whether the app-specific store and its sidecars existed. Existing legacy-store migration remains unchanged and takes priority. Automatic cloud restore is allowed only when no app-specific store existed and no legacy data was migrated. The controller opens the new local container, requests validated cloud records, and imports them through the same whole-library replacement operation used by manual import.

The restore eligibility decision is based on store existence before `ModelContainer` creates a new database, not on whether the opened database currently contains zero records. This prevents a deliberately emptied existing library from being repopulated.

### Save and import integration

After `ModelContext.save()` succeeds, `ContentView` asks the backup service to capture the container. Failed local saves still roll back as they do today and never trigger a cloud write. A successful manual import also triggers a backup after the replacement completes.

The app launch path requests a backup after persistence and any automatic restoration finish. This creates the first cloud snapshot for existing installations and provides retry behavior without a background daemon.

## Restore flow and safety

For automatic restore:

1. Confirm that this launch created a genuinely new app-specific store and did not migrate a legacy store.
2. Resolve the iCloud container and request the backup file download if necessary.
3. Read no more than the transfer format's maximum supported byte count.
4. Validate the complete document with `SubscriptionTransfer.decode`.
5. Replace the empty local library in one SwiftData save.
6. If any step fails, retain the new empty local store and surface a recoverable, non-blocking message. Never modify or delete the cloud file.

For manual restore, the validated records enter the existing confirmation flow. On confirmation, `SubscriptionLibrary.importReplacingAll` first writes the normal local pre-import backup and then replaces the library. Cancelling leaves all data unchanged.

An empty, valid iCloud snapshot is meaningful and restores an empty library. A corrupt, oversized, unsupported, or partially unavailable snapshot is rejected and cannot alter the local store.

## Failure handling

- iCloud unavailable: local operation succeeds; show a concise backup-status error and retry later.
- Backup write failure: keep the previous valid cloud snapshot; never replace it with partial data.
- Backup download pending: wait for a bounded period during automatic restore, then open locally and allow manual retry from the menu.
- Invalid cloud document: reject it with the existing transfer validation message; do not overwrite either local or cloud data.
- Restore save failure: roll back the SwiftData context and retain the original local library.
- Existing local store: never run automatic replacement.

## Project configuration

The app target gains the iCloud capability with iCloud Documents enabled and an app-specific ubiquity container. The entitlements file is referenced by both Debug and Release configurations. Tests and previews do not require an iCloud account and use injected local storage.

The README privacy section will state that subscriptions remain local by default and that an automatic private iCloud backup is stored in the user's Apple account for recovery. It will also explain that signing out of iCloud or deleting the app's iCloud data makes restoration unavailable.

## Verification

Unit tests cover:

- backup data round-trips through the existing transfer codec;
- atomic-write failure preserves the previous snapshot;
- coalesced writes eventually save the newest library;
- a brand-new store restores a valid snapshot;
- an existing empty or non-empty store is never automatically replaced;
- legacy migration wins over cloud restore;
- corrupt, oversized, unavailable, and unsupported backups leave local data untouched;
- manual restore continues to create a local pre-import backup;
- cloud failures do not turn successful local edits into failures.

The app will be built with `xcodebuild`, and the `SubsCore` package test suite plus new backup tests will run. A manual development-container check will verify initial upload and restore using a disposable debug data directory. Final proof of persistence across app deletion requires a signed build, an Apple ID with iCloud Drive enabled, and the configured container; if that environment is unavailable, it will be reported explicitly rather than inferred from unit tests.

## Out of scope

- Live synchronization or conflict resolution between multiple Macs.
- Historical cloud backup versions.
- User-selectable backup locations or schedules.
- Background agents or periodic timers while the menu bar app is not running.
- Restoring settings such as Launch at Login; only subscriptions are backed up.
