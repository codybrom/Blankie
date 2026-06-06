//
//  EditPresetSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import MediaPlayer
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import os

extension UTType {
  static let blankie = UTType(exportedAs: "com.codybrom.blankie.preset")
}

/// Value-type navigation key for pushing Edit Sound. Pushing the `Sound`
/// class itself into the NavigationStack path can hand the destination a
/// zeroed reference on re-render (EXC_BAD_ACCESS), so navigate by fileName
/// and resolve the live instance at the destination.
struct SoundEditDestination: Hashable {
  let fileName: String
}

// MARK: - Exportable Preset

struct ExportablePreset: Transferable {
  let sheet: EditPresetSheet

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .blankie) { exportable in
      // Generate the export file on-demand
      let updatedPreset = await exportable.sheet.createUpdatedPreset()
      let tempArchiveURL = try await PresetExporter.shared.createArchive(for: updatedPreset)

      // Move to Documents directory for proper sharing
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!
      let fileName = "\(updatedPreset.name).blankie"
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
      let finalURL = documentsPath.appendingPathComponent(fileName)

      // Remove existing file if it exists
      try? FileManager.default.removeItem(at: finalURL)

      // Move the file
      try FileManager.default.moveItem(at: tempArchiveURL, to: finalURL)

      // Store the URL for cleanup later
      await MainActor.run {
        exportable.sheet.exportedURL = finalURL
      }

      return SentTransferredFile(finalURL, allowAccessingOriginalFile: true)
    }
  }
}

struct EditPresetSheet: View {
  let preset: Preset
  @Binding var isPresented: Preset?
  @ObservedObject var presetManager = PresetManager.shared
  @ObservedObject var audioManager = AudioManager.shared
  @ObservedObject var globalSettings = GlobalSettings.shared
  @State var presetName: String = ""
  @State var creatorName: String = ""
  @State var moods: Set<SoundMood> = []
  @State var selectedSounds: Set<String> = []
  @State var soundOrder: [String] = []
  @State var error: String?
  @State var showingSoundSelection = false
  @State var artworkData: Data?
  @State var artworkId: UUID?
  @State var animatedArtwork: AnimatedArtworkRef?
  @State var staticArtworkPath: String?
  @State var showingImagePicker = false
  @State var accentColor: Color?
  @State var presetToDelete: Preset?
  @State var exportError: String?
  @State var exportedURL: URL?
  @State var isExporting = false
  @State var useCustomTheme = false
  /// Whether this preset overrides the app-wide grid/list view mode. When off,
  /// the preset stores `nil` and follows `GlobalSettings.showingListView`.
  @State var useCustomViewMode = false
  @State var viewModeOverride: PresetViewMode?
  /// Whether this preset overrides the app-wide background blur. When off, the
  /// preset stores `nil` and follows `GlobalSettings.backgroundBlurRadius`.
  @State var useCustomBlur = false
  @State var blurOverride: Double = defaultBackgroundBlurRadius
  #if os(iOS) || os(visionOS)
    @State var soundEditMode: EditMode = .inactive
  #endif
  @State var navPath = NavigationPath()
  @Environment(\.dismiss) private var dismiss

  init(preset: Preset, isPresented: Binding<Preset?>) {
    self.preset = preset
    _isPresented = isPresented

    // Seed editing state before first render. Populating it in onAppear
    // tripped the accent/theme onChange handlers, dirtying the preset (and
    // re-saving its artwork under a new ID) on every open.
    _presetName = State(initialValue: preset.name)
    _creatorName = State(initialValue: preset.creatorName ?? "")
    _moods = State(initialValue: Set(preset.moods ?? []))
    _selectedSounds = State(initialValue: Set(preset.soundStates.map(\.fileName)))
    let order: [String]
    if let presetOrder = preset.soundOrder {
      order = presetOrder
    } else if preset.isDefault {
      order = AudioManager.shared.defaultSoundOrder
    } else {
      order = preset.soundStates.map(\.fileName)
    }
    _soundOrder = State(initialValue: order)
    _artworkId = State(initialValue: preset.artworkId)
    _animatedArtwork = State(initialValue: preset.animatedArtwork)
    _staticArtworkPath = State(initialValue: preset.staticArtworkPath)
    _accentColor = State(initialValue: preset.accentColor)
    _useCustomTheme = State(initialValue: preset.accentColor != nil)
    _useCustomViewMode = State(initialValue: preset.viewMode != nil)
    _viewModeOverride = State(initialValue: preset.viewMode)
    _useCustomBlur = State(initialValue: preset.backgroundBlurRadius != nil)
    // Seed with the effective value so enabling the override doesn't jump the
    // background; normalize legacy radii (e.g. the old "High" 15) to on/off.
    let effectiveBlur = preset.backgroundBlurRadius ?? GlobalSettings.shared.backgroundBlurRadius
    _blurOverride = State(initialValue: effectiveBlur > 0 ? defaultBackgroundBlurRadius : 0)
  }

  var orderedSounds: [Sound] {
    audioManager.sounds.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  var body: some View {
    NavigationStack(path: $navPath) {
      Form {
        if preset.isDefault {
          defaultPresetSection
        } else {
          editablePresetSections
        }
      }
      .navigationTitle(preset.isDefault ? "View Preset" : "Edit Preset")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isPresented = nil }
            .tint(Color.primary)
          }
          ToolbarItem(placement: .topBarTrailing) {
            exportButton
            .tint(Color.primary)
          }
        }
      #else
        .formStyle(.grouped)
        .frame(minWidth: 400, idealWidth: 500, minHeight: preset.isDefault ? 200 : 300)
        .toolbar {
          // Keep these as separate items: macOS 26 sheet bottom bars render
          // only ONE item per action slot, so grouping share with Done (or
          // sharing the .confirmationAction placement) silently drops Done.
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isPresented = nil }
            .keyboardShortcut(.escape)
          }
          ToolbarItem(placement: .automatic) {
            exportButton
          }
        }
      #endif
      .navigationDestination(for: SoundEditDestination.self) { destination in
        if let sound = audioManager.sounds.first(where: { $0.fileName == destination.fileName }) {
          SoundSheet(mode: .edit(sound), embedInNavigation: false)
        }
      }
      .onAppear(perform: setupInitialValues)
      .onDisappear {
        // Clean up exported file when sheet closes
        cleanupExportedFile()
      }
      .onChange(of: accentColor) { _, _ in
        applyChangesInstantly()
      }
      .onChange(of: useCustomTheme) { _, _ in
        applyChangesInstantly()
      }
      #if os(macOS)
        // macOS edits sounds via an inline NavigationLink (no sheet to close),
        // so there's no dismiss event to apply on. Apply whenever the selection
        // set changes instead. iOS keeps its sheet-close trigger below.
        .onChange(of: selectedSounds) { _, _ in
          applyChangesInstantly()
        }
      #endif
      #if os(iOS) || os(visionOS)
        .sheet(isPresented: $showingSoundSelection) {
          soundSelectionSheet
        }
        .onChange(of: showingSoundSelection) { _, isShowing in
          if !isShowing {
            applyChangesInstantly()
          }
        }
        .sheet(isPresented: $showingImagePicker) {
          imagePickerSheet
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
    .tint(
      useCustomTheme
        ? (accentColor ?? globalSettings.customAccentColor ?? .accentColor)
        : (globalSettings.customAccentColor ?? .accentColor)
    )
    .alert(
      "Delete Preset",
      isPresented: .init(
        get: { presetToDelete != nil },
        set: { if !$0 { presetToDelete = nil } }
      )
    ) {
      Button("Cancel", role: .cancel) {
        presetToDelete = nil
      }
      Button("Delete", role: .destructive) {
        if let preset = presetToDelete {
          deletePreset(preset)
        }
      }
    } message: {
      if let preset = presetToDelete {
        Text("Are you sure you want to delete \"\(preset.name)\"? This action cannot be undone.")
      }
    }
  }

  @ViewBuilder
  var soundSelectionSheet: some View {
    NavigationStack {
      SoundSelectionView(
        selectedSounds: $selectedSounds,
        orderedSounds: orderedSounds,
        editingPreset: preset
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            showingSoundSelection = false
          }
          .tint(Color.primary)
        }
      }
      .navigationDestination(for: SoundEditDestination.self) { destination in
        if let sound = audioManager.sounds.first(where: { $0.fileName == destination.fileName }) {
          SoundSheet(mode: .edit(sound), embedInNavigation: false)
        }
      }
      // Match the editor's preset accent so the pushed Edit Sound page (which
      // inherits tint when embedded) themes like the sheet that opened it.
      .tint(activeAccentColor)
    }
  }

  @ViewBuilder
  var imagePickerSheet: some View {
    #if os(iOS)
      ImagePicker(imageData: $artworkData)
        .onDisappear {
          Logger.ui.debug(
            "EditPresetSheet: ImagePicker dismissed, artworkData is \(artworkData != nil ? "set" : "nil")"
          )
          if artworkData != nil {
            // Generate new ID for the new artwork
            Logger.ui.debug("EditPresetSheet: Generating new artwork ID and applying changes")
            artworkId = UUID()
            applyChangesInstantly()
          } else {
            Logger.ui.debug("EditPresetSheet: No artwork data, user likely cancelled")
          }
        }
    #endif
  }
}

// MARK: - Export Section

extension EditPresetSheet {
  /// Share-sheet preview: the preset's artwork when set, else the app icon.
  private var sharePreview: SharePreview<Image, Image> {
    if let artworkData = artworkData {
      #if os(iOS)
        if let uiImage = UIImage(data: artworkData) {
          return SharePreview(
            presetName,
            image: Image(uiImage: uiImage),
            icon: Image(systemName: "doc.fill")
          )
        }
      #else
        if let nsImage = NSImage(data: artworkData) {
          return SharePreview(
            presetName,
            image: Image(nsImage: nsImage),
            icon: Image(systemName: "doc.fill")
          )
        }
      #endif
    }
    // The app icon is the default share preview image.
    return SharePreview(
      presetName,
      image: Image("BlankieAppIconDisplay"),
      icon: Image(systemName: "doc.fill")
    )
  }

  @ViewBuilder
  var exportButton: some View {
    if !preset.isDefault {
      if isExporting {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        ShareLink(item: ExportablePreset(sheet: self), preview: sharePreview) {
          Image(systemName: "square.and.arrow.up")
        }
        // The ShareLink label is icon-only so we must name it for VoiceOver.
        .accessibilityLabel(Text("Share Preset"))
        .onDisappear {
          // Clean up the exported file when share sheet dismisses
          cleanupExportedFile()
        }
      }
    }
  }

  private func cleanupExportedFile() {
    if let url = exportedURL {
      // Delete the temporary file
      try? FileManager.default.removeItem(at: url)
      Logger.ui.debug("Cleaned up temporary export file: \(url.lastPathComponent)")
    }
    // Reset the state
    exportedURL = nil
    exportError = nil
  }

  // Safety net only: the Edit affordances route the default preset to the
  // create-preset flow instead of this sheet, so this should never show.
  var defaultPresetSection: some View {
    Group {
      Section {
        Text("For more customization options, create a new preset")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      errorSection
    }
  }

  var editablePresetSections: some View {
    Group {
      errorSection
      basicDetailsSection
      soundsSection
      visualsSection
      deleteSection
    }
  }

  // The default preset shares the "allSounds" token; custom presets use their
  // UUID string.
  var starToken: String {
    preset.isDefault ? GlobalSettings.allSoundsToken : preset.id.uuidString
  }
}

extension EditPresetSheet {
  func setupInitialValues() {
    Task {
      if let id = artworkId {
        if let image = await PresetArtworkManager.shared.loadArtwork(id: id) {
          await MainActor.run {
            self.artworkData = image.jpegData(compressionQuality: 0.8)
          }
        }
      }
    }
  }

  func applyChangesInstantly(skipRefresh: Bool = false) {
    Logger.ui.debug("EditPresetSheet: Applying changes instantly (skipRefresh: \(skipRefresh))")

    // Only validate name for non-default presets
    if !preset.isDefault {
      guard !presetName.isEmpty else {
        error = "Preset name cannot be empty"
        return
      }
    }

    Task {
      let updatedPreset = await createUpdatedPreset()

      await MainActor.run {
        var currentPresets = presetManager.presets
        if let index = currentPresets.firstIndex(where: { $0.id == preset.id }) {
          currentPresets[index] = updatedPreset
          presetManager.setPresets(currentPresets)

          // Update current preset reference if this is the active preset
          if presetManager.currentPreset?.id == preset.id {
            presetManager.setCurrentPreset(updatedPreset)
            // Don't reapply the preset - just update the metadata
            // This prevents audio from restarting when editing non-sound properties

            // Force full Now Playing update to refresh lock screen artwork immediately
            if !skipRefresh {
              audioManager.nowPlayingManager.forceRefresh(
                preset: updatedPreset,
                isPlaying: audioManager.isGloballyPlaying
              )
            }
          }

          // Mark that user has edited a preset for onboarding tracking
          OnboardingManager.shared.markPresetEdited()

          // Save presets directly without overriding the current preset state
          savePresetsDirectly()

          // Post notification that preset was updated
          NotificationCenter.default.post(
            name: Notification.Name("PresetUpdated"), object: updatedPreset)
        }
      }

      // Regenerate the CarPlay thumbnail (force, so new artwork replaces a
      // stale cached image), or drop it if the artwork was removed.
      if updatedPreset.artworkId != nil || updatedPreset.animatedArtwork != nil {
        await presetManager.cacheThumbnail(for: updatedPreset, force: true)
      } else {
        presetManager.removeThumbnail(for: updatedPreset.id)
      }
    }
  }

  func createUpdatedPreset() async -> Preset {
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var updatedPreset = preset

    // Only update name, creator, and sounds for non-default presets
    if !preset.isDefault {
      // Create sound states
      let selectedSoundStates = createSoundStates()

      updatedPreset.name = presetName
      updatedPreset.creatorName = creatorName.isEmpty ? nil : creatorName
      updatedPreset.moods = moods.isEmpty ? nil : Array(moods)
      updatedPreset.soundStates = selectedSoundStates
      updatedPreset.soundOrder = soundOrder
    }

    // Handle artwork (allowed for all presets including default)
    await handleArtworkChanges()

    // Update preset properties
    updatedPreset.artworkId = artworkId
    updatedPreset.animatedArtwork = animatedArtwork
    updatedPreset.staticArtworkPath = staticArtworkPath
    updatedPreset.lastModifiedVersion = currentVersion

    if preset.isDefault {
      // The default preset takes no theme overrides (its sheet doesn't offer
      // them); clear any set before this rule so they can't linger invisibly.
      updatedPreset.accentColorName = nil
      updatedPreset.viewMode = nil
      updatedPreset.backgroundBlurRadius = nil
    } else {
      // Save accent color
      if useCustomTheme, let color = accentColor {
        updatedPreset.accentColorName = color.toString
      } else {
        updatedPreset.accentColorName = nil
      }

      // Save per-preset view-mode override (nil = follow app setting).
      updatedPreset.viewMode = useCustomViewMode ? viewModeOverride : nil

      // Save per-preset background blur override (nil = follow app setting).
      updatedPreset.backgroundBlurRadius = useCustomBlur ? blurOverride : nil
    }

    return updatedPreset
  }

  private func createSoundStates() -> [PresetState] {
    // Get existing sound states for this preset
    let existingSoundStates = preset.soundStates

    // Use soundOrder state variable, filtering to only include currently selected sounds
    let validOrder = soundOrder.filter { selectedSounds.contains($0) }
    // Add any newly selected sounds that aren't in the order yet
    let newSounds = selectedSounds.filter { !validOrder.contains($0) }
    let orderedFileNames = validOrder + newSounds.sorted()

    let states: [PresetState] = orderedFileNames.compactMap { fileName -> PresetState? in
      guard let sound = audioManager.sounds.first(where: { $0.fileName == fileName }) else {
        return nil
      }

      // If this sound was already in the preset, preserve its state
      if let existingState = existingSoundStates.first(where: { $0.fileName == fileName }) {
        return existingState
      }

      // New sound added to preset - set it as selected by default
      return PresetState(
        fileName: sound.fileName,
        isSelected: true,
        volume: sound.volume
      )
    }

    Logger.ui.debug(
      "EditPresetSheet: Creating \(states.count) sound states from \(selectedSounds.count) selected sounds"
    )

    return states
  }

  private func handleArtworkChanges() async {
    if let data = artworkData {
      // Save artwork (this will update existing or create new)
      do {
        let savedId = try await PresetArtworkManager.shared.saveArtwork(
          data, for: preset.id, type: .artwork
        )
        artworkId = savedId
        Logger.ui.debug("EditPresetSheet: Saved artwork with ID: \(savedId)")
      } catch {
        Logger.ui.error("EditPresetSheet: Failed to save artwork: \(error, privacy: .public)")
      }
    } else if artworkId == nil, preset.artworkId != nil {
      // Artwork was deleted - clean up old artwork
      do {
        try await PresetArtworkManager.shared.deleteArtwork(for: preset.artworkId!)
        Logger.ui.debug("EditPresetSheet: Deleted old artwork")
      } catch {
        Logger.ui.error("EditPresetSheet: Failed to delete old artwork: \(error, privacy: .public)")
      }
    }
  }

  // MARK: - Direct Preset Saving

  private func savePresetsDirectly() {
    let defaultPreset = presetManager.presets.first { $0.isDefault }
    let customPresets = presetManager.presets.filter { !$0.isDefault }

    if let defaultPreset = defaultPreset {
      PresetStorage.saveDefaultPreset(defaultPreset)
    }
    PresetStorage.saveCustomPresets(customPresets)
    Logger.ui.debug("EditPresetSheet: Presets saved directly without state override")
  }

  private func deletePreset(_ preset: Preset) {
    presetManager.deletePreset(preset)
    isPresented = nil
  }

  #if os(macOS)
    func handleMacOSImageImport(_ result: Result<[URL], Error>) {
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
            // Process and crop the image
            let targetSize = CGSize(width: 300, height: 300)
            if let processedData = processImage(nsImage: nsImage, targetSize: targetSize) {
              artworkData = processedData
              artworkId = UUID()  // Generate new ID for the new artwork
              applyChangesInstantly()
            }
          }
        } catch {
          Logger.ui.error("EditPresetSheet: Failed to import image: \(error, privacy: .public)")
        }
      case .failure(let error):
        Logger.ui.error("EditPresetSheet: Failed to import image: \(error, privacy: .public)")
      }
    }

    private func processImage(nsImage: NSImage, targetSize: CGSize) -> Data? {
      let imageSize = nsImage.size
      let scale = min(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
      let newSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

      let image = NSImage(size: newSize)
      image.lockFocus()
      nsImage.draw(
        in: NSRect(origin: .zero, size: newSize),
        from: NSRect(origin: .zero, size: imageSize),
        operation: .copy,
        fraction: 1.0
      )
      image.unlockFocus()

      return image.jpegData(compressionQuality: 0.8)
    }
  #endif

  private func processImage(data: Data) -> Data? {
    #if os(macOS)
      guard let image = NSImage(data: data) else { return nil }

      // Resize if needed (max 2048x2048)
      let maxSize: CGFloat = 2048
      var targetSize = image.size

      if image.size.width > maxSize || image.size.height > maxSize {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        targetSize = CGSize(
          width: image.size.width * scale,
          height: image.size.height * scale
        )
      }

      let resizedImage = NSImage(size: targetSize)
      resizedImage.lockFocus()
      image.draw(
        in: NSRect(origin: .zero, size: targetSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
      )
      resizedImage.unlockFocus()

      // Convert to JPEG with compression
      guard let tiffData = resizedImage.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
      else { return nil }

      return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])

    #else
      guard let image = UIImage(data: data) else { return nil }

      // Resize if needed (max 2048x2048)
      let maxSize: CGFloat = 2048
      var targetSize = image.size

      if image.size.width > maxSize || image.size.height > maxSize {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        targetSize = CGSize(
          width: image.size.width * scale,
          height: image.size.height * scale
        )
      }

      let renderer = UIGraphicsImageRenderer(size: targetSize)
      let resizedImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
      }

      return resizedImage.jpegData(compressionQuality: 0.8)
    #endif
  }
}
