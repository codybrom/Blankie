//
//  VolumeControlsView.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

public enum VolumeControlStyle {
  case popover
  case sheet
}

struct VolumeControlsView: View {
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss

  let style: VolumeControlStyle

  var accentColor: Color {
    globalSettings.customAccentColor ?? .accentColor
  }

  // Check if all volumes are at their default values
  private var isAtDefaultVolumes: Bool {
    // Check global volume (default is 1.0)
    guard globalSettings.volume == 1.0 else { return false }

    // Check all individual sound volumes (default is 1.0)
    return audioManager.sounds.allSatisfy { $0.volume == 1.0 }
  }

  var body: some View {
    if style == .sheet {
      NavigationStack {
        ScrollView {
          sheetContent
            .padding(.bottom, 30)
        }
        .navigationTitle("Volume")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(action: {
              // TODO: Implement preset default volume restoration
              // This should restore volumes to the current preset's default settings
              // For now, reset to global defaults

              audioManager.resetSounds()
            }) {
              Text("Reset")
            }
            .disabled(isAtDefaultVolumes)
            .sensoryFeedback(.success, trigger: isAtDefaultVolumes)
          }

          ToolbarItem(placement: .primaryAction) {
            Button {
              dismiss()
            } label: {
              Text("Done")
            }
          }
        }
      }
    } else {
      popoverContent
    }
  }

  // Popover-style content view
  private var popoverContent: some View {
    VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("All Sounds")
          .font(.caption)
        Slider(
          value: Binding(
            get: { globalSettings.volume },
            set: { globalSettings.setVolume($0) }
          ),
          in: 0...1
        )
        .frame(width: 200)
        .tint(accentColor)
        .accessibilityLabel(Text("All Sounds"))
        .accessibilityValue(
          Text(globalSettings.volume.formatted(.percent.precision(.fractionLength(0)))))
      }

      if audioManager.sounds.contains(where: \.isSelected) {
        Divider()

        ForEach(audioManager.sounds.filter(\.isSelected)) { sound in
          VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(sound.title))
              .font(.caption)

            Slider(
              value: Binding(
                get: { Double(sound.volume) },
                set: { sound.volume = Float($0) }
              ), in: 0...1
            )
            .frame(width: 200)
            .tint(accentColor)
            .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
            .accessibilityValue(
              Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0)))))
          }
        }
      }

      Divider()

      Button {
        // TODO: Implement preset default volume restoration
        // This should restore volumes to the current preset's default settings
        // For now, reset to global defaults
        audioManager.resetSounds()
      } label: {
        Text("Reset")
      }
      .font(.caption)
      .disabled(isAtDefaultVolumes)
      .sensoryFeedback(.success, trigger: isAtDefaultVolumes)
    }
    .padding()
  }

  // Sheet-style content view
  private var sheetContent: some View {
    VStack(spacing: 24) {
      // All Sounds slider
      VStack(alignment: .leading, spacing: 8) {
        Text("All Sounds")
          .font(.headline)

        HStack {
          Image(systemName: "speaker.wave.1.fill")
            .foregroundColor(.secondary)
            .accessibilityHidden(true)

          Slider(
            value: Binding(
              get: { globalSettings.volume },
              set: { globalSettings.setVolume($0) }
            ),
            in: 0...1
          )
          .tint(accentColor)
          .accessibilityLabel(Text("All Sounds"))
          .accessibilityValue(
            Text(globalSettings.volume.formatted(.percent.precision(.fractionLength(0)))))

          Image(systemName: "speaker.wave.3.fill")
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal)
      .padding(.top)

      // Active sound sliders
      if audioManager.sounds.contains(where: \.isSelected) {
        Divider()
          .padding(.horizontal)

        VStack(alignment: .leading, spacing: 16) {
          Text("Active Sounds")
            .font(.headline)
            .padding(.horizontal)

          ForEach(audioManager.sounds.filter(\.isSelected)) { sound in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: sound.systemIconName)
                  .foregroundColor(accentColor)

                if globalSettings.showSoundNames {
                  Text(LocalizedStringKey(sound.title))
                    .font(.callout)
                }
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel(Text(LocalizedStringKey(sound.title)))

              HStack {
                Image(systemName: "speaker.wave.1.fill")
                  .foregroundColor(.secondary)
                  .font(.caption)
                  .accessibilityHidden(true)

                Slider(
                  value: Binding(
                    get: { Double(sound.volume) },
                    set: { sound.volume = Float($0) }
                  ), in: 0...1
                )
                .tint(accentColor)
                .accessibilityLabel(Text(LocalizedStringKey(sound.title)))
                .accessibilityValue(
                  Text(Double(sound.volume).formatted(.percent.precision(.fractionLength(0)))))

                Image(systemName: "speaker.wave.3.fill")
                  .foregroundColor(.secondary)
                  .font(.caption)
                  .accessibilityHidden(true)
              }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
          }
        }
      }

    }
    .padding()
  }
}

// Preview Provider
struct VolumeControlsView_Previews: PreviewProvider {
  static var previews: some View {
    VolumeControlsView(style: .sheet)
  }
}
