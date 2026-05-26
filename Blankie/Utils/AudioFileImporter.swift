//
//  AudioFileImporter.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class AudioFileImporter: ObservableObject {
  static let shared = AudioFileImporter()

  @Published var showingSoundSheet = false
  @Published var fileToImport: URL?
  /// True while a preset archive is being imported (no sheet covers this, so a
  /// global indicator does). Audio imports are covered by the add-sound sheet.
  @Published var isProcessingImport = false

  func handleIncomingFile(_ url: URL) {
    // Handle direct file imports via URL scheme or document picker

    debugLog("🎵 AudioFileImporter: Received file: \(url.lastPathComponent)")

    // Check if it's a .blankie preset file first
    if url.pathExtension.lowercased() == "blankie" {
      debugLog("📦 AudioFileImporter: Detected .blankie preset file, importing as preset")
      handleBlankiePresetImport(url)
      return
    }

    // Verify it's an audio file
    guard let type = UTType(filenameExtension: url.pathExtension),
      type.conforms(to: .audio)
    else {
      debugLog("❌ AudioFileImporter: Unsupported file type: \(url.pathExtension)")
      return
    }

    // Start accessing security-scoped resource
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    debugLog("🔐 AudioFileImporter: Security-scoped access started: \(didStartAccessing)")

    // Copy the file to a temporary location that the app owns
    let tempDir = FileManager.default.temporaryDirectory
    let tempFileURL = tempDir.appendingPathComponent(url.lastPathComponent)

    do {
      // Remove existing temp file if needed
      try? FileManager.default.removeItem(at: tempFileURL)

      // Copy the file to temp directory
      try FileManager.default.copyItem(at: url, to: tempFileURL)
      debugLog(
        "✅ AudioFileImporter: Copied file to temp directory: \(tempFileURL.lastPathComponent)")

      // Store the temp file URL and show the sound sheet
      fileToImport = tempFileURL
      showingSoundSheet = true
    } catch {
      debugLog("❌ AudioFileImporter: Failed to copy file: \(error)")
      ErrorReporter.shared.report(AudioError.loadFailed(error))
    }

    // Stop accessing the security-scoped resource
    if didStartAccessing {
      url.stopAccessingSecurityScopedResource()
    }
  }

  func clearImport() {
    fileToImport = nil
    showingSoundSheet = false
  }

  private func handleBlankiePresetImport(_ url: URL) {
    isProcessingImport = true
    Task {
      defer { isProcessingImport = false }
      do {
        let preset = try await PresetImporter.shared.importArchive(from: url)
        debugLog("📦 AudioFileImporter: Successfully imported preset '\(preset.name)'")
      } catch {
        debugLog("❌ AudioFileImporter: Failed to import preset: \(error)")
        // Surface the failure: PresetImporter.ImportError is a LocalizedError,
        // so AudioErrorHandler's alert shows a meaningful message.
        ErrorReporter.shared.report(error)
      }
    }
  }

}
