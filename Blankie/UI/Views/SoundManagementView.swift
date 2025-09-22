//
//  SoundManagementView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftData
import SwiftUI

struct SoundManagementView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var customSoundData: [CustomSoundData]
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared

  @State private var showingFilePicker = false
  @State private var showingImportSheet = false
  @State private var showingEditSheet = false
  @State private var selectedSound: Sound?
  @State private var selectedFileURL: URL?
  @State private var showingDeleteConfirmation = false
  @State private var builtInSoundsExpanded = true
  @State private var customSoundsExpanded = true

  private var builtInSounds: [Sound] {
    audioManager.sounds.filter { !$0.isCustom }.sorted { $0.title < $1.title }
  }

  private var customSounds: [Sound] {
    audioManager.sounds.filter { $0.isCustom }.sorted { $0.title < $1.title }
  }

  var body: some View {
    NavigationStack {
      mainContentView
        .navigationTitle("Settings")
      #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              dismiss()
            }
          }
          ToolbarItem(placement: .primaryAction) {
            Button {
              showingFilePicker = true
            } label: {
              Label("Import", systemImage: "plus")
            }
          }
        }
        .fileImporter(
          isPresented: $showingFilePicker,
          allowedContentTypes: [.audio, .blankiePreset],
          allowsMultipleSelection: false
        ) { result in
          handleFileImport(result)
        }
        .sheet(isPresented: $showingImportSheet) {
          if let fileURL = selectedFileURL {
            SoundSheet(mode: .add, preselectedFile: fileURL)
          }
        }
        .sheet(isPresented: $showingEditSheet) {
          if let sound = selectedSound {
            SoundSheet(mode: .edit(sound))
          }
        }
        .alert(
          Text("Delete Sound", comment: "Delete sound confirmation alert title"),
          isPresented: $showingDeleteConfirmation
        ) {
          Button("Cancel", role: .cancel) {}
          Button("Delete", role: .destructive) {
            if let sound = selectedSound {
              deleteSound(sound)
            }
          }
        } message: {
          Text(
            "Are you sure you want to delete '\(selectedSound?.title ?? "this sound")'? This action cannot be undone.",
            comment: "Delete custom sound confirmation message"
          )
        }
    }
  }

  private var mainContentView: some View {
    Form {
      playbackSettingsSection
      builtInSoundsSection
      customSoundsSection
    }
  }

  @ViewBuilder
  private var playbackSettingsSection: some View {
    PlaybackSettingsSection(globalSettings: globalSettings)
  }

  @ViewBuilder
  private var builtInSoundsSection: some View {
    Section(
      header: Text("Built-in Sounds"),
      footer: Text("\(builtInSounds.count) sounds")
    ) {
      if builtInSoundsExpanded {
        ForEach(builtInSounds) { sound in
          builtInSoundRow(sound: sound, isLast: false)
        }
      }
    }
  }

  @ViewBuilder
  private var customSoundsSection: some View {
    Section(
      header: Text("Custom Sounds"),
      footer: Text(
        customSounds.isEmpty
          ? "No custom sounds"
          : "\(customSounds.count) sounds")
    ) {
      if customSoundsExpanded {
        if customSounds.isEmpty {
          customSoundsEmptyState
        } else {
          ForEach(customSounds) { sound in
            customSoundRow(sound: sound, isLast: false)
          }
        }
      }
    }
  }

  private func builtInSoundRow(sound: Sound, isLast: Bool) -> some View {
    Button {
      selectedSound = sound
      showingEditSheet = true
    } label: {
      SoundManagementRowContent(
        sound: sound,
        isLast: isLast,
        onDelete: {}
      )
    }
    .buttonStyle(.plain)
  }

  private func customSoundRow(sound: Sound, isLast: Bool) -> some View {
    Button {
      selectedSound = sound
      showingEditSheet = true
    } label: {
      SoundManagementRowContent(
        sound: sound,
        isLast: isLast,
        onDelete: {
          selectedSound = sound
          showingDeleteConfirmation = true
        }
      )
    }
    .buttonStyle(.plain)
  }

  private var customSoundsEmptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "waveform.circle")
        .font(.system(size: 32))
        .foregroundColor(.secondary)

      Text("No Custom Sounds", comment: "Empty state title for custom sounds")
        .font(.headline)

      Text(
        "Import your own sounds to personalize your mix.",
        comment: "Empty state description for custom sounds"
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .font(.caption)

      Button {
        showingFilePicker = true
      } label: {
        Text("Import Sound", comment: "Import sound button label")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .padding(.horizontal)
    .background(
      Group {
        #if os(macOS)
          Color(NSColor.controlBackgroundColor).opacity(0.5)
        #else
          Color(UIColor.systemBackground).opacity(0.5)
        #endif
      }
    )
  }

  private func deleteSound(_ sound: Sound) {
    guard sound.isCustom,
          let customSoundDataID = sound.customSoundDataID,
          let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
    else {
      return
    }

    let result = CustomSoundManager.shared.deleteCustomSound(customSoundData)

    if case let .failure(error) = result {
      print("❌ SoundManagementView: Failed to delete custom sound: \(error)")
    }
  }

  private func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case let .success(urls):
      guard let url = urls.first else { return }

      // Check if it's a .blankie preset file
      if url.pathExtension.lowercased() == "blankie" {
        // Use AudioFileImporter to handle preset import
        AudioFileImporter.shared.handleIncomingFile(url)
        return
      }

      // Otherwise, it's an audio file for custom sound
      selectedFileURL = url
      showingImportSheet = true
    case let .failure(error):
      print("❌ SoundManagementView: File import failed: \(error)")
    }
  }
}

private struct PlaybackSettingsSection: View {
  @ObservedObject var globalSettings: GlobalSettings

  var body: some View {
    Section(
      header: Text("Playback", comment: "Settings section header for playback options")
    ) {
      Toggle(
        "Autoplay on Open",
        isOn: Binding(
          get: { globalSettings.autoPlayOnLaunch },
          set: { globalSettings.setAutoPlayOnLaunch($0) }
        )
      )
      .tint(globalSettings.customAccentColor ?? .accentColor)

      #if os(iOS) || os(visionOS)
        mixWithOthersSection
      #endif
    }
  }

  #if os(iOS) || os(visionOS)
    @ViewBuilder
    private var mixWithOthersSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(
          "Mix with Other Audio",
          isOn: Binding(
            get: { globalSettings.mixWithOthers },
            set: { globalSettings.setMixWithOthers($0) }
          )
        )
        .tint(globalSettings.customAccentColor ?? .accentColor)

        if globalSettings.mixWithOthers {
          mixWithOthersDetails
        } else {
          Text("Blankie pauses other audio and responds to device media controls")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }

    @ViewBuilder
    private var mixWithOthersDetails: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
            .font(.caption)
          Text("Device media controls won't pause Blankie")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.orange.opacity(0.1))
        .cornerRadius(6)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Blankie Volume with Media")
              .font(.subheadline)
            Spacer()
            Text("\(Int(globalSettings.volumeWithOtherAudio * 100))%")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Slider(
            value: Binding(
              get: { globalSettings.volumeWithOtherAudio },
              set: { globalSettings.setVolumeWithOtherAudio($0) }
            ),
            in: 0.0 ... 1.0
          )
          .tint(globalSettings.customAccentColor ?? .accentColor)

          Text("Other media plays at system volume")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  #endif
}

#Preview {
  SoundManagementView()
    .frame(width: 400, height: 600)
    .modelContainer(for: CustomSoundData.self, inMemory: true)
}
