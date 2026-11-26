//
//  FileHashUtility.swift
//  Blankie
//
//  Created by Cody Bromley on 6/26/25.
//

import CryptoKit
import Foundation

enum FileHashUtility {
  /// Hex-encoded SHA-256 of the file at `url`, read in chunks off the main actor.
  /// Throws `CancellationError` between reads once the task is cancelled.
  @concurrent static func sha256Hash(for url: URL) async throws -> String {
    let bufferSize = 1024 * 1024  // 1MB buffer for streaming

    guard let inputStream = InputStream(url: url) else {
      throw FileHashError.cannotOpenFile
    }

    inputStream.open()
    defer { inputStream.close() }

    var hasher = SHA256()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while inputStream.hasBytesAvailable {
      try Task.checkCancellation()
      let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
      if bytesRead > 0 {
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
      } else if bytesRead < 0 {
        throw FileHashError.readError
      }
    }

    let digest = hasher.finalize()
    return digest.map { String(format: "%02hhx", $0) }.joined()
  }

  /// Hex-encoded SHA-256 of `data`.
  static func sha256Hash(for data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02hhx", $0) }.joined()
  }
}

enum FileHashError: LocalizedError {
  case cannotOpenFile
  case readError

  var errorDescription: String? {
    switch self {
    case .cannotOpenFile:
      return "Cannot open file for hashing"
    case .readError:
      return "Error reading file during hash calculation"
    }
  }
}
