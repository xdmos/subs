# subs

A small macOS menu bar app for keeping track of subscriptions that renew every 30 days.
It shows how many days are left until each renewal, with a Liquid Glass interface.

<p align="center">
  <img src="readme.png" alt="subs menu bar panel with a list of subscriptions" width="389">
</p>

## Features

- Lives in the menu bar, no Dock icon.
- Each subscription shows the days remaining in its current 30-day cycle and a progress bar.
  Click a card to switch between days remaining and days elapsed.
- Sorted by the nearest renewal; cards renewing within 3 days are highlighted.
  On the renewal day a card says *Renews today*; a subscription with a future start date
  counts down the days until it starts.
- Add (`⌘N`), edit (right-click → Edit…) and delete subscriptions. Deleting asks for
  confirmation inside the panel.
- Move the whole list between devices: `⋯ → Export JSON…` writes a versioned file,
  and `Import JSON…` validates the whole file, saves a copy of the current data to
  the `Import Backups` folder next to the data file, and only then replaces the list —
  so a bad file never changes anything and the previous data can always be imported back.
- Keeps an automatic, private recovery snapshot in iCloud Drive after every successful
  change. A fresh installation restores that snapshot automatically; an existing local
  database is never replaced without confirmation. `⋯ → Restore from iCloud…` provides
  a manual recovery path.
- Launch at Login, from the `⋯` menu, with a shortcut to System Settings when macOS
  asks for approval.
- If saving fails, for example on a full disk, the change is undone and the error is shown
  in the panel.
- If the data file can't be opened, the panel says so instead of crashing. *Start Fresh*
  moves the unreadable file to a backup folder next to it, never deleting it, and
  *Show in Finder* reveals it.
- English interface; dates follow your region's format.
- Light and dark app icon.

## Requirements

- macOS 27
- Xcode 27

## Build

1. Open `subs.xcodeproj` in Xcode.
2. Under *Signing & Capabilities*, select your own development team.
3. Enable iCloud Documents for the `iCloud.pl.glasek.subs` container, or replace that
   container identifier in `subs/subs.entitlements` with one owned by your team.
4. Build and run the `subs` scheme.

To install, build the Release configuration and copy `subs.app` to `/Applications`.
Launch at Login is meant to be used from there.

## Privacy

- Data is stored locally with SwiftData. A versioned recovery snapshot is stored in the
  app's private iCloud Drive container in your Apple account.
- Recovery requires the same Apple account with iCloud Drive enabled. Signing out of
  iCloud or deleting the app's data from iCloud makes that recovery copy unavailable.
- No third-party networking, app account, telemetry, or analytics.
- Built with the Hardened Runtime.

## License

MIT. See [LICENSE](LICENSE).
