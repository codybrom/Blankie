//
//  PresetArtwork.swift
//  Blankie
//
//  Created by Cody Bromley on 6/14/25.
//

import Foundation
import SwiftData

enum PresetImageType: String, Codable, CaseIterable {
  case artwork
  case background
}

@Model
final class PresetArtwork {
  @Attribute(.unique) var id: UUID
  var presetId: UUID
  var imageType: String = "artwork"
  var imageData: Data
  var createdAt: Date
  var updatedAt: Date

  init(presetId: UUID, imageData: Data, type: PresetImageType = .artwork) {
    self.id = UUID()
    self.presetId = presetId
    self.imageType = type.rawValue
    self.imageData = imageData
    self.createdAt = Date()
    self.updatedAt = Date()
  }

  var type: PresetImageType {
    get { PresetImageType(rawValue: imageType) ?? .artwork }
    set { imageType = newValue.rawValue }
  }
}
