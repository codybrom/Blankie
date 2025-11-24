//
//  GridSoundButton.swift
//  Blankie
//
//  Created by Cody Bromley on 6/10/25.
//

import SwiftUI

// Animation trigger struct to consolidate multiple animation values
private struct GridButtonAnimationTrigger: Equatable {
  let isSelected: Bool
  let isPressed: Bool
  let isDragging: Bool
}

#if os(iOS) || os(visionOS)
  struct GridSoundButton: View {
    @ObservedObject var sound: Sound
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared
    @State private var showingOptions = false
    @State private var isPressed = false
    @State private var isDragging = false
    @State private var selectionTrigger = 0
    @State private var popoverPosition: CGRect = .zero
    @Binding var editMode: EditMode
    var showOptionsMenu: Bool = true // Allow disabling the long-press menu

    // For progress border
    private var shouldShowProgressBorder: Bool {
      globalSettings.showProgressBorder && sound.isSelected && audioManager.isGloballyPlaying
    }

    var body: some View {
      VStack(spacing: 12) {
        // Icon without tap gesture (moved to parent)
        ZStack {
          // Background circle
          Circle()
            .fill(iconBackgroundColor)
            .frame(width: 80, height: 80)

          // Progress border if enabled
          if shouldShowProgressBorder {
            ProgressBorderView(
              iconSize: 80,
              borderWidth: 3,
              sound: sound,
              color: sound.customColor ?? globalSettings.customAccentColor ?? .accentColor
            )
            .allowsHitTesting(false) // Progress border is decorative, doesn't need hit testing
          }

          // Icon
          Image(systemName: sound.systemIconName)
            .font(.system(size: 32, weight: .medium))
            .foregroundColor(iconForegroundColor)
        }

        // Title
        if globalSettings.showSoundNames {
          Text(sound.title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .allowsHitTesting(!isDragging)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.clear)
          .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 16, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .strokeBorder(
                sound.isSelected
                  ? (sound.customColor ?? (globalSettings.customAccentColor ?? .accentColor))
                  : .primary.opacity(0.15),
                lineWidth: sound.isSelected ? 2 : 1
              )
          )
      }
      .contentShape(RoundedRectangle(cornerRadius: 16))
      .overlay(alignment: .topTrailing) {
        // Edit mode indicator
        if editMode == .active {
          Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(8)
            .transition(.opacity)
        }
      }
      .scaleEffect(isPressed ? 0.95 : (sound.isSelected ? 1.05 : 1.0))
      .opacity(isDragging ? 0.8 : (editMode == .active ? 0.9 : 1.0))
      .animation(
        .easeInOut(duration: 0.1),
        value: GridButtonAnimationTrigger(
          isSelected: sound.isSelected,
          isPressed: isPressed,
          isDragging: isDragging
        )
      )
      .background(
        GeometryReader { geometry in
          Color.clear
            .onAppear {
              popoverPosition = geometry.frame(in: .global)
            }
            .onChange(of: geometry.frame(in: .global)) { _, newFrame in
              popoverPosition = newFrame
            }
        }
      )
      .onTapGesture {
        if editMode == .inactive {
          if !audioManager.isGloballyPlaying && sound.isSelected {
            audioManager.setGlobalPlaybackState(true)
          } else {
            sound.toggle()
          }
        }
      }
      .sensoryFeedback(.selection, trigger: sound.isSelected)
      .onLongPressGesture(
        minimumDuration: 0.3,
        maximumDistance: 5.0, // Reduced from infinity to prevent scroll triggering
        pressing: { pressing in
          withAnimation(.easeInOut(duration: 0.1)) {
            isPressed = pressing && editMode == .inactive && showOptionsMenu
          }
          if pressing, editMode == .inactive, showOptionsMenu {
            // Start selection feedback after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              if isPressed {
                // Trigger repeated selection feedback
                let feedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
                  timer in
                  guard isPressed else {
                    timer.invalidate()
                    return
                  }
                  selectionTrigger += 1

                  // Stop after ~0.2 seconds (4 triggers)
                  if selectionTrigger >= 4 {
                    timer.invalidate()
                  }
                }

                feedbackTimer.tolerance = 0.01
              }
            }
          }
        },
        perform: {
          if editMode == .inactive, showOptionsMenu {
            showingOptions = true
          }
        }
      )
      .sensoryFeedback(.selection, trigger: selectionTrigger)
      .sensoryFeedback(.levelChange, trigger: showingOptions) { _, newValue in
        newValue == true
      }
      .simultaneousGesture(
        TapGesture()
          .onEnded { _ in
            // This helps prevent accidental long press triggers
          }
      )
      .popover(isPresented: $showingOptions, arrowEdge: popoverArrowEdge) {
        GridSoundOptionsPopover(sound: sound, editMode: $editMode)
          .presentationCompactAdaptation(.popover)
          .interactiveDismissDisabled(false)
      }
    }

    // MARK: - Color Properties

    private var backgroundColor: Color {
      let effectiveColor = sound.customColor ?? globalSettings.customAccentColor ?? .accentColor

      if !audioManager.isGloballyPlaying {
        return sound.isSelected ? Color.gray.opacity(0.1) : Color.clear
      }
      return sound.isSelected ? effectiveColor.opacity(0.1) : Color.clear
    }

    private var borderColor: Color {
      let effectiveColor = sound.customColor ?? globalSettings.customAccentColor ?? .accentColor

      if sound.isSelected {
        return audioManager.isGloballyPlaying ? effectiveColor : Color.gray
      } else {
        return Color.secondary.opacity(0.2)
      }
    }

    private var iconBackgroundColor: Color {
      let effectiveColor = sound.customColor ?? globalSettings.customAccentColor ?? .accentColor

      if !audioManager.isGloballyPlaying {
        return sound.isSelected ? Color.gray.opacity(0.2) : .clear
      }
      return sound.isSelected ? effectiveColor.opacity(0.2) : .clear
    }

    private var iconForegroundColor: Color {
      let effectiveColor = sound.customColor ?? globalSettings.customAccentColor ?? .accentColor

      if !audioManager.isGloballyPlaying {
        return .gray
      }
      return sound.isSelected ? effectiveColor : .gray
    }

    private var popoverArrowEdge: Edge {
      // iOS handles popover positioning automatically
      .bottom
    }
  }

  // MARK: - Options Popover

  struct GridSoundOptionsPopover: View {
    @ObservedObject var sound: Sound
    @ObservedObject var audioManager = AudioManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var currentVolume: Double = 0
    @State private var volumeChangeTrigger = 0
    @State private var showingEditSheet = false
    @Binding var editMode: EditMode

    var body: some View {
      VStack(spacing: 16) {
        // Volume Control
        VStack(spacing: 8) {
          HStack {
            Text("Volume")
              .font(.subheadline)
              .fontWeight(.medium)
            Spacer()
            Text("\(Int(currentVolume * 100))%")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.secondary)
          }

          HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
              .font(.caption)
              .foregroundColor(.secondary)

            Slider(
              value: $currentVolume,
              in: 0 ... 1,
              onEditingChanged: { editing in
                if !editing {
                  sound.volume = Float(currentVolume)
                }
              }
            )
            .onChange(of: currentVolume) { _, _ in
              volumeChangeTrigger += 1
            }

            Image(systemName: "speaker.wave.3.fill")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Divider()

        // Button Row
        HStack(spacing: 8) {
          // Solo Mode Button
          Button(action: {
            audioManager.toggleSoloMode(for: sound)
            dismiss()
          }) {
            VStack(spacing: 4) {
              Image(
                systemName: audioManager.soloModeSound?.id == sound.id
                  ? "headphones.circle.fill" : "headphones"
              )
              .font(.title3)
              Text("Solo")
                .font(.caption)
                .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
              audioManager.soloModeSound?.id == sound.id
                ? Color.orange.opacity(0.15)
                : Color.secondary.opacity(0.15)
            )
            .cornerRadius(8)
          }

          // Customize Button
          Button(action: {
            showingEditSheet = true
          }) {
            VStack(spacing: 4) {
              Image(systemName: "paintbrush")
                .font(.title3)
              Text("Edit")
                .font(.caption)
                .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
          }

          // Reorder Button
          Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
              editMode = editMode == .active ? .inactive : .active
            }
            dismiss()
          }) {
            VStack(spacing: 4) {
              Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
                .font(.title3)
              Text(editMode == .active ? "Done" : "Move")
                .font(.caption)
                .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
              editMode == .active
                ? Color.green.opacity(0.15)
                : Color.secondary.opacity(0.15)
            )
            .cornerRadius(8)
          }
        }
      }
      .padding(16)
      .frame(minWidth: 280)
      .background(.regularMaterial)
      .sensoryFeedback(.selection, trigger: volumeChangeTrigger)
      .onAppear {
        currentVolume = Double(sound.volume)
      }
      .sheet(isPresented: $showingEditSheet) {
        SoundSheet(mode: .edit(sound))
          .interactiveDismissDisabled() // Prevent accidental dismissal
      }
    }
  }

  #if DEBUG
    struct GridSoundButton_Previews: PreviewProvider {
      static var previews: some View {
        let sound = Sound(
          title: "Rain",
          systemIconName: "cloud.rain",
          fileName: "rain",
          fileExtension: "m4a",
          defaultOrder: 1,
          lufs: nil,
          normalizationFactor: nil,
          truePeakdBTP: nil,
          needsLimiter: false,
          isCustom: false,
          fileURL: nil,
          dateAdded: nil,
          customSoundDataID: nil
        )

        GridSoundButton(sound: sound, editMode: .constant(.inactive))
          .frame(width: 180)
          .padding()
      }
    }
  #endif
#endif
