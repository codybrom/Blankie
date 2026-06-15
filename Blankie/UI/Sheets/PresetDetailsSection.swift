//
//  PresetDetailsSection.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/26.
//

import SwiftUI

/// Shared Name / Creator / Favorite / Artwork card for the preset editors,
/// so New Preset and Edit Preset stay visually identical. Edit persists
/// instantly via `onEdited` and shows the Favorite row via `starToken`;
/// New Preset omits both (values commit when Create is pressed).
struct PresetDetailsSection: View {
  @Binding var presetName: String
  @Binding var creatorName: String
  @Binding var artworkData: Data?
  @Binding var showingImagePicker: Bool
  @Binding var animatedArtwork: AnimatedArtworkRef?
  @Binding var staticArtworkPath: String?

  /// Star token for the Favorite row; nil hides it (New Preset).
  var starToken: String?
  var accent: Color
  /// Selected sound titles for AI naming (sparkles hides when empty).
  var aiSoundTitles: [String]
  /// Edit offers sparkles only while the name is empty (a typed name is
  /// settled); New Preset always offers a regenerate.
  var sparklesOnlyWhenEmpty: Bool
  /// Runs after any field change (Edit persists instantly; nil for create).
  var onEdited: (() -> Void)?
  /// Extra cleanup when artwork is removed (Edit also clears its artwork ID).
  var onRemoveArtwork: (() -> Void)?

  @State private var isGeneratingName = false
  @State private var aiAvailable = false
  private let globalSettings = GlobalSettings.shared

  var body: some View {
    Section {
      nameRow
      creatorRow
      if let starToken {
        favoriteRow(starToken)
      }
      artworkRow

      // Animated artwork editing is iOS-only; hide it on macOS.
      #if !os(macOS)
        AnimatedArtworkPicker(
          artwork: $animatedArtwork,
          staticArtworkPath: $staticArtworkPath,
          accent: accent,
          onChange: { onEdited?() }
        )
      #endif
    }
    .onChange(of: artworkData) { _, _ in
      onEdited?()
    }
    .onAppear {
      aiAvailable = AIPresetNameGenerator.isAvailable
    }
  }

  private var nameRow: some View {
    LabeledContent("Name") {
      HStack(spacing: 8) {
        // prompt: (not the title) so "Required" only shows while empty — a
        // titled TextField renders its title as a permanent mid-row label in
        // macOS grouped forms.
        TextField("Name", text: $presetName, prompt: Text("Required"))
          .labelsHidden()
          #if os(iOS)
            // Trailing alignment looks right on iOS; macOS keeps the
            // standard leading form-field alignment.
            .multilineTextAlignment(.trailing)
          #endif
          .onChange(of: presetName) { _, _ in
            onEdited?()
          }

        // Apple Intelligence name suggestion from the selected sounds.
        if aiAvailable, !aiSoundTitles.isEmpty, !sparklesOnlyWhenEmpty || presetName.isEmpty {
          if isGeneratingName {
            ProgressView()
              .controlSize(.small)
          } else {
            Button {
              Task {
                await generateNameSuggestion()
              }
            } label: {
              Image(systemName: "sparkles")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Generate Name with Apple Intelligence")
          }
        }
      }
    }
  }

  private var creatorRow: some View {
    LabeledContent("Creator") {
      TextField("Creator", text: $creatorName, prompt: Text("Optional"))
        .labelsHidden()
        #if os(iOS)
          .multilineTextAlignment(.trailing)
        #endif
        .onChange(of: creatorName) { _, _ in
          onEdited?()
        }
    }
  }

  private func favoriteRow(_ token: String) -> some View {
    Toggle(
      isOn: Binding(
        get: { globalSettings.isStarred(token) },
        set: { _ in globalSettings.toggleStarred(token) }
      )
    ) {
      Label {
        Text("Favorite")
      } icon: {
        Image(systemName: "star")
          .foregroundColor(accent)
      }
    }
    // Without this the row separator insets to the label text, leaving a gap
    // under the star. Pin it to the row's leading edge like the plain rows.
    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
      dimensions[.leading]
    }
  }

  private var artworkRow: some View {
    LabeledContent("Artwork") {
      HStack(spacing: 8) {
        if artworkData != nil {
          Button {
            artworkData = nil
            onRemoveArtwork?()
            onEdited?()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove Artwork")
        }

        Button {
          showingImagePicker = true
        } label: {
          artworkPreview
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose Artwork")
      }
    }
  }

  @ViewBuilder
  private var artworkPreview: some View {
    if let artworkData = artworkData {
      #if os(iOS) || os(visionOS)
        if let uiImage = UIImage(data: artworkData) {
          Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      #elseif os(macOS)
        if let nsImage = NSImage(data: artworkData) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      #endif
    } else {
      Text("Select Image")
        .foregroundStyle(.secondary)
    }
  }

  /// Fills/replaces the name with an Apple Intelligence suggestion from the
  /// selected sounds. In fill-empty mode a name typed mid-generation wins.
  private func generateNameSuggestion() async {
    guard !isGeneratingName, !aiSoundTitles.isEmpty else { return }

    isGeneratingName = true
    let suggestion = await AIPresetNameGenerator.generateName(
      from: aiSoundTitles, allowVariation: true)
    await MainActor.run {
      if !suggestion.isEmpty, !(sparklesOnlyWhenEmpty && !presetName.isEmpty) {
        presetName = suggestion
        onEdited?()
      }
      isGeneratingName = false
    }
  }
}
