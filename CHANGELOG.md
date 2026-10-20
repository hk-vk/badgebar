# Changelog

What changed in each release of BadgeBar. The release workflow copies a version's section into
its GitHub release notes, so add one before tagging.

## 0.2.0

The first public release.

- **One icon per app.** Any app that shows a badge on the Dock can have its own menu bar icon with
  its unread count. Icons dim when there's nothing new, or hide until something arrives.
- **Click to open, right-click to read.** Click an icon to open its app. Right-click it to see the
  latest messages, mark them as read, or show all of them.
- **Apps you haven't added still show up** while they have a badge.
- **Badge styles:** the count on the icon, the number beside it, or a dot, for every app or per app.
- **Badge effects:** a pulse, glow or shimmer when a count goes up, with an option to keep
  animating until you read it. Reduce Motion turns every effect into a gentle glow.
- **Groups:** put related apps under one icon that shows their total, with any SF Symbol or your
  own image.
- **Your icons:** each app's own icon, a monochrome version, an SF Symbol, or an image you drop in.
- **Arrange icons** in Settings or by ⌘-dragging them in the menu bar.
- **Hide apps that aren't open**, and bring their icons back when they launch.
- **Light and dark app icon**, with a choice in Settings.
- A short first-run guide for the Accessibility permission.
- Runs on macOS 14 or later, on Apple silicon and Intel.
- Install with Homebrew: `brew install --cask hk-vk/tap/badgebar`.
