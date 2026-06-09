# CarPlay implementation

## Overview

Blankie supports CarPlay (for compatible devices and vehicles) with a tabbed interface for presets, sounds and Quick Mix.

Any contributor can build the standard app and test CarPlay in the simulator. Building CarPlay for a real device (not the simulator) requires the `com.apple.developer.carplay-audio` entitlement. Apple grants it per developer bundle ID, and registered developers have to apply for it.

For this reason, Blankie's CarPlay code lives behind its own build configurations and scheme. Official releases with CarPlay are exclusively built by maintainers whose bundle ID carries the approved entitlement.

## Scheme details

| Component | Universal | Universal with CarPlay |
| -------------------------- | --------------------- | ---------------------------------- |
| **Scheme** | `Blankie (Universal)` | `Blankie (Universal with CarPlay)` |
| **Build configs** | `Debug`, `Release` | `Debug-CarPlay`, `Release-CarPlay` |
| **Can build for** | iPhone, iPad, Mac | iPhone, iPad, Mac |
| **Entitlements** | `Blankie.entitlements` | `Blankie-CarPlay.entitlements` |
| **Info.plist** | `Blankie-Info.plist` | `Blankie-CarPlay.plist` |
| **Scene generation** (iOS) | Automatic (`YES`) | Manual (`NO`) |
| **CarPlay compiler flag** | — | `CARPLAY_ENABLED` (iOS SDKs only) |

Both schemes build the same universal app for iPhone, iPad, and Mac (native, no Mac Catalyst). The CarPlay scheme adds four things:

- CarPlay code, gated to the iOS SDKs by `CARPLAY_ENABLED` (the flag is set only for `iphoneos` and `iphonesimulator`, so CarPlay code never reaches the Mac build)
- `Blankie-CarPlay.entitlements` that includes `com.apple.developer.carplay-audio`
- A custom Info.plist (`Blankie-CarPlay.plist`) with the CarPlay scene configuration
- Manual scene-manifest generation on iOS (`NO`), so the app handles the CarPlay scene itself

## Implementation files

All CarPlay code lives under `Blankie/CarPlay/`:

- `CarPlaySceneDelegate.swift` — CarPlay scene lifecycle
- `CarPlayInterfaceController.swift` — root interface controller and tab setup
- `CarPlayAudioBridge.swift` — bridges CarPlay actions to the audio managers
- `CarPlayNowPlayingExtensions.swift` — Now Playing buttons (favoriting, sleep timer, preset edit)
- `CarPlayPresetEditController.swift` — the in-car preset editor
- `Templates/` — the CarPlay list and grid templates:
  - `PresetListTemplate.swift` — Recent, Favorites, and All presets
  - `SoundsListTemplate.swift` — individual sounds
  - `QuickMixGridTemplate.swift` — the Quick Mix soundboard
  - `PresetEditTemplate.swift` — preset editor template
  - `TimerOptionsTemplate.swift` — sleep-timer picker

## Development workflow

**Normal build (any platform):** use `Blankie (Universal)`. CarPlay code is excluded. No setup needed.

**Test CarPlay in the simulator:** use `Blankie (Universal with CarPlay)`. No entitlement needed. The iOS Simulator has a CarPlay display under I/O → External Displays → CarPlay.

**CarPlay on a real device:** use `Blankie (Universal with CarPlay)` with the `com.apple.developer.carplay-audio` entitlement approved for your developer bundle ID. Alternatively, a maintainer can build and push the change on a TestFlight build.

### Conditional compilation

CarPlay-specific code is wrapped with `CARPLAY_ENABLED`, so it only compiles into the CarPlay build and only for iOS:

```swift
#if CARPLAY_ENABLED && canImport(CarPlay)
  import CarPlay

  class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    // CarPlay scene lifecycle
  }
#endif
```
