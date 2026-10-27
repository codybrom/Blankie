//
//  CarPlayEditStackTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/13/26.
//
//  The CarPlay edit stack edits only its own preset's live mix, and a single sound tap after
//  disconnect starts nothing. Builds only under the CarPlay scheme; uses SingletonSandbox.
//

#if CARPLAY_ENABLED && canImport(CarPlay)

  import Foundation
  import Testing

  @testable import Blankie

  @Suite(.serialized) @MainActor final class CarPlayEditStackTests {
    private let sandbox: SingletonSandbox
    private let controller = CarPlayInterfaceController.shared
    private let originalEditPresetID: UUID?

    init() async {
      sandbox = await SingletonSandbox.make(soundNames: ["test-car-a", "test-car-b"])
      originalEditPresetID = controller.currentEditPresetID
    }

    isolated deinit {
      controller.currentEditPresetID = originalEditPresetID
      sandbox.restore()
    }

    @Test func editStackIsLiveOnlyForItsPresetsOwnMix() async {
      let a = TestSound(fileName: "test-car-a")
      let b = TestSound(fileName: "test-car-b")
      sandbox.audioManager.sounds = [a, b]
      let first = PresetFactory.makePreset(name: "Car One")
      let second = PresetFactory.makePreset(name: "Car Two")
      sandbox.presetManager.setPresets([first, second])
      sandbox.presetManager.setCurrentPreset(first)
      controller.currentEditPresetID = first.id
      #expect(controller.editStackIsLive)

      sandbox.presetManager.setCurrentPreset(second)
      #expect(!controller.editStackIsLive, "a switch on the phone")
      sandbox.presetManager.setCurrentPreset(first)

      sandbox.audioManager.singleSound = b
      #expect(!controller.editStackIsLive, "single sound")
      sandbox.audioManager.singleSound = nil

      sandbox.audioManager.isQuickMix = true
      #expect(!controller.editStackIsLive, "Quick Mix")
      sandbox.audioManager.isQuickMix = false
    }

    @Test func singleTapAfterDisconnectStartsNothing() {
      let a = TestSound(fileName: "test-car-a")
      sandbox.audioManager.sounds = [a]
      #expect(!controller.isConnected)

      SoundsListTemplate.playSingleSound(a)

      #expect(sandbox.audioManager.singleSound == nil)
    }
  }

#endif
