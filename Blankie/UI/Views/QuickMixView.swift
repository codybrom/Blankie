//
//  QuickMixView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct QuickMixView: View {
  @ObservedObject var audioManager = AudioManager.shared
  @ObservedObject var globalSettings = GlobalSettings.shared

  private var quickMixSounds: [Sound] {
    return globalSettings.quickMixSoundFileNames.compactMap { fileName in
      audioManager.sounds.first { $0.fileName == fileName && !$0.isCustom }
    }
  }

  var body: some View {
    NavigationView {
      ZStack {
        // Gradient background
        LinearGradient(
          colors: [
            (globalSettings.customAccentColor ?? .accentColor).opacity(0.6),
            (globalSettings.customAccentColor ?? .accentColor).opacity(0.3),
            Color.black.opacity(0.8),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16
          ) {
            ForEach(quickMixSounds, id: \.id) { sound in
              QuickMixSoundButton(
                sound: sound
              )
            }
          }
          .padding()
          .padding(.top, 44)
        }
      }
      #if !os(macOS)
        .navigationBarHidden(true)
      #endif
    }
    #if !os(macOS)
      .navigationViewStyle(StackNavigationViewStyle())
    #endif
  }
}

struct QuickMixSoundButton: View {
  @ObservedObject var sound: Sound
  @ObservedObject var audioManager = AudioManager.shared
  @ObservedObject var globalSettings = GlobalSettings.shared
  @State private var showingQuickMixOptions = false
  @State private var popoverPosition: CGRect = .zero
  @State private var isPressed = false
  @State private var selectionTrigger = 0

  // Only show as selected if we're in Quick Mix mode (not solo mode)
  private var isSelectedInQuickMix: Bool {
    return audioManager.isQuickMix && sound.isSelected
  }

  var body: some View {
    VStack(spacing: 12) {
      // Icon
      ZStack {
        Circle()
          .fill(iconBackgroundColor)
          .frame(width: 80, height: 80)

        Image(systemName: sound.systemIconName)
          .font(.system(size: 32, weight: .medium))
          .foregroundColor(iconForegroundColor)
      }

      // Title
      Text(sound.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(.primary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .glassEffect(
      isSelectedInQuickMix
        ? .regular.tint(globalSettings.customAccentColor ?? .accentColor).interactive()
        : .regular.interactive(),
      in: .rect(cornerRadius: 16)
    )
    .scaleEffect(isPressed ? 0.95 : (isSelectedInQuickMix ? 1.05 : 1.0))
    .animation(.easeInOut(duration: 0.15), value: isSelectedInQuickMix)
    .animation(.easeInOut(duration: 0.1), value: isPressed)
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
      // Enter Quick Mix mode if not already in it
      if !audioManager.isQuickMix {
        audioManager.enterQuickMix()
      }
      audioManager.toggleQuickMixSound(sound)
    }
    .sensoryFeedback(.selection, trigger: isSelectedInQuickMix)
    .onLongPressGesture(
      minimumDuration: 0.3,
      maximumDistance: 5.0, // Reduced from infinity to prevent scroll triggering
      pressing: { pressing in
        withAnimation(.easeInOut(duration: 0.1)) {
          isPressed = pressing
        }
        if pressing {
          // Start selection feedback after delay
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if isPressed {
              // Trigger repeated selection feedback
              Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
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
            }
          }
        }
      },
      perform: {
        showingQuickMixOptions = true
      }
    )
    .sensoryFeedback(.selection, trigger: selectionTrigger)
    .sensoryFeedback(.levelChange, trigger: showingQuickMixOptions) { _, newValue in
      newValue == true
    }
    .simultaneousGesture(
      TapGesture()
        .onEnded { _ in
          // This helps prevent accidental long press triggers
        }
    )
    .popover(isPresented: $showingQuickMixOptions, arrowEdge: popoverArrowEdge) {
      QuickMixSoundOptionsPopover(
        sound: sound
      )
      .presentationCompactAdaptation(.popover)
      .interactiveDismissDisabled(false)
    }
  }

  private var popoverArrowEdge: Edge {
    // iOS handles popover positioning automatically
    .bottom
  }

  private var iconBackgroundColor: Color {
    if isSelectedInQuickMix {
      return globalSettings.customAccentColor ?? .accentColor
    } else {
      return Color.secondary.opacity(0.2)
    }
  }

  private var iconForegroundColor: Color {
    if isSelectedInQuickMix {
      return .white
    } else {
      return .secondary
    }
  }
}

struct QuickMixSoundOptionsPopover: View {
  @ObservedObject var sound: Sound
  @ObservedObject var audioManager = AudioManager.shared
  @ObservedObject var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) var dismiss
  @State private var currentVolume: Double = 0
  @State private var volumeChangeTrigger = 0

  // Available sounds for replacement (exclude custom sounds and sounds already in Quick Mix)
  private var availableSounds: [Sound] {
    return audioManager.sounds.filter { availableSound in
      !availableSound.isCustom
        && !globalSettings.quickMixSoundFileNames.contains(availableSound.fileName)
    }
  }

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

      // Replace Sound Button
      Menu {
        ForEach(availableSounds, id: \.id) { availableSound in
          Button(availableSound.title) {
            replaceSound(with: availableSound)
          }
        }
      } label: {
        HStack {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.subheadline)
          Text("Replace Sound")
            .font(.subheadline)
            .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(10)
      }
    }
    .padding(16)
    .frame(minWidth: 280)
    .background(.regularMaterial)
    .sensoryFeedback(.selection, trigger: volumeChangeTrigger)
    .onAppear {
      currentVolume = Double(sound.volume)
    }
  }

  private func replaceSound(with newSound: Sound) {
    // Find the index of the current sound in quickMixSoundFileNames
    guard let currentIndex = globalSettings.quickMixSoundFileNames.firstIndex(of: sound.fileName)
    else { return }

    // Stop the current sound if it's playing
    if sound.isSelected {
      sound.pause(immediate: true)
      sound.isSelected = false
    }

    // Replace the sound at the same position
    var updatedSounds = globalSettings.quickMixSoundFileNames
    updatedSounds[currentIndex] = newSound.fileName
    globalSettings.setQuickMixSoundFileNames(updatedSounds)

    // Start the new sound if we were playing the old one
    if audioManager.isGloballyPlaying {
      newSound.isSelected = true
      newSound.play()
    }

    // Dismiss the popover
    dismiss()
  }
}

#Preview {
  QuickMixView()
}
