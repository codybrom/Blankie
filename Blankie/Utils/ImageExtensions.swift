//
//  ImageExtensions.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import SwiftUI

#if os(macOS)
  import AppKit

  extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
      guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      return bitmapRep.representation(
        using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
      guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      return bitmapRep.representation(using: .png, properties: [:])
    }
  }
#endif
