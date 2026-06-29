//
//  PresetState.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import SwiftUI

nonisolated struct PresetState: Codable, Equatable {
  let fileName: String
  let isSelected: Bool
  let volume: Float

  static func == (lhs: PresetState, rhs: PresetState) -> Bool {
    lhs.fileName == rhs.fileName && lhs.isSelected == rhs.isSelected
      && abs(lhs.volume - rhs.volume) < Float.ulpOfOne
  }
}
