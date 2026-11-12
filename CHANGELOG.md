# Changelog

What changed in each release of BadgeBar. The release workflow copies a version's section into its GitHub release notes, so add one before tagging.

## 0.4.0

- **Click again to hide.** Clicking the icon of the app you're using hides it, so one click opens an app and the next puts it away. An app in front with no window open gets a window back instead. Turn it off under Menu Bar ▸ Clicking Icons in Settings.
- **Take your setup to another Mac.** Settings ▸ General ▸ Back Up and Move exports your apps, groups, custom icons and settings to a file, and imports one. Notification history stays on the Mac it belongs to.
- **Share unread counts with other apps.** Turn it on under Integrations in Settings ▸ General, and SketchyBar, Raycast, Shortcuts or your own scripts can show your counts. They're told as soon as a count changes, so they don't need to check over and over. Only counts are shared, never message text. `badgebar://` links can open an app, mark messages as read or open Settings. See the README for the details and a SketchyBar example.
- After setup, BadgeBar asks once whether you'd like to star it on GitHub.

## 0.3.2

- **Automatic updates.** BadgeBar now checks for updates once a day, and its menu has a Check for Updates… item. Downloads are signed and verified before they're installed. This version has to be installed by hand, since older versions can't update themselves. Later ones will arrive on their own.

## 0.3.1

- **Custom icons keep their shape.** SF Symbols and non-square images used to be squeezed into a square. They now keep their proportions, and symbols fill the icon space so they sit evenly next to app icons.
- **A separate color for new activity.** Badges with no number, like Slack's unread channels, were a see-through gray that was hard to spot on white icons. A new Colors section in Settings sets this color apart from the notification count, and the default is now a solid, darker gray.
- **The color panel opens beside Settings.** Other… opens it next to the window instead of wherever it was last, and outlines the row you're editing.

## 0.3.0

- **Notification history that sticks around.** BadgeBar keeps its own copy of recent messages, so they're still there after you clear them in Notification Center. Choose how many to keep per app, or clear them, in Settings.
- **Recent messages when nothing's new.** An app's menu and preview show its last few messages, dimmed, instead of coming up empty. Notification History sits right under them.
- **Quit apps from their icons.** Each icon's menu has a Quit item for its app, and groups get Quit All.
- **Icons keep their place in the menu bar.** An icon hidden while its app isn't open used to come back at the far left, inside a menu bar hider's hidden section, after a restart or when the app relaunched.
- **Showing apps you haven't added is now off by default.** Turn it on while choosing your apps during setup, or later under Menu Bar in Settings.

## 0.2.0

The first public release.

- **One icon per app.** Any app that shows a badge on the Dock can have its own menu bar icon with its unread count. Icons dim when there's nothing new, or hide until something arrives.
- **Click to open, right-click to read.** Click an icon to open its app. Right-click it to see the latest messages, mark them as read, or show all of them.
- **Apps you haven't added still show up** while they have a badge.
- **Badge styles:** the count on the icon, the number beside it, or a dot, for every app or per app.
- **Badge effects:** a pulse, glow or shimmer when a count goes up, with an option to keep animating until you read it. Reduce Motion turns every effect into a gentle glow.
- **Groups:** put related apps under one icon that shows their total, with any SF Symbol or your own image.
- **Your icons:** each app's own icon, a monochrome version, an SF Symbol, or an image you drop in.
- **Arrange icons** in Settings or by ⌘-dragging them in the menu bar.
- **Hide apps that aren't open**, and bring their icons back when they launch.
- **Light and dark app icon**, with a choice in Settings.
- A short first-run guide for the Accessibility permission.
- Runs on macOS 14 or later, on Apple silicon and Intel.
- Install with Homebrew: `brew install --cask hk-vk/tap/badgebar`.
