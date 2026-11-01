//
//  UnsavedMixPrompt.swift
//  Blankie
//
//  Created by Cody Bromley on 10/29/26.
//
//  Asks to save an unsaved mix before an in-app control leaves it
//  (`AudioManager.leaveUnsavedMixAsking(then:)` holds the control's action).
//

import SwiftUI

extension View {
  /// Hosts the save prompt. `isActive` turns a host off while a sheet above it hosts its own.
  func unsavedMixPrompt(isActive: Bool = true) -> some View {
    modifier(UnsavedMixPrompt(isActive: isActive))
  }
}

private struct UnsavedMixPrompt: ViewModifier {
  /// What the dialog presents. Its buttons read the action from here, since dismissing
  /// clears `pendingLeave`.
  struct Leaving {
    let mixName: String
    let action: @MainActor () -> Void
  }

  let isActive: Bool
  private let audioManager = AudioManager.shared
  @State private var showingSave = false
  /// The held action, run once the mix is saved. Cancelling the save keeps the mix.
  @State private var actionAfterSave: (@MainActor () -> Void)?
  @State private var didSave = false

  private var isAsking: Binding<Bool> {
    Binding(
      get: { isActive && audioManager.pendingLeave != nil },
      set: { if !$0 { audioManager.pendingLeave = nil } })
  }

  private var leaving: Leaving? {
    guard let mix = audioManager.unsavedMix, let action = audioManager.pendingLeave else {
      return nil
    }
    return Leaving(mixName: mix.name, action: action)
  }

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Save this mix?", isPresented: isAsking, titleVisibility: .visible,
        presenting: leaving
      ) { leaving in
        Button("Save") {
          actionAfterSave = leaving.action
          showingSave = true
        }
        // The action lets the mix go itself (New Preset on Create), so next and previous
        // count from the mix's sound.
        Button("Don't Save", role: .destructive) {
          leaving.action()
        }
        Button("Cancel", role: .cancel) {}
      } message: { leaving in
        Text("\(leaving.mixName) isn't saved yet. If you don't save it, it's gone.")
      }
      // The action runs once the sheet is gone, so it can open a sheet of its own.
      .saveMixSheet(
        isPresented: $showingSave,
        onDismiss: {
          let action = didSave ? actionAfterSave : nil
          actionAfterSave = nil
          didSave = false
          action?()
        },
        onSaved: { didSave = true })
  }
}

extension View {
  /// New Preset for the unsaved mix: its sounds filled in, and its name made unique the
  /// way an import's is.
  func saveMixSheet(
    isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
    onSaved: (() -> Void)? = nil
  ) -> some View {
    sheet(isPresented: isPresented, onDismiss: onDismiss) {
      CreatePresetSheet(
        isPresented: isPresented,
        initialSelectedSounds: Set(
          AudioManager.shared.unsavedMixSounds.filter(\.isSelected).map(\.fileName)),
        initialName: AudioManager.shared.unsavedMix.map {
          PresetManager.shared.uniquePresetName($0.name)
        },
        savesUnsavedMix: true,
        onCreated: onSaved
      )
      // Switching sounds off in the sheet leaves the mix a mix, even with one sound on.
      .onAppear { AudioManager.shared.isSavingUnsavedMix = true }
      .onDisappear { AudioManager.shared.isSavingUnsavedMix = false }
    }
  }
}
