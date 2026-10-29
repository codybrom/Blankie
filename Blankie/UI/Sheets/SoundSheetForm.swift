//
//  SoundSheetForm.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/25.
//

import AVFoundation
import SwiftUI

struct SoundSheetForm: View {
  let mode: SoundSheetMode
  let isFilePreselected: Bool
  @Binding var soundName: String
  @Binding var selectedIcon: String
  @Binding var selectedFile: URL?
  @Binding var isImporting: Bool
  @Binding var convertToAACOnImport: Bool
  @Binding var randomizeStartPosition: Bool
  @Binding var normalizeAudio: Bool
  @Binding var volumeAdjustment: Float
  @Binding var loopSound: Bool
  @Binding var fadeSound: Bool
  @Binding var isPresetUseOnly: Bool
  @Binding var isMusic: Bool
  @Binding var addToPresetIDs: Set<UUID>
  @Binding var createMixPreset: Bool
  @Binding var isPreviewing: Bool
  @Binding var previewSound: Sound?
  @Binding var previewProgress: Double
  @Binding var showingDeleteConfirmation: Bool
  @Binding var showingResetConfirmation: Bool
  @Binding var isDisappearing: Bool

  let globalSettings = GlobalSettings.shared
  let presetManager = PresetManager.shared
  @State var showingIconPicker = false
  @State var isGeneratingDetails = false
  @State var isGeneratingIcon = false
  /// Import-time AAC conversion state, refreshed on each file change. `forced`
  /// locks the toggle on over the raw-import ceiling. `estimate` is non-nil when
  /// conversion is worth offering.
  @State var importConvertForced = false
  @State var importConvertEstimate: CustomSoundManager.CompressionEstimate?
  @State private var presetMembershipExpanded = false
  /// Pre-AI values for one-tap undo of the last suggestion, per field.
  @State var aiNameUndo: String?
  @State var aiIconUndo: String?
  #if os(macOS)
    @State var showingCreditsEditor = false
  #endif

  /// The music tag is editable only for custom sounds (`.add` is always one).
  /// Built-ins take it from sounds.json (`isMusicDefault`).
  var isCustomSound: Bool {
    if case .edit(let sound) = mode { return sound.isCustom }
    return true
  }

  var body: some View {
    Form {
      if case .add = mode {
        Section {
          SoundFileSelector(
            selectedFile: $selectedFile,
            soundName: $soundName,
            isImporting: $isImporting,
            hideChangeButton: isFilePreselected
          )
        }
      }

      basicInformationSection

      creditsSection

      audioProcessingSection

      addToPresetsSection

      presetMembershipSection

      technicalDetailsSection

      actionSection
    }
    #if os(macOS)
      .formStyle(.grouped)
    #endif
    .sheet(isPresented: $showingIconPicker) {
      NavigationStack {
        IconPickerView(selectedIcon: $selectedIcon)
      }
    }
    // Suggest a name and icon whenever an import picks a file.
    .task(id: selectedFile) {
      await autoSuggestDetailsIfNeeded()
    }
    .task(id: selectedFile) {
      await refreshImportConversion()
    }
    #if os(macOS)
      .sheet(isPresented: $showingCreditsEditor) {
        if let sound = currentEditSound {
          NavigationStack {
            SoundCreditsEditorView(sound: sound)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showingCreditsEditor = false }
              }
            }
          }
          .frame(minWidth: 420, minHeight: 420)
        }
      }
    #endif
  }

  #if os(macOS)
    /// The sound whose credits editor to present (edit mode only).
    private var currentEditSound: Sound? {
      if case .edit(let sound) = mode { return sound }
      return nil
    }
  #endif
}

// MARK: - Add to Presets (import only)
extension SoundSheetForm {
  private var customPresets: [Preset] {
    presetManager.presets.filter { !$0.isDefault }
  }

  /// Name the New Preset row creates. A format string so locales control the
  /// word order.
  private var mixPresetName: String {
    let name = soundName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? String(localized: "Mix") : String(localized: "\(name) Mix")
  }

  /// Offers existing custom presets and a fresh "<Name> Mix" preset for the
  /// imported sound. The active custom preset arrives pre-checked.
  @ViewBuilder
  var addToPresetsSection: some View {
    if mode.isAdd {
      Section {
        Button {
          createMixPreset.toggle()
        } label: {
          HStack(spacing: 10) {
            selectionIndicator(isOn: createMixPreset)
            Text("New Preset")
            Spacer()
            Text(verbatim: mixPresetName)
              .foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(createMixPreset ? [.isSelected] : [])

        ForEach(customPresets) { preset in
          let isOn = addToPresetIDs.contains(preset.id)
          Button {
            if isOn {
              addToPresetIDs.remove(preset.id)
            } else {
              addToPresetIDs.insert(preset.id)
            }
          } label: {
            HStack(spacing: 10) {
              selectionIndicator(isOn: isOn)
              Text(preset.name)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
      } header: {
        Text("Add to Presets")
      }
    }
  }

  private func selectionIndicator(isOn: Bool) -> some View {
    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
      .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      .accessibilityHidden(true)
  }

  /// Edit mode: a folded list of custom presets that toggles this sound's
  /// membership live. The default preset holds every sound, so it isn't listed.
  @ViewBuilder
  var presetMembershipSection: some View {
    if case .edit(let sound) = mode {
      Section {
        DisclosureGroup(isExpanded: $presetMembershipExpanded) {
          if customPresets.isEmpty {
            Text("You don't have any presets yet.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(customPresets) { preset in
              let isOn = preset.soundStates.contains { $0.fileName == sound.fileName }
              Button {
                presetManager.setSound(
                  sound.fileName, member: !isOn, ofPreset: preset.id, volume: sound.volume)
              } label: {
                HStack(spacing: 10) {
                  selectionIndicator(isOn: isOn)
                  Text(preset.name)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
          }
        } label: {
          Text("Presets (\(presetMembershipCount(for: sound)))")
        }
      }
    }
  }

  private func presetMembershipCount(for sound: Sound) -> Int {
    customPresets.filter {
      $0.soundStates.contains { $0.fileName == sound.fileName }
    }.count
  }

  /// Recomputes the import-conversion state for the picked file under a brief
  /// security scope. Resets the opt-in so a previous pick's choice can't carry over.
  func refreshImportConversion() async {
    convertToAACOnImport = false
    guard mode.isAdd, let url = selectedFile else {
      importConvertForced = false
      importConvertEstimate = nil
      return
    }
    let didScope = url.startAccessingSecurityScopedResource()
    defer { if didScope { url.stopAccessingSecurityScopedResource() } }
    let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    let seconds = (try? await AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds)
    importConvertForced = CustomSoundManager.importRequiresConversion(
      bytes: bytes, fileExtension: url.pathExtension)
    importConvertEstimate = CustomSoundManager.shared.compressionEstimate(
      forExtension: url.pathExtension, currentBytes: bytes, duration: seconds)
  }
}

// MARK: - Color Helpers
extension SoundSheetForm {
  var textColorForCurrentTheme: Color {
    (globalSettings.customAccentColor ?? .accentColor).contrastingLabel
  }

  func textColorForAccentColor(_ accentColor: AccentColor) -> Color {
    guard let color = accentColor.color else { return .white }
    return color.contrastingLabel
  }
}

// MARK: - Volume Helpers
extension SoundSheetForm {
  var volumePercentageText: String {
    let delta = Double(volumeAdjustment) - 1.0
    return delta.formatted(
      .percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
  }
}

// MARK: - Preview Helpers
extension SoundSheetForm {
  func togglePreview() {
    isPreviewing.toggle()
  }

  func startPreview() {
    isPreviewing = true
  }

  func stopPreview() {
    isPreviewing = false
  }
}
