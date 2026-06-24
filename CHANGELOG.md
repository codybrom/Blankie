# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.2] - 2026-06-24

### Fixed

- On iPad, lock screen animations played as a static image. Each animation will now properly show a version for the iPad lock screen.

## [2.0.1] - 2026-06-24

A quick follow-up to 2.0 with two small additions and a handful of fixes.

### Added

- **Quick Look preview for shared presets (iOS)** - Tap a `.blankie` file in Messages or Files and you'll see the preset's name, artwork, and sound count, plus how to add it to Blankie.
- **Collapsible Library sections** - Collapse the Sounds and Presets lists in your Library. Blankie will remembers what you left open.

### Changed

- **Import sounds of any length**: Removed unnecessary two-hour cap on custom sounds.

### Fixed

- White Noise had an audible seam where its loop repeated. It's been re-cut to loop cleanly.
- A preset made from your currently playing sounds might not have working lock screen and Control Center controls until you changed presets.
- On iPad, the Now Playing screen and some sheets opened as floating cards instead of filling the screen.
- Tapping a sound while everything was paused only selected it without starting playback
- The Apple Intelligence preset name suggestion wasn't showing its spinner while it was generating.
- Improved localizations for some languages.

## [2.0.0] - 2026-06-23

Blankie 2 brings Blankie to iPhone and iPad, adds CarPlay, and rebuilds the Mac app around a Library sidebar with Liquid Glass throughout.

### Breaking

- The minimum macOS version to use Blankie is now macOS 26 (Tahoe)

### Added

- **iPhone and iPad support** - Blankie is now a universal app, with layouts that adapt to each screen, iPad Split View, and an iPad sidebar for favorite presets, Quick Mix, and settings
- **CarPlay support** - Connect Blankie for iPhone to your car with CarPlay for a tabbed infotainment interface. A Home tab shows what's playing plus your recents and favorites, a Presets and Soundss tabs lists everything A to Z and Quick Mix lets you make simple mixes. Blankie's Now Playing screen also gives you one-tap favoriting, a simple preset editor and a sleep timer you can set or cancel right from CarPlay.
- **Menu bar control (macOS)** - Added a new popover to browse your Library, mix sounds, and start a timer without opening the main window. There's also options in settings to run Blankie from the menu bar only or hide the Dock icon when the window is closed.
- **Custom sounds** - Blankie now lets you import your own audio files and play them alongside the built-in library, with automatic loudness matching so they play right at a comparable volume. Import most audio formats with the option to convert to AAC to save space .
- **Ten new built-in sounds** - Airplane, Ambient Synth, Deep Noise, Fan, Forest, Gentle Guitar, Green Noise, Laundry Room, Lo-Fi Beats and Warm Piano
- **Music Loops** - some loops are now tagged as music, which tells a preset to only play one music loop at a time. Start another music loop and it will replace the playing one. Ambient Synth, Gentle Guitar, and Lo-Fi Beats come tagged, and you can tag your own imports too.
- **Favorites** - star presets or individual sounds to promote them in the iPad sidebar and CarPlay and step through them with system-wide Now Playing next/previous controls
- **Single sound playback** - play and favorite any sound on its own without making a preset
- **Lock screen animations** (iPhone) - choose from multiple video backgrounds that play on your lock screen while Blankie plays
- **Spatial Audio, experimental** - opt in via Settings to place a preset's sounds around you on a draggable map, rendered binaurally on any headphones with optional head tracking on supported AirPods
- **Apple Intelligence name and icon suggestions** - Where enabled/available, Blankie will use the on-device Apple Intelligence model to suggest a display name and icon when importing a sound (based on the file name), or a preset name based on the attached sounds. There is also one-tap re-roll and undo for each. The feature is available when importing/creating or editing sounds and presets.
- **Quick Mix** (iPhone and iPad) - a lightweight soundboard for starting sounds quickly without saving a preset
- **Now Playing screen** (iPhone and iPad) - a full-screen view with animated artwork, previous/play/next controls, a volume slider, and an AirPlay route picker. Swipe down anywhere to dismiss.
- **Library** - browse favorites, presets, and single sounds with artwork thumbnails, plus an Import menu for new presets, audio files, and `.blankie` files. On macOS, a new sidebar replaces the preset dropdown and hamburger menu.
- **Sleep timer** - stop playback after a set time, with the option to add more time on the fly
- **Make a preset from playing sounds** - When you're on the built-in "All Blankie Sounds" preset, a simple button offers to start a new preset from your current mix
- **Smooth fades and crossfades** - sounds ease in and out when played, paused, or toggled, and switching presets crossfades between mixes
- Preset import and export as `.blankie` files for sharing
- Per-sound Fade In and Out, Preset Use Only, Loop and Randomize Start options
- Per-preset theme overrides (view mode, accent color, background blur)
- Drag to reorder sounds in both grid and list views
- Interactive onboarding on first launch. Onboarding is always skippable and finishes on your new preset.
- Settings to toggle sound name labels and a visual progress border around playing sounds
- **App icon picker** - choose your ideal app icon from a grid in Settings, with twelve accent-color variants, a Dark version and a few others
- A heads-up at launch when the app volume is turned all the way down
- **VoiceOver support** - labeled controls throughout, sliders that announce and adjust volume, sounds that announce their selection state, grouped sound credits and color pickers, and a Now Playing screen that properly holds focus
- **Full keyboard control of the sound grid** (macOS) - Tab to any sound, Space to toggle it, arrow keys to adjust its volume
- **Dynamic Type support** - text scales to the preferred reading size with adaptive layouts and 44-point minimum touch targets, with larger text styles on macOS
- Polish (Polski) translation support (thanks to **Kristopheros**) and additional machine translations for new strings of existing localizations

### Changed

- New app icon, redesigned for Liquid Glass with dark and tinted variants
- Rebuilt on new audio engine so loudness normalization runs live and can now genuinely boost quiet sounds to the library's target level, a peak limiter on the final mix can prevent clipping and playback can survive output-device switches and system audio resets
- Improved the built-in sound library: re-normalized every sound with two-way K-weighted (LUFS) loudness analysis so the whole library plays at a consistent level, migrated all built-in sounds to M4A (AAC), recut the loops on most sounds so they now repeat without audible seams. Most notably, replaced the fireplace sound entirely, and made train a longer loop from the same source
- Blankie now always uses the dark system appearance on every platform to improve contrast and readability
- The Mac window now adapts its minimum size to the sidebar and opens at a roomier default size
- The Dock icon badge that shows when Blankie is paused (macOS) is now configurable
- Rebuilt Settings and Preferences rows with SwiftUI (Picker, LabeledContent, NavigationLink) so assistive technologies handle them natively
- Rebuilt the documentation website on Astro 6
- Improved German (Deutsch) translations - thanks to **H. Rapp**
- Improved Spanish (Español) translations - thanks to **Dizz7**

### Fixed

- If Blankie's global volume was saved at zero, it now prompts a warning on relaunch instead so you'll know what sounds aren't audible

### Removed

- macOS — "Hide Inactive Sounds" option: To hide sounds you do not wish to see, make a new preset.

## [1.0.13] - 2025-10-27

### Added

- Hungarian (Magyar) translation support - thanks to **Balázs**

## [1.0.12] - 2025-06-01

### Added

- Korean (한국어) translation support - thanks to **Jinhwan Kim**

### Fixed

- Fixed missing Japanese translation for a help label in the Preferences window

## [1.0.11] - 2025-05-30

### Added

- Japanese (日本語) translation support - thanks to **yoshida-uji**

### Changed

- Improved some German (Deutsch) translations

## [1.0.10] - 2025-05-29

### Added

- Portuguese (Português, pt-PT) translation support - thanks to **Júlio Coelho**

## [1.0.9] - 2025-05-27

### Changed

- Improved French (Français) translations - thanks to **Richard_M**
- Improved Chinese, Simplified (简体中文) translations - thanks to **kur1k0**
- Fixed an issue where the app wasn't restarting properly after language changes
- Improved translation credits layout

## [1.0.8] - 2025-05-21

### Added

- Italian (Italiano) translation support - thanks to **davnr**
- Language selection in Preferences (requires app restart)

### Changed

- Improved translation system with language picker

## [1.0.7] - 2025-05-15

### Added

- Turkish (Türkçe) translation support - thanks to **aybarsnazlica**
- Homebrew cask installation support (`brew install --cask blankie`)

## [1.0.6] - 2025-04-28

### Added

- Community translation templates available at blankie.rest/i18n
- Ability to submit translations without developer experience

### Changed

- Improved Spanish (Español) translations - thanks to **Chuskas**

## [1.0.5] - 2025-04-21

### Added

- Multi-language support for:
  - Spanish (Español)
  - German (Deutsch)
  - French (Français)
  - Chinese, Simplified (简体中文)

### Fixed

- UI adjustments for proper text display in all languages
- Minor UI issues

## [1.0.4] - 2025-04-04

### Added

- **Mac App Store availability** - Blankie is now available on the Mac App Store
- High-quality white noise and pink noise sound files (m4a format)
- Comprehensive FAQ document
- FAQ page on website
- Contributing page on website
- Enhanced Credits page with detailed attribution
- Proper app delegate for better lifecycle management

### Changed

- **Major project reorganization** - all source files now in centralized `/Blankie` directory
- Modernized build settings and project configuration
- Improved sound attribution with better metadata
- Enhanced sound credits display
- Updated website visuals and styling
- Better integration with macOS media controls and Now Playing
- Improved code organization with logical file structure

### Fixed

- Media control buttons not properly reflecting application state
- Preset management and display in Now Playing widget
- Sound initialization issues causing incorrect playback state on startup

## [1.0.3] - 2025-01-12

### Added

- Unified menus - combined vertical ellipsis and title bar menus
- Theme picker reintroduced - accent color customization from main window
- `WindowDefaults` and `WindowObserver` for better window management
- Debounced volume adjustments for performance
- `Link+pointHandCursor` extension for better visual feedback

### Changed

- **Breaking**: Minimum macOS requirement updated to macOS 14.5+ (Sonoma)
- Improved handling of window positions, inactive sound visibility, and global volume settings
- Enhanced "About Blankie" view consistency
- Refactored menu system for simpler navigation
- Moved `WindowObserver.swift` to `/UI/Windows`
- Enhanced error handling UI with modern SwiftUI conventions

### Fixed

- Volume changes not saving reliably or applying correctly
- Window position and size restoration across sessions

### Removed

- Unused resources and redundant code

## [1.0.2] - 2025-01-11

### Added

- blankie.rest website launch
- GitHub stars component on website
- Dynamic sound loading from JSON metadata
- Command menu toggle for showing/hiding inactive sounds
- Help menu link to blankie.rest/usage
- Detailed licensing information in About view
- Unit tests for AudioManager, PresetManager, and SoundManager
- Promo and social Open Graph images
- Docker script for website development

### Changed

- Migrated sounds metadata to `sound.json` for better structure
- Simplified new preset creation (no naming required first)
- "Now Playing" artwork, title, and info reflect current preset changes
- Enhanced toggle behavior for sound playback
- Website migrated from Jekyll to Astro (100 Lighthouse score)
- Updated README with sound credits
- Fixed keyboard shortcut for toggle (#4)

### Fixed

- Excess padding removed from icons
- Fixed relative image paths
- Optimized PNG alpha padding

## [1.0.1] - 2025-01-06

### Changed

- Refactored preset management system (#9)

## [1.0.0-alpha] - 2025-01-03

### Added

- Initial alpha release
- TestFlight availability

[Unreleased]: https://github.com/codybrom/blankie/compare/v2.0.0...HEAD
[2.0.2]: https://github.com/codybrom/blankie/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/codybrom/blankie/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/codybrom/blankie/compare/v1.0.13...v2.0.0
[1.0.13]: https://github.com/codybrom/blankie/compare/v1.0.12...v1.0.13
[1.0.12]: https://github.com/codybrom/blankie/compare/v1.0.11...v1.0.12
[1.0.11]: https://github.com/codybrom/blankie/compare/v1.0.10...v1.0.11
[1.0.10]: https://github.com/codybrom/blankie/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/codybrom/blankie/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/codybrom/blankie/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/codybrom/blankie/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/codybrom/blankie/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/codybrom/blankie/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/codybrom/blankie/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/codybrom/blankie/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/codybrom/blankie/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/codybrom/blankie/compare/v1.0.0-alpha...v1.0.1
[1.0.0-alpha]: https://github.com/codybrom/blankie/releases/tag/v1.0.0-alpha
