---
layout: ../../layouts/Post.astro
title: How to hide the Dock on Mac (and still see your unread counts)
description: Hide the Dock on your Mac with a shortcut or a setting, make it hide faster or for good, fix a Dock that won't hide, and keep your apps' unread badges in view.
published: 2026-11-15
---

The Dock takes up the bottom of your screen all day, even though most people only look at it to
open an app or check a red badge. Hiding it gives you that space back. This guide covers every way
to hide it, how to tune it, and what to do about the badges you lose.

## The quick way: a keyboard shortcut

Press <kbd>Option</kbd> <kbd>Command</kbd> <kbd>D</kbd>. The Dock slides away, and comes back when
you move the pointer to the bottom of the screen. Press the same shortcut again to keep it on
screen.

## Turn it on in System Settings

1. Open the Apple menu and choose **System Settings**.
2. Click **Desktop & Dock** in the sidebar.
3. Turn on **Automatically hide and show the Dock**.

This is the same setting the shortcut changes, so you can use either one.

While you're there, a few other settings make the Dock less of a presence:

- **Show suggested and recent apps in Dock.** Turn this off to stop apps you've closed from
  staying in the Dock.
- **Size** and **Magnification.** A smaller Dock is less in the way when it does appear.
- **Position on screen.** Put it on the left or right if you'd rather keep the full height of your
  screen.

## Make the Dock appear faster

When the Dock is hidden, macOS waits a moment before showing it, then animates it in. You can
remove the wait with Terminal:

```sh
defaults write com.apple.dock autohide-delay -float 0
killall Dock
```

To also make the slide-in animation quicker, set how long it takes, in seconds:

```sh
defaults write com.apple.dock autohide-time-modifier -float 0.15
killall Dock
```

To go back to the normal behavior:

```sh
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock autohide-time-modifier
killall Dock
```

`killall Dock` only restarts the Dock. Your apps and windows stay open.

## Hide the Dock for good

macOS has no setting to remove the Dock entirely, but you can make it so slow to appear that it
never shows up by accident. This sets the delay to 1,000 seconds:

```sh
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000
killall Dock
```

You can still switch apps with <kbd>Command</kbd> <kbd>Tab</kbd>, open them with Spotlight
(<kbd>Command</kbd> <kbd>Space</kbd>), and see open windows with Mission Control. To undo it, run
`defaults delete com.apple.dock autohide-delay` and `killall Dock`.

## Hide the Dock in full screen

Apps in full screen hide the Dock for you. Click the green button in a window's top-left corner,
or press <kbd>Control</kbd> <kbd>Command</kbd> <kbd>F</kbd>. Move the pointer to the bottom of the
screen to bring the Dock back while you're in full screen.

## If the Dock won't hide, or keeps hiding

- **An app wants your attention.** When an app bounces in the Dock, the Dock stays visible until
  you switch to that app.
- **The setting didn't stick.** Run `killall Dock` in Terminal to restart it, then check the
  setting in Desktop & Dock again.
- **It hides when you don't want it to.** Press <kbd>Option</kbd> <kbd>Command</kbd> <kbd>D</kbd>,
  or turn off **Automatically hide and show the Dock**.
- **It shows up on the wrong display.** With more than one display, the Dock moves to whichever
  screen you push the pointer against the bottom of. Leave the pointer at the bottom edge of the
  display you want for a moment.

## The catch: you lose your unread badges

The Dock does one job that nothing else on your Mac does. The red badges on its icons tell you
that Slack has 12 unread messages, Mail has 3, and WhatsApp has 2. Once the Dock is hidden, you
only see those counts when you bring it back. Notification banners go away after a few seconds,
and Notification Center doesn't show a count per app.

[BadgeBar](/) fixes this. It reads the badges macOS already puts on Dock icons and gives each app
its own icon in the menu bar, with its count on top. Click an icon to open the app, like you
would in the Dock. Right-click it to see the latest messages. Icons dim when there's nothing new,
or you can hide them until something arrives.

It's free and open source, and works next to menu bar managers like Bartender, Ice and Hidden Bar.
Install it with Homebrew:

```sh
brew install --cask hk-vk/tap/badgebar
```

Or download it from the [BadgeBar website](/).

## Summary

- Press <kbd>Option</kbd> <kbd>Command</kbd> <kbd>D</kbd> to hide or show the Dock.
- Or turn on **Automatically hide and show the Dock** in System Settings ▸ Desktop & Dock.
- Use `autohide-delay` in Terminal to make it appear instantly, or almost never.
- Use BadgeBar to keep your apps' unread counts in the menu bar once the Dock is gone.
