---
layout: ../../layouts/Post.astro
title: "Mac notifications not showing? How to fix them and stop missing messages"
description: Fix Mac notifications and badges that don't show up, from Focus and app settings to screen sharing, and find a way to see unread messages at a glance with the Dock hidden.
published: 2026-11-15
---

You find out about a message an hour late, and there was never a banner. Or an app's red badge
never appears. Mac notifications fail quietly, but the cause is nearly always one of a handful of
settings. Work through these in order.

## 1. Check Focus

Focus, including Do Not Disturb, silences notifications from most apps. When a Focus is on, its
icon appears in the menu bar.

- Click **Control Center** in the menu bar and look at **Focus**. Click it to turn it off.
- In **System Settings ▸ Focus**, check each Focus's schedule. A Focus can turn itself on at a set
  time, at a place, or when you open a particular app.
- Turn off **Share across devices** if a Focus on your iPhone keeps turning one on on your Mac.

## 2. Check the app's notification settings

1. Open **System Settings ▸ Notifications**.
2. Click the app in the list.
3. Make sure **Allow notifications** is on.
4. Choose **Banners** or **Alerts** as the style. Banners go away on their own; alerts stay until
   you dismiss them.
5. Make sure **Badge application icon** is on. This is what puts the red count on the app's Dock
   icon.

Also check the app's own settings. Slack, Teams, Mail and most chat apps have their own
notification options, which can turn notifications off even when macOS allows them.

## 3. Check screen sharing and mirroring

By default, macOS hides notifications while you mirror or share your screen, so they don't pop
up in a presentation. In **System Settings ▸ Notifications**, turn on **Allow notifications when
mirroring or sharing the display** if you want them anyway.

## 4. Check previews and the lock screen

If notifications arrive but show no text, look at **Show previews** at the top of **System
Settings ▸ Notifications**. Set it to **Always** to see message text even when your Mac is locked.

## 5. Restart Notification Center

If the settings are right and notifications still don't come, restart the process that shows
them. Open Terminal and run:

```sh
killall NotificationCenter
```

It restarts on its own. If that doesn't help, restart your Mac, and check for a macOS update in
**System Settings ▸ General ▸ Software Update**.

## Where to find notifications you missed

Click the date and time in the menu bar, or swipe left from the right edge of the trackpad with two
fingers. Notification Center lists recent notifications grouped by app. Click a group to expand it.

## Why you still miss messages, even when it all works

Banners disappear after a few seconds. If you're away from your desk, or deep in something else,
they're gone before you look. Notification Center keeps them, but you have to remember to open it,
and it doesn't tell you at a glance how many messages are waiting in each app.

The Dock does tell you, with its red badges, but only while it's on screen. Many people hide it to
get the space back, and then the badges are gone too.

[BadgeBar](/) keeps them in view. It puts each app's unread count in the menu bar, which is always
visible, so you can see that Slack has 12 unread messages and Mail has 3 without opening anything.
Right-click an icon to read the latest messages, and set a badge to pulse or glow when a new one
arrives. It reads the same badges the Dock shows, so make sure **Badge application icon** is on for
each app, as in step 2.

BadgeBar is free and open source. See
[how to hide the Dock on Mac](/blog/hide-dock-mac/) for the rest of the setup.
