---
layout: ../../layouts/Post.astro
title: "Full Disk Access and Accessibility on Mac: what they do and when to allow them"
description: Why Mac apps ask for Full Disk Access, Accessibility and Screen Recording, what each permission lets them see, how to check who has it, and how to decide if it's safe.
published: 2026-11-15
---

Sooner or later a Mac app asks for **Full Disk Access** or **Accessibility**, and macOS shows a
warning that sounds alarming. These permissions are powerful, but they're also how many everyday
utilities work. Here's what each one lets an app do, and how to decide whether to allow it.

## Accessibility

Accessibility was built for assistive tools like screen readers, which need to read what's on
screen and press buttons for you. Any app with this permission can:

- read the contents of other apps' windows, buttons and menus, including the Dock and menu bar
- click, type and move windows on your behalf

That's why window managers, launchers, keyboard remappers and menu bar tools ask for it. They
can't move a window or read a Dock icon any other way.

**The risk:** an app with Accessibility can see what's on your screen and act like you. Only allow
it for apps you trust.

## Full Disk Access

macOS protects some folders even from apps you've opened yourself: Mail, Messages, Safari history,
Time Machine backups, and the database where Notification Center keeps past notifications. Full
Disk Access lifts that protection for one app, so it can read files in those places.

Backup apps, disk cleaners, security scanners and some productivity tools need it.

**The risk:** an app with Full Disk Access can read your private data on the Mac. It still needs a
network connection to send anything anywhere, so it matters what the app does with what it reads.

## Screen Recording

Screen Recording lets an app capture images of your screen. Video calls, screenshot tools and some
menu bar managers use it. Ice and Thaw, for example, use it to show previews of menu bar items. In
those apps it's optional.

## How to check which apps have each permission

1. Open **System Settings** and click **Privacy & Security**.
2. Click **Accessibility**, **Full Disk Access** or **Screen & System Audio Recording**.
3. Turn off any app you don't recognize or no longer use. Select an app and click the minus button
   to remove it entirely.

Removing a permission is safe. The app just stops being able to do the thing that needed it, and
asks again next time.

## How to decide whether to allow it

Ask four questions:

- **Does the app need it for what it does?** A tool that reads Dock badges needs Accessibility. A
  note-taking app probably doesn't need Full Disk Access.
- **Is it open source?** If the code is public, you, or anyone else, can check what it does with
  the access.
- **Does it go online, and why?** An app that only checks for updates is very different from one
  that syncs your data to a server.
- **Is it optional?** Good apps explain what each permission is for, and keep working, with fewer
  features, if you say no.

## What BadgeBar asks for, and why

[BadgeBar](/) shows each app's unread count in the menu bar, so it has to read those counts from
somewhere. Here's exactly what it uses:

- **Accessibility, required.** macOS shows unread badges on Dock icons, and Accessibility is the
  only way another app can read them. BadgeBar reads the Dock's icons and badges, and uses the
  same permission to hide an app when you click its menu bar icon a second time. It doesn't read
  other apps' windows.
- **Full Disk Access, optional.** With it, BadgeBar reads the notifications macOS has already
  saved, so you can right-click an app's icon and see its latest messages. Without it, you still
  get every count.
- **Network:** only to check for updates. Your badges and messages never leave your Mac.

BadgeBar is [open source](https://github.com/hk-vk/badgebar), so you can read exactly how it uses
each permission, or build it yourself. The [privacy policy](/privacy/) has the details.
