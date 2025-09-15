//
//  SoundAboutSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftData
import SwiftUI

struct SoundAboutSheet: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) var modelContext
  @ObservedObject private var creditsManager = SoundCreditsManager.shared

  let sound: Sound

  @State private var editableCredits = EditableCredits()
  @State private var allowOthersToEdit = true
  @State private var allowOthersToReshare = true
  @State private var selectedLicense: License?

  var body: some View {
    Form {
      // Credits Section
      Section(header: Text("Credits")) {
        if sound.isCustom {
          editableCreditsView
        } else {
          builtInCreditsView
        }
      }

      if sound.isCustom {
        // Permissions Section (Custom Sounds Only)
        permissionsSection
      }

      // Combined Details Section
      detailsSection
    }
    .navigationTitle("About \(sound.title)")
    #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      loadEditableCredits()
      // Ensure sound metadata is loaded
      if sound.channelCount == nil {
        sound.loadSound()
      }
    }
  }

  private var editableCreditsView: some View {
    EditableCreditsView(
      editableCredits: $editableCredits,
      selectedLicense: $selectedLicense,
      onChange: saveCredits
    )
  }
  private var builtInCreditsView: some View {
    BuiltInCreditsView(sound: sound, creditsManager: creditsManager)
  }
  @ViewBuilder
  private var permissionsSection: some View {
    Section(
      header: Text("Sharing Permissions"),
      footer: Text(
        "In a future update these settings will allow you to control if others can edit a sound's credits or export this sound as a part of a preset."
      )
    ) {
      Toggle("Allow others to edit this sound", isOn: $allowOthersToEdit)
      Toggle("Allow others to re-share this sound", isOn: $allowOthersToReshare)
    }
  }
  @ViewBuilder
  private var detailsSection: some View {
    SoundDetailsSection(sound: sound)
  }
  @MainActor
  private func loadEditableCredits() {
    // Load existing credits for custom sounds
    if sound.isCustom {
      // Try to load from CustomSoundData first
      if let customSoundDataID = sound.customSoundDataID,
        let customSoundData = try? modelContext.fetch(
          FetchDescriptor<CustomSoundData>(
            predicate: #Predicate { $0.id == customSoundDataID }
          )
        ).first
      {
        // Use ID3 title first, then fall back to original filename
        editableCredits.soundName =
          customSoundData.id3Title ?? customSoundData.originalFileName ?? ""

        // Use ID3 artist first, then fall back to creditAuthor
        editableCredits.author = customSoundData.creditAuthor ?? customSoundData.id3Artist ?? ""

        // Use creditSourceUrl first, then fall back to ID3 URL
        editableCredits.sourceUrl = customSoundData.creditSourceUrl ?? customSoundData.id3Url ?? ""

        // Convert license type string to License enum
        if !customSoundData.creditLicenseType.isEmpty,
          let license = License(rawValue: customSoundData.creditLicenseType)
        {
          selectedLicense = license
        } else {
          selectedLicense = nil
        }

        editableCredits.customLicenseText = customSoundData.creditCustomLicenseText ?? ""
        editableCredits.customLicenseUrl = customSoundData.creditCustomLicenseUrl ?? ""
      }
    }
  }

  @MainActor
  private func saveCredits() {
    // Save credits to CustomSoundData
    if sound.isCustom,
      let customSoundDataID = sound.customSoundDataID
    {

      do {
        let customSoundData = try modelContext.fetch(
          FetchDescriptor<CustomSoundData>(
            predicate: #Predicate { $0.id == customSoundDataID }
          )
        ).first

        if let data = customSoundData {
          // Update with new credit information
          data.originalFileName =
            editableCredits.soundName.isEmpty ? data.originalFileName : editableCredits.soundName
          data.creditAuthor = editableCredits.author.isEmpty ? nil : editableCredits.author
          data.creditSourceUrl = editableCredits.sourceUrl.isEmpty ? nil : editableCredits.sourceUrl
          data.creditLicenseType = selectedLicense?.rawValue ?? ""
          data.creditCustomLicenseText =
            editableCredits.customLicenseText.isEmpty ? nil : editableCredits.customLicenseText
          data.creditCustomLicenseUrl =
            editableCredits.customLicenseUrl.isEmpty ? nil : editableCredits.customLicenseUrl

          try modelContext.save()
        }
      } catch {
        print("Error saving credits: \(error)")
      }
    }
  }
}

// MARK: - Previews

#Preview("Built-in Sound") {
  let sound = Sound(
    title: "Rain",
    systemIconName: "cloud.rain",
    fileName: "rain",
    fileExtension: "m4a",
    defaultOrder: 1,
    lufs: -23.0,
    normalizationFactor: 1.0
  )

  SoundAboutSheet(sound: sound)
    .modelContainer(for: CustomSoundData.self, inMemory: true)
}

#Preview("Custom Sound") {
  let customData = CustomSoundData(
    title: "My Custom Sound",
    systemIconName: "waveform.circle",
    fileName: "custom_sound",
    fileExtension: "m4a"
  )

  let sound = Sound(
    title: "My Custom Sound",
    systemIconName: "waveform.circle",
    fileName: "custom_sound",
    fileExtension: "m4a",
    isCustom: true,
    customSoundDataID: customData.id
  )

  SoundAboutSheet(sound: sound)
    .modelContainer(for: CustomSoundData.self, inMemory: true)
}
