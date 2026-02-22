//
//  SoundGridView.swift
//  Blankie
//
//  Reusable grid view for displaying sounds with drag-to-reorder support
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct SoundGridView: View {
    let sounds: [Sound]
    @Binding var editMode: EditMode
    var onMove: (IndexSet, Int) -> Void
    var onEditSound: ((Sound) -> Void)?

    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var soundsUpdateTrigger = 0

    var body: some View {
      ScrollView {
        if editMode == .active {
          Text("Drag sounds to reorder")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 8)
        }

        ReorderableGrid(
          items: sounds,
          columns: 2,
          spacing: 16,
          isReorderEnabled: editMode == .active,
          onMove: { from, to in
            onMove(IndexSet(integer: from), to)
          }
        ) { sound, _ in
          GridSoundButton(sound: sound, editMode: $editMode)
            .id("\(sound.id)-\(sound.isSelected)-\(audioManager.isGloballyPlaying)-\(soundsUpdateTrigger)")
        }
        .padding()
        .padding(.bottom, editMode == .active ? 80 : 0)
      }
      .overlay(alignment: .bottom) {
        if editMode == .active {
          doneReorderingButton
        }
      }
    }

    private var doneReorderingButton: some View {
      VStack(spacing: 0) {
        Divider()

        Button(action: {
          withAnimation(.easeInOut(duration: 0.3)) {
            editMode = .inactive
          }
        }) {
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .font(.title2)
            Text("Done Moving")
              .font(.headline)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .foregroundColor(.white)
          .background(globalSettings.customAccentColor ?? .accentColor)
        }
        .sensoryFeedback(.selection, trigger: editMode)
      }
      .background(.regularMaterial)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  #Preview {
    SoundGridView(
      sounds: [],
      editMode: .constant(.inactive),
      onMove: { _, _ in }
    )
  }
#endif
