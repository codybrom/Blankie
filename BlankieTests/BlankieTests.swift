//
//  BlankieTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 1/10/25.
//

import XCTest

@testable import Blankie

class BlankieTests: XCTestCase {
  override func tearDown() async throws {
    // Reset global state
    await MainActor.run {
      // Reset global settings
      GlobalSettings.shared.setVolume(1.0)
      GlobalSettings.shared.setAccentColor(nil)
      GlobalSettings.shared.setAppearance(.system)
      GlobalSettings.shared.setAutoPlayOnLaunch(false)

      // Reset audio manager
      AudioManager.shared.resetSounds()
    }

    // Delete non-default presets
    await MainActor.run {
      for preset in PresetManager.shared.presets.filter({ !$0.isDefault }) {
        PresetManager.shared.deletePreset(preset)
      }
    }

    try await super.tearDown()
  }
}
