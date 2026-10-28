# Frequently Asked Questions

## Getting started

### What devices can run Blankie?

Blankie runs on **Mac** (macOS 26 Tahoe or later), **iPhone** (iOS 26.4 or later) and **iPad** (iPadOS 26.4 or later). **CarPlay** is available when you connected a compatible iPhone to a CarPlay-enabled vehicle.

### Can I use Blankie on older versions of macOS?

If your Mac is on macOS 15 Sequoia or macOS 14 Sonoma (14.6 or later), you can [download Blankie Classic](https://github.com/codybrom/blankie/releases/download/v1.0.13/Blankie.zip), the final release of Blankie v1. Classic doesn't have the same features as the current version and won't get new features or updates, but it's still free and still works offline.

### How do I install Blankie?

There are a few different ways to install Blankie depending on your platform:

- **[App Store](https://apps.apple.com/us/app/blankie/id6740096581)** (***Recommended*** - All Platforms)

  - Blankie is free to download for iPhone, iPad and Mac and will receive automatic updates.
  
- **Homebrew** (Mac Only)

  - If you use Homebrew, you can install Blankie by running `brew install --cask blankie` in your terminal.
  - Blankie will be installed in your Applications folder and future updates can be managed through Homebrew by running `brew upgrade`
  - Visit the [Blankie cask page on brew.sh](https://formulae.brew.sh/cask/blankie) for more information

- **Direct download** (Mac Only)

  - Download `Blankie.zip` from the newest version on the [Releases](https://github.com/codybrom/blankie/releases) page on GitHub
  - Copy the app to your Applications folder, then open Blankie to start!
  - *Note: Direct download copies of Blankie do not check for updates or update automatically.*

### Does Blankie work offline?

Yes. All sounds are bundled inside the app, so once Blankie is downloaded it plays entirely offline.

The only time it connects to the internet is to fetch animated Lock Screen artwork (iOS Only), but these are fetched from Apple's servers, not Blankie's, and no identifiers are ever sent or stored.

### Can my school or organization deploy Blankie?

Yes. Schools and organizations have already deployed Blankie to 1,000+ devices worldwide. Blankie is available for free in Apple School Manager and Apple Business Manager and can be installed in bulk on managed Mac, iPad and iPhone devices.

Blankie is a great fit for locked-down, educational and organizational devices because there's no account to create and the app never collects or sends any personal or usage data whatsoever.

If your organization is interested in a customized or white-labeled version of Blankie with your organization's branding, sounds or presets, email <info@blankie.rest> for licensing.

## Sounds and presets

### Can I add my own sounds?

Yes! As of Blankie 2.0 you can import your own audio files (M4A, MP3, WAV, FLAC, OGG and more) and play them alongside the built-in library. Imported sounds are automatically loudness-matched so they sit at a comparable volume to the built-in sounds, and you can give each imported sound its own name, icon and loop settings.

To import a sound, choose **File → Import** on Mac, or tap the **+** button in your Library on iPhone and iPad. For step-by-step instructions (including how to turn a Voice Memo into a Blankie sound), see our [import guides](https://blankie.rest/guides).

### Can I save my favorite sound combinations?

Yes! Presets store active sounds and their volume levels. You can save and load different combinations as presets. If you don't have any presets saved, Blankie will load whatever sounds were active when you last closed the app.

To save a preset, click the **+** button at the top of the sidebar (Mac and iPad) or in your Library (iPhone), then choose "New Preset." Any changes you make to an active preset's sounds or volumes are saved immediately. There's no need to manually save your changes.

To rename or delete a preset, right-click it on Mac (or touch and hold on iPhone and iPad) and choose "Edit Preset" or "Delete Preset."

### What customization options are available?

- You can import your own sounds and assign an icon to each one
- Give each preset its own accent color and Now Playing artwork
- Set a grid or list layout for your sounds (iPhone and iPad)
- Star presets as favorites
- Set a sleep timer to stop playback automatically
- Set whether to auto-play on launch

## Playback and controls

### How do I control playback and volume?

**Play/Pause:** The main play/pause button at the bottom center controls all selected sounds simultaneously. You can also:

- Use media keys on your keyboard
- Use the system Now Playing control in the macOS menu bar
- Control directly from AirPods and other compatible headphones
- Use Blankie's Home Screen widgets on iPhone and iPad
- Ask Siri on iPhone and iPad to start a preset, a single sound or a sleep timer, or use Blankie actions in Shortcuts

**Volume:**

- Use individual sliders for each sound
- Access the "All Sounds" volume slider from the controls bar (speaker icon) to blend with other apps

### What widgets does Blankie have?

On iPhone and iPad, add **Now Playing**, **Favorites**, **Pinned Sound** or **Quick Mix** from the Home Screen widget gallery. Favorites and Quick Mix offer medium, large and portrait XL (iOS 27) sizes, plus custom widget colors; Now Playing and Pinned Sound are small. Edit the Pinned Sound widget to choose either a preset or a sound.

### Can I use Blankie with Siri and Shortcuts?

Yes. On iPhone and iPad, say "Start a preset in Blankie" or "Start a sound in Blankie," then give its name when Siri asks, or say "Start a sleep timer in Blankie." Starting a single sound plays it on its own and leaves your saved presets unchanged.

Blankie's actions are also available in Shortcuts on Mac, iPhone and iPad. You can control playback, choose presets and sounds, set a sleep timer and adjust volume. On iPhone and iPad, the overall Set Volume action requires **Mix with Other Audio** in Settings; individual sound volumes can be set separately. Spotlight can find your presets and sounds on all three platforms.

### Where can I find keyboard shortcuts for Mac?

Access the full list of keyboard shortcuts from "Keyboard Shortcuts" in the Help menu.

### How do I access Settings?

Open Settings by clicking the gear button at the bottom of the sidebar on Mac, or the gear button in your Library on iPhone and iPad.

## Free, open source and community

### Is Blankie free?

Yes! Blankie is both [free as in beer](https://en.wiktionary.org/wiki/free_as_in_beer) ***and*** [free as in freedom](https://www.gnu.org/philosophy/free-sw.html). It costs nothing to download and use, forever, and it's [open source](#what-does-open-source-mean), so anyone can read, change and share the code.

Blankie is my passion project. I'm [Cody Bromley](https://github.com/codybrom), the independent developer who makes it. I wanted a good ambient mixer that didn't suck, so I built one and I'm happy to give it away (read the full story in [Why is Blankie free?](https://blankie.rest/guides/why-is-blankie-free/)). It keeps getting better thanks to contributors and translators around the world.

While Blankie will always remain free, if you'd like to support development you can:

- Star and contribute to the project on [GitHub](https://github.com/codybrom/blankie)
- Help test new features through [TestFlight](https://testflight.apple.com/join/XgpBpWv8)
- Share Blankie with others who might find it useful

### What does open source mean?

Open source means that Blankie's source code (the raw programming instructions that make the app and this website work) is publicly available for anyone to view, modify and even contribute to.

***Why does this matter if you're not a programmer?***

Even if you don't write code, Blankie being open source benefits you in several important ways:

- **Transparency:** You can trust Blankie because nothing is hidden. Anyone can verify exactly how it works, what data it collects (or doesn't collect) and help identify and fix problems. Blankie can also be downloaded for use separate of the Mac App Store in an official version that is still scanned and signed by Apple to safely run as a trusted app.

- **Community:** Blankie exists thanks to a collaborative ecosystem. From sounds, to translations, to developer resources and inspirations, Blankie builds upon contributions from creators around the world who've shared their work openly. By also being open source, Blankie honors this tradition and ensures it can continue to evolve even if the original developer moves on.

- **Freedom:** The open-source MIT license means Blankie is free to use without cost or restrictions, today and in the future. It also means you can make your own version of Blankie or reuse portions of its code in your own projects (as long as you follow the license terms).

Blankie's complete source code, including both the Blankie app and this entire website, is available on [GitHub](https://github.com/codybrom/blankie) for anyone to explore, use or contribute to.

### How is Blankie different from Blanket?

Blankie is a native app for Apple platforms inspired by Blanket. It uses some of the same openly licensed sounds but is completely separate and independently developed:

- Native apps for Mac, iPhone and iPad written in Swift
- Different sound mixing and playback technology
- Different features and developers

### Is Blankie available in my language?

Blankie is currently available in the following languages:

- English - Default (en, en-GB, en-CA)
- Deutsch (de)
- Español (es)
- Français (fr)
- Italiano (it)
- Magyar (hu)
- Polski (pl)
- 日本語 (ja)
- 한국어 (ko)
- Português (pt-PT)
- Türkçe (tr)
- 简体中文 (zh-Hans)

We're actively working on translations for more languages, and you can help! If you'd like to contribute translations for your language, visit our [translation page](https://blankie.rest/i18n) to see the current status and download a translation template.

### Can I contribute translations for my language?

We welcome translation contributions from the community! To help translate Blankie into your language:

- Download the English text strings template or existing translation files for your language from [blankie.rest/i18n](https://blankie.rest/i18n)
- Translate the strings in the CSV or JSON file
- Submit your translations either:
  - Through a [GitHub Issue](https://github.com/codybrom/blankie/issues/new?assignees=&labels=translation-contribution&projects=&template=translation_contribution.yml&title=%5BTranslation%5D%3A+)
  - By emailing updated localization templates to <i18n@blankie.rest>
  - Creating a pull request on our [GitHub repository](https://github.com/codybrom/blankie) with changes added to `Localizable.xcstrings`

No coding experience is required to contribute translations! For more detailed instructions, see our [contribution guidelines](https://blankie.rest/contributing#translation-contributions).

If you notice any translation issues or have general feedback about existing translations, please email <i18n@blankie.rest>.

### How can I contribute to Blankie?

Check out our [Contributing guide](/CONTRIBUTING.md) for more information on how to get involved.

## Privacy and support

### Does Blankie collect data about me?

No. Blankie never collects any user data, usage analytics or identifiers that can be used to track you. Because Blankie never collects any information about you, it can't transmit any information about you.

When you download Blankie from an Apple platform, Apple collects basic anonymous statistics about downloads and crashes, some of which may be shared with us but without any ability to identify you.

The only time Blankie connects to the internet is to download animated artwork from Apple's servers (not Blankie's). No personal data is ever sent to or shared with the developer. See our [Privacy Policy](https://blankie.rest/privacy) for more details.

### Where is my data stored?

All Blankie data is stored on your device. Your presets, settings and any sounds you import are 100% local to the app. There's no Blankie account to sign into and nothing synced to a Blankie server. Your library is yours and yours alone.

### I found a bug. How do I report it?

The easiest way to share feedback is [through our Google Form](https://forms.gle/fRwxBEQqPK5qgH427). Providing your email address is optional. We only collect an email address so we can respond to your messages. Emails are never shared with any other parties.

If you're technically inclined, you can also open an issue on our [GitHub Issues page](https://github.com/codybrom/blankie/issues). Include as much detail as possible about what happened and how to reproduce the bug.
