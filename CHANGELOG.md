# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.10] - 2025-05-29

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

[Unreleased]: https://github.com/codybrom/blankie/compare/v1.0.10...HEAD
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
