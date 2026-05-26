//
//  PreferencesView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import Foundation
import SwiftUI

struct PreferencesView: View {
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @State private var showingRestartAlert = false
  @State private var showingHiddenSounds = false

  var accentColorForUI: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  var textColorForAccent: Color {
    #if os(macOS)
      if let nsColor = NSColor(accentColorForUI).usingColorSpace(.sRGB) {
        let brightness =
          (0.299 * nsColor.redComponent) + (0.587 * nsColor.greenComponent)
          + (0.114 * nsColor.blueComponent)
        return brightness > 0.5 ? .black : .white
      }
      return .white
    #elseif os(iOS) || os(visionOS)
      let uiColor = UIColor(accentColorForUI)
      var red: CGFloat = 0
      var green: CGFloat = 0
      var blue: CGFloat = 0
      var alpha: CGFloat = 0

      uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      let brightness = (0.299 * red) + (0.587 * green) + (0.114 * blue)
      return brightness > 0.5 ? .black : .white
    #else
      return .white
    #endif
  }

  var appearanceButtons: some View {
    HStack(spacing: 8) {
      ForEach(AppearanceMode.allCases, id: \.self) { mode in
        Button(
          action: { globalSettings.setAppearance(mode) },
          label: {
            HStack(spacing: 4) {
              Image(systemName: mode.icon)
              Text(mode.localizedName)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              globalSettings.appearance == mode ? accentColorForUI : Color.secondary.opacity(0.2)
            )
            .foregroundColor(globalSettings.appearance == mode ? textColorForAccent : .primary)
            .cornerRadius(6)
          }
        )
        .buttonStyle(.plain)
      }
    }
  }

  var colorButtons: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Button(
          action: { globalSettings.setAccentColor(nil) },
          label: {
            Text("System")
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                globalSettings.customAccentColor == nil
                  ? accentColorForUI : Color.secondary.opacity(0.2)
              )
              .foregroundColor(
                globalSettings.customAccentColor == nil ? textColorForAccent : .primary
              )
              .cornerRadius(6)
          }
        )
        .buttonStyle(.plain)

        Spacer()
      }

      #if os(macOS)
        // The "System" button above handles the no-accent state, so the circle
        // row only offers the concrete colors.
        AccentColorCirclePicker(
          selectedColor: $globalSettings.customAccentColor, allowSystem: false
        )
        .onChange(of: globalSettings.customAccentColor) { _, newColor in
          globalSettings.setAccentColor(newColor)
        }
      #else
        SpectrumColorPicker(selectedColor: $globalSettings.customAccentColor)
          .onChange(of: globalSettings.customAccentColor) { _, newColor in
            globalSettings.setAccentColor(newColor)
          }
      #endif
    }
  }

  var languageMenu: some View {
    Picker(
      "Language",
      selection: Binding(
        get: { globalSettings.language },
        set: { globalSettings.setLanguage($0) }
      )
    ) {
      ForEach(globalSettings.availableLanguages) { language in
        HStack {
          Image(systemName: language.icon)
          Text(language.displayName)
        }
        .tag(language)
      }
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .frame(width: 220)
  }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 16) {
          Text("Appearance")
            .frame(width: 100, alignment: .leading)
          appearanceButtons
        }

        HStack(alignment: .top, spacing: 16) {
          Text("Accent Color")
            .frame(width: 100, alignment: .leading)
          colorButtons
        }

        HStack(spacing: 16) {
          Text("Language")
            .frame(width: 100, alignment: .leading)
          languageMenu
        }

        Toggle(
          "Show Labels",
          isOn: Binding(
            get: { globalSettings.showSoundNames },
            set: { globalSettings.setShowSoundNames($0) }
          )
        )
        .tint(accentColorForUI)

        Toggle(
          "Show Progress Border",
          isOn: Binding(
            get: { globalSettings.showProgressBorder },
            set: { globalSettings.setShowProgressBorder($0) }
          )
        )
        .tint(accentColorForUI)
      } header: {
        Text("Appearance")
      }

      Section {
        Button(action: {
          showingHiddenSounds = true
        }) {
          HStack(spacing: 16) {
            Text("Manage Sounds")
              .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
              Text("Import custom sounds and manage hidden sounds")
                .foregroundColor(.secondary)
                .font(.caption)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundColor(.secondary)
              .font(.caption)
          }
        }
        .buttonStyle(.plain)
      } header: {
        Text("Sounds")
      }

      Section {
        Toggle(
          LocalizedStringKey("Autoplay on Open"),
          isOn: Binding(
            get: { globalSettings.autoPlayOnLaunch },
            set: { globalSettings.setAutoPlayOnLaunch($0) }
          )
        )
        #if os(macOS)
          .help("If enabled, Blankie will immediately play your most recent preset on launch")
        #endif
        .tint(accentColorForUI)
      } header: {
        Text("Behavior")
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 500)
    .onChange(of: globalSettings.needsRestartForLanguageChange) { _, _ in
      if globalSettings.needsRestartForLanguageChange {
        showingRestartAlert = true
        globalSettings.needsRestartForLanguageChange = false  // reset
      }
    }
    .alert(
      Text("Language Changed"),
      isPresented: $showingRestartAlert
    ) {
      Button {
        Language.restartApp()
      } label: {
        Text("Restart Now")
      }
      Button(role: .cancel) {
      } label: {
        Text("Later")
      }
    } message: {
      Text(
        "You will need to restart Blankie for the language change to take effect."
      )
    }
    .sheet(isPresented: $showingHiddenSounds) {
      NavigationStack {
        SoundManagementView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") {
                showingHiddenSounds = false
              }
            }
          }
      }
    }
  }
}

#Preview("Preferences") {
  PreferencesView()
}

#Preview("Dark Mode") {
  PreferencesView()
    .preferredColorScheme(.dark)
}
