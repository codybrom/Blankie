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

/// Reads a preset thumbnail cached by the app under `preset_thumb_<uuid>`
/// (the same App Group key CarPlay already uses), so widgets show real
/// artwork with no widget-specific asset pipeline.
func thumbnailImage(forKey key: String) -> Image? {
  guard let data = UserDefaults.shared.data(forKey: key) else { return nil }
  #if canImport(UIKit)
    guard let platformImage = UIImage(data: data) else { return nil }
    return Image(uiImage: platformImage)
  #elseif canImport(AppKit)
    guard let platformImage = NSImage(data: data) else { return nil }
    return Image(nsImage: platformImage)
  #else
    return nil
  #endif
}
