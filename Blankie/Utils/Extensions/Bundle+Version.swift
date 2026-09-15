//
//  Bundle+Version.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//

import Foundation

extension Bundle {
  /// The app's marketing version (`CFBundleShortVersionString`). A shipped build
  /// always defines it (from `MARKETING_VERSION`); a missing value means the
  /// build is misconfigured, so trap rather than stamp a fabricated version into
  /// presets and archive-compatibility checks.
  nonisolated var appVersion: String {
    guard let version = infoDictionary?["CFBundleShortVersionString"] as? String else {
      preconditionFailure("CFBundleShortVersionString missing from Info.plist")
    }
    return version
  }
}
