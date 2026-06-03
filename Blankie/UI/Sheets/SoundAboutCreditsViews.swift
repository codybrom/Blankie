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
          .accessibilityLabel("Original Work")
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
          .accessibilityLabel("Author")
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
          .accessibilityLabel("Source URL")
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
          .accessibilityLabel("License Details")

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
            .accessibilityLabel("License URL")
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

struct EditableCredits: Equatable {
  var soundName = ""
  var author = ""
  var sourceUrl = ""
  var customLicenseText = ""
  var customLicenseUrl = ""
}
