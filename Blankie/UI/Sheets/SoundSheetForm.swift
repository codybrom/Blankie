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
  /// Import-time AAC conversion state for the picked file, refreshed on each file
  /// change. `forced` is true over the raw-import ceiling (toggle locks on);
  /// `estimate` is non-nil when conversion is worth offering (drives the savings
  /// caption). Both internal so the Audio section (other file) can read them.
  @State var importConvertForced = false
  @State var importConvertEstimate: CustomSoundManager.CompressionEstimate?
  /// The editor's preset-membership list starts folded; the row's trailing
  /// summary shows the count (or "None") without expanding.
  @State private var presetMembershipExpanded = false
  /// Pre-AI values for one-tap undo of the last suggestion, per field.
  @State var aiNameUndo: String?
  @State var aiIconUndo: String?
  #if os(macOS)
    @State var showingCreditsEditor = false
  #endif

  /// The music tag is user-editable only for custom sounds. Built-ins take it
  /// from sounds.json (`isMusicDefault`) and must not be overridable. `.add` is
  /// always a new custom import, so its tag is editable.
  var isCustomSound: Bool {
    if case .edit(let sound) = mode { return sound.isCustom }
    return true
  }

  var body: some View {
    Form {
      // File selection (only for add mode)
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

      // Basic Information
      basicInformationSection

      // Credits (read-only)
      creditsSection

      // Audio Processing (includes preview)
      audioProcessingSection

      // Add to Presets (import only)
      addToPresetsSection

      // Preset membership (edit only)
      presetMembershipSection

      // Technical Details (edit mode only)
      technicalDetailsSection

      // Actions Section (Reset/Delete)
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
    // Suggest a clean name + icon as soon as an import lands a file (and
    // again if the person swaps the file).
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

  /// Name the New Preset row creates, derived live from the sound name.
  /// Format string so locales control the word order.
  private var mixPresetName: String {
    let name = soundName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? String(localized: "Mix") : String(localized: "\(name) Mix")
  }

  /// Imports often happen without a custom preset active, so the sheet offers
  /// where the sound should live: any existing custom presets and/or a fresh
  /// "<Name> Mix" preset. The active custom preset arrives pre-checked.
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

  /// Edit mode: a folded list to view and toggle which custom presets this sound
  /// belongs to. Membership changes apply live. The collapsed row's trailing
  /// summary shows the membership count (or "None"), so unused sounds are easy to
  /// spot without expanding. (The default preset always holds every sound, so it
  /// isn't listed.)
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

  /// Number of custom presets containing `sound` (0 reads as unused everywhere).
  private func presetMembershipCount(for sound: Sound) -> Int {
    customPresets.filter {
      $0.soundStates.contains { $0.fileName == sound.fileName }
    }.count
  }

  /// Recomputes the import-conversion state for the picked file. Reads size and
  /// duration under a brief security scope (the file may be outside the sandbox)
  /// and resets the opt-in each time the file changes so a stale "on" from a
  /// previous pick can't carry over to an ineligible one.
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
    importConvertForced = bytes > CustomSoundManager.maxRawImportBytes
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
