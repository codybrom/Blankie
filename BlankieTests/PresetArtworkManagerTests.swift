//
//  PresetArtworkManagerTests.swift
//  BlankieTests
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import SwiftData
import Testing

@testable import Blankie

@Suite(.serialized) @MainActor
struct PresetArtworkManagerTests {

  /// `saveArtwork` must delete EVERY existing row of the same type, not just the
  /// first, so a legacy duplicate can't survive and shadow the new artwork.
  @Test func saveArtworkReplacesAllDuplicateRows() async throws {
    let container = try ModelContainer(
      for: PresetArtwork.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)

    let presetId = UUID()
    // Two legacy duplicate rows for the same preset + type.
    context.insert(PresetArtwork(presetId: presetId, imageData: Data([0x01]), type: .artwork))
    context.insert(PresetArtwork(presetId: presetId, imageData: Data([0x02]), type: .artwork))
    try context.save()

    let manager = PresetArtworkManager.shared
    manager.setModelContext(context)

    let newData = Data([0x03, 0x04])
    let newId = try await manager.saveArtwork(newData, for: presetId, type: .artwork)

    let rows = try context.fetch(
      FetchDescriptor<PresetArtwork>(predicate: #Predicate { $0.presetId == presetId }))
    #expect(rows.count == 1)
    #expect(rows.first?.id == newId)
    #expect(rows.first?.imageData == newData)
  }
}
