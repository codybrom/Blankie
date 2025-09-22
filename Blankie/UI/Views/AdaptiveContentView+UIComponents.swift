//
//  AdaptiveContentView+UIComponents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)

  // MARK: - UI Components Extension

  extension AdaptiveContentView {
    // MARK: - Status Banners

    @ViewBuilder
    var statusBanners: some View {
      // Timer banner (highest priority)
      if TimerManager.shared.isTimerActive && editMode == .inactive {
        HStack(spacing: 8) {
          Image(systemName: "timer")
            .font(.system(size: 16))
            .foregroundColor(globalSettings.customAccentColor ?? .accentColor)

          if TimerManager.shared.remainingTime < 60 {
            // Show countdown for less than 1 minute
            Text("Blankie will stop in \(formatTime(TimerManager.shared.remainingTime))")
              .font(.system(.subheadline, design: .rounded, weight: .medium))
              .foregroundColor(.primary)
          } else {
            // Show end time for 1 minute or more
            Text("Blankie will stop at \(formatEndTime())")
              .font(.system(.subheadline, design: .rounded, weight: .medium))
              .foregroundColor(.primary)
          }

          Spacer()

          Button("Modify") {
            showingTimer = true
          }
          .font(.system(.subheadline, weight: .medium))
          .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .foregroundStyle(.primary)
        .background(.regularMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
      } else if audioManager.soloModeSound != nil && editMode == .inactive {
        // Solo mode banner
        HStack(spacing: 12) {
          Image(systemName: "headphones.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          Text("Solo Mode")
            .font(.system(.subheadline, design: .rounded, weight: .medium))

          Spacer()

          Button("Exit") {
            withAnimation(.easeInOut(duration: 0.3)) {
              audioManager.exitSoloMode()
            }
          }
          .font(.system(.subheadline, weight: .medium))
          .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          .buttonStyle(.plain)
          .sensoryFeedback(.selection, trigger: audioManager.soloModeSound?.id)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .foregroundStyle(.primary)
        .background(.regularMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
      } else if !audioManager.hasSelectedSounds && editMode == .inactive
        && !audioManager.isQuickMix
      {
        // No sounds selected banner (not shown in Quick Mix mode)
        HStack(spacing: 12) {
          Image(systemName: "speaker.slash.fill")
            .font(.system(size: 16))
          Text("No Sounds Selected")
            .font(.system(.subheadline, design: .rounded, weight: .medium))

          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .foregroundStyle(.secondary)
        .background(.regularMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }

    // MARK: - Navigation Elements

    var navigationTitle: String {
      if let soloSound = audioManager.soloModeSound {
        return soloSound.title
      }

      if audioManager.isQuickMix {
        return "Quick Mix"
      }

      if let preset = presetManager.currentPreset {
        return preset.isDefault ? "Blankie" : preset.name
      }

      return "Blankie"
    }

    var presetButton: some View {
      Button(action: {
        showingPresetPicker = true
      }) {
        HStack(spacing: 4) {
          if audioManager.soloModeSound != nil {
            Image(systemName: "headphones.circle.fill")
              .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          } else if audioManager.isQuickMix {
            Image(systemName: "square.grid.2x2.fill")
              .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
          }
          Text(navigationTitle)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
          Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .sensoryFeedback(.selection, trigger: showingPresetPicker)
    }

    // MARK: - Toolbar Components

    var bottomToolbar: some View {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          // Grid/List toggle (or exit Quick Mix)
          Spacer()
          Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
              if audioManager.isQuickMix {
                // Exit Quick Mix mode and return to previous view mode
                audioManager.exitQuickMix()
              } else {
                // Normal toggle between grid and list
                showingListView.toggle()
                globalSettings.setShowingListView(showingListView)
              }
            }
          }) {
            Image(
              systemName: audioManager.isQuickMix
                ? "arrow.backward"
                : (showingListView ? "list.bullet" : "square.grid.3x3")
            )
            .font(.system(size: 22))
            .foregroundColor(.primary)
            .contentTransition(.symbolEffect(.replace))
          }
          .buttonStyle(.plain)
          .sensoryFeedback(
            .selection,
            trigger: audioManager.isQuickMix
              ? audioManager.isQuickMix : showingListView
          )
          Spacer()

          // Play/Pause button
          Spacer()
          playPauseButton
          Spacer()

          // Menu button
          Spacer()
          menuButton
          Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
      }
    }

    var playPauseButton: some View {
      Button(action: {
        if audioManager.hasSelectedSounds {
          playPauseTrigger += 1
          audioManager.togglePlayback()
        }
      }) {
        ZStack {
          Circle()
            .fill(
              audioManager.hasSelectedSounds
                ? (globalSettings.customAccentColor?.opacity(0.2) ?? Color.accentColor.opacity(0.2))
                : Color.secondary.opacity(0.1)
            )
            .frame(width: 60, height: 60)

          Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 26))
            .foregroundColor(
              audioManager.hasSelectedSounds
                ? (globalSettings.customAccentColor ?? .accentColor)
                : .secondary
            )
            .contentTransition(
              .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
            )
            .offset(x: audioManager.isGloballyPlaying ? 0 : 2)
        }
      }
      .buttonStyle(.plain)
      .disabled(!audioManager.hasSelectedSounds)
      .sensoryFeedback(.selection, trigger: playPauseTrigger)
    }

    var menuButton: some View {
      Menu {
        if audioManager.soloModeSound != nil {
          Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
              audioManager.exitSoloMode()
            }
          }) {
            Label("Exit Solo Mode", systemImage: "headphones.slash")
          }
        }

        Section {
          Button(action: {
            showingAbout = true
          }) {
            Label("About Blankie", systemImage: "info.circle")
          }
        }

        Button(action: {
          showingSoundManagement = true
        }) {
          Label("Settings", systemImage: "waveform")
        }

        Button(action: {
          showingViewSettings = true
        }) {
          Label("Appearance", systemImage: "slider.horizontal.3")
        }

        Button(action: {
          withAnimation {
            editMode = editMode == .active ? .inactive : .active
          }
        }) {
          Label(
            editMode == .active ? "Done Reordering" : "Reorder",
            systemImage: editMode == .active ? "checkmark.circle" : "arrow.up.arrow.down"
          )
        }

        Button(action: {
          showingTimer = true
        }) {
          Label("Timer", systemImage: "timer")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 22))
          .foregroundColor(.primary)
          .onTapGesture {
            menuTrigger += 1
          }
      }
      .sensoryFeedback(.selection, trigger: menuTrigger)
    }

    // MARK: - Helper Functions

    private func formatTime(_ timeInterval: TimeInterval) -> String {
      let formatter = DateComponentsFormatter()
      formatter.unitsStyle = .full
      formatter.allowedUnits = timeInterval >= 60 ? [.hour, .minute] : [.minute, .second]
      formatter.zeroFormattingBehavior = .dropAll

      return formatter.string(from: timeInterval) ?? "0 seconds"
    }

    private func formatEndTime() -> String {
      let endTime = Date().addingTimeInterval(TimerManager.shared.remainingTime)
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      return formatter.string(from: endTime)
    }
  }
#endif
