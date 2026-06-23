//
//  CreatePresetSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import SwiftUI
import os

struct CreatePresetSheet: View {
  @Binding var isPresented: Bool
  /// Sound file names to pre-select ("create from playing sounds" while on
  /// the default preset). Empty = start with nothing selected.
  var initialSelectedSounds: Set<String> = []
  /// Fired after the new preset is created and applied so the owner can
  /// navigate to it (iPhone Library pushes the mixer); nil at the mixer.
  var onCreated: (() -> Void)?
  private let presetManager = PresetManager.shared
  private let audioManager = AudioManager.shared
  private let globalSettings = GlobalSettings.shared
  @State private var presetName = ""
  @State private var creatorName = ""
  @State private var error: String?
  @State private var selectedSounds: Set<String> = []
  @State private var showingSoundSelection = false
  @State private var artworkData: Data?
  @State private var showingImagePicker = false
  @State private var showingImageCropper = false
  @State private var animatedArtwork: AnimatedArtworkRef?
  @State private var staticArtworkPath: String?
  // Theme overrides (same semantics as Edit Preset: toggled off = nil =
  // follow the app-wide setting).
  @State private var useCustomTheme = false
  @State private var accentColor: Color?
  @State private var useCustomViewMode = false
  @State private var viewModeOverride: PresetViewMode?
  @State private var didCreatePreset = false
  @State private var isGeneratingName = false
  #if os(iOS) || os(visionOS)
    @State private var selectedImage: UIImage?
  #endif
  @Environment(\.dismiss) private var dismiss

  var orderedSounds: [Sound] {
    audioManager.sounds.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  /// Live accent: the in-flight custom accent once enabled, else app-wide —
  /// mirrors Edit Preset so the sheet re-themes while you pick.
  private var activeAccentColor: Color {
    if useCustomTheme {
      return accentColor ?? globalSettings.customAccentColor ?? .accentColor
    }
    return globalSettings.customAccentColor ?? .accentColor
  }

  var body: some View {
    NavigationStack {
      Form {
        errorSection
        // Same details card as Edit Preset (no Favorite — no preset yet).
        PresetDetailsSection(
          presetName: $presetName,
          creatorName: $creatorName,
          artworkData: $artworkData,
          showingImagePicker: $showingImagePicker,
          animatedArtwork: $animatedArtwork,
          staticArtworkPath: $staticArtworkPath,
          starToken: nil,
          accent: activeAccentColor,
          aiSoundTitles: selectedSoundTitles,
          sparklesOnlyWhenEmpty: false,
          isGeneratingName: $isGeneratingName
        )
        soundsSection
        PresetThemeSection(
          useCustomViewMode: $useCustomViewMode,
          viewModeOverride: $viewModeOverride,
          useCustomTheme: $useCustomTheme,
          accentColor: $accentColor
        )
      }
      .navigationTitle("New Preset")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(
          leading: Button("Cancel") { isPresented = false }
            .tint(Color.primary),
          trailing: Button("Create") { createPreset() }
            .fontWeight(.semibold)
            .disabled(presetName.isEmpty || selectedSounds.isEmpty)
            .tint(Color.primary)
        )
      #else
        .formStyle(.grouped)
        .frame(minWidth: 400, idealWidth: 500, minHeight: 300)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isPresented = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Create") { createPreset() }
            .keyboardShortcut(.return)
            .disabled(presetName.isEmpty || selectedSounds.isEmpty)
          }
        }
      #endif
      .onAppear(perform: setupDefaultSelection)
      #if os(iOS) || os(visionOS)
        .sheet(isPresented: $showingSoundSelection) {
          NavigationStack {
            SoundSelectionView(
              selectedSounds: $selectedSounds,
              orderedSounds: orderedSounds,
              editingPreset: nil
            )
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                  showingSoundSelection = false
                }
                .tint(Color.primary)
              }
            }
          }
        }
        .sheet(isPresented: $showingImagePicker) {
          #if os(iOS)
            ImagePicker(imageData: $artworkData)
          #endif
        }
      #else
        .fileImporter(
          isPresented: $showingImagePicker,
          allowedContentTypes: [.image],
          allowsMultipleSelection: false
        ) { result in
          handleMacOSImageImport(result)
        }
      #endif
    }
    // Live preview of the chosen accent across the whole sheet (mirrors
    // Edit Preset's root tint).
    .tint(activeAccentColor)
    #if os(iOS) || os(visionOS)
      // A full preset editor, not a quick dialog — page-sized on iPad instead
      // of the default small centered form sheet (no-op on iPhone). Matches
      // EditPresetSheet so both editors present identically.
      .presentationSizing(.page)
    #endif
    .onDisappear {
      cleanupAnimatedArtworkIfNeeded()
    }
  }
}

extension CreatePresetSheet {
  @ViewBuilder
  var errorSection: some View {
    if let error = error {
      Section {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
    }
  }

  /// Mirrors Edit Preset's Sounds section (header, Choose Sounds row, then a
  /// row per selected sound) minus reorder/edit — there's no preset to
  /// persist against yet.
  var soundsSection: some View {
    Section {
      #if os(iOS)
        Button {
          showingSoundSelection = true
        } label: {
          HStack {
            LabeledContent("Choose Sounds", value: "\(selectedSounds.count)")
            Image(systemName: "chevron.right")
              .foregroundStyle(.tertiary)
              .imageScale(.small)
              .accessibilityHidden(true)
          }
        }
      #else
        NavigationLink(
          destination: SoundSelectionView(
            selectedSounds: $selectedSounds, orderedSounds: orderedSounds, editingPreset: nil
          )
        ) {
          LabeledContent("Choose Sounds", value: "\(selectedSounds.count)")
        }
      #endif

      if selectedSounds.isEmpty {
        Text("No sounds selected")
          .foregroundStyle(.secondary)
          .font(.subheadline)
      } else {
        ForEach(orderedSounds.filter { selectedSounds.contains($0.fileName) }) { sound in
          HStack(spacing: 8) {
            Label {
              Text(sound.title)
            } icon: {
              Image(systemName: sound.systemIconName)
                .foregroundColor(activeAccentColor)
            }
            SoundCreditInfoButton(sound: sound, accent: activeAccentColor)
            Spacer()
          }
        }
      }
    } header: {
      Text("Sounds")
    }
  }

  func setupDefaultSelection() {
    // Seed from the caller's pre-selection; otherwise start with no sounds
    // selected - user can add sounds as needed
    if !initialSelectedSounds.isEmpty {
      selectedSounds = initialSelectedSounds
      // Offer an Apple Intelligence name for the seeded mix up front.
      Task {
        await generateInitialNameSuggestion()
      }
    }
  }

  /// Titles of the currently selected sounds, for the name prompt.
  private var selectedSoundTitles: [String] {
    orderedSounds.filter { selectedSounds.contains($0.fileName) }.map(\.title)
  }

  /// Fills the name on open when seeded from playing sounds; taps on the
  /// details card's sparkles button regenerate from there.
  @MainActor
  private func generateInitialNameSuggestion() async {
    guard !isGeneratingName, AIPresetNameGenerator.isAvailable, presetName.isEmpty else { return }
    let titles = selectedSoundTitles
    guard !titles.isEmpty else { return }

    // Shared flag drives the details card's spinner and blocks a second tap
    // on the sparkles button while this initial suggestion is in flight.
    isGeneratingName = true
    defer { isGeneratingName = false }

    let suggestion = await AIPresetNameGenerator.generateName(from: titles, allowVariation: false)
    // Don't clobber anything typed while generating (or a failed "" result).
    if presetName.isEmpty, !suggestion.isEmpty {
      presetName = suggestion
    }
  }

  func createPreset() {
    guard !presetName.isEmpty else {
      error = "Preset name cannot be empty"
      return
    }

    Task {
      do {
        let newPreset = try await buildNewPreset()

        var currentPresets = presetManager.presets
        currentPresets.append(newPreset)
        presetManager.setPresets(currentPresets)
        presetManager.updateCustomPresetStatus()
        presetManager.savePresets()

        // Cache thumbnail for CarPlay if static or animated artwork was added
        if newPreset.artworkId != nil || newPreset.animatedArtwork != nil {
          await presetManager.cacheThumbnail(for: newPreset)
        }

        // Leave solo/Quick Mix first, like a Library row tap, so the prior
        // mix doesn't linger as the current selection.
        if audioManager.soloModeSound != nil {
          audioManager.exitSoloModeWithoutResuming()
        }
        if audioManager.isQuickMix {
          audioManager.exitQuickMix()
        }
        try presetManager.applyPreset(newPreset)
        await MainActor.run {
          didCreatePreset = true
          // Re-arm the remote command handlers and refresh Now Playing for the
          // freshly created preset. Browsing the animated-artwork gallery while
          // creating can make iOS disconnect the handlers, which otherwise
          // leaves the new preset's lock-screen / Control Center transport dead
          // (existing presets are fine because nothing tore their handlers
          // down). Mirrors EditPresetSheet and the artwork picker's restore.
          audioManager.setupMediaControls()
          audioManager.nowPlayingManager.updateInfo(
            preset: newPreset,
            presetName: newPreset.name,
            creatorName: newPreset.creatorName,
            artworkId: newPreset.artworkId,
            isPlaying: audioManager.isGloballyPlaying
          )
        }
        isPresented = false
        onCreated?()
      } catch {
        await MainActor.run {
          self.error = "Failed to create preset"
        }
      }
    }
  }

  private func buildNewPreset() async throws -> Preset {
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let selectedSoundStates =
      orderedSounds
      .filter { selectedSounds.contains($0.fileName) }
      .map { sound in
        PresetState(
          fileName: sound.fileName,
          isSelected: true,  // Newly added sounds should be selected by default
          volume: sound.volume
        )
      }

    let presetId = UUID()
    let artworkId = await saveArtworkIfPresent(for: presetId)

    // Assign order based on existing custom presets count
    let customPresetsCount = presetManager.presets.filter { !$0.isDefault }.count

    var newPreset = Preset(
      id: presetId,
      name: presetName,
      soundStates: selectedSoundStates,
      isDefault: false,
      createdVersion: currentVersion,
      lastModifiedVersion: currentVersion,
      soundOrder: nil,
      creatorName: creatorName.isEmpty ? nil : creatorName,
      artworkId: artworkId,
      animatedArtwork: animatedArtwork,
      staticArtworkPath: staticArtworkPath,
      order: customPresetsCount
    )

    // Theme overrides, persisted exactly like Edit Preset's save path
    // (toggled off = nil = follow the app-wide setting).
    newPreset.accentColorName = useCustomTheme ? accentColor?.toString : nil
    newPreset.viewMode = useCustomViewMode ? viewModeOverride : nil
    // Background blur is now a global Display setting, not a per-preset override.

    Logger.ui.debug(
      "CreatePresetSheet: Creating preset '\(presetName)' with artwork: \(artworkId != nil ? "set" : "none")"
    )

    return newPreset
  }

  private func saveArtworkIfPresent(for presetId: UUID) async -> UUID? {
    guard let data = artworkData else { return nil }

    do {
      let artworkId = try await PresetArtworkManager.shared.saveArtwork(
        data, for: presetId, type: .artwork
      )
      Logger.ui.debug("CreatePresetSheet: Saved artwork with ID: \(artworkId)")
      return artworkId
    } catch {
      Logger.ui.error("CreatePresetSheet: Failed to save artwork: \(error, privacy: .public)")
      return nil
    }
  }

  private func cleanupAnimatedArtworkIfNeeded() {
    guard !didCreatePreset else { return }
    AnimatedArtworkFileStore.removeItemIfExists(relativePath: animatedArtwork?.loopPath)
    if animatedArtwork?.previewPath != staticArtworkPath {
      AnimatedArtworkFileStore.removeItemIfExists(relativePath: animatedArtwork?.previewPath)
    }
    AnimatedArtworkFileStore.removeItemIfExists(relativePath: staticArtworkPath)
  }
}

// MARK: - macOS Image Handling

#if os(macOS)
  extension CreatePresetSheet {
    fileprivate func handleMacOSImageImport(_ result: Result<[URL], Error>) {
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
          if accessing {
            url.stopAccessingSecurityScopedResource()
          }
        }

        do {
          let data = try Data(contentsOf: url)
          if let nsImage = NSImage(data: data) {
            if abs(nsImage.size.width - nsImage.size.height) < 1 {
              artworkData = nsImage.jpegData(compressionQuality: 0.8)
            } else {
              let squareImage = cropToSquareMacOS(image: nsImage)
              artworkData = squareImage.jpegData(compressionQuality: 0.8)
            }
          } else {
            artworkData = data
          }
        } catch {
          Logger.ui.error("macOS Image Picker: Failed to load image: \(error, privacy: .public)")
        }
      case .failure(let error):
        Logger.ui.error("macOS Image Picker: Image picker error: \(error, privacy: .public)")
      }
    }

    fileprivate func cropToSquareMacOS(image: NSImage) -> NSImage {
      let size = min(image.size.width, image.size.height)
      let offsetX = (image.size.width - size) / 2
      let offsetY = (image.size.height - size) / 2
      let cropRect = NSRect(x: offsetX, y: offsetY, width: size, height: size)

      guard
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(
          to: cropRect)
      else {
        return image
      }

      return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
  }
#endif
