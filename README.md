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
- Add, edit (right-click → Edit…) and delete subscriptions.
- Launch at Login, from the `⋯` menu.
- Light and dark app icon.
- Data is stored locally with SwiftData.

## Requirements

- macOS 27
- Xcode 27

## Build

1. Open `subs.xcodeproj` in Xcode.
2. Under *Signing & Capabilities*, select your own development team.
3. Build and run the `subs` scheme.

To install, build the Release configuration and copy `subs.app` to `/Applications`.
Launch at Login is meant to be used from there.
