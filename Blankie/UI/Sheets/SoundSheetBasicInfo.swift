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

      // About
      switch mode {
      case .edit:
        aboutRow
      case .add:
        EmptyView()
      }
    }
  }

  @ViewBuilder
  var nameRow: some View {
    HStack {
      Text("Name", comment: "Display name field label")
      Spacer()
      HStack {
        TextField(text: $soundName) {
          Text("Sound Name", comment: "Sound name text field placeholder")
        }
        .multilineTextAlignment(.trailing)
        .textFieldStyle(.plain)
        #if os(iOS)
          .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
              Spacer()
              Button("Done") {
                UIApplication.shared.sendAction(
                  #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              }
            }
          }
        #endif

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
  }

  @ViewBuilder
  var iconRow: some View {
    Button {
      showingIconPicker = true
    } label: {
      HStack {
        Text("Icon", comment: "Icon selection label")
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
  var aboutRow: some View {
    if let currentSound = getCurrentSound() {
      NavigationLink(destination: SoundAboutSheet(sound: currentSound)) {
        HStack {
          Text("About & Sharing", comment: "About and sharing button label")
          Spacer()
        }
      }
    }
  }

  private func getCurrentSound() -> Sound? {
    switch mode {
    case .edit(let sound):
      return sound
    case .add:
      return nil
    }
  }

  @ViewBuilder
  var actionSection: some View {
    if shouldShowActionSection {
      Section {
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
