//
//  SoundsLibraryView.swift
//  Blankie
//
//  Sounds library with alphabetical and mood organization
//

import SwiftUI

#if os(iOS) || os(visionOS)

  struct SoundsLibraryView: View {
    @Binding var expandPlayer: Bool
    @StateObject private var audioManager = AudioManager.shared
    @State private var selectedMood: SoundMood?
    @State private var searchText = ""

    var body: some View {
      NavigationStack {
        List {
          // Mood filters
          Section {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                MoodFilterPill(
                  title: "All",
                  icon: "waveform",
                  isSelected: selectedMood == nil,
                  action: { selectedMood = nil }
                )

                ForEach(SoundMood.allCases, id: \.self) { mood in
                  MoodFilterPill(
                    title: mood.displayName,
                    icon: mood.icon,
                    isSelected: selectedMood == mood,
                    action: { selectedMood = mood }
                  )
                }
              }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
          }

          // Sounds list
          if filteredSounds.isEmpty {
            Section {
              VStack(spacing: 12) {
                Image(systemName: "waveform")
                  .font(.system(size: 48))
                  .foregroundStyle(.secondary)
                Text("No Sounds")
                  .font(.headline)
                  .foregroundStyle(.secondary)
                Text(selectedMood == nil ? "No sounds available" : "No sounds for this mood")
                  .font(.subheadline)
                  .foregroundStyle(.tertiary)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 40)
              .listRowBackground(Color.clear)
            }
          } else {
            ForEach(filteredSounds) { sound in
              SoundRow(sound: sound, expandPlayer: $expandPlayer)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
          }
        }
        .navigationTitle("Sounds")
        .searchable(text: $searchText, prompt: "Search sounds")
      }
    }

    private var filteredSounds: [Sound] {
      var sounds = audioManager.sounds

      // Filter by mood if selected
      if let mood = selectedMood {
        sounds = sounds.filter { sound in
          // Check if sound data has this mood
          if let soundData = audioManager.soundsData.first(where: { $0.fileName == sound.fileName }) {
            return soundData.moods?.contains(mood) == true
          }
          return false
        }
      }

      // Filter by search text
      if !searchText.isEmpty {
        sounds = sounds.filter { sound in
          sound.title.localizedCaseInsensitiveContains(searchText)
        }
      }

      // Sort alphabetically
      return sounds.sorted { $0.title < $1.title }
    }
  }

  // MARK: - Sound Row

  struct SoundRow: View {
    @ObservedObject var sound: Sound
    @Binding var expandPlayer: Bool

    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var soundToEdit: Sound?
    @State private var playTrigger = 0

    private var isPlaying: Bool {
      audioManager.soloModeSound?.id == sound.id || sound.isSelected
    }

    var body: some View {
      Button {
        playTrigger += 1
        // Tap to play solo mode
        audioManager.enterSoloMode(for: sound)
        // Expand player to show now playing
        withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
          expandPlayer = true
        }
      } label: {
        HStack(spacing: 16) {
          // Icon with filled circle background when playing
          ZStack {
            Circle()
              .fill(isPlaying ? (globalSettings.customAccentColor ?? .accentColor) : Color.clear)
              .frame(width: 56, height: 56)

            Image(systemName: sound.systemIconName)
              .font(.system(size: 32, weight: .medium))
              .foregroundColor(isPlaying ? .white : (globalSettings.customAccentColor ?? .accentColor))
          }
          .frame(width: 56)

          // Info
          VStack(alignment: .leading, spacing: 2) {
            Text(sound.title)
              .font(.body)
              .fontWeight(.medium)
              .foregroundColor(.primary)

            if let duration = sound.duration {
              Text(formatDuration(duration))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          Spacer(minLength: 0)

          // Edit button (just 3 dots)
          Button {
            soundToEdit = sound
          } label: {
            Image(systemName: "ellipsis")
              .font(.body)
              .foregroundColor(.secondary)
              .frame(width: 40, height: 40)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playTrigger)
      .sheet(item: $soundToEdit) { sound in
        SoundSheet(mode: .edit(sound))
      }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
      let minutes = Int(duration) / 60
      let seconds = Int(duration) % 60
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  #Preview {
    SoundsLibraryView(expandPlayer: .constant(false))
  }

#endif
