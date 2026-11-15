---
layout: ../../layouts/Post.astro
title: "Free Bartender alternatives for Mac: Ice, Thaw and Hidden Bar"
description: Bartender is the best-known menu bar manager for Mac, but it's paid. Here are the free, open source alternatives, how they compare, and which one to pick.
published: 2026-11-15
---

A Mac's menu bar fills up fast. Every utility you install adds an icon, and on a MacBook with a
notch, the ones that don't fit just disappear behind it. A menu bar manager lets you hide the
icons you rarely need and keep the ones you do.

[Bartender](https://www.macbartender.com) is the best-known one. It's polished and has a lot of
features, but it's a paid app, and plenty of people only need it to hide a few icons. These free,
open source apps do that job.

## At a glance

| App | Price | Source | Best for |
| -- | -- | -- | -- |
| Bartender | Paid | Closed | Every feature, with support |
| Ice | Free | Open source | A Bartender-style setup on older macOS versions |
| Thaw | Free | Open source | An actively maintained Ice, on macOS 26 or later |
| Hidden Bar | Free | Open source | Hiding icons with one click, and nothing else |
| macOS itself | Free | Built in | Turning off a few system icons |

## Ice

[Ice](https://github.com/jordanbaird/Ice) is the open source app most people reach for first. It
hides icons behind a divider, can show hidden icons in a separate bar below the menu bar (handy on
a notched MacBook), and lets you rearrange items and change the menu bar's look.

The catch is maintenance. Development has slowed, and people running the newest macOS versions
report bugs, such as hidden items not appearing. If Ice works on your Mac, it's a great choice. If
it doesn't, try Thaw.

## Thaw

[Thaw](https://github.com/thaw-app/Thaw) is a fork of Ice, started to keep the project going. It
fixes bugs and keeps up with new macOS releases, and adds features like searching your menu bar
items. Like Ice, it can show hidden items in their own bar under the menu bar.

It's free under the GPL and has no account or tracking. Screen Recording permission is optional;
it's only needed for item previews and tinting. Thaw needs macOS 26 or later. Install it with
Homebrew:

```sh
brew install --cask thaw
```

## Hidden Bar

[Hidden Bar](https://github.com/dwarvesf/hidden) is the simplest option. It adds an arrow to the
menu bar. Everything on one side of it is hidden until you click the arrow. There's no separate
bar and not much to set up. If you just want fewer icons on screen, it's enough. It's free on the
Mac App Store.

## The built-in option

Recent versions of macOS let you turn off many of Apple's own menu bar items, like Wi-Fi,
Bluetooth or Spotlight, in **System Settings ▸ Control Center**, and on macOS 26 in **System
Settings ▸ Menu Bar**. You can also ⌘-drag most icons to rearrange them, or drag them out of the
menu bar to remove them. This doesn't hide third-party icons behind a divider, but it may be all
you need.

## Which one should you pick?

- **You want it to just work and don't mind paying:** Bartender.
- **You want the Bartender experience for free, on macOS 26 or later:** Thaw.
- **Ice already works well on your Mac:** stay with Ice.
- **You only want fewer icons, with no setup:** Hidden Bar.

## Pair it with a hidden Dock

People who tidy their menu bar often hide the Dock too, so the whole screen is theirs. The one
thing you lose is the red unread badges on Dock icons.

[BadgeBar](/) brings them back: each app gets its own menu bar icon with its unread count on top.
It works next to every app above. Hide BadgeBar's icons behind the divider when there's nothing
new, or let them show only when something arrives. See
[how to hide the Dock on Mac](/blog/hide-dock-mac/) for the full setup.
