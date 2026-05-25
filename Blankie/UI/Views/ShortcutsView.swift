//
//  ShortcutsView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

struct ShortcutsView: View {
  @Environment(\.dismiss) private var dismiss

  let shortcuts: [(String, String)] = [
    ("⏯", "Play/Pause Sounds"),
    //        ("⌘ O", "Add Custom Sound"),
    ("⌘ W", "Close Window"),
    ("⌘ ,", "Preferences"),
    ("⌘ ⇧ ?", "Keyboard Shortcuts"),
    ("⌘ Q", "Quit"),
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
        ForEach(shortcuts, id: \.0) { shortcut in
          HStack {
            Text(LocalizedStringKey(shortcut.1))
              .foregroundColor(.primary)

            Spacer()

            Text(shortcut.0)
              .foregroundColor(.secondary)
              .font(.system(.body, design: .rounded))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(6)
          }
        }
      }
    }
    .padding()
    .frame(width: 300)
    .background(backgroundColorForPlatform)
    .cornerRadius(12)
  }
}
