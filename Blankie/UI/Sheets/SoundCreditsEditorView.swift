//
//  SoundCreditsEditorView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/3/26.
//

import SwiftData
import SwiftUI
import os

/// Editor for a custom sound's credit metadata. Changes save automatically.
struct SoundCreditsEditorView: View {
  @Environment(\.modelContext) var modelContext

  let sound: Sound

  @State private var editableCredits = EditableCredits()
  @State private var selectedLicense: License?

  var body: some View {
    Form {
      Section {
        EditableCreditsView(
          editableCredits: $editableCredits,
          selectedLicense: $selectedLicense,
          onChange: saveCredits
        )
      }
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .navigationTitle("Edit Credits")
    #if !os(macOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear(perform: loadCredits)
  }

  @MainActor
  private func loadCredits() {
    guard sound.isCustom,
      let customSoundDataID = sound.customSoundDataID,
      let customSoundData = try? modelContext.fetch(
        FetchDescriptor<CustomSoundData>(
          predicate: #Predicate { $0.id == customSoundDataID }
        )
      ).first
    else { return }

    // Use ID3 metadata captured at import as the fallback for empty fields.
    editableCredits.soundName =
      customSoundData.id3Title ?? customSoundData.originalFileName ?? ""
    editableCredits.author = customSoundData.creditAuthor ?? customSoundData.id3Artist ?? ""
    editableCredits.sourceUrl = customSoundData.creditSourceUrl ?? customSoundData.id3Url ?? ""

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

  @MainActor
  private func saveCredits() {
    guard sound.isCustom,
      let customSoundDataID = sound.customSoundDataID
    else { return }

    do {
      let customSoundData = try modelContext.fetch(
        FetchDescriptor<CustomSoundData>(
          predicate: #Predicate { $0.id == customSoundDataID }
        )
      ).first

      if let data = customSoundData {
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
        // Refresh the file mirror so edited credits survive a store rebuild.
        CustomSoundManager.shared.writeMirror(for: data)
      }
    } catch {
      Logger.ui.error("Error saving credits: \(error, privacy: .public)")
    }
  }
}

// MARK: - Previews

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

  NavigationStack {
    SoundCreditsEditorView(sound: sound)
  }
  .modelContainer(for: CustomSoundData.self, inMemory: true)
}
