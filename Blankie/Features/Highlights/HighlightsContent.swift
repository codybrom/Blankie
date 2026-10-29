//
//  HighlightsContent.swift
//  Blankie
//
//  Created by Cody Bromley on 10/28/26.
//

import Foundation

#if canImport(UIKit)
  import UIKit
#endif

/// One release's highlights on the Highlights page.
struct HighlightsRelease: Identifiable {
  let version: String
  let items: [HighlightItem]
  var id: String { version }

  /// Keeps only the items that apply to this device.
  init(version: String, items: [HighlightItem]) {
    self.version = version
    self.items = items.filter { $0.platforms.contains(.current) }
  }
}

struct HighlightItem: Identifiable {
  enum Platform {
    case iPhone, iPad, mac

    static var current: Platform {
      #if os(macOS)
        .mac
      #else
        UIDevice.current.userInterfaceIdiom == .phone ? .iPhone : .iPad
      #endif
    }
  }

  let systemImage: String
  let title: String
  let detail: String
  var platforms: Set<Platform> = [.iPhone, .iPad, .mac]
  var id: String { title }
}

/// Release highlights, newest first. Written in English only and kept out of the
/// string catalog: HighlightsView translates them on device for other languages.
/// Adding a release here badges the Settings gear until its page is opened.
enum Highlights {
  static let releases: [HighlightsRelease] = [
    HighlightsRelease(version: "2.1.1", items: items211),
    HighlightsRelease(version: "2.1", items: items21),
  ]

  static var latestVersion: String { releases[0].version }

  /// True until the user opens the newest release's page.
  static func hasUnseen(lastSeen: String?) -> Bool {
    guard let lastSeen else { return true }
    return latestVersion.compare(lastSeen, options: .numeric) == .orderedDescending
  }

  /// Every title and detail, for one batch translation.
  static var allText: [String] {
    releases.flatMap { $0.items.flatMap { [$0.title, $0.detail] } }
  }

  private static let items211 = [
    HighlightItem(
      systemImage: "sparkles", title: "Update Highlights",
      detail:
        "You found it! When you install an update, a little dot on Settings will let you know there's new features and highlights to read. Blankie's release highlights are written in English but your device will offer to translate them if needed."
    )
  ]

  private static let items21 = [
    HighlightItem(
      systemImage: "photo.on.rectangle", title: "Preset artwork on the Mac",
      detail:
        "A preset's background artwork now shows behind your sound tiles, dimmed so they stay readable.",
      platforms: [.mac]
    ),
    HighlightItem(
      systemImage: "widget.small", title: "Home Screen widgets",
      detail:
        "Start a favorite, Quick Mix or a single sound in one tap, or play and pause from Now Playing.",
      platforms: [.iPhone, .iPad]
    ),
    HighlightItem(
      systemImage: "rectangle.split.2x1", title: "Support for iPhone Duo",
      detail:
        "Lucky enough to get your hand on Apple's newest iPhone? If so, you can enjoy an experience fully optimized for every pose.",
      platforms: [.iPhone]
    ),
    HighlightItem(
      systemImage: "square.stack.3d.up", title: "Shortcuts Support",
      detail:
        "Create workflows using Blankie in the Shortcuts app to play or pause, start a preset or sound, set a sleep timer or change the volume."
    ),
    HighlightItem(
      systemImage: "mic.fill", title: "Ask Siri to Play Blankie",
      detail:
        "Ask Siri to play a preset or sound without opening the app."
    ),
    HighlightItem(
      systemImage: "play.circle", title: "Now Playing opens first on iPhone",
      detail:
        "Picking a preset or sound now takes you to what's playing, and Quick Mix still opens to its tiles. To go straight to the mixer instead, turn off Open to Now Playing in Settings.",
      platforms: [.iPhone]
    ),
    HighlightItem(
      systemImage: "ipad.landscape", title: "Wider layout on iPad",
      detail:
        "A preset's page now shows its artwork at the top. Preset and sound editors open in a side panel (iPadOS 27), so the page you're changing stays in view.",
      platforms: [.iPad]
    ),
    HighlightItem(
      systemImage: "captions.bubble", title: "Sound subtitles",
      detail:
        "Every built-in sound now has a short subtitle that appears wherever the sound is played, including the app, on the Lock Screen, and in CarPlay."
    ),
  ]
}
