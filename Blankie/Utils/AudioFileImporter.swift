//
//  AudioFileImporter.swift
//  Blankie
//
//  Created by Cody Bromley on 6/6/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os

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

    Logger.app.debug("AudioFileImporter: Received file: \(url.lastPathComponent)")

    // Check if it's a .blankie preset file first
    if url.pathExtension.lowercased() == "blankie" {
      Logger.app.debug("AudioFileImporter: Detected .blankie preset file, importing as preset")
      handleBlankiePresetImport(url)
      return
    }

    // Verify it's an audio file
    guard let type = UTType(filenameExtension: url.pathExtension),
      type.conforms(to: .audio)
    else {
      Logger.app.debug("AudioFileImporter: Unsupported file type: \(url.pathExtension)")
      return
    }

    // Copy to an app-owned temp location so the file outlives the picker's
    // security scope and stays readable (AVAudioPlayer, preview-before-save).
    guard let tempFileURL = stagedTempCopy(of: url) else {
      ErrorReporter.shared.report(AudioError.fileNotFound)
      return
    }
    fileToImport = tempFileURL
    showingSoundSheet = true
  }

  /// Copies a (possibly security-scoped) file into an app-owned temp location
  /// and returns the new URL. A URL handed back by a document picker is only
  /// readable while its security scope is held; copying gives a stable URL that
  /// `AVAudioPlayer` can load later — e.g. when previewing a not-yet-saved
  /// imported sound. Returns nil if the copy fails.
  func stagedTempCopy(of url: URL) -> URL? {
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    Logger.app.debug("AudioFileImporter: Security-scoped access started: \(didStartAccessing)")
    defer {
      if didStartAccessing { url.stopAccessingSecurityScopedResource() }
    }

    let tempFileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(url.lastPathComponent)
    do {
      try? FileManager.default.removeItem(at: tempFileURL)
      try FileManager.default.copyItem(at: url, to: tempFileURL)
      Logger.app.debug("AudioFileImporter: Staged temp copy: \(tempFileURL.lastPathComponent)")
      return tempFileURL
    } catch {
      Logger.app.error("AudioFileImporter: Failed to stage temp copy: \(error, privacy: .public)")
      return nil
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
        Logger.app.debug("AudioFileImporter: Successfully imported preset '\(preset.name)'")
      } catch {
        Logger.app.error("AudioFileImporter: Failed to import preset: \(error, privacy: .public)")
        // Surface the failure: PresetImporter.ImportError is a LocalizedError,
        // so AudioErrorHandler's alert shows a meaningful message.
        ErrorReporter.shared.report(error)
      }
    }
  }

}
