//
//  SoundManagementRow.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import SwiftUI

struct SoundManagementRow: View {
  let sound: Sound
  let isLast: Bool
  let onTap: () -> Void
  let onDelete: () -> Void

  @ObservedObject private var audioManager = AudioManager.shared

  private var isCustomSound: Bool {
    sound.isCustom
  }

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onTap) {
        HStack {
          soundIcon
          soundInfo
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(backgroundView)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .contextMenu {
        if isCustomSound {
          customSoundContextMenu
        }
      }

      if !isLast {
        Divider()
          .padding(.leading, 60)
      }
    }
  }
}

struct SoundManagementRowContent: View {
  let sound: Sound
  let isLast: Bool
  let onDelete: () -> Void

  @ObservedObject private var audioManager = AudioManager.shared

  private var isCustomSound: Bool {
    sound.isCustom
  }

  var body: some View {
    HStack {
      soundIcon
      soundInfo
      Spacer()
    }
    .background(backgroundView)
    .contentShape(Rectangle())
    .contextMenu {
      if isCustomSound {
        customSoundContextMenu
      }
    }
  }

  private var soundIcon: some View {
    Image(systemName: sound.systemIconName)
      .font(.body)
      .foregroundStyle(.primary)
  }

  private var soundInfo: some View {
    Text(
      isCustomSound
        ? LocalizedStringKey(stringLiteral: sound.title) : LocalizedStringKey(sound.title)
    )
    .foregroundColor(.primary)
  }

  @ViewBuilder
  private var customSoundContextMenu: some View {
    Button("Delete Sound", systemImage: "trash", role: .destructive) {
      onDelete()
    }
  }

  @ViewBuilder
  private var backgroundView: some View {
    if isCustomSound {
      customSoundRowBackground
    } else {
      Color.clear
    }
  }

  private var customSoundRowBackground: some View {
    Group {
      #if os(macOS)
        Color(NSColor.controlBackgroundColor).opacity(0.3)
      #else
        Color(UIColor.secondarySystemBackground)
      #endif
    }
  }
}

// Keep the original SoundManagementRow view intact
extension SoundManagementRow {
  private var soundIcon: some View {
    Image(systemName: sound.systemIconName)
      .font(.title2)
      .frame(width: 32)
      .foregroundStyle(.primary)
  }

  private var soundInfo: some View {
    Text(
      isCustomSound
        ? LocalizedStringKey(stringLiteral: sound.title) : LocalizedStringKey(sound.title)
    )
    .fontWeight(.medium)
    .foregroundColor(.primary)
  }

  @ViewBuilder
  private var customSoundContextMenu: some View {
    Button("Edit Sound", systemImage: "pencil") {
      onTap()
    }

    Button("Delete Sound", systemImage: "trash", role: .destructive) {
      onDelete()
    }
  }

  @ViewBuilder
  private var backgroundView: some View {
    if isCustomSound {
      customSoundRowBackground
    } else {
      Color.clear
    }
  }

  private var customSoundRowBackground: some View {
    Group {
      #if os(macOS)
        Color(NSColor.controlBackgroundColor).opacity(0.3)
      #else
        Color(UIColor.secondarySystemBackground)
      #endif
    }
  }

}
