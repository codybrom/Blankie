//
//  WidgetImageHelpers.swift
//  BlankieWidget
//
//  Created by Cody Bromley on 7/1/26.
//

import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Prefer widget-resolution artwork, with the legacy CarPlay cache as a
/// migration fallback. Downsample before decoding to bound widget memory.
func thumbnailImage(forKey key: String, maxPixelSize: Int) -> Image? {
  let image =
    WidgetArtworkCache.fileURL(for: key).flatMap {
      WidgetArtworkCache.image(at: $0, maxPixelSize: maxPixelSize)
    }
    ?? UserDefaults.shared.data(forKey: key).flatMap {
      WidgetArtworkCache.image(from: $0, maxPixelSize: maxPixelSize)
    }
  guard let image else { return nil }
  #if canImport(UIKit)
    return Image(uiImage: UIImage(cgImage: image))
  #elseif canImport(AppKit)
    return Image(nsImage: NSImage(cgImage: image, size: .zero))
  #else
    return nil
  #endif
}
