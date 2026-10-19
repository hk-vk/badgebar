# BadgeBar

An open-source macOS menu bar app that shows your apps' notification badges, in the spirit of [Badgeify](https://badgeify.app).
Hide the Dock and still see the unread counts for Slack, Mail, Messages, Discord, and other apps.

## Features

- **Dock badges in the menu bar.** Each tracked app gets its own icon with its unread count.
- **Badge styles.** *Circle* draws an iOS-style pill, *Text* draws the count beside the icon, and *Dot* only shows that something is waiting.
- **Per-app colors and icons.** Use the original, monochrome, or a custom icon image.
- **Empty state.** When an app has no badge, its icon can be dimmed, hidden, or shown normally.
- **Groups.** Combine several apps under one icon that shows their total count. Clicking the icon lists the apps in the group.
- **Auto mode.** Any badged app you aren't tracking appears automatically. Right-click it and choose *Keep in Menu Bar* to keep it.
- **Click to open.** Left-click opens the app. Right-click shows more options.
- **⌘-drag to reorder.** Positions are remembered, and the icons work alongside Ice, Bartender, and Hidden Bar.
- **Launch at login.** Turn it on in the General tab.

## How it works

macOS draws app badges on Dock tiles. The Dock exposes each tile through the Accessibility API as an `AXApplicationDockItem`, and the tile's `AXStatusLabel` attribute holds the badge text. BadgeBar reads that attribute every 1.5 seconds by default. It also reads right away when an app launches or quits. This is the same approach Badgeify uses, and it has the same limits:

- BadgeBar needs **Accessibility** permission. Grant it in System Settings → Privacy & Security → Accessibility.
- Apps must be **running** to report a badge. The Dock can be auto-hidden.
- Nothing leaves your Mac. BadgeBar makes no network requests.

## Build

You need Xcode 15 or later and macOS 13 or later.

```sh
scripts/build-app.sh            # ad-hoc signed build/BadgeBar.app
scripts/build-app.sh "Developer ID Application: …"   # signed with your identity
open build/BadgeBar.app
```

For development, use `swift build && .build/debug/BadgeBar`. Accessibility permission is then granted to your terminal.

> macOS ties the Accessibility grant to the app's code signature. An ad-hoc signed build gets a new signature each time you rebuild. If badges stop showing up, remove BadgeBar from the Accessibility list and add it again.

## Project layout

| File | Purpose |
| --- | --- |
| `DockReader.swift` | Reads badges from the Dock's accessibility tree |
| `BadgeMonitor.swift` | Polls the Dock and publishes changes |
| `BadgeRenderer.swift` | Draws the icon and badge images |
| `StatusBarController.swift` | Creates the menu bar items, menus, and click handling |
| `SettingsView.swift` | Settings window (SwiftUI) |
| `Store.swift`, `Models.swift` | Configuration, saved to UserDefaults |

## License

MIT
