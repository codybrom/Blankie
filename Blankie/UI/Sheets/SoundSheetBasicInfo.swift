//
//  SoundSheetBasicInfo.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

extension SoundSheetForm {
  /// Source file name the AI cleanup derives from: the picked file on import;
  /// in edit mode the custom sound's ORIGINAL imported file name — the stored
  /// `fileName` is an internal sanitized name with no semantic content, which
  /// left the model guessing. No original on record → no sparkles (built-ins
  /// already have real names).
  private var aiSourceFileName: String? {
    switch mode {
    case .add:
      return selectedFile?.lastPathComponent
    case .edit(let sound):
      guard sound.isCustom, let dataID = sound.customSoundDataID,
        let original = CustomSoundManager.shared.getCustomSound(by: dataID)?.originalFileName,
        !original.isEmpty
      else { return nil }
      return original
    }
  }

  /// Auto-runs the name + icon suggestion the moment an import has a file.
  /// Captures the fields first so anything the person edits mid-generation
  /// wins over the suggestion.
  func autoSuggestDetailsIfNeeded() async {
    guard mode.isAdd, let file = selectedFile,
      AIPresetNameGenerator.isAvailable, !isGeneratingDetails
    else { return }

    isGeneratingDetails = true
    let nameAtStart = soundName
    let iconAtStart = selectedIcon

    let details = await AIPresetNameGenerator.generateSoundDetails(
      fromFileName: file.lastPathComponent)
    if !details.name.isEmpty, soundName == nameAtStart {
      aiNameUndo = nameAtStart
      soundName = details.name
    }
    if let icon = details.icon, selectedIcon == iconAtStart {
      aiIconUndo = iconAtStart
      selectedIcon = icon
    }
    isGeneratingDetails = false
  }

  /// Sparkles next to the name field: cleans the raw file name into a display
  /// name. Name only — the icon row has its own sparkles; only the initial
  /// auto-suggest on import fills both at once.
  @ViewBuilder
  var aiDetailsButton: some View {
    if let fileName = aiSourceFileName, AIPresetNameGenerator.isAvailable {
      if isGeneratingDetails {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          Task {
            isGeneratingDetails = true
            let nameAtStart = soundName
            let details = await AIPresetNameGenerator.generateSoundDetails(
              fromFileName: fileName, includingIcon: false)
            if !details.name.isEmpty {
              aiNameUndo = nameAtStart
              soundName = details.name
            }
            isGeneratingDetails = false
          }
        } label: {
          Image(systemName: "sparkles")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel("Suggest Name with Apple Intelligence")
      }
    }
  }

  /// One-tap revert of the last AI name suggestion.
  @ViewBuilder
  var aiNameUndoButton: some View {
    if let previous = aiNameUndo {
      Button {
        soundName = previous
        aiNameUndo = nil
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Undo Name Suggestion")
    }
  }

  /// One-tap revert of the last AI icon suggestion.
  @ViewBuilder
  var aiIconUndoButton: some View {
    if let previous = aiIconUndo {
      Button {
        selectedIcon = previous
        aiIconUndo = nil
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Undo Icon Suggestion")
    }
  }

  @ViewBuilder
  var basicInformationSection: some View {
    Section {
      // Name
      nameRow

      // Icon
      iconRow
    } header: {
      // Edits here are per-sound, not per-preset — make the blast radius clear.
      if case .edit = mode {
        Text("Changes affect this sound across all modes")
          .textCase(nil)
      }
    }
  }

  @ViewBuilder
  var nameRow: some View {
    #if os(macOS)
      // LabeledContent keeps the label and field aligned in a grouped form; a
      // trailing-aligned plain TextField renders the prompt and value together
      // on macOS.
      LabeledContent {
        HStack(spacing: 6) {
          // Use `prompt:` (placeholder) — the label-closure initializer renders
          // its text as a visible field label, which collides with the
          // LabeledContent "Name" label.
          TextField(
            "Sound Name",
            text: $soundName,
            prompt: Text("Sound Name")
          )
          .labelsHidden()
          .textFieldStyle(.plain)

          if !soundName.isEmpty {
            Button {
              soundName = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear Name")
          }

          aiNameUndoButton
          aiDetailsButton
        }
      } label: {
        Text("Name")
      }
    #else
      HStack {
        Text("Name")
        Spacer()
        HStack {
          TextField(text: $soundName) {
            Text("Sound Name")
          }
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
              Spacer()
              Button("Done") {
                UIApplication.shared.sendAction(
                  #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              }
            }
          }

          if !soundName.isEmpty {
            Button {
              soundName = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear Name")
          }

          aiNameUndoButton
          aiDetailsButton
        }
      }
    #endif
  }

  /// Sparkles on the icon row: re-rolls just the icon for the current name
  /// (constraint-decoded against the picker catalog). Disabled — not hidden —
  /// while the name is empty (there's nothing to depict yet).
  @ViewBuilder
  var aiIconButton: some View {
    if AIPresetNameGenerator.isAvailable {
      let hasName = !soundName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      if isGeneratingIcon {
        ProgressView()
          .controlSize(.small)
      } else {
        Button {
          Task {
            isGeneratingIcon = true
            let iconAtStart = selectedIcon
            if let icon = await AIPresetNameGenerator.generateSoundIcon(for: soundName) {
              aiIconUndo = iconAtStart
              selectedIcon = icon
            }
            isGeneratingIcon = false
          }
        } label: {
          Image(systemName: "sparkles")
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasName ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .disabled(!hasName)
        .accessibilityLabel("Suggest Icon with Apple Intelligence")
      }
    }
  }

  @ViewBuilder
  var iconRow: some View {
    // The sparkles is its own button, so the picker button owns everything
    // else in the row (a single full-row button would fire both on tap).
    HStack(spacing: 8) {
      Button {
        showingIconPicker = true
      } label: {
        HStack {
          Text("Icon")
          Spacer()
          Image(systemName: selectedIcon)
            .font(.title3)
            .foregroundStyle(.tint)
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      aiIconUndoButton
      aiIconButton
    }
  }

  @ViewBuilder
  var actionSection: some View {
    if shouldShowActionSection {
      Section {
        #if os(macOS)
          // Full-width borderless rows; a default Button in a grouped form
          // renders as a cramped bordered pill.
          if case .edit = mode {
            Button {
              showingResetConfirmation = true
            } label: {
              Text("Reset to Defaults")
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
          }

          if case .edit(let sound) = mode, sound.isCustom {
            Button {
              showingDeleteConfirmation = true
            } label: {
              Text("Delete Sound")
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
          }
        #else
          if case .edit = mode {
            Button(action: { showingResetConfirmation = true }) {
              HStack {
                Text("Reset to Defaults")
                  .foregroundStyle(.tint)
              }
            }
          }

          // Delete button for custom sounds
          if case .edit(let sound) = mode, sound.isCustom {
            Button(action: { showingDeleteConfirmation = true }) {
              HStack {
                Text("Delete Sound")
                  .foregroundColor(.red)
              }
            }
          }
        #endif
      }
    }
  }

  private var shouldShowActionSection: Bool {
    switch mode {
    case .edit:
      return true
    default:
      return false
    }
  }

}
