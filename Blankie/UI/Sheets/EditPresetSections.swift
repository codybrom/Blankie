//
//  EditPresetSections.swift
//  Blankie
//
//  Created by Cody Bromley on 6/11/25.
//

import PhotosUI
import SwiftUI

// MARK: - Default Preset Section

// MARK: - Core Section (Name and Sounds)

extension EditPresetSheet {
  var coreSection: some View {
    Section {
      // Name field
      LabeledContent("Name") {
        TextField("Required", text: $presetName)
          .multilineTextAlignment(.trailing)
          .onChange(of: presetName) { _, _ in
            applyChangesInstantly()
          }
      }

      // Sounds field
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          LabeledContent("Sounds") {
            HStack {
              Text("\(selectedSounds.count) Selected")
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
          }
        }
        .buttonStyle(.plain)
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          LabeledContent("Sounds") {
            Text("\(selectedSounds.count) Selected")
              .foregroundStyle(.secondary)
          }
        }
      #endif
    }
    .onChange(of: selectedSounds) { _, _ in
      applyChangesInstantly()
    }
  }
}

// MARK: - Now Playing Section (Creator & Artwork)

extension EditPresetSheet {
  var nowPlayingSection: some View {
    Section("Now Playing") {
      // Creator field (only for non-default presets)
      if !preset.isDefault {
        LabeledContent("Creator") {
          TextField("Optional", text: $creatorName)
            .multilineTextAlignment(.trailing)
            .onChange(of: creatorName) { _, _ in
              applyChangesInstantly()
            }
        }
      }

      // Artwork field
      LabeledContent("Artwork") {
        HStack(spacing: 8) {
          if artworkData != nil {
            Button {
              artworkData = nil
              artworkId = nil
              // Apply changes to persist the removal
              applyChangesInstantly()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
          }

          Button {
            showingImagePicker = true
          } label: {
            artworkPreview
          }
          .buttonStyle(.plain)
        }
      }

      AnimatedArtworkPicker(
        artwork: $animatedArtwork,
        staticArtworkPath: $staticArtworkPath,
        onChange: applyChangesInstantly
      )
    }
    .onChange(of: artworkData) { _, _ in
      applyChangesInstantly()
    }
  }
}

// MARK: - Error Section

extension EditPresetSheet {
  @ViewBuilder
  var errorSection: some View {
    if let error = error {
      Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
  }
}

// MARK: - Basic Info Section (deprecated - use nowPlayingSection)

extension EditPresetSheet {
  var basicInfoSection: some View {
    nowPlayingSection
  }
}

// MARK: - Creator Section (deprecated - now part of nowPlayingInfoSection)

extension EditPresetSheet {
  var creatorSection: some View {
    EmptyView()
  }
}

// MARK: - Artwork Section (deprecated - now part of nowPlayingInfoSection)

extension EditPresetSheet {
  var artworkSection: some View {
    EmptyView()
  }
}

// MARK: - Artwork Preview

extension EditPresetSheet {
  @ViewBuilder
  var artworkPreview: some View {
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
}

// MARK: - Sounds Section

extension EditPresetSheet {
  var soundsSection: some View {
    Section {
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          LabeledContent("Sounds") {
            HStack {
              Text("\(selectedSounds.count) Selected")
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
          }
        }
        .buttonStyle(.plain)
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: preset
          )
        ) {
          LabeledContent("Sounds") {
            Text("\(selectedSounds.count) Selected")
              .foregroundStyle(.secondary)
          }
        }
      #endif
    }
    .onChange(of: selectedSounds) { _, _ in
      applyChangesInstantly()
    }
  }
}

// MARK: - Background Section

extension EditPresetSheet {
  var backgroundSection: some View {
    Section("Background") {
      // Show background toggle
      Toggle("Show Background Image", isOn: $showBackgroundImage)

      if showBackgroundImage {
        // Use cover art toggle
        Toggle("Use Cover Art", isOn: $useArtworkAsBackground)

        // Only show image picker if not using cover art
        if !useArtworkAsBackground {
          LabeledContent {
            HStack(spacing: 8) {
              if backgroundImageData != nil {
                Button {
                  print("🎨 Clear tapped - removing background")
                  withAnimation {
                    backgroundImageData = nil
                    backgroundImageId = nil
                    backgroundBlurRadius = 3.0 // Low Blur
                    backgroundOpacity = 0.3 // Low Opacity
                    // Apply changes to persist the removal
                    applyChangesInstantly()
                  }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
              }

              PhotosPicker(
                selection: $selectedBackgroundPhoto,
                matching: .images
              ) {
                Text(backgroundImageData != nil ? "Change" : "Choose Photo")
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.plain)
            }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text("Background Image")
              Text("9:16 aspect ratio recommended")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        // Preview and controls - show for cover art, custom image, or animated artwork
        if (useArtworkAsBackground && (artworkData != nil || animatedArtwork != nil))
          || (!useArtworkAsBackground && backgroundImageData != nil)
        {
          backgroundPreviewRow
          backgroundBlurRow
          backgroundOpacityRow
        }
      }
    }
    .onChange(of: showBackgroundImage) { _, _ in
      applyChangesInstantly()
    }
    .onChange(of: useArtworkAsBackground) { _, _ in
      applyChangesInstantly()
    }
    .onChange(of: backgroundImageData) { _, _ in
      applyChangesInstantly()
    }
    .onChange(of: backgroundBlurRadius) { _, _ in
      applyChangesInstantly()
    }
    .onChange(of: backgroundOpacity) { _, _ in
      applyChangesInstantly()
    }
  }

  private var backgroundPreviewRow: some View {
    HStack {
      backgroundPreview
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .cornerRadius(8)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
  }

  private var backgroundBlurRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Blur")
        .font(.subheadline)

      Picker("Blur", selection: $backgroundBlurRadius) {
        Text("None").tag(0.0)
        Text("Low").tag(3.0)
        Text("Medium").tag(15.0)
        Text("High").tag(25.0)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  private var backgroundOpacityRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Opacity")
        .font(.subheadline)

      Picker(
        "Opacity",
        selection: Binding(
          get: {
            // Convert opacity value to closest option
            switch backgroundOpacity {
            case 0 ..< 0.5: return 0.3
            case 0.5 ..< 0.85: return 0.65
            default: return 1.0
            }
          },
          set: { newValue in
            backgroundOpacity = newValue
          }
        )
      ) {
        Text("Low").tag(0.3)
        Text("Medium").tag(0.65)
        Text("Full").tag(1.0)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
  }

  private var backgroundResetRow: some View {
    Button {
      backgroundBlurRadius = 3.0 // Low blur
      backgroundOpacity = 0.3 // Low opacity
    } label: {
      Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
        .font(.caption)
    }
    .buttonStyle(.plain)
    .foregroundColor(.secondary)
  }

  @ViewBuilder
  private var backgroundPreview: some View {
    let imageData = useArtworkAsBackground ? artworkData : backgroundImageData

    if let imageData = imageData {
      #if os(macOS)
        if let nsImage = NSImage(data: imageData) {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: backgroundBlurRadius)
            .opacity(backgroundOpacity)
            .background(Color.black)
        }
      #else
        if let uiImage = UIImage(data: imageData) {
          Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: backgroundBlurRadius)
            .opacity(backgroundOpacity)
            .background(Color.black)
        }
      #endif
    } else if useArtworkAsBackground, let animatedArtwork = animatedArtwork {
      // Show animated artwork's 3:4 preview as background fallback
      AnimatedArtworkPreviewBackground(
        animatedArtwork: animatedArtwork,
        staticArtworkPath: staticArtworkPath,
        blurRadius: backgroundBlurRadius,
        opacity: backgroundOpacity
      )
    }
  }
}

// MARK: - Animated Artwork Preview Background

#if canImport(UIKit)
  private struct AnimatedArtworkPreviewBackground: View {
    let animatedArtwork: AnimatedArtworkRef
    let staticArtworkPath: String?
    let blurRadius: Double
    let opacity: Double

    @State private var previewImage: UIImage?

    var body: some View {
      Group {
        if let image = previewImage {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .background(Color.black)
        } else {
          Color.secondary.opacity(0.2)
        }
      }
      .task {
        await loadPreview()
      }
    }

    private func loadPreview() async {
      // Check Documents directory first for cached preview
      if let previewPath = animatedArtwork.previewPath ?? staticArtworkPath {
        let previewURL = AnimatedArtworkFileStore.absoluteURL(for: previewPath)
        if FileManager.default.fileExists(atPath: previewURL.path) {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            await MainActor.run {
              previewImage = image
            }
            return
          }
        }
      }

      // If not cached, try loading from bundle for bundled resources
      if animatedArtwork.source == .bundled, let bundledId = animatedArtwork.bundledIdentifier {
        let previewName = bundledId
        if let previewURL = Bundle.main.url(forResource: previewName, withExtension: "jpg") {
          if let image = UIImage(contentsOfFile: previewURL.path) {
            await MainActor.run {
              previewImage = image
            }
            return
          }
        }
      }
    }
  }
#endif

// MARK: - Delete Section

extension EditPresetSheet {}

// MARK: - Delete Section

extension EditPresetSheet {
  @ViewBuilder
  var deleteSection: some View {
    Section {
      Button(role: .destructive) {
        presetToDelete = preset
      } label: {
        HStack {
          Spacer()
          Text("Delete Preset")
          Spacer()
        }
      }
    }
  }
}
