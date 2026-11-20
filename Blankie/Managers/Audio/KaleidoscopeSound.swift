//
//  KaleidoscopeSound.swift
//  Blankie
//
//  Created by Cody Bromley on 11/2/26.
//

import Foundation
import os

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// An audio kaleidoscope: tones played live from a `KaleidoscopeRecipe`, so it never
/// sounds the same twice. It has no file, always plays continuously, and stays in
/// stereo when a spatial session is on.
final class KaleidoscopeSound: Sound {

  let recipe: KaleidoscopeRecipe

  init(recipe: KaleidoscopeRecipe) {
    self.recipe = recipe
    super.init(
      title: recipe.title,
      systemIconName: recipe.systemIconName,
      fileName: recipe.fileName,
      fileExtension: "live",
      lufs: recipe.lufs,
      normalizationFactor: AudioAnalyzer.calculateLUFSNormalizationFactor(lufs: recipe.lufs),
      isMusic: true)
  }

  /// A still of its own glass, for the Library, the Lock Screen, Control Center and
  /// CarPlay. It is rendered ahead of time and bundled beside the recipe.
  private(set) lazy var artwork: PlatformImage? = {
    guard let url = Bundle.main.url(forResource: "\(fileName)-artwork", withExtension: "heic")
    else { return nil }
    #if os(macOS)
      return PlatformImage(contentsOf: url)
    #else
      return PlatformImage(contentsOfFile: url.path)
    #endif
  }()

  override var isSpatialEligible: Bool { false }

  override var isSpatialReady: Bool { false }

  /// Spatial sessions never change how it plays, so there's nothing to rebuild.
  override func rebuildPlayerForSpatialChange() {}

  override func loadSound() {
    guard player == nil else { return }
    let kaleidoscopePlayer = KaleidoscopePlayer(recipe: recipe)
    player = kaleidoscopePlayer
    AudioEngineManager.shared.attach(kaleidoscopePlayer)
    updateVolume()
    // Rewinds and marks it stopped, so play() starts through the attack.
    resetSoundPosition()
    Logger.sounds.debug("KaleidoscopeSound: Loaded '\(self.fileName)'")
  }
}
