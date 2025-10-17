# Animated Lock-Screen Artwork (iOS 26)

Implementation guide for bringing animated “Now Playing” artwork to Blankie presets in iOS 26, with graceful fallbacks for earlier OS versions and motion-sensitive contexts.

## Scope & Objectives

- Surface a short looping animation for the active preset on Lock Screen, Control Center, Now Playing widgets, and other system surfaces that honour `MPNowPlayingInfoProperty1x1AnimatedArtwork`.
- Keep static artwork behaviour unchanged everywhere else; animated keys are additive.
- Ensure users can opt into bundled loops or import their own video per preset.
- Respect Reduced Motion, Low Power Mode, and an explicit app-level toggle.

## Compatibility Matrix

- **Animated path**: iOS 26+ devices that report support for `MPNowPlayingInfoProperty1x1AnimatedArtwork`, Reduce Motion OFF, Low Power Mode OFF, and the user setting enabled.
- **Static fallback**: iOS 15–25, CarPlay surfaces that do not opt in, Reduce Motion ON, Low Power Mode ON, or when animated assets are missing/corrupt.
- Always publish the static `MPMediaItemPropertyArtwork` entry to guarantee a baseline image on every surface.

## Data Model & Storage

- Add `AnimatedArtworkRef` and `staticArtworkPath` to `Preset` in `Blankie/Models/Preset.swift`.

  ```swift
  struct AnimatedArtworkRef: Codable, Hashable {
    enum Source: String, Codable { case auto, bundled, custom }
    var source: Source
    var loopPath: String?        // Documents-relative path (e.g. "Artwork/<uuid>.mov")
    var previewPath: String?     // Documents-relative path (e.g. "Artwork/<uuid>.jpg")
    var preferredAspect: String? // "1x1" today; keep string for future 16x9/9x16 keys
  }
  ```

- Store built-in and user imports under `Documents/Artwork/…`. Keep file naming deterministic (`<uuid>.mov/.jpg`) to avoid collisions and simplify export/import.
- Increment the preset schema version (e.g., to `2`) and add a migration that initialises `artwork = nil` and `staticArtworkPath` from legacy data if present.
- Update preset serialisation, export/import flows, and sample JSON seeds to carry the new fields.

## Bundled Assets

- Place two demo loops and their JPG previews in `Blankie/Assets/AnimatedArtwork/`.
  - Suggested names: `RainLoop.mov`, `RainLoop.jpg`, `CampfireLoop.mov`, `CampfireLoop.jpg`.
  - Encode as HEVC or H.264, 1080×1080, 3–7 s, muted, < 12 MB.
- Expose them via an enum or lookup table in code so the picker can copy the correct file into the Documents sandbox on selection.
- Ensure the asset catalog or build phase copies the `.mov` and `.jpg` files into the main bundle for runtime access.

## Animated Artwork Publisher

- Add `Blankie/Shared/NowPlaying/BlankieAnimatedArtwork.swift` implementing `@MainActor func publishNowPlaying(for preset: Preset)`.
- Behavioural flow:
  1. Start with existing `nowPlayingInfo` and set `MPMediaItemPropertyTitle`/`Artist`.
  2. If `preset.staticArtworkPath` exists and loads, set `MPMediaItemPropertyArtwork` using `MPMediaItemArtwork`.
  3. Gate animated artwork behind:
     - `#available(iOS 26, *)`
     - `UIAccessibility.isReduceMotionEnabled == false`
     - `ProcessInfo.processInfo.isLowPowerModeEnabled == false`
     - App-level “Lock-Screen Background” toggle (new setting).
     - Non-nil `AnimatedArtworkRef.loopPath` and `previewPath` that can be loaded.
  4. Query `MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys`; proceed only if it contains `MPNowPlayingInfoProperty1x1AnimatedArtwork`.
  5. Build `AVURLAsset` for the loop video and `UIImage` preview, then assign an `MPMediaItemAnimatedArtwork` instance into the `nowPlayingInfo` dictionary under the animated key.
  6. Assign the final dictionary back to `MPNowPlayingInfoCenter.default().nowPlayingInfo`.
- Provide a helper `func appDocumentsPath(_ relative: String) -> URL` to keep path handling consistent across the app.

## Playback Integration Points

- Invoke `publishNowPlaying(for:)` whenever playback starts or resumes, the active preset changes (e.g., QuickMix, next/previous), artwork metadata is updated, or the user toggles Lock-Screen background in Settings.
- Centralise these calls in the playback manager/view model to avoid race conditions between UI components.
- Consider debouncing rapid preset switches to avoid thrashing the Now Playing center.

## Preset Editor UI

- Create `Blankie/Features/Presets/AnimatedArtworkPicker.swift` (SwiftUI):
  - Segmented control for `Auto (scene)`, `Built-in loop`, `Custom video…`.
  - When switching sources, initialise `AnimatedArtworkRef` if needed and update `source`.
  - For built-in selection, copy the chosen bundle asset into Documents/Artwork and update `loopPath` + `previewPath`.
  - For custom video:
    1. Use `PhotosPicker` (`matching: .videos`) to select a clip.
    2. Copy to Documents/Artwork/`<uuid>.mov`.
    3. Generate a preview JPG using `AVAssetImageGenerator` frame 0 → Documents/Artwork/`<uuid>.jpg`.
    4. Update the bound `AnimatedArtworkRef`.
    5. Optionally, warn if duration > 7 s or file size > 15 MB (future enhancement).
- Surface a thumbnail/loop preview in the editor (static preview image is sufficient for v1).

## Settings Toggle

- Add “Lock-Screen Background” (default ON) to Settings.
- Store in persistent settings (UserDefaults or existing config store).
- Ensure toggling republishers Now Playing info and updates the UI state.

## Reduce Motion & Low Power

- Listen for `UIAccessibility.reduceMotionStatusDidChangeNotification` and `NSProcessInfoPowerStateDidChange` to re-publish metadata if system preferences change mid-session.
- Provide local logging when animated artwork is skipped, aiding QA.

## Migration & Backups

- Include animated artwork files in existing preset export/import flows.
- Update backup/restore scripts to include `Documents/Artwork/`.
- When deleting a preset or removing custom artwork, delete orphaned files to keep storage tidy.

## QA Matrix

- Devices: iOS 26 simulator + physical device (animated path), one iOS 15–25 device (static path), at least one CarPlay session if possible.
- Scenarios:
  1. Start playback → animated loop shows on Lock Screen and Control Center within 1 s.
  2. Switch presets rapidly → animation updates without stale imagery.
  3. Reduce Motion ON → static image only; turning OFF re-enables animation after republish.
  4. Low Power Mode ON while playing → animation removed on next publish.
  5. Background/foreground transitions keep the chosen artwork.
  6. Route changes (Bluetooth, AirPlay, calls) do not clear animated keys.
  7. Import oversized clip → handled gracefully (warning or truncation if implemented).
  8. CarPlay → static artwork present, no crashes.

## Optional Analytics

- Events: `animated_artwork_enabled`, `animated_artwork_disabled`, `animated_artwork_imported`.
- Properties: preset ID, loop source (`auto/bundled/custom`), file size buckets, duration buckets.
- Guard analytics emissions behind privacy consent.

## Definition of Done

- Preset model schema migrated and persisted across app surfaces.
- Publisher sets all static fields and only appends `MPNowPlayingInfoProperty1x1AnimatedArtwork` when supported.
- Preset editor exposes auto/bundled/custom flows; imports create preview JPGs.
- Bundled loops compile into the app and appear in picker.
- Settings toggle works and re-publishes metadata immediately.
- Reduce Motion & Low Power overrides verified.
- QA scenarios above pass on target OS versions.
- Release notes include: “Animated Lock-Screen backgrounds for presets (iOS 26+). Choose built-in loops or attach your own short video. Respects Reduced Motion and Low Power Mode.”

## Open Questions / Follow-ups

- Do we need trimming/compression UI for custom videos on day one, or is a warning modal sufficient?
- Should auto mode derive artwork from scene metadata or fallback to static imagery today?
- Coordinate with marketing for loop asset approvals before shipping.
