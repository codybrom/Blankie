---
title: "Convert Audio Files for Blankie"
description: "Convert WMA and other unsupported audio formats, or pull the audio from a video, so it imports into Blankie on Mac, iPhone, and iPad."
category: "import"
order: 5
updated: 2026-06-06
---

Blankie works with the most common audio formats on its own: M4A, MP3, WAV, FLAC, AIFF, OGG, CAF, AAC and AU. Two things still need a step first: a video you only want the sound from and a Windows Media (WMA) file. Here's how to handle each.

<!-- image-todo: macOS, dark mode, Blankie in a Mac window frame. Capture the custom-sound import sheet that appears after you select an audio file to import (reached by opening Manage Sounds, default shortcut Cmd+O, then choosing Import and picking a file). Use a single chosen file named 'bedroom-fan.m4a' with the name field filled in as 'Bedroom Fan'. Show the name field, the SF Symbol icon picker with an icon selected, a visible preview/play button, the Sound Check toggle ON with its description line ('Sound Check adjusts the loudness between different sounds to play at the same volume.'), any supported-format/size hint the sheet shows, and the Import/Add button. The grid of built-in sounds (rain, ocean waves, fireplace) can be dimmed behind the sheet. Crop to the window/sheet with the sheet as the clear focus; no desktop clutter. -->

## Pull the audio out of a video

Got a video and only want its sound? A video of rain, a clip with good ambience in the background, a screen recording? Apple's Shortcuts app can pull the audio into an M4A on iPhone, iPad, and Mac, no extra software needed.

The easy way is a ready-made shortcut. Add **[Convert Video to Audio](https://www.icloud.com/shortcuts/67392ea91eea434285b237f36dddaf42)**, then use it whichever way suits the device:

- **On Mac**, right-click a video in Finder and choose **Quick Actions → Convert Video to Audio**.
- **On iPhone or iPad**, share a video to it from the share sheet, or open the shortcut and pick the video from Photos or Files.

It saves an M4A into a "Converted" folder and opens the result, ready to [import into Blankie](/guides/import-sounds-iphone-ipad/).

You can also build your own version. In the Shortcuts app, add **Encode Media** with **Audio Only** turned on, feed it a video from **Select Photos** or **Select File**, and finish with **Save File**.

Alternatively, you can use free browser-based tools like [Convertio](https://convertio.co/audio-converter/) to pull out just the audio, or if you're at a computer use [Audacity](https://www.audacityteam.org) with its free [FFmpeg add-on](https://support.audacityteam.org/basics/installing-ffmpeg). [Import the result](/guides/import-sounds-iphone-ipad/) like any other sound.

## Convert an unsupported format (like WMA)

WMA is far less common of a format than it used to be, but it's just about the only one Blankie can't read. The fastest and easiest option (and only one on iPhone and iPad) to make it Blankie-compatible is to use a free, browser-based converter. Load up [Convertio](https://convertio.co/audio-converter/), or one of the many sites like it, in your browser, choose M4A or MP3 as the output and then download the result.

If you have a computer, [Audacity](https://www.audacityteam.org) is a free audio editor, but you'll need to install the free [FFmpeg add-on](https://support.audacityteam.org/basics/installing-ffmpeg) (a one-time setup) before it can read and convert a WMA file. After that's set up, open the file, choose **[File → Export Audio](https://manual.audacityteam.org/man/file_export_dialog.html)**, and then pick M4A or MP3. Both are compact, and Blankie reads them natively.

## Related guides

- [Import Your Own Sounds on Mac](/guides/import-sounds-mac/)
- [Import Your Own Sounds on iPhone & iPad](/guides/import-sounds-iphone-ipad/)
- [Where to Find Free Ambient Sounds](/guides/find-free-ambient-sounds/)
