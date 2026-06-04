//
//  SoundSheetBasicInfo.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

extension CleanSoundSheetForm {
  @ViewBuilder
  var basicInformationSection: some View {
    Section {
      // Name
      nameRow

      // Icon
      iconRow
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
        }
      }
    #endif
  }

  @ViewBuilder
  var iconRow: some View {
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
    }
    .buttonStyle(.plain)
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
            .foregroundStyle(globalSettings.customAccentColor ?? .accentColor)
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
                  .foregroundColor(.accentColor)
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
