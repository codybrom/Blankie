//
//  ArchiveUtility.swift
//  Blankie
//
//  Created by Cody Bromley on 6/26/25.
//

import Foundation
import ZIPFoundation
import os

/// ZIP archive utility using ZIPFoundation
nonisolated struct ArchiveUtility {

  enum ArchiveError: Error {
    case limitExceeded
  }

  // Caps for untrusted .blankie archives — far above any real preset
  // (a manifest, artwork, and a few sounds capped at 50 MB each).
  private static let maxEntryCount = 512
  private static let maxTotalUncompressedBytes: Int64 = 512 << 20  // 512 MiB (8 sounds @ 50 MB + artwork)
  private static let maxEntryUncompressedBytes: Int64 = 64 << 20  // 64 MiB per entry (clears a 50 MB sound)

  static func extract(from archiveURL: URL, to destinationURL: URL) throws {
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

    let archive = try Archive(url: archiveURL, accessMode: .read)

    // .blankie archives are untrusted shared input. Resolve each entry path and
    // confirm it stays inside the extraction directory so a crafted entry like
    // "../../foo" can't write outside it (zip-slip).
    let root = destinationURL.standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"

    var entryCount = 0
    var totalBytes: Int64 = 0

    for entry in archive {
      entryCount += 1
      guard entryCount <= maxEntryCount else {
        throw ArchiveError.limitExceeded
      }
      // A symlink could redirect later entries' writes outside the destination.
      guard entry.type != .symlink else { continue }
      // Use appending(path:directoryHint:) (no filesystem access) rather than
      // appendingPathComponent, which stats the path and canonicalizes the base
      // (e.g. /var -> /private/var). That canonicalization made `path` diverge
      // from `rootPrefix` and the containment check rejected every entry.
      let path = root.appending(path: entry.path, directoryHint: .inferFromPath)
        .standardizedFileURL
      guard path.path.hasPrefix(rootPrefix) else {
        Logger.app.error(
          "ArchiveUtility: Skipping archive entry escaping destination: \(entry.path)"
        )
        continue
      }
      if entry.type == .directory {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
      } else {
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        // Count decompressed bytes as they're written: header-declared sizes
        // can lie, so the zip-bomb cap is enforced on actual output.
        FileManager.default.createFile(atPath: path.path, contents: nil)
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        var entryBytes: Int64 = 0
        _ = try archive.extract(entry) { data in
          entryBytes += Int64(data.count)
          totalBytes += Int64(data.count)
          guard entryBytes <= maxEntryUncompressedBytes,
            totalBytes <= maxTotalUncompressedBytes
          else {
            throw ArchiveError.limitExceeded
          }
          try handle.write(contentsOf: data)
        }
      }
    }
  }

  static func create(from sourceURL: URL, to archiveURL: URL) throws {
    Logger.app.debug(
      "ArchiveUtility: Creating archive from \(sourceURL.path) to \(archiveURL.path)")

    // Remove existing archive if needed
    try removeExistingArchive(at: archiveURL)

    // Create new archive
    Logger.app.debug("ArchiveUtility: Creating new archive...")
    let archive = try Archive(url: archiveURL, accessMode: .create)
    Logger.app.debug("ArchiveUtility: Archive created successfully")

    // Enumerate and add files
    let fileCount = try addFilesToArchive(archive, from: sourceURL)

    Logger.app.debug("ArchiveUtility: Archive creation completed with \(fileCount) files")
  }

  private static func removeExistingArchive(at archiveURL: URL) throws {
    if FileManager.default.fileExists(atPath: archiveURL.path) {
      try FileManager.default.removeItem(at: archiveURL)
      Logger.app.debug("ArchiveUtility: Removed existing archive")
    }
  }

  private static func addFilesToArchive(_ archive: Archive, from sourceURL: URL) throws -> Int {
    let fileManager = FileManager.default
    guard
      let enumerator = fileManager.enumerator(
        at: sourceURL, includingPropertiesForKeys: [.isDirectoryKey])
    else {
      throw NSError(
        domain: "ArchiveUtility", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Cannot enumerate source directory"])
    }

    Logger.app.debug("ArchiveUtility: Starting to enumerate files...")
    var fileCount = 0

    for case let fileURL as URL in enumerator {
      let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.path + "/", with: "")

      // Skip empty relative paths
      if relativePath.isEmpty {
        continue
      }

      Logger.app.debug("ArchiveUtility: Processing \(relativePath)")

      var isDirectory: ObjCBool = false
      fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)

      if isDirectory.boolValue {
        try addDirectoryEntry(to: archive, relativePath: relativePath)
      } else {
        try addFileEntry(to: archive, fileURL: fileURL, relativePath: relativePath)
        fileCount += 1
      }
    }

    return fileCount
  }

  private static func addDirectoryEntry(to archive: Archive, relativePath: String) throws {
    try archive.addEntry(
      with: relativePath + "/",
      type: .directory,
      uncompressedSize: Int64(0),
      compressionMethod: .none
    ) { _, _ in return Data() }
    Logger.app.debug("ArchiveUtility: Added directory: \(relativePath)/")
  }

  private static func addFileEntry(to archive: Archive, fileURL: URL, relativePath: String) throws {
    // Get file size without loading into memory
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = fileAttributes[.size] as? Int64 ?? 0

    try archive.addEntry(
      with: relativePath,
      type: .file,
      uncompressedSize: fileSize,
      compressionMethod: .none  // Store without compression
    ) { position, size in
      // Stream file data in chunks
      let fileHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? fileHandle.close() }

      try fileHandle.seek(toOffset: UInt64(position))
      let data = fileHandle.readData(ofLength: size)
      return data
    }
    Logger.app.debug("ArchiveUtility: Added file: \(relativePath) (\(fileSize) bytes)")
  }
}
