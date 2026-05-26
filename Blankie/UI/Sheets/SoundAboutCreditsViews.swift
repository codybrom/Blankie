//
//  SoundAboutCreditsViews.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI

struct EditableCreditsView: View {
  @Binding var editableCredits: EditableCredits
  @Binding var selectedLicense: License?
  let onChange: () -> Void

  var body: some View {
    Group {
      // Original Work Title.
      // prompt + labelsHidden: on macOS a bare titleKey renders as a visible
      // label next to the value; this keeps it a placeholder only (no-op on iOS).
      HStack {
        Text("Original Work")
        Spacer()
        TextField("Title", text: $editableCredits.soundName, prompt: Text("Title"))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .foregroundColor(.secondary)
      }

      // Author/Creator
      HStack {
        Text("Author")
        Spacer()
        TextField("Author name", text: $editableCredits.author, prompt: Text("Author name"))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .foregroundColor(.secondary)
      }

      // Source URL
      HStack {
        Text("Source URL")
        Spacer()
        TextField("https://...", text: $editableCredits.sourceUrl, prompt: Text("https://..."))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .foregroundColor(.secondary)
          #if !os(macOS)
            .keyboardType(.URL)
          #endif
      }

      // License
      Picker("License", selection: $selectedLicense) {
        Text("None").tag(nil as License?)
        ForEach(License.allCases, id: \.self) { license in
          Text(license.linkText).tag(license as License?)
        }
      }

      // Custom License Details
      if selectedLicense == .custom {
        VStack(alignment: .leading, spacing: 8) {
          Text("License Details")
          TextField(
            "Describe the license terms", text: $editableCredits.customLicenseText,
            prompt: Text("Describe the license terms"), axis: .vertical
          )
          .labelsHidden()
          .textFieldStyle(.plain)
          .foregroundColor(.secondary)
          .lineLimit(3...6)

          HStack {
            Text("License URL")
            Spacer()
            TextField(
              "https://...", text: $editableCredits.customLicenseUrl, prompt: Text("https://...")
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .foregroundColor(.secondary)
            #if !os(macOS)
              .keyboardType(.URL)
            #endif
          }
        }
      }
    }
    .onChange(of: editableCredits) { _, _ in
      onChange()
    }
    .onChange(of: selectedLicense) { _, _ in
      onChange()
    }
  }
}

struct BuiltInCreditsView: View {
  let sound: Sound
  let creditsManager: SoundCreditsManager

  var body: some View {
    Group {
      if let soundCredit = creditsManager.credits.first(where: { $0.name == sound.title }) {
        // Original Work
        HStack {
          Text("Original Work")
          Spacer()
          if let url = soundCredit.soundUrl {
            Link(soundCredit.soundName, destination: url)
              .foregroundColor(.accentColor)
          } else {
            Text(soundCredit.soundName)
              .foregroundColor(.secondary)
          }
        }

        // Author
        HStack {
          Text("Author")
          Spacer()
          Text(soundCredit.author)
            .foregroundColor(.secondary)
        }

        // License
        HStack {
          Text("License")
          Spacer()
          if let url = soundCredit.license.url {
            Link(soundCredit.license.linkText, destination: url)
              .foregroundColor(.accentColor)
          } else {
            Text(soundCredit.license.linkText)
              .foregroundColor(.secondary)
          }
        }
      }
    }
  }
}

struct EditableCredits: Equatable {
  var soundName = ""
  var author = ""
  var sourceUrl = ""
  var customLicenseText = ""
  var customLicenseUrl = ""
}
