//
//  EditPresetSheet.swift
//  Blankie
//
//  Created by Cody Bromley on 6/9/25.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let blankie = UTType(exportedAs: "com.codybrom.blankie.preset")
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
  @ObservedObject private var presetManager = PresetManager.shared
  @ObservedObject private var audioManager = AudioManager.shared
  @State var presetName: String = ""
  @State var creatorName: String = ""
  @State var selectedSounds: Set<String> = []
  @State var error: String?
  @State var showingSoundSelection = false
  @State var artworkData: Data?
  @State var artworkId: UUID?
  @State var showingImagePicker = false
  @State var presetToDelete: Preset?
  @State var showBackgroundImage: Bool = false
  @State var useArtworkAsBackground: Bool = false
  @State var backgroundImageData: Data?
  @State var backgroundImageId: UUID?
  @State var backgroundBlurRadius: Double = 3.0  // Low Blur by default
  @State var backgroundOpacity: Double = 0.3  // Low Opacity by default
  @State var selectedBackgroundPhoto: PhotosPickerItem?
  @State var exportError: String?
  @State var exportedURL: URL?
  @State var isExporting = false
  @Environment(\.dismiss) private var dismiss

  var orderedSounds: [Sound] {
    audioManager.sounds.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  var body: some View {
    NavigationStack {
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
        .navigationBarItems(
          leading: Button("Done") { isPresented = nil },
          trailing: exportButton
        )
      #else
        .formStyle(.grouped)
        .frame(minWidth: 400, idealWidth: 500, minHeight: preset.isDefault ? 200 : 300)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { isPresented = nil }
            .keyboardShortcut(.escape)
          }
          ToolbarItem(placement: .automatic) {
            exportButton
          }
        }
      #endif
      .onAppear(perform: setupInitialValues)
      .onDisappear {
        // Clean up exported file when sheet closes
        cleanupExportedFile()
      }
      #if os(iOS) || os(visionOS)
        .sheet(isPresented: $showingSoundSelection) {
          NavigationStack {
            SoundSelectionView(
              selectedSounds: $selectedSounds,
              orderedSounds: orderedSounds
            )
            .navigationBarItems(
              leading: Button("Done") {
                showingSoundSelection = false
              }
            )
          }
        }
        .sheet(isPresented: $showingImagePicker) {
          #if os(iOS)
            ImagePicker(imageData: $artworkData)
              .onDisappear {
                if artworkData != nil {
                  // Generate new ID for the new artwork
                  artworkId = UUID()
                  applyChangesInstantly()
                }
              }
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
    .onChange(of: selectedBackgroundPhoto) { _, newItem in
      print("🎨 EditPresetSheet: Background photo selection changed")
      if let item = newItem {
        Task {
          await loadBackgroundImage(from: item)
          // Reset selection to allow selecting the same image again
          await MainActor.run {
            selectedBackgroundPhoto = nil
          }
        }
      }
    }
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
}

// MARK: - Export Section

extension EditPresetSheet {
  @ViewBuilder
  var exportButton: some View {
    if !preset.isDefault {
      if isExporting {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        ShareLink(
          item: ExportablePreset(sheet: self),
          preview: {
            if let artworkData = artworkData {
              #if os(iOS)
                if let uiImage = UIImage(data: artworkData) {
                  SharePreview(
                    presetName,
                    image: Image(uiImage: uiImage),
                    icon: Image(systemName: "doc.fill")
                  )
                } else {
                  SharePreview(
                    presetName,
                    image: Image("NowPlaying"),
                    icon: Image(systemName: "doc.fill")
                  )
                }
              #else
                if let nsImage = NSImage(data: artworkData) {
                  SharePreview(
                    presetName,
                    image: Image(nsImage: nsImage),
                    icon: Image(systemName: "doc.fill")
                  )
                } else {
                  SharePreview(
                    presetName,
                    image: Image("NowPlaying"),
                    icon: Image(systemName: "doc.fill")
                  )
                }
              #endif
            } else {
              // Use the default Now Playing image
              SharePreview(
                presetName,
                image: Image("NowPlaying"),
                icon: Image(systemName: "doc.fill")
              )
            }
          }()
        ) {
          Image(systemName: "square.and.arrow.up")
        }
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
      print("🗑️ Cleaned up temporary export file: \(url.lastPathComponent)")
    }
    // Reset the state
    exportedURL = nil
    exportError = nil
  }

}

extension EditPresetSheet {
  var editablePresetSections: some View {
    Group {
      errorSection
      coreSection
      nowPlayingSection  // Creator & Artwork
      if artworkData != nil || artworkId != nil {
        backgroundSection
      }
      deleteSection
    }
  }

  func setupInitialValues() {
    presetName = preset.name
    creatorName = preset.creatorName ?? ""
    selectedSounds = Set(preset.soundStates.map(\.fileName))
    artworkId = preset.artworkId
    showBackgroundImage = preset.showBackgroundImage ?? true
    // Default to using artwork as background
    useArtworkAsBackground = preset.useArtworkAsBackground ?? true
    backgroundImageId = preset.backgroundImageId
    backgroundBlurRadius = preset.backgroundBlurRadius ?? 15.0
    backgroundOpacity = preset.backgroundOpacity ?? 0.65

    // Load existing images if they exist
    Task {
      if let id = artworkId {
        if let image = await PresetArtworkManager.shared.loadArtwork(id: id) {
          await MainActor.run {
            #if os(macOS)
              self.artworkData = image.jpegData(compressionQuality: 0.8)
            #else
              self.artworkData = image.jpegData(compressionQuality: 0.8)
            #endif
          }
        }
      }
      if let id = backgroundImageId {
        if let image = await PresetArtworkManager.shared.loadArtwork(id: id) {
          await MainActor.run {
            #if os(macOS)
              self.backgroundImageData = image.jpegData(compressionQuality: 0.8)
            #else
              self.backgroundImageData = image.jpegData(compressionQuality: 0.8)
            #endif
          }
        }
      }
    }
  }

  func applyChangesInstantly() {
    print("🎨 EditPresetSheet: Applying changes instantly")
    guard !presetName.isEmpty else {
      error = "Preset name cannot be empty"
      return
    }

    Task {
      let updatedPreset = await createUpdatedPreset()
      print(
        "🎨 EditPresetSheet: Updated preset has background: \(updatedPreset.backgroundImageId != nil)"
      )

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
          }

          // Save presets directly without overriding the current preset state
          savePresetsDirectly()
        }
      }
    }
  }

  func createUpdatedPreset() async -> Preset {
    let currentVersion =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // Create sound states ONLY for sounds that were selected in the form
    let selectedSoundStates: [PresetState] =
      selectedSounds.compactMap { fileName in
        guard let sound = audioManager.sounds.first(where: { $0.fileName == fileName }) else {
          return nil
        }
        return PresetState(
          fileName: sound.fileName,
          isSelected: sound.isSelected,
          volume: sound.volume
        )
      }

    print(
      "🎨 EditPresetSheet: Creating \(selectedSoundStates.count) sound states from \(selectedSounds.count) selected sounds"
    )

    var updatedPreset = preset
    updatedPreset.name = presetName
    updatedPreset.creatorName = creatorName.isEmpty ? nil : creatorName
    updatedPreset.soundStates = selectedSoundStates

    // Handle artwork saving or deletion
    if let data = artworkData {
      // Save artwork (this will update existing or create new)
      do {
        let savedId = try await PresetArtworkManager.shared.saveArtwork(
          data, for: preset.id, type: .artwork)
        artworkId = savedId
        print("🎨 EditPresetSheet: Saved artwork with ID: \(savedId)")
      } catch {
        print("❌ EditPresetSheet: Failed to save artwork: \(error)")
      }
    } else if artworkId == nil && preset.artworkId != nil {
      // Artwork was deleted - clean up old artwork
      do {
        try await PresetArtworkManager.shared.deleteArtwork(for: preset.artworkId!)
        print("🎨 EditPresetSheet: Deleted old artwork")
      } catch {
        print("❌ EditPresetSheet: Failed to delete old artwork: \(error)")
      }
    }

    if let data = backgroundImageData {
      // Save background (this will update existing or create new)
      do {
        let savedId = try await PresetArtworkManager.shared.saveArtwork(
          data, for: preset.id, type: .background)
        backgroundImageId = savedId
        print("🎨 EditPresetSheet: Saved background with ID: \(savedId)")
      } catch {
        print("❌ EditPresetSheet: Failed to save background: \(error)")
      }
    }

    updatedPreset.artworkId = artworkId
    updatedPreset.showBackgroundImage = showBackgroundImage
    updatedPreset.useArtworkAsBackground = useArtworkAsBackground
    updatedPreset.backgroundImageId = backgroundImageId
    updatedPreset.backgroundBlurRadius = backgroundBlurRadius
    updatedPreset.backgroundOpacity = backgroundOpacity
    updatedPreset.lastModifiedVersion = currentVersion

    return updatedPreset
  }

  // MARK: - Direct Preset Saving

  private func savePresetsDirectly() {
    let defaultPreset = presetManager.presets.first { $0.isDefault }
    let customPresets = presetManager.presets.filter { !$0.isDefault }

    if let defaultPreset = defaultPreset {
      PresetStorage.saveDefaultPreset(defaultPreset)
    }
    PresetStorage.saveCustomPresets(customPresets)
    print("🎨 EditPresetSheet: Presets saved directly without state override")
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
          print("❌ EditPresetSheet: Failed to import image: \(error)")
        }
      case .failure(let error):
        print("❌ EditPresetSheet: Failed to import image: \(error)")
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
        fraction: 1.0)
      image.unlockFocus()

      return image.jpegData(compressionQuality: 0.8)
    }
  #endif

  func loadBackgroundImage(from item: PhotosPickerItem) async {
    do {
      print("🎨 EditPresetSheet: Loading background image...")
      if let data = try await item.loadTransferable(type: Data.self) {
        // Process the image to optimize size
        if let processedData = processImage(data: data) {
          await MainActor.run {
            self.backgroundImageData = processedData
            print("🎨 EditPresetSheet: Background image loaded successfully")
          }
        }
      }
    } catch {
      print("🎨 EditPresetSheet: Failed to load image: \(error)")
    }
  }

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
