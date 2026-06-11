//
//  SoundManagementRow.swift
//  Blankie
//
//  Created by Cody Bromley on 6/1/25.
//

import SwiftUI

struct SoundManagementRowContent: View {
  let sound: Sound
  let isLast: Bool
  let onDelete: () -> Void

  private let audioManager = AudioManager.shared

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
      .accessibilityHidden(true)
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
