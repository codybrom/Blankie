//
//  PendingSaveFlushTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Volume edits save on a 0.1 s debounce. Quitting or suspending inside that
//  window used to drop the edit, so termination now fires the pending timers.
//

import Foundation
import Testing

@testable import Blankie

@MainActor
@Suite(.serialized)
struct PendingSaveFlushTests {
  @Test func flushingSavesAPendingGlobalVolumeNow() {
    let settings = GlobalSettings.shared
    let snapshot = DefaultsSnapshot([UserDefaultsKeys.volume])
    let originalVolume = settings.volume
    defer {
      settings.setVolume(originalVolume)
      settings.flushPendingVolumeSave()
      snapshot.restore()
    }

    let target = originalVolume == 0.42 ? 0.43 : 0.42
    settings.setVolume(target)
    settings.flushPendingVolumeSave()

    #expect(UserDefaults.shared.double(forKey: UserDefaultsKeys.volume) == target)
  }

  @Test func flushingSavesAPendingSoundVolumeNow() throws {
    let sound = TestSound(fileName: "flush-probe-\(UUID().uuidString)")
    let key = "\(sound.fileName)_volume"
    let snapshot = DefaultsSnapshot([key])
    defer { snapshot.restore() }

    sound.volume = 0.31
    sound.flushPendingVolumeSave()

    #expect(abs(UserDefaults.shared.float(forKey: key) - 0.31) < 0.0001)
  }
}
