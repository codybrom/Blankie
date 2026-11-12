//
//  Bundle+Version.swift
//  Blankie
//
//  Created by Cody Bromley on 7/8/26.
//

import Foundation

extension Bundle {
  /// The app's marketing version (`CFBundleShortVersionString`). A missing value
  /// means a misconfigured build, so this traps. Presets and archive checks never
  /// get a made-up version.
  nonisolated var appVersion: String {
    guard let version = infoDictionary?["CFBundleShortVersionString"] as? String else {
      preconditionFailure("CFBundleShortVersionString missing from Info.plist")
    }
    return version
  }

  /// The language the app runs in, which a per-app language setting can set apart from
  /// the system's.
  nonisolated var appLanguage: Locale.Language {
    Locale.Language(identifier: preferredLocalizations.first ?? "en")
  }
}
