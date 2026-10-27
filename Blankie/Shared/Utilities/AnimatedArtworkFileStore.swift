//
//  AnimatedArtworkFileStore.swift
//  Blankie
//
//  Created by Cody Bromley on 7/3/25.
//

import Foundation

nonisolated enum AnimatedArtworkFileStore {
  private static let directoryName = "Artwork"

  static func ensureBaseDirectory() throws {
    let directory = try baseDirectoryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  static func makeRelativeLoopPath(for id: UUID, fileExtension: String = "mov") -> String {
    "\(directoryName)/\(id.uuidString).\(fileExtension)"
  }

  static func makeRelativePreviewPath(
    for id: UUID, fileExtension: String = "jpg", suffix: String = ""
  ) -> String {
    let fileName = suffix.isEmpty ? id.uuidString : "\(id.uuidString)\(suffix)"
    return "\(directoryName)/\(fileName).\(fileExtension)"
  }

  nonisolated static func absoluteURL(for relativePath: String) -> URL {
    // Artwork is a flat file in the Artwork directory. Keeping only the last
    // component stops a traversal path from an imported preset escaping it.
    let fileName = (relativePath as NSString).lastPathComponent
    return documentsDirectoryURL().appendingPathComponent(directoryName).appendingPathComponent(
      fileName)
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
    // Atomic replace so a crash mid-write can't leave a truncated artwork file.
    try data.write(to: destination, options: .atomic)
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
