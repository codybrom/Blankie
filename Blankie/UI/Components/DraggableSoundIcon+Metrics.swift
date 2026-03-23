//
//  DraggableSoundIcon+Metrics.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  extension DraggableSoundIcon {
    // MARK: - Size Metrics

    var iconSize: CGFloat {
      // Solo mode has fixed larger size
      if isSoloMode {
        return 200
      }

      // Normal mode uses settings
      switch globalSettings.iconSize {
      case .small:
        return 75
      case .medium:
        return 100
      case .large:
        return maxWidth * 0.85
      }
    }

    var innerIconScale: CGFloat {
      return 0.64
    }

    var sliderWidth: CGFloat {
      switch globalSettings.iconSize {
      case .small:
        return 70
      case .medium:
        return 85
      case .large:
        return maxWidth * 0.75
      }
    }

    var borderWidth: CGFloat {
      switch globalSettings.iconSize {
      case .small: return 4
      case .medium: return 4
      case .large: return 6
      }
    }

    // MARK: - Color Computations

    var accentColor: Color {
      globalSettings.customAccentColor ?? .accentColor
    }

    var iconColor: Color {
      let isSoloMode = AudioManager.shared.soloModeSound?.id == sound.id
      let effectiveColor = accentColor

      if isSoloMode {
        return effectiveColor  // Solo mode color
      }

      if !AudioManager.shared.isGloballyPlaying {
        return .gray
      }
      return sound.isSelected ? effectiveColor : .gray
    }

    var backgroundFill: Color {
      let isSoloMode = AudioManager.shared.soloModeSound?.id == sound.id
      let effectiveColor = accentColor

      // In edit mode, always show a semi-transparent background
      if editMode == .active {
        return effectiveColor.opacity(0.25)
      }

      if isSoloMode {
        return effectiveColor.opacity(0.3)  // Solo mode background
      }

      if !AudioManager.shared.isGloballyPlaying {
        return sound.isSelected ? Color.gray.opacity(0.2) : .clear
      }
      return sound.isSelected ? effectiveColor.opacity(0.2) : .clear
    }

    var isSliderEnabled: Bool {
      // Always enabled in solo mode
      if isSoloMode {
        return true
      }

      // Otherwise, only when selected
      return sound.isSelected
    }

    var sliderTintColor: Color {
      let isSoloMode = AudioManager.shared.soloModeSound?.id == sound.id
      let effectiveColor = accentColor

      if !AudioManager.shared.isGloballyPlaying {
        return .gray
      }

      if isSoloMode {
        return effectiveColor
      }

      return sound.isSelected ? effectiveColor : .gray
    }
  }
#endif
