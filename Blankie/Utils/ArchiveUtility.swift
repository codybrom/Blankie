//
//  ArchiveUtility.swift
//  Blankie
//
//  Created by Cody Bromley on 6/26/25.
//

import Foundation
import ZIPFoundation

/// ZIP archive utility using ZIPFoundation
struct ArchiveUtility {

  static func extract(from archiveURL: URL, to destinationURL: URL) throws {
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

    let archive = try Archive(url: archiveURL, accessMode: .read)

    for entry in archive {
      let path = destinationURL.appendingPathComponent(entry.path)
      if entry.type == .directory {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
      } else {
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        _ = try archive.extract(entry, to: path)
      }
    }
  }

  static func create(from sourceURL: URL, to archiveURL: URL) throws {
    debugLog("ArchiveUtility: Creating archive from \(sourceURL.path) to \(archiveURL.path)")

    // Remove existing archive if needed
    try removeExistingArchive(at: archiveURL)

    // Create new archive
    debugLog("ArchiveUtility: Creating new archive...")
    let archive = try Archive(url: archiveURL, accessMode: .create)
    debugLog("ArchiveUtility: Archive created successfully")

    // Enumerate and add files
    let fileCount = try addFilesToArchive(archive, from: sourceURL)

    debugLog("ArchiveUtility: Archive creation completed with \(fileCount) files")
  }

  private static func removeExistingArchive(at archiveURL: URL) throws {
    if FileManager.default.fileExists(atPath: archiveURL.path) {
      try FileManager.default.removeItem(at: archiveURL)
      debugLog("ArchiveUtility: Removed existing archive")
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

    debugLog("ArchiveUtility: Starting to enumerate files...")
    var fileCount = 0

    for case let fileURL as URL in enumerator {
      let relativePath = fileURL.path.replacingOccurrences(of: sourceURL.path + "/", with: "")

      // Skip empty relative paths
      if relativePath.isEmpty {
        continue
      }

      debugLog("ArchiveUtility: Processing \(relativePath)")

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
    debugLog("ArchiveUtility: Added directory: \(relativePath)/")
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
    debugLog("ArchiveUtility: Added file: \(relativePath) (\(fileSize) bytes)")
  }
}
