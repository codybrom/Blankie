//
//  ShortcutsView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

/// A keyboard shortcut definition shared by the menu bar (`AppCommands`) and
/// the on-screen cheat sheet (`ShortcutsView`), so the two can't drift apart.
///
/// `KeyEquivalent` + `EventModifiers` are the source of truth: the displayed
/// glyphs and the VoiceOver-spoken label are both derived from them.
struct AppShortcut: Identifiable {
  let action: LocalizedStringKey
  let key: KeyEquivalent?
  let modifiers: EventModifiers
  /// Glyph for actions triggered by a media key rather than a `KeyEquivalent`
  /// (e.g. the Play/Pause key), which has no `KeyboardShortcut` representation.
  let mediaGlyph: String?

  init(
    _ action: LocalizedStringKey,
    key: KeyEquivalent? = nil,
    modifiers: EventModifiers = [],
    mediaGlyph: String? = nil
  ) {
    self.action = action
    self.key = key
    self.modifiers = modifiers
    self.mediaGlyph = mediaGlyph
  }

  var id: String { displayGlyphs }

  /// The native shortcut to attach with `.keyboardShortcut(_:)`, or `nil` for
  /// display-only entries (media keys, or system-owned shortcuts like ⌘W).
  var keyboardShortcut: KeyboardShortcut? {
    key.map { KeyboardShortcut($0, modifiers: modifiers) }
  }

  /// Glyph tokens in Apple's canonical order (⌃⌥⇧⌘, then the key).
  private var tokens: [String] {
    if let mediaGlyph { return [mediaGlyph] }
    var tokens: [String] = []
    if modifiers.contains(.control) { tokens.append("⌃") }
    if modifiers.contains(.option) { tokens.append("⌥") }
    if modifiers.contains(.shift) { tokens.append("⇧") }
    if modifiers.contains(.command) { tokens.append("⌘") }
    if let key { tokens.append(Self.displayName(for: key)) }
    return tokens
  }

  /// Name for keys whose `character` doesn't render legibly on its own
  /// (Space is blank; the arrows are private-use glyphs). Letters and symbols
  /// pass through uppercased.
  private static func displayName(for key: KeyEquivalent) -> String {
    switch key.character {
    case " ": return "Space"
    case KeyEquivalent.upArrow.character: return "↑"
    case KeyEquivalent.downArrow.character: return "↓"
    case KeyEquivalent.leftArrow.character: return "←"
    case KeyEquivalent.rightArrow.character: return "→"
    default: return String(key.character).uppercased()
    }
  }

  /// Glyphs shown on screen, e.g. "⌘ ⇧ ?".
  var displayGlyphs: String { tokens.joined(separator: " ") }

  /// Spoken names for glyphs VoiceOver mispronounces or treats as punctuation.
  /// Values are localizable; letters and digits are read verbatim.
  private static let spokenNames: [String: LocalizedStringKey] = [
    "⌘": "Command",
    "⇧": "Shift",
    "⌥": "Option",
    "⌃": "Control",
    "⏯": "Play Pause",
    "Space": "Space",
    "↑": "Up Arrow",
    "↓": "Down Arrow",
    "←": "Left Arrow",
    "→": "Right Arrow",
    ",": "Comma",
    ".": "Period",
    "?": "Question Mark",
    "/": "Slash",
  ]

  /// `displayGlyphs` spelled out in words so VoiceOver doesn't read symbols as
  /// punctuation. Composed from `Text` so each word stays localizable.
  var spokenLabel: Text {
    let words = tokens.map { token -> Text in
      Self.spokenNames[token].map { Text($0) } ?? Text(verbatim: token)
    }
    return words.dropFirst().reduce(words.first ?? Text(verbatim: "")) { combined, word in
      Text("\(combined) \(word)")
    }
  }
}

extension AppShortcut {
  // Canonical definitions. Bound entries are applied via `.keyboardShortcut(_:)`
  // in AppCommands; display-only entries (`closeWindow`) are owned by the
  // system and just shown in the cheat sheet.
  static let playPause = AppShortcut("Play/Pause Sounds", key: .space)
  static let nextFavorite = AppShortcut("Next Favorite", key: .rightArrow, modifiers: .command)
  static let previousFavorite = AppShortcut(
    "Previous Favorite", key: .leftArrow, modifiers: .command)
  static let volumeUp = AppShortcut("Volume Up", key: .upArrow, modifiers: .command)
  static let volumeDown = AppShortcut("Volume Down", key: .downArrow, modifiers: .command)
  static let toggleSidebar = AppShortcut("Show/Hide Sidebar", key: "s", modifiers: .command)
  static let manageSounds = AppShortcut("Manage Sounds", key: "o", modifiers: .command)
  static let importFile = AppShortcut("Import", key: "i", modifiers: .command)
  static let exportPreset = AppShortcut("Export Preset", key: "e", modifiers: .command)
  static let newWindow = AppShortcut("New Window", key: "n", modifiers: .command)
  static let keyboardShortcuts = AppShortcut(
    "Keyboard Shortcuts", key: "?", modifiers: [.command, .shift])
  static let settings = AppShortcut("Settings", key: ",", modifiers: .command)
  static let closeWindow = AppShortcut("Close Window", key: "w", modifiers: .command)
  static let quit = AppShortcut("Quit", key: "q", modifiers: .command)
}

extension View {
  /// Applies a shared `AppShortcut`'s key binding, if it has one.
  @ViewBuilder
  func keyboardShortcut(_ appShortcut: AppShortcut) -> some View {
    if let shortcut = appShortcut.keyboardShortcut {
      keyboardShortcut(shortcut)
    } else {
      self
    }
  }
}

struct ShortcutsView: View {
  @Environment(\.dismiss) private var dismiss

  let shortcuts: [AppShortcut] = [
    .playPause,
    .nextFavorite,
    .previousFavorite,
    .volumeUp,
    .volumeDown,
    .toggleSidebar,
    .manageSounds,
    .importFile,
    .exportPreset,
    .newWindow,
    .closeWindow,
    .settings,
    .keyboardShortcuts,
    .quit,
  ]

  var backgroundColorForPlatform: Color {
    #if os(macOS)
      return Color(NSColor.windowBackgroundColor)
    #else
      return Color(UIColor.systemBackground)
    #endif
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header with close button
      HStack {
        Text(LocalizedStringKey("Keyboard Shortcuts"))
          .font(.headline)

        Spacer()

        Button(action: {
          dismiss()
        }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
      }
      .padding(.bottom, 8)

      // Shortcuts list
      VStack(spacing: 12) {
        ForEach(shortcuts) { shortcut in
          HStack {
            Text(shortcut.action)
              .foregroundColor(.primary)

            Spacer()

            Text(shortcut.displayGlyphs)
              .foregroundColor(.secondary)
              .font(.system(.body, design: .rounded))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(6)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text(shortcut.action))
          .accessibilityValue(shortcut.spokenLabel)
        }
      }
    }
    .padding()
    .frame(width: 300)
    .background(backgroundColorForPlatform)
    .cornerRadius(12)
  }
}
