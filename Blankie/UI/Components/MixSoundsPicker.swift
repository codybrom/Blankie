//
//  MixSoundsPicker.swift
//  Blankie
//
//  Created by Cody Bromley on 10/29/26.
//
//  The + button's checklist of sounds in the unsaved mix. Checking a sound adds it and
//  unchecking removes it, right away. A sheet on iOS, and a popover from the toolbar on macOS.
//

import SwiftUI

struct MixSoundsPicker: View {
  private let audioManager = AudioManager.shared
  @Environment(\.dismiss) private var dismiss

  /// Sounds that can join a mix, by title.
  static func candidates(from sounds: [Sound]) -> [Sound] {
    sounds.filter { !$0.isPresetUseOnly }.sortedByLocalizedTitle()
  }

  private var selection: Binding<Set<String>> {
    Binding(
      get: { audioManager.soundsInCurrentMix },
      set: { audioManager.setMixSounds($0) })
  }

  /// The mix keeps at least one sound, so its last one can't be unchecked.
  private func isLastSound(_ sound: Sound) -> Bool {
    audioManager.soundsInCurrentMix == [sound.fileName]
  }

  var body: some View {
    #if os(iOS) || os(visionOS)
      NavigationStack {
        List(selection: selection) {
          ForEach(Self.candidates(from: audioManager.sounds), id: \.fileName) { sound in
            // The last sound keeps its check, and unchecking it does nothing.
            row(sound)
              .tag(sound.fileName)
          }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
      }
      .presentationDetents([.medium, .large])
    #else
      List(Self.candidates(from: audioManager.sounds), id: \.fileName) { sound in
        Toggle(
          isOn: Binding(
            get: { selection.wrappedValue.contains(sound.fileName) },
            set: { isOn in
              var fileNames = selection.wrappedValue
              if isOn {
                fileNames.insert(sound.fileName)
              } else {
                fileNames.remove(sound.fileName)
              }
              selection.wrappedValue = fileNames
            })
        ) {
          row(sound)
        }
        .toggleStyle(.checkbox)
        .disabled(isLastSound(sound))
      }
      .frame(width: 280, height: 380)
    #endif
  }

  private func row(_ sound: Sound) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 2) {
        Text(sound.localizedTitle)
        if let subtitle = sound.localizedSubtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: sound.systemIconName)
    }
    .foregroundStyle(.primary)
  }
}
