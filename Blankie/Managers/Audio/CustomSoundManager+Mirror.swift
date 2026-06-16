//
//  CustomSoundManager+Mirror.swift
//  Blankie
//
//  Created by Cody Bromley on 6/15/26.
//

import Foundation
import SwiftData
import os

// MARK: - App-group file mirror for custom-sound metadata

/// Codable snapshot of a `CustomSoundData` row, written beside its audio file in
/// the shared app-group container. The audio file already survives a SwiftData
/// store rebuild on its own, but the row's metadata (title, icon, credits, loop
/// flags, LUFS/normalization, moods…) lived only in the store — so a rebuild
/// orphaned the audio and lost everything else. This sidecar lets the row be
/// reconstructed from disk. Mirrors the artwork file mirror in
/// `PresetArtworkManager`. A value type, so it crosses actors safely.
struct CustomSoundSnapshot: Codable, Sendable {
  var id: UUID
  var title: String
  var systemIconName: String
  var fileName: String
  var fileExtension: String
  var dateAdded: Date
  var randomizeStartPosition: Bool
  var loopSound: Bool
  var normalizeAudio: Bool
  var volumeAdjustment: Float
  var detectedPeakLevel: Float?
  var detectedLUFS: Float?
  var normalizationFactor: Float?
  var sha256Hash: String?
  var originalFileName: String?
  var creditAuthor: String?
  var creditSourceUrl: String?
  var creditLicenseType: String
  var creditCustomLicenseText: String?
  var creditCustomLicenseUrl: String?
  var id3Title: String?
  var id3Artist: String?
  var id3Album: String?
  var id3Comment: String?
  var id3Url: String?
  var importedFromPresetId: UUID?
  var importedFromPresetName: String?
  var moods: [SoundMood]?
  var duration: TimeInterval?

  @MainActor
  init(_ model: CustomSoundData) {
    id = model.id
    title = model.title
    systemIconName = model.systemIconName
    fileName = model.fileName
    fileExtension = model.fileExtension
    dateAdded = model.dateAdded
    randomizeStartPosition = model.randomizeStartPosition
    loopSound = model.loopSound
    normalizeAudio = model.normalizeAudio
    volumeAdjustment = model.volumeAdjustment
    detectedPeakLevel = model.detectedPeakLevel
    detectedLUFS = model.detectedLUFS
    normalizationFactor = model.normalizationFactor
    sha256Hash = model.sha256Hash
    originalFileName = model.originalFileName
    creditAuthor = model.creditAuthor
    creditSourceUrl = model.creditSourceUrl
    creditLicenseType = model.creditLicenseType
    creditCustomLicenseText = model.creditCustomLicenseText
    creditCustomLicenseUrl = model.creditCustomLicenseUrl
    id3Title = model.id3Title
    id3Artist = model.id3Artist
    id3Album = model.id3Album
    id3Comment = model.id3Comment
    id3Url = model.id3Url
    importedFromPresetId = model.importedFromPresetId
    importedFromPresetName = model.importedFromPresetName
    moods = model.moods
    duration = model.duration
  }

}

extension CustomSoundData {
  /// Rebuild a row from its file-mirror snapshot, preserving the original `id`
  /// so presets that reference this sound still resolve.
  @MainActor
  convenience init(_ snapshot: CustomSoundSnapshot) {
    self.init(
      title: snapshot.title, systemIconName: snapshot.systemIconName, fileName: snapshot.fileName,
      fileExtension: snapshot.fileExtension, originalFileName: snapshot.originalFileName,
      randomizeStartPosition: snapshot.randomizeStartPosition, loopSound: snapshot.loopSound,
      normalizeAudio: snapshot.normalizeAudio, volumeAdjustment: snapshot.volumeAdjustment,
      detectedPeakLevel: snapshot.detectedPeakLevel, detectedLUFS: snapshot.detectedLUFS,
      normalizationFactor: snapshot.normalizationFactor, creditAuthor: snapshot.creditAuthor,
      creditSourceUrl: snapshot.creditSourceUrl, creditLicenseType: snapshot.creditLicenseType,
      creditCustomLicenseText: snapshot.creditCustomLicenseText,
      creditCustomLicenseUrl: snapshot.creditCustomLicenseUrl,
      importedFromPresetId: snapshot.importedFromPresetId,
      importedFromPresetName: snapshot.importedFromPresetName, moods: snapshot.moods,
      duration: snapshot.duration)
    id = snapshot.id
    dateAdded = snapshot.dateAdded
    sha256Hash = snapshot.sha256Hash
    id3Title = snapshot.id3Title
    id3Artist = snapshot.id3Artist
    id3Album = snapshot.id3Album
    id3Comment = snapshot.id3Comment
    id3Url = snapshot.id3Url
  }
}

extension CustomSoundManager {
  /// Suffix for a sound's metadata sidecar. Audio files are `<uuid>.<ext>`, so a
  /// `.meta.json` sidecar can never collide with one. Not private so the
  /// reconcile logic is unit tested.
  static let mirrorSuffix = ".meta.json"

  private func mirrorURL(for fileName: String) -> URL? {
    getCustomSoundsDirectoryURL()?.appendingPathComponent("\(fileName)\(Self.mirrorSuffix)")
  }

  /// Write (or refresh) the sidecar for one sound. Cheap and idempotent — the
  /// mirror actor skips the write when the on-disk copy already matches — so it's
  /// safe to call from every save path. Encoding and the write run off the main
  /// actor, serialized with every other mirror write.
  @MainActor
  func writeMirror(for sound: CustomSoundData) {
    let snapshot = CustomSoundSnapshot(sound)
    guard let url = mirrorURL(for: snapshot.fileName) else { return }
    Task { await AppGroupFileMirror.shared.writeJSONIfChanged(snapshot, to: url) }
  }

  /// Refresh every sound's sidecar. Called after a `saveContext()` (the editor
  /// mutates a row then saves) and once after launch load to back-fill mirrors
  /// for sounds saved before mirroring existed.
  @MainActor
  func syncAllMirrors() {
    for sound in getAllCustomSounds() {
      writeMirror(for: sound)
    }
  }

  /// Remove a sound's sidecar when the sound is deleted, so a stranded mirror
  /// can't resurrect it on the next reconcile.
  @MainActor
  func removeMirror(fileName: String) {
    guard let url = mirrorURL(for: fileName) else { return }
    Task { await AppGroupFileMirror.shared.remove(at: url) }
  }

  /// Re-insert any custom-sound rows that exist on disk (audio + sidecar) but are
  /// missing from the store — the recovery path after a SwiftData store rebuild.
  /// A no-op on a healthy launch (every row is already present). Idempotent.
  ///
  /// The directory scan and sidecar decode run off the main actor; only the
  /// insert/save (which must use the main context) hops back to the main actor.
  @MainActor
  func reconcileCustomSoundsFromDisk() async {
    guard let dir = getCustomSoundsDirectoryURL() else { return }
    let existing = Set(getAllCustomSounds().map { $0.fileName })

    let snapshotsToRestore = await Task.detached(priority: .utility) {
      Self.restorableSnapshots(in: dir, excluding: existing)
    }.value
    guard !snapshotsToRestore.isEmpty else { return }

    do {
      try withModelContext { context in
        for snapshot in snapshotsToRestore {
          context.insert(CustomSoundData(snapshot))
        }
        try context.save()
      }
      // .error level so the recovery is captured in a sysdiagnose.
      Logger.sounds.error(
        "CustomSoundManager: Reconciled \(snapshotsToRestore.count) custom sound(s) from the file mirror after a store rebuild"
      )
    } catch {
      Logger.sounds.error(
        "CustomSoundManager: Failed to reconcile custom sounds from mirror: \(error, privacy: .public)"
      )
    }
  }

  /// Decode every sidecar in `dir` whose row is missing (not in `excluding`) and
  /// whose audio file is still present. Pure file work — safe to run off-main,
  /// and not private so the reconcile logic is unit tested directly.
  nonisolated static func restorableSnapshots(in dir: URL, excluding existing: Set<String>)
    -> [CustomSoundSnapshot]
  {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }

    var result: [CustomSoundSnapshot] = []
    for entry in entries where entry.hasSuffix(mirrorSuffix) {
      let fileName = String(entry.dropLast(mirrorSuffix.count))
      guard !existing.contains(fileName) else { continue }

      let sidecarURL = dir.appendingPathComponent(entry)
      guard let data = try? Data(contentsOf: sidecarURL),
        let snapshot = try? JSONDecoder().decode(CustomSoundSnapshot.self, from: data)
      else { continue }

      // Only restore when the audio file is actually present; a row with no file
      // would just fail to load and clutter the library.
      let audioURL = dir.appendingPathComponent("\(snapshot.fileName).\(snapshot.fileExtension)")
      guard fileManager.fileExists(atPath: audioURL.path) else { continue }

      result.append(snapshot)
    }
    return result
  }
}
