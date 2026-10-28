---
title: "Looking for Blanket on Mac? Meet Blankie"
description: "Blanket is a Linux app with no official Mac version, but Blankie is a free, open-source Mac app inspired by it, with many of the same sounds and features."
category: "basics"
order: 47
updated: 2026-10-28
author: "Cody Bromley"
platforms: "Mac"
---

If you landed here looking for a way to run Blanket on your Mac, I know the feeling. [Blanket](https://apps.gnome.org/Blanket/) is an open-source ambient sound app by Rafael Mardojai and contributors built for Linux and the GNOME desktop. Linux and macOS are both Unix-like, so you'd might think there's a way it could carry over with some tweaks, but there's not official Mac version of Blanket and that's unlikely to change.

Blanket is written in Python, a language Macs can run just fine. The only problem is that Blanket's source code depends on a bunch of libraries that only work on Linux desktops. To get Blanket running as a real Mac app, you would need to replace all of the Linux-only dependencies with Mac-compatible ones. In other words, you'd pretty much have to start from scratch. And that's exactly what I did.

A few years ago, I moved from Linux to a Mac, and I missed Blanket so much I decided I couldn't go without it. The Mac version I started building for myself over Christmas break eventually became Blankie.

## Everything you know and love from Blanket

Blankie is fully independent and unaffiliated with the Blanket project, but it's free and open source, just like Blanket, and it's designed to work in much the same way: turn on a few sounds and set each one to its own volume.

Every one of Blanket's 14 sounds has a match in Blankie with the same name: Birds, Boat, City, Coffee Shop, Fireplace, Pink Noise, Rain, Storm, Stream, Summer Night, Train, Waves, White Noise and Wind. Some use the same openly licensed recordings while others are using new, longer loops.

Blankie has 10 more sounds on top of those: Brown Noise, Green Noise, Fan, Forest, Airplane, Laundry Room, Ambient Synth, Gentle Guitar, Warm Piano and Lo-Fi Beats. Every built-in sound is also hand-tuned for a perfect loop with a normalized volume so they blend seamlessly when mixed together.

<!-- image-todo: Blankie on Mac with All Blankie Sounds open, showing the Blanket-named tiles (Rain, Storm, Wind, Waves, Stream, Birds, Summer Night, Train, Boat, City, Coffee Shop, Fireplace, Pink Noise, White Noise) -->

## Rebuilding your Blanket mix

There's no way to bring your Blanket presets over, but rebuilding one only takes about a minute.

1. Open Blankie and choose **All Blankie Sounds** in the sidebar.
2. Click the tiles for the sounds in your Blanket mix, then drag each slider to about where you had it.
3. Click the edit icon in the top right to save the mix as a preset, with a name, artwork and an accent color.

Once it's saved, star the presets you reach for most and your keyboard's media keys will step through them. [Create and Theme Presets](/guides/create-and-manage-presets/) has the rest.

## Bringing your own sounds over

If you added your own sounds to Blanket, you can bring those same files into Blankie. Choose **File → Import** (or press {{kbd:⌘ I}}), pick the file and click **Import Sound**. Blankie reads OGG (Vorbis or Opus), MP3, M4A, WAV, FLAC, AIFF and more. Leave **Sound Check** on and Blankie will level the import to match the built-in sounds. [Import Your Own Sounds on Mac](/guides/import-sounds-mac/) walks through the whole thing.

## Keeping it running in the background

For a couple of years, Blanket was just part of the background of working at my desk. It can start with your computer so you never have to think about it, and Blankie can do the same once you change a few settings.

Blankie keeps an icon in the menu bar with your Library, volume sliders and the sleep timer. Turn on **Menu Bar Only** in **Settings → App** and it stays out of the Dock.

To have your mix start the moment Blankie opens, turn on **Autoplay on Open** in **Settings → Playback & Sounds**. Then add Blankie to **Open at Login** in **System Settings → General → Login Items & Extensions** so macOS opens it for you.

## Controlling it like any other Mac app

Blanket hooks into your Linux desktop's media controls, and Blankie does the same on a Mac. It shows up in Now Playing, so the play/pause key, Control Center and your AirPods all control your mix. [Control Blankie from Anywhere](/guides/control-blankie-anywhere/) and [Blankie Keyboard Shortcuts for Mac](/guides/keyboard-shortcuts-mac/) cover every option.

## Taking it with you

Blanket was designed for a desktop, so when people started asking me for Blankie on iPhone, I had to rethink a lot of it for your finger. Today Blankie runs on iPhone and iPad with the same sounds, and it plays in the car with [CarPlay](/guides/blankie-carplay/).

You can get it free from the [App Store](https://apps.apple.com/app/blankie/id6740096581) or with Homebrew (`brew install --cask blankie`). There are no ads, no subscriptions, no accounts and no tracking.

If you'd like the longer story of how a little Lenovo running Linux turned into Blankie, I wrote about it in [Why is Blankie free?](/guides/why-is-blankie-free/)

## Related guides

- [Get Started with Blankie](/guides/get-started/)
- [Import Your Own Sounds on Mac](/guides/import-sounds-mac/)
- [Control Blankie from Anywhere](/guides/control-blankie-anywhere/)
