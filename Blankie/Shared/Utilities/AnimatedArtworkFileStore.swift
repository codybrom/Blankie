//
//  AnimatedArtworkFileStore.swift
//  Blankie
//
//  Created by Codex on 7/3/25.
//

import Foundation

enum AnimatedArtworkFileStore {
  private static let directoryName = "Artwork"

  static func ensureBaseDirectory() throws {
    let directory = try baseDirectoryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  static func makeRelativeLoopPath(for id: UUID, fileExtension: String = "mov") -> String {
    "\(directoryName)/\(id.uuidString).\(fileExtension)"
  }

  static func makeRelativePreviewPath(for id: UUID, fileExtension: String = "jpg", suffix: String = "") -> String {
    let fileName = suffix.isEmpty ? id.uuidString : "\(id.uuidString)\(suffix)"
    return "\(directoryName)/\(fileName).\(fileExtension)"
  }

  static func absoluteURL(for relativePath: String) -> URL {
    let trimmed = relativePath.hasPrefix("\(directoryName)/")
      ? String(relativePath.dropFirst(directoryName.count + 1))
      : relativePath
    return documentsDirectoryURL().appendingPathComponent(directoryName).appendingPathComponent(
      trimmed)
  }

  static func removeItemIfExists(relativePath: String?) {
    guard let relativePath else { return }
    let url = absoluteURL(for: relativePath)
    try? FileManager.default.removeItem(at: url)
  }

  static func copyItem(at sourceURL: URL, to relativePath: String) throws -> URL {
    try ensureBaseDirectory()
    let destination = absoluteURL(for: relativePath)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return destination
  }

  @discardableResult
  static func writeData(_ data: Data, to relativePath: String) throws -> URL {
    try ensureBaseDirectory()
    let destination = absoluteURL(for: relativePath)
    try? FileManager.default.removeItem(at: destination)
    try data.write(to: destination)
    return destination
  }

  static func fileExists(at relativePath: String?) -> Bool {
    guard let relativePath else { return false }
    return FileManager.default.fileExists(atPath: absoluteURL(for: relativePath).path)
  }

  static func documentsDirectoryURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private static func baseDirectoryURL() throws -> URL {
    documentsDirectoryURL().appendingPathComponent(directoryName, isDirectory: true)
  }
}
