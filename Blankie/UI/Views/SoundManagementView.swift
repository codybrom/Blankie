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
  @State private var builtInSoundsExpanded = false
  @State private var customSoundsExpanded = true

  private var builtInSounds: [Sound] {
    audioManager.sounds.filter { !$0.isCustom }.sorted { $0.title < $1.title }
  }

  private var customSounds: [Sound] {
    audioManager.sounds.filter { $0.isCustom }.sorted { $0.title < $1.title }
  }

  var body: some View {
    mainContentView
      .navigationTitle("Manage Sounds")
      #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingFilePicker = true
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "plus")
              Text("Import")
            }
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

  private var mainContentView: some View {
    #if os(macOS)
      macContent
    #else
      Form {
        playbackSettingsSection
        builtInSoundsSection
        customSoundsSection
      }
    #endif
  }

  @ViewBuilder
  private var playbackSettingsSection: some View {
    PlaybackSettingsSection(globalSettings: globalSettings)
  }

  @ViewBuilder
  private var builtInSoundsSection: some View {
    Section {
      DisclosureGroup(isExpanded: $builtInSoundsExpanded) {
        ForEach(builtInSounds) { sound in
          builtInSoundRow(sound: sound, isLast: false)
        }
      } label: {
        HStack {
          Text("Built-in Sounds")
          Spacer()
          Text("\(builtInSounds.count)")
            .foregroundStyle(.secondary)
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

  #if os(macOS)
    private var macAccent: Color {
      globalSettings.customAccentColor ?? .accentColor
    }

    /// macOS layout: a roomy grouped list focused on sound management. The
    /// global "Autoplay on Open" toggle lives in the parent Preferences window,
    /// so it's intentionally omitted here.
    private var macContent: some View {
      List {
        Section {
          if customSounds.isEmpty {
            macEmptyState
          } else {
            ForEach(customSounds) { sound in
              macSoundRow(sound: sound, isCustom: true)
            }
          }
        } header: {
          macSectionHeader("Custom Sounds", count: customSounds.count)
        } footer: {
          Text(
            "Import M4A, MP3, WAV, or other audio files to mix in your own sounds.",
            comment: "Custom sounds section footer"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section {
          ForEach(builtInSounds) { sound in
            macSoundRow(sound: sound, isCustom: false)
          }
        } header: {
          macSectionHeader("Built-in Sounds", count: builtInSounds.count)
        }
      }
      .listStyle(.inset)
      .frame(minWidth: 540, minHeight: 560)
    }

    private func macSectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
      HStack {
        Text(title)
        Spacer()
        Text("\(count)")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.headline)
    }

    private func macSoundRow(sound: Sound, isCustom: Bool) -> some View {
      HStack(spacing: 12) {
        Image(systemName: sound.systemIconName)
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(width: 26)

        Text(
          isCustom
            ? LocalizedStringKey(stringLiteral: sound.title) : LocalizedStringKey(sound.title)
        )
        .foregroundStyle(.primary)

        Spacer()

        Button {
          selectedSound = sound
          showingEditSheet = true
        } label: {
          Image(systemName: "pencil")
        }
        .buttonStyle(.borderless)
        .help(Text("Edit Sound", comment: "Tooltip for editing a sound"))
        .accessibilityLabel(Text("Edit Sound", comment: "Tooltip for editing a sound"))

        if isCustom {
          Button {
            selectedSound = sound
            showingDeleteConfirmation = true
          } label: {
            Image(systemName: "trash")
              .foregroundStyle(.red)
          }
          .buttonStyle(.borderless)
          .help(Text("Delete Sound", comment: "Tooltip for deleting a sound"))
          .accessibilityLabel(Text("Delete Sound", comment: "Tooltip for deleting a sound"))
        }
      }
      .padding(.vertical, 4)
      .contextMenu {
        Button("Edit Sound", systemImage: "pencil") {
          selectedSound = sound
          showingEditSheet = true
        }
        if isCustom {
          Button("Delete Sound", systemImage: "trash", role: .destructive) {
            selectedSound = sound
            showingDeleteConfirmation = true
          }
        }
      }
    }

    private var macEmptyState: some View {
      VStack(spacing: 12) {
        Image(systemName: "waveform.circle")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)

        Text("No Custom Sounds", comment: "Empty state title for custom sounds")
          .font(.headline)

        Text(
          "Import your own sounds to personalize your mix.",
          comment: "Empty state description for custom sounds"
        )
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .font(.subheadline)

        Button {
          showingFilePicker = true
        } label: {
          Label("Import Sound", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(macAccent)
        .padding(.top, 4)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 32)
    }
  #endif

  private func deleteSound(_ sound: Sound) {
    guard sound.isCustom,
      let customSoundDataID = sound.customSoundDataID,
      let customSoundData = CustomSoundManager.shared.getCustomSound(by: customSoundDataID)
    else {
      return
    }

    let result = CustomSoundManager.shared.deleteCustomSound(customSoundData)

    if case .failure(let error) = result {
      debugLog("❌ SoundManagementView: Failed to delete custom sound: \(error)")
    }
  }

  private func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
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
    case .failure(let error):
      debugLog("❌ SoundManagementView: File import failed: \(error)")
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
            Text(
              globalSettings.volumeWithOtherAudio.formatted(.percent.precision(.fractionLength(0)))
            )
            .font(.caption)
            .foregroundColor(.secondary)
          }

          Slider(
            value: Binding(
              get: { globalSettings.volumeWithOtherAudio },
              set: { globalSettings.setVolumeWithOtherAudio($0) }
            ),
            in: 0.0...1.0
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
