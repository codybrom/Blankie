//
//  AudioManagerLaunchTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 7/8/26.
//
//  The single-flight launch bootstrap: concurrent callers share one custom-sound load,
//  and a run without a model context retries once one arrives.
//  Serialized: mutates AudioManager.shared. Each test restores its fields and defaults keys.
//

import Foundation
import SwiftData
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor final class AudioManagerLaunchTests {
  private let audioManager = AudioManager.shared
  private let snapshot = DefaultsSnapshot([
    "soundState",
    UserDefaultsKeys.singleSoundFileName,
    UserDefaultsKeys.starredItems,
    "defaultPreset",
    "savedPresets",
    "lastActivePresetID",
  ])
  private let originalTask: Task<Void, Never>?
  private let originalHasLoaded: Bool
  private let originalLoadPasses: Int
  private let originalContext: ModelContext?

  init() {
    originalTask = audioManager.launchBootstrapTask
    originalHasLoaded = audioManager.hasLoadedCustomSounds
    originalLoadPasses = audioManager.customSoundLoadPasses
    originalContext = audioManager.modelContext
    snapshot.clear()
    audioManager.launchBootstrapTask = nil
    audioManager.hasLoadedCustomSounds = false
    audioManager.customSoundLoadPasses = 0
    audioManager.modelContext = nil
  }

  isolated deinit {
    audioManager.launchBootstrapTask = originalTask
    audioManager.hasLoadedCustomSounds = originalHasLoaded
    audioManager.customSoundLoadPasses = originalLoadPasses
    audioManager.modelContext = originalContext
    snapshot.restore()
  }

  private func makeInMemoryContext() throws -> ModelContext {
    let container = try ModelContainer(
      for: CustomSoundData.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
  }

  @Test func concurrentCallersCoalesceToOneLoad() async throws {
    audioManager.setModelContext(try makeInMemoryContext())

    async let first: Void = audioManager.loadCustomSoundsWhenReady()
    async let second: Void = audioManager.loadCustomSoundsWhenReady()
    _ = await (first, second)

    #expect(audioManager.customSoundLoadPasses == 1)
    #expect(audioManager.hasLoadedCustomSounds)
  }

  @Test func noContextRunRetriesOnceContextArrives() async throws {
    audioManager.modelContext = nil
    await audioManager.loadCustomSoundsWhenReady()
    #expect(!audioManager.hasLoadedCustomSounds)
    #expect(audioManager.customSoundLoadPasses == 0)

    audioManager.setModelContext(try makeInMemoryContext())
    await audioManager.loadCustomSoundsWhenReady()
    #expect(audioManager.customSoundLoadPasses == 1)
    #expect(audioManager.hasLoadedCustomSounds)
  }
}
