//
//  WidgetArtworkCache.swift
//  Blankie
//

import Foundation
import ImageIO

/// Bounded file-backed artwork cache shared with the widget extension. The small
/// CarPlay thumbnail stays in defaults.
nonisolated enum WidgetArtworkCache {
  static let maximumPixelSize = 1024

  static func fileURL(for key: String) -> URL? {
    let prefix = "preset_thumb_"
    guard key.hasPrefix(prefix), let id = UUID(uuidString: String(key.dropFirst(prefix.count)))
    else { return nil }
    return AppGroupConfiguration.containerURL?
      .appendingPathComponent("Library/Caches/WidgetArtwork/v1", isDirectory: true)
      .appendingPathComponent("\(id.uuidString).jpg")
  }

  static func jpegThumbnail(from data: Data, maxPixelSize: Int = maximumPixelSize) -> Data? {
    guard let image = image(from: data, maxPixelSize: maxPixelSize) else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  static func image(from data: Data, maxPixelSize: Int) -> CGImage? {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return image(from: source, maxPixelSize: maxPixelSize)
  }

  static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return image(from: source, maxPixelSize: maxPixelSize)
  }

  private static func image(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
    CGImageSourceCreateThumbnailAtIndex(
      source, 0,
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, min(maximumPixelSize, maxPixelSize)),
      ] as CFDictionary)
  }
}
