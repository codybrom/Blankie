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
  /// In-flight flag for AI naming, owned by the parent so the auto-suggest on
  /// open and the sparkles button share one guard (spinner + no double-fire).
  @Binding var isGeneratingName: Bool

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
    }
    .onAppear {
      aiAvailable = AIPresetNameGenerator.isAvailable
    }
  }

  /// Two side-by-side preview tiles that mirror the iPhone Home Screen / Lock
  /// Screen pairing: "Background" is the photo shown behind the sounds (and the
  /// Now Playing thumbnail); "Lock Screen" is the free animated artwork. They
  /// are independent — a preset can carry both — so the footer explains each
  /// rather than the UI forcing a single choice. macOS has no animated artwork,
  /// so it shows the Background tile only.
  private var artworkSection: some View {
    Section {
      HStack(alignment: .top, spacing: 16) {
        backgroundTile
          .frame(maxWidth: 160)

        // Animated artwork editing is iOS-only; hide it on macOS.
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
    } footer: {
      #if os(iOS)
        Text(
          "Your background shows behind your sounds. Lock Screen art is free animated artwork that plays while your phone is locked."
        )
      #else
        Text("Your background shows behind your sounds.")
      #endif
    }
    .onChange(of: artworkData) { _, _ in
      onEdited?()
    }
  }

  private var backgroundTile: some View {
    // A chosen photo wins; with no photo, mirror the animation's still preview
    // so the tile shows what actually sits behind the sounds (the runtime
    // background is a blurred still of the animation, not the moving video).
    let mirror = mirroredAnimationImage
    let shown = backgroundImage ?? mirror
    return ArtworkTile(
      caption: "Background",
      valueLabel: artworkData != nil ? "Image" : (mirror != nil ? "From Lock Screen" : "None"),
      isSet: shown != nil,
      placeholderIcon: "photo",
      placeholderLabel: "Add Image",
      accent: accent,
      onTap: { showingImagePicker = true },
      // Only removable when it is an actual photo; the mirrored still is owned
      // by the Lock Screen tile.
      onRemove: artworkData == nil
        ? nil
        : {
          artworkData = nil
          onRemoveArtwork?()
          onEdited?()
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

  /// SwiftUI image for the current background photo, built per platform.
  private var backgroundImage: Image? {
    guard let artworkData else { return nil }
    #if os(iOS) || os(visionOS)
      return UIImage(data: artworkData).map(Image.init(uiImage:))
    #elseif os(macOS)
      return NSImage(data: artworkData).map(Image.init(nsImage:))
    #endif
  }

  /// The animation's still square preview, shown in the Background tile only
  /// when no photo is set — mirroring the runtime precedence where the animated
  /// artwork's still is the background fallback.
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

/// A tappable square artwork preview tile: a thumbnail (or an empty
/// placeholder) with a caption and the current selection beneath it. Purely
/// presentational — the caller supplies the thumbnail content (an image or a
/// looping video) and the tap/remove actions. Shared by the preset editor's
/// Background and Lock Screen tiles, echoing the iPhone wallpaper picker's pair.
struct ArtworkTile<Thumbnail: View>: View {
  let caption: LocalizedStringKey
  let valueLabel: LocalizedStringKey
  /// Whether artwork is set: drives the border, the remove control, and whether
  /// the thumbnail or the empty placeholder shows.
  let isSet: Bool
  let placeholderIcon: String
  let placeholderLabel: LocalizedStringKey
  let accent: Color
  let onTap: () -> Void
  var onRemove: (() -> Void)?
  /// The filled-state content, already sized to fill (`.aspectRatio(.fill)` for
  /// images; a looping player fills on its own). Shown only when `isSet`.
  @ViewBuilder var thumbnail: () -> Thumbnail

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
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

        if let onRemove, isSet {
          Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, .black.opacity(0.5))
              .font(.title3)
              .padding(6)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove")
        }
      }

      Text(caption)
        .font(.subheadline)
        .fontWeight(.medium)
      Text(valueLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}
