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
- **Hover previews.** Rest the pointer on an icon to see that app's recent notifications as macOS-style cards. Moving to the next icon switches the preview right away. Hover a card and click ✕ to dismiss it, or use *Clear* to dismiss them all.
- **Notification viewer.** Click the BadgeBar icon to see every app's notifications in stacks you can expand, with *Clear All*.
- **Click to open, right-click to read.** Click an icon to open the app, like the Dock. Right-click it for a menu of its latest messages (sender and text), Mark as Read, and *Show All Messages…*. Clicking a group opens its combined view.
- **Compact layout.** By default, app icons share one menu bar item, so they sit close together. Reorder them by dragging apps in the settings sidebar, or turn this off to get separate items you can ⌘-drag.
- **Easy adding.** Installed messaging and work apps (Slack, Teams, WhatsApp, Discord and more) are suggested first, every installed app is searchable, and you can drag apps from Finder onto the settings sidebar.
- **Native settings.** The settings window works like System Settings: use the arrow keys to move through the sidebar, press ⌫ to remove an item, and drag apps to reorder them. On macOS 26 and later it uses Liquid Glass.
- **Guided setup.** A welcome guide walks you through each permission and notices when you grant it. If macOS needs BadgeBar to restart before a permission takes effect, BadgeBar restarts itself.
- **⌘-drag to reorder.** Positions are remembered, and the icons work alongside Ice, Bartender, and Hidden Bar.
- **Launch at login.** Turn it on in the General tab.

## How it works

macOS draws app badges on Dock tiles. The Dock exposes each tile through the Accessibility API as an `AXApplicationDockItem`, and the tile's `AXStatusLabel` attribute holds the badge text. BadgeBar reads that attribute every 1.5 seconds by default. It also reads right away when an app launches or quits. This is the same approach Badgeify uses, and it has the same limits:

- BadgeBar needs **Accessibility** permission to read badges.
- **Full Disk Access** is optional. With it, BadgeBar can show message previews by reading Notification Center's history in `~/Library/Group Containers/group.com.apple.usernoted/db2/db`. Without it, hovering an icon shows the unread count only.
- *Clear* hides notifications in BadgeBar only. macOS doesn't let another app delete Notification Center history or reset an app's badge.
- Apps must be **running** to report a badge. The Dock can be auto-hidden.
- Nothing leaves your Mac. BadgeBar makes no network requests.

## Build

You need Xcode 16 or later and macOS 14 or later.

```sh
scripts/create-signing-cert.sh  # once: a local signing identity so permissions survive rebuilds
scripts/build-app.sh            # build/BadgeBar.app
scripts/build-app.sh "Developer ID Application: …"   # signed with your identity
open build/BadgeBar.app
```

For development, use `swift build && .build/debug/BadgeBar`. Accessibility permission is then granted to your terminal.

> macOS ties privacy permissions to the app's code signature. An ad-hoc signature changes on every build, so a permission granted to one build silently stops working for the next. The switch in System Settings still looks on, and dragging the app in again doesn't fix it. Sign with the local identity from `scripts/create-signing-cert.sh` to avoid this. To clear a stale entry, run `tccutil reset Accessibility io.github.badgebar`.

`scripts/make-icon.sh` regenerates the app icon from `scripts/make-icon.swift`.

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
