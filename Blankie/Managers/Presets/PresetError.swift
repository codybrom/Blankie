//
//  PresetError.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

//
//  PresetError.swift
//  Blankie
//
//  Created by Cody Bromley on 1/5/25.
//

import Foundation

enum PresetError: LocalizedError {
  case invalidPreset
  case saveFailed
  case loadFailed
  case defaultPresetMissing

  var errorDescription: String? {
    switch self {
    case .invalidPreset:
      return String(localized: "The preset is invalid or corrupted")
    case .saveFailed:
      return String(localized: "Failed to save preset")
    case .loadFailed:
      return String(localized: "Failed to load preset")
    case .defaultPresetMissing:
      return String(localized: "Default preset is missing")
    }
  }
}
