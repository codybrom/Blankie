//
//  PresetDetailsSection.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/26.
//

import SwiftUI

/// Name, Creator, Favorite and Artwork card shared by New Preset and Edit Preset.
/// Edit passes `onEdited` and `starToken`. New Preset commits on Create.
struct PresetDetailsSection: View {
  @Binding var presetName: String
  @Binding var creatorName: String
  @Binding var artworkData: Data?
  @Binding var showingImagePicker: Bool
  @Binding var animatedArtwork: AnimatedArtworkRef?
  @Binding var staticArtworkPath: String?

  /// Star token for the Favorite row. Nil hides it (New Preset).
  var starToken: String?
  var accent: Color
  /// Selected sound titles for AI naming (sparkles hides when empty).
  var aiSoundTitles: [String]
  /// Edit offers sparkles only while the name is empty (a typed name is
  /// settled). New Preset always offers a regenerate.
  var sparklesOnlyWhenEmpty: Bool
  /// Runs after any field change. Edit persists instantly, and create passes nil.
  var onEdited: (() -> Void)?
  /// Extra cleanup when artwork is removed (Edit also clears its artwork ID).
  var onRemoveArtwork: (() -> Void)?
  /// In-flight flag for AI naming, owned by the parent so the auto-suggest on
  /// open and the sparkles button share one guard.
  @Binding var isGeneratingName: Bool
  /// Shown under the details, such as a clash with an existing name.
  var nameNote: LocalizedStringKey?

  @State private var aiAvailable = false
  private let globalSettings = GlobalSettings.shared

  var body: some View {
    detailsSection
    artworkSection
  }

  private var detailsSection: some View {
    Section {
      nameRow
      creatorRow
      if let starToken {
        favoriteRow(starToken)
      }
    } footer: {
      if let nameNote {
        Text(nameNote)
          .foregroundStyle(.red)
      }
    }
    .onAppear {
      aiAvailable = AIPresetNameGenerator.isAvailable
    }
  }

  /// Background (the photo behind the sounds and the Now Playing thumbnail) and
  /// Lock Screen (animated artwork) tiles. A preset can carry both. macOS shows
  /// Background only.
  private var artworkSection: some View {
    Section {
      HStack(alignment: .top, spacing: 16) {
        Spacer(minLength: 0)

        backgroundTile
          .frame(maxWidth: 160)

        #if os(iOS)
          AnimatedArtworkPicker(
            artwork: $animatedArtwork,
            staticArtworkPath: $staticArtworkPath,
            presentation: .tile,
            accent: accent,
            onChange: { onEdited?() }
          )
          .frame(maxWidth: 160)
        #endif

        Spacer(minLength: 0)
      }
      .padding(.vertical, 4)
    } header: {
      Text("Artwork")
    }
    .onChange(of: artworkData) { _, _ in
      onEdited?()
    }
  }

  private var backgroundTile: some View {
    // With no photo, show the animation's still, which is what the runtime
    // background uses.
    let mirror = mirroredAnimationImage
    let shown = backgroundImage ?? mirror
    return ArtworkTile(
      caption: "Background",
      isSet: shown != nil,
      placeholderIcon: "photo",
      placeholderLabel: "Add Image",
      accent: accent,
      onTap: { showingImagePicker = true },
      // Only a photo is removable here. Clearing artworkData already fires
      // `onEdited` through the section's `.onChange(of: artworkData)`.
      onRemove: artworkData == nil
        ? nil
        : {
          artworkData = nil
          onRemoveArtwork?()
        },
      thumbnail: {
        if let shown {
          shown
            .resizable()
            .aspectRatio(contentMode: .fill)
        }
      }
    )
  }

  private var backgroundImage: Image? {
    guard let artworkData else { return nil }
    #if os(iOS) || os(visionOS)
      return UIImage(data: artworkData).map(Image.init(uiImage:))
    #elseif os(macOS)
      return NSImage(data: artworkData).map(Image.init(nsImage:))
    #endif
  }

  /// The animation's square still, shown in the Background tile when no photo is
  /// set (the same fallback the runtime background uses).
  private var mirroredAnimationImage: Image? {
    guard artworkData == nil,
      let path = animatedArtwork?.squarePreviewPath ?? animatedArtwork?.previewPath,
      AnimatedArtworkFileStore.fileExists(at: path)
    else { return nil }
    let url = AnimatedArtworkFileStore.absoluteURL(for: path)
    #if os(iOS) || os(visionOS)
      return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
    #elseif os(macOS)
      return NSImage(contentsOf: url).map(Image.init(nsImage:))
    #endif
  }

  private var nameRow: some View {
    LabeledContent("Name") {
      HStack(spacing: 8) {
        // A titled TextField shows its title as a permanent mid-row label in
        // macOS grouped forms, so "Required" goes in prompt:.
        TextField("Name", text: $presetName, prompt: Text("Required"))
          .labelsHidden()
          #if os(iOS)
            .multilineTextAlignment(.trailing)
          #endif
          .onChange(of: presetName) { _, _ in
            onEdited?()
          }

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
    // Pins the row separator to the leading edge like the plain rows (it
    // otherwise insets to the label text).
    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
      dimensions[.leading]
    }
  }

  /// Fills or replaces the name with an Apple Intelligence suggestion. In
  /// fill-empty mode, a name typed mid-generation wins.
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

/// A tappable square artwork tile with a caption. The caller supplies the
/// thumbnail (an image or a looping video) and the tap and remove actions.
struct ArtworkTile<Thumbnail: View>: View {
  let caption: LocalizedStringKey
  let isSet: Bool
  let placeholderIcon: String
  let placeholderLabel: LocalizedStringKey
  let accent: Color
  let onTap: () -> Void
  var onRemove: (() -> Void)?
  /// The filled-state content, already sized to fill (`.aspectRatio(.fill)` for
  /// images, and a looping player fills on its own). Shown only when `isSet`.
  @ViewBuilder var thumbnail: () -> Thumbnail

  var body: some View {
    VStack(alignment: .center, spacing: 8) {
      ZStack(alignment: .topTrailing) {
        Button(action: onTap) {
          RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.12))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
              if isSet {
                thumbnail()
              } else {
                VStack(spacing: 6) {
                  Image(systemName: placeholderIcon)
                    .font(.title2)
                  Text(placeholderLabel)
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
              }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
              RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                  isSet ? accent.opacity(0.7) : Color.secondary.opacity(0.25),
                  lineWidth: isSet ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(caption)
        .accessibilityValue(isSet ? Text("Artwork set") : Text("No artwork"))

        if let onRemove, isSet {
          Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, .black.opacity(0.5))
              .font(.title3)
              .padding(6)
          }
          .buttonStyle(.plain)
          // Includes the caption so VoiceOver tells the two remove buttons apart.
          .accessibilityLabel(Text("Remove \(Text(caption))"))
        }
      }

      Text(caption)
        .accessibilityHidden(true)
        .font(.subheadline)
        .fontWeight(.medium)
        .multilineTextAlignment(.center)
    }
  }
}
