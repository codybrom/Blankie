# Frequently Asked Questions

## How do I get started with Blankie?

There are several ways to get started:

1. **Mac App Store**

   - Download the latest stable version of Blankie on the  [Mac App Store](https://apps.apple.com/us/app/blankie/id6740096581) and receive automatic updates.
   - _This is the recommended way to install Blankie._

2. **Homebrew**
   - If you use Homebrew, you can install Blankie with:

   ``` bash
   brew install --cask blankie
   ```

   - Blankie will be installed in your Applications folder
   - Updates can be managed through Homebrew with `brew upgrade`
   - Visit the [Blankie cask page on brew.sh](https://formulae.brew.sh/cask/blankie) for more information

3. **Direct Download**
   - Download the latest .zip from the [Releases](https://github.com/codybrom/blankie/releases) on GitHub
   - Copy the app to your Applications folder
   - Open Blankie and click a sound to start!

4. **TestFlight (Beta Versions)**

   Get early access to new features by joining our [TestFlight Public Beta](https://testflight.apple.com/join/XgpBpWv8)

## Is Blankie free?

Yes! Blankie is completely free (and open source). You can download and use Blankie at no cost, forever.

We believe everyone should have access to tools that help them focus, relax, and be productive. Blankie is developed and maintained as a passion project supported by an amazing open source community.

While Blankie will always remain free, if you'd like to support development you can:

- Star and contribute to the project on [GitHub](https://github.com/codybrom/blankie)
- Help test new features through [TestFlight](https://testflight.apple.com/join/XgpBpWv8)
- Share Blankie with others who might find it useful

## What does open source mean?

Open source means that Blankie's source code (the raw programming instructions that make the app and this website work) is publicly available for anyone to view, modify, and even contribute to.

_**Why does this matter if you're not a programmer?**_

Even if you don't write code, Blankie being open source benefits you in several important ways:

- **Transparency:** You can trust Blankie because nothing is hidden. Anyone can verify exactly how it works, what data it collects (or doesn't collect), and help identify and fix problems. Blankie can also be downloaded for use separate of the Mac App Store in an official version that is still scanned and signed by Apple to safely run as a trusted app.

- **Community:** Blankie exists thanks to a collaborative ecosystem. From sounds, to icons, to developer resources and inspirations, Blankie builds upon contributions from creators around the world who've shared their work openly. By also being open source, Blankie honors this tradition and ensures it can continue to evolve even if the original developer moves on.

- **Freedom:** The open source MIT license means Blankie is free to use without cost or restrictions, today and in the future. It also means you can make your own version of Blankie or reuse portions of its code in your own projects (as long as you follow the license terms).

Blankie's complete source code, including both the macOS app and this entire website, is available on [GitHub](https://github.com/codybrom/blankie) for anyone to explore, use, or contribute to.

## Is Blankie available in my language?

Blankie is currently available in the following languages:

- English - Default (en, en-GB)
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

## Can I contribute translations for my language?

We welcome translation contributions from the community! To help translate Blankie into your language:

1. Download the English text strings template or existing translation files for your language from [blankie.rest/i18n](https://blankie.rest/i18n)
2. Translate the strings in the CSV or JSON file
3. Submit your translations either:
   - Through a [GitHub Issue](https://github.com/codybrom/blankie/issues/new?assignees=&labels=translation-contribution&projects=&template=translation_contribution.yml&title=%5BTranslation%5D%3A+)
   - By emailing updated localization templates to <i18n@blankie.rest>
   - Creating a pull request on our [GitHub repository](https://github.com/codybrom/blankie) with changes added to `Localizable.xcstrings`

No coding experience is required to contribute translations! For more detailed instructions, see our [contribution guidelines](https://blankie.rest/contributing#translation-contributions).

If you notice any translation issues or have general feedback about existing translations, please email <i18n@blankie.rest>.

## How can I contribute to Blankie?

Check out our [Contributing guide](/CONTRIBUTING.md) for more information on how to get involved.

## How do I control playback and volume?

**Play/Pause:** The main play/pause button at the bottom center controls all selected sounds simultaneously. You can also:

- Use media keys on your keyboard
- Control from the Now Playing widget in your menubar
- Control directly from AirPods and other compatible headphones

**Volume:**

- Use individual sliders for each sound
- Access the "All Sounds" volume slider from the controls bar (speaker icon) to blend with other apps

## Can I save my favorite sound combinations?

Yes! Presets store active sounds and their volume levels. You can save and load different combinations as presets. If you don't have any presets saved, Blankie will load whatever sounds were active when you last closed the app.

To save a preset, click the "Presets" dropdown in the titlebar, and then click "New Preset". When you create your first preset, Blankie will automatically copy your current sound settings to it. Any changes you make to an active preset's sounds or volumes are saved immediately. There's no need to manually save your changes.

To rename or delete a preset, click the "Presets" dropdown in the titlebar, and then click either the pencil or trash icon next to the preset you want to edit.

## Can I add my own sounds?

Not yet, but custom sound support is planned for a future update. Follow our GitHub repository for updates!

## What customization options are available?

- Hide inactive sounds for a cleaner interface
- Use keyboard shortcuts for quick access to main functions
- Customize appearance and auto-start settings in Preferences

## Where can I find keyboard shortcuts?

Access the full list of keyboard shortcuts from the "Keyboard Shortcuts" panel in the Titlebar menu.

## How do I access Preferences?

Open Preferences through either:

- The Settings menu in your Mac's menubar under Blankie
- The titlebar menu

## What is the difference between Blankie and Blanket?

Blankie is a native macOS app inspired by Blanket, but it's completely separate and independently developed:

- Written specifically for macOS using Swift and SwiftUI
- Designed to feel native on Apple Silicon and Intel Macs
- Built with different sound mixing and playback technology
- Independent codebase (though we use some of the same openly licensed sounds)

## Does Blankie collect any data?

No. Blankie doesn't collect any data or connect to the internet. When distributed through Apple's platforms, Apple provides basic anonymous statistics about downloads and crashes, but the app itself never collects or transmits any data. See our [Privacy Policy](https://blankie.rest/privacy) for more details.

## I found a bug. How do I report it?

Please open an issue on our [GitHub Issues page](https://github.com/codybrom/blankie/issues). Include as much detail as possible about what happened and how to reproduce the bug.
