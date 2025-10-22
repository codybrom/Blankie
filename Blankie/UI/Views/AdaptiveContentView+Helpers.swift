import SwiftUI

#if os(iOS) || os(visionOS)
  extension AdaptiveContentView {
    // Calculate filtered sounds based on current preset and hideInactiveSounds preference
    var filteredSounds: [Sound] {
      return filterSounds()
    }

    private func filterSounds() -> [Sound] {
      let visibleSounds = audioManager.getVisibleSounds()

      let filteredSounds = visibleSounds.filter { sound in
        // First check if sound is included in current preset
        if let currentPreset = presetManager.currentPreset {
          // For default preset, show all sounds
          if currentPreset.isDefault {
            // Apply hideInactiveSounds filter for default preset (but not in edit mode)
            if hideInactiveSounds, editMode == .inactive {
              return sound.isSelected
            } else {
              return true
            }
          } else {
            // For custom presets, only show sounds that are part of the preset
            let isInPreset = currentPreset.soundStates.contains { $0.fileName == sound.fileName }
            if !isInPreset {
              return false
            }

            // If sound is in preset, apply hideInactiveSounds filter (but not in edit mode)
            if hideInactiveSounds, editMode == .inactive {
              return sound.isSelected
            } else {
              return true
            }
          }
        } else {
          // No current preset - show all sounds with hideInactiveSounds filter (but not in edit mode)
          if hideInactiveSounds, editMode == .inactive {
            return sound.isSelected
          } else {
            return true
          }
        }
      }

      // Sort filtered sounds according to preset order or default sound order
      if let currentPreset = presetManager.currentPreset,
         !currentPreset.isDefault,
         let soundOrder = currentPreset.soundOrder
      {
        // Use preset's sound order for custom presets
        print("🔍 FilteredSounds: Using preset order: \(soundOrder)")
        let orderDict = Dictionary(uniqueKeysWithValues: soundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      } else {
        // Use default sound order for default preset or no preset
        print("🔍 FilteredSounds: Using default order: \(audioManager.defaultSoundOrder)")
        let orderDict = Dictionary(
          uniqueKeysWithValues: audioManager.defaultSoundOrder.enumerated().map { ($1, $0) })

        return filteredSounds.sorted { sound1, sound2 in
          let index1 = orderDict[sound1.fileName] ?? Int.max
          let index2 = orderDict[sound2.fileName] ?? Int.max
          return index1 < index2
        }
      }
    }

    // Determine if we're on iPad or Mac
    var isLargeDevice: Bool {
      horizontalSizeClass == .regular
    }

    // Preset background view
    @ViewBuilder
    var presetBackgroundView: some View {
      if let preset = presetManager.currentPreset,
         preset.showBackgroundImage ?? false
      {
        GeometryReader { geometry in
          if let image = backgroundImage {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .blur(radius: preset.backgroundBlurRadius ?? 15)
              .opacity(preset.backgroundOpacity ?? 0.65)
              .clipped()
              .overlay(
                Color.black.opacity(0.2) // Add slight darkening for better UI contrast
              )
          }
        }
        .ignoresSafeArea()
        .task(
          id:
          "\(preset.id)-\(preset.artworkId?.uuidString ?? "")-\(preset.backgroundImageId?.uuidString ?? "")-\(preset.useArtworkAsBackground ?? false)"
        ) {
          Task { @MainActor in
            self.lastPresetId = preset.id
            self.backgroundImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(
              for: preset)
          }
        }
      }
    }

    // Computed properties for columns and columnWidth
    var columns: [GridItem] {
      // This is now only used for macOS since iOS uses fixed 2-column grid
      #if os(macOS)
        // macOS can continue using icon size settings
        switch globalSettings.iconSize {
        case .small:
          return [GridItem(.adaptive(minimum: 50, maximum: 60), spacing: 4)]
        case .medium:
          return [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)]
        case .large:
          return [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 24)]
        }
      #else
        // iOS uses fixed 2-column grid (handled in gridView)
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
      #endif
    }

    var columnWidth: CGFloat {
      #if os(macOS)
        switch globalSettings.iconSize {
        case .small:
          return 60
        case .medium:
          return 150
        case .large:
          return 300
        }
      #else
        // Cache column width calculation for iOS
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth != lastScreenWidth {
          DispatchQueue.main.async {
            self.lastScreenWidth = screenWidth
            let spacing: CGFloat = 16
            let padding: CGFloat = 32 // 16 on each side
            self.cachedColumnWidth = (screenWidth - padding - spacing) / 2
          }
          let spacing: CGFloat = 16
          let padding: CGFloat = 32 // 16 on each side
          return (screenWidth - padding - spacing) / 2
        }
        return cachedColumnWidth
      #endif
    }

    // MARK: - Helper Properties

    var hasSelectedSounds: Bool {
      audioManager.hasSelectedSounds
    }

    func enterEditMode() {
      editMode = .active
    }

    func exitEditMode() {
      editMode = .inactive
    }
  }
#endif
