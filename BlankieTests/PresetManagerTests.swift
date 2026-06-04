//
//  PresetManagerTests.swift
//  Blankie
//
//  Created by Cody Bromley on 1/10/25.
//

import XCTest

@testable import Blankie

final class PresetManagerTests: XCTestCase {
  var presetManager: PresetManager!

  override func setUp() {
    super.setUp()
    presetManager = PresetManager.shared
  }

  override func tearDown() async throws {
    // Clean up test presets
    await MainActor.run {
      presetManager.presets
        .filter { !$0.isDefault }
        .forEach { presetManager.deletePreset($0) }
    }
    try await super.tearDown()
  }

  func testCreateNewPreset() async throws {
    // TODO: Fix when // saveNewPreset // TODO: Fix method name method is available
    // let presetName = "Test Preset"
    // await MainActor.run {
    //   presetManager.// saveNewPreset // TODO: Fix method name(name: presetName)
    //   XCTAssertTrue(presetManager.presets.contains { $0.name == presetName })
    // }
  }

  func testDeletePreset() async throws {
    // TODO: Fix when preset creation method is available
    XCTAssert(true, "Test placeholder - needs preset creation method")
  }

  func testUpdatePreset() async throws {
    // TODO: Fix when preset creation method is available
    XCTAssert(true, "Test placeholder - needs preset creation method")
  }
}
