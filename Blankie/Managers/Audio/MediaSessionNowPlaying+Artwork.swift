//
//  MediaSessionNowPlaying+Artwork.swift
//  Blankie
//
//  Created by Cody Bromley on 9/15/26.
//
//  Artwork and App Intents identity for the OS 27 session: the same source
//  priority as the 26 backend, published as id-addressed providers.

#if canImport(NowPlaying)
  import AppIntents
  import Foundation
  import NowPlaying
  import SwiftUI
  import os

  #if os(iOS)
    import UIKit
  #endif

  @available(iOS 27, macOS 27, visionOS 27, *)
  extension MediaSessionNowPlaying {

    // MARK: - App Intents identity

    /// What the card points at in Siri and Shortcuts. Quick Mix is not a preset
    /// and has no entity of its own, so it points at nothing.
    func entityIdentifiers(for preset: Preset?) -> [EntityIdentifier] {
      if let soloSound = AudioManager.shared.soloModeSound {
        return [EntityIdentifier(for: SoundEntity.self, identifier: soloSound.fileName)]
      }
      guard !AudioManager.shared.isQuickMix, let preset else { return [] }
      return [EntityIdentifier(for: PresetEntity.self, identifier: preset.id)]
    }

    // MARK: - Artwork

    /// Rebuilds the card's artwork, but after the first pass only when the
    /// preset or the soloed sound actually changed — the system caches artwork
    /// by id, and a new animated artwork restarts the video.
    func refreshArtwork(preset: Preset?, fallbackArtworkId: UUID?) {
      let soloSound = AudioManager.shared.soloModeSound
      let soloSoundId = soloSound?.id
      guard !hasBuiltArtwork || preset?.id != lastPresetId || soloSoundId != lastSoloSoundId
      else {
        refreshFallbackArtworkIfItsIdChanged()
        return
      }
      hasBuiltArtwork = true
      lastPresetId = preset?.id
      lastSoloSoundId = soloSoundId

      if let soloSound {
        // Solo mode: the sound's own icon, not the last preset's artwork.
        applySoloArtwork(for: soloSound)
        #if os(iOS)
          clearAnimatedArtwork()
        #endif
        return
      }

      let effectivePreset = effectiveArtworkPreset(for: preset)
      applyStaticArtwork(
        for: preset, inherited: effectivePreset, fallbackArtworkId: fallbackArtworkId)
      #if os(iOS)
        refreshAnimatedArtwork(for: effectivePreset)
      #endif
    }

    /// Presets without their own lock screen background inherit the app-wide
    /// default (preset → default → Blankie icon). Substituted on a value copy so
    /// the fallback is never persisted onto the preset.
    private func effectiveArtworkPreset(for preset: Preset?) -> Preset? {
      var effectivePreset = preset
      if effectivePreset != nil, effectivePreset?.animatedArtwork == nil {
        effectivePreset?.animatedArtwork = GlobalSettings.shared.defaultLockScreenArtwork
      } else if effectivePreset == nil, AudioManager.shared.isQuickMix,
        let defaultArtwork = GlobalSettings.shared.defaultLockScreenArtwork
      {
        // Quick Mix has no preset of its own, so it never reaches the fallback
        // above. Give it the app-wide default lock screen animation via a
        // throwaway preset that only carries the artwork.
        effectivePreset = Preset(
          id: UUID(),
          name: "Quick Mix",
          soundStates: [],
          isDefault: false,
          createdVersion: nil,
          animatedArtwork: defaultArtwork
        )
      }
      return effectivePreset
    }

    /// The still image: stored artwork, then the preset's own previews (bundled
    /// square preview, cached square preview, any other cached preview), then
    /// the same previews of the inherited default animation, then the drawn
    /// fallback. A preset's own image always beats the app-wide default's.
    private func applyStaticArtwork(
      for preset: Preset?, inherited: Preset?, fallbackArtworkId: UUID?
    ) {
      if let artworkId = preset?.artworkId ?? fallbackArtworkId {
        // Decided in the same pass as the title: the system reads an item's
        // artwork once, so a still that arrives later is never shown.
        if let data = PresetArtworkManager.shared.storedArtworkData(id: artworkId) {
          setArtwork(data: data, source: .stored(artworkId))
        } else {
          Logger.nowPlaying.debug("MediaSessionNowPlaying: no stored artwork, using fallback")
          applyFallbackArtwork()
        }
        return
      }

      #if os(iOS) && !WIDGET_EXTENSION
        if let preset, applyCachedArtwork(for: preset) { return }
        if let inherited, inherited != preset, applyCachedArtwork(for: inherited) { return }
      #endif

      applyFallbackArtwork()
    }

    #if os(iOS) && !WIDGET_EXTENSION
      /// The bundled and Documents-cached previews. False when none applies.
      private func applyCachedArtwork(for preset: Preset) -> Bool {
        if let bundledId = preset.animatedArtwork?.bundledIdentifier,
          let asset = BundledAnimatedLoop.allCases.first(where: { $0.id == bundledId }),
          let squarePreviewURL = Bundle.main.url(
            forResource: asset.squarePreviewResourceName,
            withExtension: asset.squarePreviewExtension
          ),
          let data = try? Data(contentsOf: squarePreviewURL)
        {
          setArtwork(data: data, source: .bundled(bundledId))
          return true
        }

        if let squarePreviewPath = preset.animatedArtwork?.squarePreviewPath,
          AnimatedArtworkFileStore.fileExists(at: squarePreviewPath),
          let data = try? Data(
            contentsOf: AnimatedArtworkFileStore.absoluteURL(for: squarePreviewPath))
        {
          setArtwork(data: data, source: .file(squarePreviewPath))
          return true
        }

        let candidatePath = preset.staticArtworkPath ?? preset.animatedArtwork?.previewPath
        if let candidatePath, AnimatedArtworkFileStore.fileExists(at: candidatePath),
          let data = try? Data(contentsOf: AnimatedArtworkFileStore.absoluteURL(for: candidatePath))
        {
          setArtwork(data: data, source: .file(candidatePath))
          return true
        }

        return false
      }
    #endif

    /// A soloed sound's artwork: its SF Symbol on the accent-tinted card.
    private func applySoloArtwork(for sound: Sound) {
      guard let data = Self.jpegData(NowPlayingDisplay.soloFallbackImage(for: sound)) else {
        applyFallbackArtwork()
        return
      }
      setArtwork(data: data, source: .solo(fileName: sound.fileName))
    }

    /// The drawn fallback encodes the selected sounds' icons and the accent, so
    /// a selection change within the same preset needs a new still although the
    /// identity gate holds. Static only: the animated loop stays put.
    private func refreshFallbackArtworkIfItsIdChanged() {
      guard let current = model.artwork?.id, current.hasPrefix("fallback:") else { return }
      let id = NowPlayingSessionMapping.artworkID(
        source: Self.fallbackArtworkSource(), accentColorName: artworkAccentName)
      if id != current { applyFallbackArtwork() }
    }

    /// The drawn fallback a mix without artwork of its own shows. A render can
    /// fail while the app is in the background; then the last good render for
    /// the same id stands in, and the next publish tries again rather than
    /// leaving the card bare (the system never re-reads a bare item).
    private func applyFallbackArtwork() {
      let source = Self.fallbackArtworkSource()
      let id = NowPlayingSessionMapping.artworkID(
        source: source, accentColorName: artworkAccentName)
      if let data = Self.jpegData(NowPlayingDisplay.mixFallbackImage()) {
        fallbackArtworkCache[id] = data
        setArtwork(data: data, source: source)
      } else if let data = fallbackArtworkCache[id] {
        Logger.nowPlaying.error(
          "MediaSessionNowPlaying: fallback artwork render failed, reusing \(id, privacy: .public)")
        setArtwork(data: data, source: source)
      } else {
        Logger.nowPlaying.error(
          "MediaSessionNowPlaying: fallback artwork render failed for \(id, privacy: .public)")
        model.artwork = nil
        hasBuiltArtwork = false
      }
    }

    /// The provider is called on the system's schedule and cached by id, so it
    /// captures the bytes and nothing else.
    private func setArtwork(data: Data, source: NowPlayingSessionMapping.ArtworkSource) {
      let id = NowPlayingSessionMapping.artworkID(
        source: source, accentColorName: artworkAccentName)
      model.artwork = Artwork(id: id) { _ in try ArtworkRepresentation(data: data) }
    }

    /// The accent the drawn fallbacks render in, as a stable id component —
    /// the same two reads `NowPlayingDisplay.fallbackArtworkImage` makes.
    private var artworkAccentName: String? {
      PresetManager.shared.themingPreset?.accentColorName
        ?? GlobalSettings.shared.customAccentColor?.toString
    }

    /// Everything about the drawn fallback that changes the rendered image.
    private static func fallbackArtworkSource() -> NowPlayingSessionMapping.ArtworkSource {
      let glyph = FallbackArtwork.Glyph.playback(
        isQuickMix: AudioManager.shared.isQuickMix,
        isDefaultPreset: PresetManager.shared.currentPreset?.isDefault ?? true,
        icons: AudioManager.shared.playingSoundIcons())
      switch glyph {
      case .symbol(let name): return .fallback(kind: name, icons: [])
      case .brand: return .fallback(kind: "brand", icons: [])
      case .composite(let icons): return .fallback(kind: "composite", icons: icons)
      }
    }

    private static func jpegData(_ image: PlatformImage?) -> Data? {
      image?.jpegData(compressionQuality: 0.9)
    }

    // MARK: - Animated artwork

    #if os(iOS)
      /// The lock screen's loop, published for every aspect ratio this device
      /// can show and we have both a video and a preview for.
      private func refreshAnimatedArtwork(for preset: Preset?) {
        guard let preset, NowPlayingDisplay.shouldPublishAnimatedArtwork() else {
          clearAnimatedArtwork()
          return
        }

        // Bundled artwork has no Documents loopPath (its video is served from
        // the Background Assets pack), so key change-detection off the bundled
        // id. Re-assigning an unchanged loop would restart the video.
        let loopKey = preset.animatedArtwork?.loopPath ?? preset.animatedArtwork?.bundledIdentifier
        let previewPath = preset.animatedArtwork?.previewPath ?? preset.staticArtworkPath
        guard currentAnimatedLoopPath != loopKey || currentAnimatedPreviewPath != previewPath else {
          return
        }

        let found = animatedResources(for: preset)
        let ratios = NowPlayingSessionMapping.supportedRatios(
          compatible: AnimatedArtwork.compatibleAspectRatios.map(Self.sessionRatio),
          available: Set(found.keys))
        // Nothing playable yet (a pack is most likely still downloading): keep
        // whatever is on the card and let `onDownloaded` come back for it.
        guard !ratios.isEmpty else { return }

        model.animatedArtwork = AnimatedArtwork(
          id: NowPlayingSessionMapping.animatedArtworkID(loopKey: loopKey, presetID: preset.id),
          supportedAspectRatios: ratios.map(Self.frameworkRatio),
          preview: { _, ratio in
            guard let data = found[Self.sessionRatio(ratio)]?.preview else {
              throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable
            }
            return try ArtworkRepresentation(data: data)
          },
          video: { _, ratio in
            guard let url = found[Self.sessionRatio(ratio)]?.loop else {
              throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable
            }
            return url
          }
        )
        currentAnimatedLoopPath = loopKey
        currentAnimatedPreviewPath = previewPath
      }

      /// The loop video and preview bytes for every ratio this device can show.
      /// Blankie-keyed and immutable, so the framework's `@Sendable` providers
      /// can capture it and convert the ratio on the way in.
      private func animatedResources(for preset: Preset)
        -> [NowPlayingSessionMapping.SessionAspectRatio: (preview: Data, loop: URL)]
      {
        // One pack per clip, as on 26: the other crop is published only if it
        // happens to be local already.
        let preferredKey = AnimatedArtworkKey.preferredForDevice
        var found: [NowPlayingSessionMapping.SessionAspectRatio: (preview: Data, loop: URL)] = [:]
        for ratio in AnimatedArtwork.compatibleAspectRatios {
          let key = Self.artworkKey(for: ratio)
          guard
            let resources = animatedArtworkResolver.resources(
              for: preset, key: key, downloadIfMissing: key == preferredKey,
              // Straight back to the animation, not through `publishInfo`: by
              // now the identity gate has recorded this preset and would drop it.
              onDownloaded: { [weak self] in self?.refreshAnimatedArtworkForCurrentPreset() }),
            let preview = Self.jpegData(resources.previewImage)
          else { continue }
          found[Self.sessionRatio(ratio)] = (preview: preview, loop: resources.loopURL)
        }
        return found
      }

      /// A pack finished downloading: refresh whatever is current now, not the
      /// preset that started the request. It may have changed since, and the
      /// resolver coalesces downloads by pack, so a later preset shares this call.
      private func refreshAnimatedArtworkForCurrentPreset() {
        guard AudioManager.shared.soloModeSound == nil else { return }
        refreshAnimatedArtwork(
          for: effectiveArtworkPreset(for: PresetManager.shared.currentPreset))
      }

      private func clearAnimatedArtwork() {
        model.animatedArtwork = nil
        currentAnimatedLoopPath = nil
        currentAnimatedPreviewPath = nil
      }

      /// The framework's ratios, mirrored onto Blankie's own so nothing keyed by
      /// a framework type is ever stored (see the weak-link note on the model).
      nonisolated private static func sessionRatio(_ ratio: AnimatedArtwork.AspectRatio)
        -> NowPlayingSessionMapping.SessionAspectRatio
      {
        ratio == .square ? .square : .tall
      }

      nonisolated private static func frameworkRatio(
        _ ratio: NowPlayingSessionMapping.SessionAspectRatio
      ) -> AnimatedArtwork.AspectRatio {
        ratio == .square ? .square : .tall
      }

      /// The resolver still speaks the 26 key names, which name the same two crops.
      nonisolated private static func artworkKey(for ratio: AnimatedArtwork.AspectRatio)
        -> AnimatedArtworkKey
      {
        ratio == .square ? .square : .portrait
      }
    #endif
  }
#endif
