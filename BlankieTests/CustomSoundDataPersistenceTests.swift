//
//  CustomSoundDataPersistenceTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//
//  SwiftData persistence for imported sounds, exercised against an in-memory
//  store, plus the `toSoundData` bridge into the playback model. (The launch
//  reconcile/snapshot path is covered by CustomSoundMirrorTests.)
//

import Foundation
import SwiftData
import Testing

@testable import Blankie

@Suite @MainActor struct CustomSoundDataPersistenceTests {

  private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
      for: CustomSoundData.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
  }

  @Test func insertFetchUpdateDelete() throws {
    let context = try makeContext()
    let model = CustomSoundData(
      title: "Rain", systemIconName: "cloud.rain", fileName: "abc", fileExtension: "m4a",
      detectedLUFS: -20, duration: 12.5)
    context.insert(model)
    try context.save()
    let id = model.id

    let fetched = try context.fetch(
      FetchDescriptor<CustomSoundData>(predicate: #Predicate { $0.id == id }))
    #expect(fetched.count == 1)
    #expect(fetched.first?.title == "Rain")
    #expect(fetched.first?.detectedLUFS == -20)

    fetched.first?.title = "Storm"
    try context.save()
    #expect(try context.fetch(FetchDescriptor<CustomSoundData>()).first?.title == "Storm")

    context.delete(model)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<CustomSoundData>()).isEmpty)
  }

  @Test func modelDefaultsAreApplied() {
    let model = CustomSoundData(
      title: "x", systemIconName: "y", fileName: "f", fileExtension: "m4a")
    #expect(model.randomizeStartPosition)
    #expect(model.loopSound)
    #expect(model.normalizeAudio)
    #expect(model.volumeAdjustment == 1.0)
    #expect(model.creditLicenseType == "")
  }

  /// The bridge to the playback model places custom sounds after built-ins and
  /// prefers the original file name for display.
  @Test func toSoundDataMapsFields() {
    let model = CustomSoundData(
      title: "Rain", systemIconName: "cloud.rain", fileName: "abc", fileExtension: "m4a",
      originalFileName: "rain.wav", detectedLUFS: -18, normalizationFactor: 1.2,
      moods: [.sleep], duration: 30)
    let data = model.toSoundData()
    #expect(data.defaultOrder == 1000)
    #expect(data.title == "Rain")
    #expect(data.author == "Custom Sound")
    #expect(data.soundName == "rain.wav")
    #expect(data.lufs == -18)
    #expect(data.normalizationFactor == 1.2)
    #expect(data.moods == [.sleep])
    #expect(data.duration == 30)
  }
}
