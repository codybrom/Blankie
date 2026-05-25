//
//  PresetOnboardingSheet.swift
//  Blankie
//
//  Created by Claude Code
//

import SwiftUI

/// Interactive onboarding sheet that guides users through creating their first preset
struct PresetOnboardingSheet: View {
  @Binding var isPresented: Bool
  @ObservedObject private var audioManager = AudioManager.shared
  @ObservedObject private var onboardingManager = OnboardingManager.shared
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @State private var currentStep = 0
  @State private var selectedSounds: Set<String> = []
  @State private var presetName = ""
  @State private var previewingSound: String?
  @State private var isGeneratingName = false
  @State private var aiAvailable = false
  @Environment(\.dismiss) private var dismiss

  private let steps = OnboardingStep.allSteps

  var body: some View {
    NavigationStack {
      ZStack {
        // Background gradient
        LinearGradient(
          colors: [
            (globalSettings.customAccentColor ?? .accentColor).opacity(0.1),
            (globalSettings.customAccentColor ?? .accentColor).opacity(0.05),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 0) {
          // Progress indicator
          progressIndicator

          // Content
          TabView(selection: $currentStep) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
              stepView(for: step, at: index)
                .tag(index)
            }
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
          .animation(.easeInOut, value: currentStep)

          // Navigation buttons
          navigationButtons
        }
      }
      .navigationBarHidden(true)
      .onChange(of: currentStep) { _, newStep in
        // Stop sound previews when leaving sound selection step
        if newStep != 2 {  // step 2 is selectSounds
          stopAllPreviews()
        }
        // Generate AI name suggestion when entering namePreset step
        if newStep == 3 {  // step 3 is namePreset
          Task {
            await generateInitialNameSuggestion()
          }
        }
      }
      .onAppear {
        aiAvailable = AIPresetNameGenerator.isAvailable
      }
    }
  }

  // MARK: - Step Views

  @ViewBuilder
  private func stepView(for step: OnboardingStep, at _: Int) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      Spacer()

      VStack(alignment: .leading, spacing: 24) {
        // Icon
        step.imageView
          .font(.system(size: 80))
          .symbolRenderingMode(.palette)
          .foregroundStyle(
            LinearGradient(
              colors: [
                globalSettings.customAccentColor ?? .accentColor,
                (globalSettings.customAccentColor ?? .accentColor).opacity(0.7),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .symbolEffect(
            .breathe.pulse.byLayer, options: .repeat(.continuous).speed(0.8),
            isActive: step == .welcome
          )
          .padding(.bottom, 8)

        // Title
        Text(step.title)
          .font(.system(size: 28, weight: .bold))
          .multilineTextAlignment(.leading)

        // Description
        Text(
          step == .complete && !presetName.isEmpty
            ? "'\(presetName)' is ready! Tap 'Create Preset' to save and start listening."
            : step.description
        )
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
      }

      // Interactive content based on step
      Group {
        switch step {
        case .welcome:
          welcomeContent
        case .chooseColor:
          colorPickerContent
        case .selectSounds:
          soundSelectionContent
        case .namePreset:
          namePresetContent
        case .complete:
          completionContent
        }
      }
      .padding(.top, 24)

      Spacer()
    }
    .padding(.horizontal, 35)
  }

  // MARK: - Step Content

  private var welcomeContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("No ads, trackers or subscriptions", systemImage: "hand.raised.fill")
      Label("Listen offline, anytime and anywhere", systemImage: "wifi.slash")
      Label("Add your own sounds and backgrounds", systemImage: "music.note.list")
    }
    .font(.subheadline)
  }

  private var colorPickerContent: some View {
    VStack(spacing: 8) {
      Text("Drag the slider to pick a color")
        .font(.headline)

      SpectrumColorPicker(
        selectedColor: Binding(
          get: { GlobalSettings.shared.customAccentColor ?? .blue },
          set: { GlobalSettings.shared.customAccentColor = $0 }
        ))
    }
  }

  private var soundSelectionContent: some View {
    VStack(spacing: 16) {
      VStack(spacing: 4) {
        Text("Pick some sounds for your first mix")
          .font(.headline)
        Text("Select at least 2 sounds")
          .font(.caption)
          .foregroundStyle(selectedSounds.count >= 2 ? Color.secondary : Color.red)
      }

      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(audioManager.sounds.filter { !$0.isCustom }.sorted { $0.title < $1.title }) {
            sound in
            soundSelectionRow(for: sound)
          }
        }
        .padding(.horizontal, 20)
      }
      .frame(maxHeight: 300)
    }
  }

  private func soundSelectionRow(for sound: Sound) -> some View {
    let isSelected = selectedSounds.contains(sound.fileName)

    return Button {
      withAnimation(.spring(response: 0.3)) {
        if isSelected {
          selectedSounds.remove(sound.fileName)
        } else {
          selectedSounds.insert(sound.fileName)
        }
      }
    } label: {
      HStack(spacing: 12) {
        // Selection Indicator
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22))
          .foregroundStyle(
            isSelected
              ? (globalSettings.customAccentColor ?? .accentColor) : .secondary.opacity(0.5))

        // Sound icon
        Image(systemName: sound.systemIconName)
          .font(.system(size: 20))  // Slightly smaller
          .foregroundStyle(isSelected ? .primary : .secondary)

        // Sound info
        VStack(alignment: .leading, spacing: 4) {
          Text(sound.title)
            .font(.body)
            .foregroundStyle(.primary)
        }

        Spacer()

        // Preview button (De-emphasized)
        Button {
          togglePreview(for: sound)
        } label: {
          Image(systemName: previewingSound == sound.fileName ? "stop.fill" : "play.fill")
            .font(.system(size: 14))  // Smaller
            .foregroundStyle(previewingSound == sound.fileName ? .primary : .secondary)
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(
            isSelected
              ? (globalSettings.customAccentColor ?? .accentColor).opacity(0.1)
              : Color.secondary.opacity(0.05)
          )
          .strokeBorder(
            isSelected
              ? (globalSettings.customAccentColor ?? .accentColor).opacity(0.3) : Color.clear,
            lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var namePresetContent: some View {
    VStack(spacing: 20) {
      Text("Give it a memorable name")
        .font(.headline)
      TextField("e.g., Mindful Meditation", text: $presetName)
        .textFieldStyle(.roundedBorder)
        .font(.title3)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)

      // AI name generation button
      if aiAvailable {
        Button {
          Task {
            await regenerateNameSuggestion()
          }
        } label: {
          if isGeneratingName {
            HStack(spacing: 8) {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
              Text("Generating...")
            }
          } else {
            Label("Generate Another Name", systemImage: "sparkles")
          }
        }
        .buttonStyle(.bordered)
        .disabled(isGeneratingName)
      }

      // Preview selected sounds
      if !selectedSounds.isEmpty {
        VStack(spacing: 8) {
          Text("Your preset will include")
            .font(.caption)
            .foregroundStyle(.secondary)

          HStack(spacing: 8) {
            ForEach(Array(selectedSounds.prefix(5)), id: \.self) { fileName in
              if let sound = audioManager.sounds.first(where: { $0.fileName == fileName }) {
                Text(sound.title)
                  .font(.caption)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(globalSettings.customAccentColor ?? .accentColor.opacity(0.2))
                  .clipShape(Capsule())
              }
            }
            if selectedSounds.count > 5 {
              Text("+\(selectedSounds.count - 5) more")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
          }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder
  private var completionContent: some View {
    if !presetName.isEmpty {
      VStack(alignment: .leading, spacing: 16) {
        Text("What's next?")
          .font(.headline)
        VStack(alignment: .leading, spacing: 12) {
          Label("Mix sounds with individual volume controls", systemImage: "slider.horizontal.3")
          Label("Import your own sounds and backgrounds", systemImage: "square.and.arrow.down")
          Label("Set a timer to fade out automatically", systemImage: "timer")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
      }
    }
  }

  // MARK: - UI Components

  private var progressIndicator: some View {
    HStack(spacing: 8) {
      ForEach(0..<steps.count, id: \.self) { index in
        Capsule()
          .fill(
            index <= currentStep
              ? (globalSettings.customAccentColor ?? .accentColor) : Color.secondary.opacity(0.3)
          )
          .frame(height: 4)
          .animation(.spring(response: 0.3), value: currentStep)
      }
    }
    .padding(.horizontal, 40)
    .padding(.top, 20)
    .padding(.bottom, 16)
  }

  private var navigationButtons: some View {
    HStack(spacing: 16) {
      // Skip/Back button
      if currentStep > 0 {
        Button {
          withAnimation {
            currentStep -= 1
          }
        } label: {
          Label("Back", systemImage: "chevron.left")
            .font(.body)
        }
        .buttonStyle(.bordered)
      } else {
        Button("Skip") {
          dismiss()
        }
        .buttonStyle(.bordered)
      }

      Spacer()

      // Next/Create button
      if currentStep < steps.count - 1 {
        Button {
          withAnimation {
            if currentStep == 2 && selectedSounds.count < 2 {
              // Don't allow progression without selecting at least 2 sounds
              return
            }
            if currentStep == 3 && presetName.isEmpty {
              // Don't allow progression without preset name
              return
            }
            currentStep += 1
          }
        } label: {
          Label(currentStep == 0 ? "Get Started" : "Next", systemImage: "chevron.right")
            .font(.body)
            .labelStyle(.trailingIcon)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          (currentStep == 2 && selectedSounds.count < 2) || (currentStep == 3 && presetName.isEmpty)
        )
      } else {
        Button {
          createPreset()
        } label: {
          Label("Create Preset", systemImage: "checkmark")
            .font(.body.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .disabled(presetName.isEmpty)
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 20)
    .background(.ultraThinMaterial)
    .tint(globalSettings.customAccentColor ?? .accentColor)
  }

  // MARK: - Actions

  private func togglePreview(for sound: Sound) {
    if previewingSound == sound.fileName {
      // Stop preview - exit solo mode
      audioManager.exitSoloMode()
      previewingSound = nil
    } else {
      // Stop any currently previewing sound
      if previewingSound != nil {
        audioManager.exitSoloMode()
      }
      // Start new preview (solo mode)
      audioManager.toggleSoloMode(for: sound)
      previewingSound = sound.fileName
    }
  }

  private func stopAllPreviews() {
    if previewingSound != nil {
      audioManager.exitSoloMode()
    }
    previewingSound = nil
  }

  private func generateInitialNameSuggestion() async {
    let selectedTitles = audioManager.sounds
      .filter { selectedSounds.contains($0.fileName) }
      .map { $0.title }
    guard !selectedTitles.isEmpty else { return }

    isGeneratingName = true
    let suggestion = await AIPresetNameGenerator.generateName(
      from: selectedTitles, allowVariation: false)
    await MainActor.run {
      if presetName.isEmpty {
        presetName = suggestion
      }
      isGeneratingName = false
    }
  }

  private func regenerateNameSuggestion() async {
    guard !isGeneratingName else { return }
    let selectedTitles = audioManager.sounds
      .filter { selectedSounds.contains($0.fileName) }
      .map { $0.title }
    guard !selectedTitles.isEmpty else { return }

    isGeneratingName = true
    let suggestion = await AIPresetNameGenerator.generateName(
      from: selectedTitles, allowVariation: true)
    await MainActor.run {
      presetName = suggestion
      isGeneratingName = false
    }
  }

  private func createPreset() {
    Task {
      do {
        // Build the preset
        let currentVersion =
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let orderedSounds = audioManager.sounds.sorted { $0.title < $1.title }
        let selectedSoundStates =
          orderedSounds
          .filter { selectedSounds.contains($0.fileName) }
          .map { sound in
            PresetState(
              fileName: sound.fileName,
              isSelected: true,
              volume: sound.volume
            )
          }

        let customPresetsCount = PresetManager.shared.presets.filter { !$0.isDefault }.count

        let newPreset = Preset(
          id: UUID(),
          name: presetName,
          soundStates: selectedSoundStates,
          isDefault: false,
          createdVersion: currentVersion,
          lastModifiedVersion: currentVersion,
          soundOrder: nil,
          creatorName: nil,
          artworkId: nil,
          animatedArtwork: nil,
          staticArtworkPath: nil,
          order: customPresetsCount
        )

        // Save the preset
        var currentPresets = PresetManager.shared.presets
        currentPresets.append(newPreset)
        PresetManager.shared.setPresets(currentPresets)
        PresetManager.shared.updateCustomPresetStatus()
        PresetManager.shared.savePresets()

        // Apply the preset
        try PresetManager.shared.applyPreset(newPreset)

        // Mark onboarding as complete
        onboardingManager.markPresetCreated()
        onboardingManager.completeOnboarding()

        // Dismiss
        dismiss()
      } catch {
        debugLog("❌ PresetOnboardingSheet: Failed to create preset: \(error)")
      }
    }
  }
}

// MARK: - Onboarding Step Model

enum OnboardingStep {
  case welcome
  case chooseColor
  case selectSounds
  case namePreset
  case complete

  var title: String {
    switch self {
    case .welcome:
      return "Welcome to Blankie"
    case .chooseColor:
      return "Yours To Keep"
    case .selectSounds:
      return "Make Some Noise"
    case .namePreset:
      return "Name Your Preset"
    case .complete:
      return "Start Listening!"
    }
  }

  var description: String {
    switch self {
    case .welcome:
      return "Blankie lets you mix your own soundscapes to focus, relax and sleep better."
    case .chooseColor:
      return
        "Almost everything in Blankie can be customized. Let's start by choosing an accent color. You can change this anytime."
    case .selectSounds:
      return
        "Blankie lets you mix and save different soundscapes for different moods and activites."
    case .namePreset:
      return "What kind of mood or activity is this preset for? You can always change it later."
    case .complete:
      return "Your preset is ready! Tap 'Create Preset' to save and start listening."
    }
  }

  var icon: String {
    switch self {
    case .welcome:
      return "blankie.symbol"
    case .chooseColor:
      return "paintpalette.fill"
    case .selectSounds:
      return "music.note.list"
    case .namePreset:
      return "textformat"
    case .complete:
      return "party.popper.fill"
    }
  }

  @ViewBuilder
  var imageView: some View {
    switch self {
    case .welcome:
      Image("blankie.symbol")
    default:
      Image(systemName: icon)
    }
  }

  static var allSteps: [OnboardingStep] {
    [.welcome, .chooseColor, .selectSounds, .namePreset, .complete]
  }
}

// MARK: - Trailing Icon Label Style

struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.title
      configuration.icon
    }
  }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
  static var trailingIcon: TrailingIconLabelStyle {
    TrailingIconLabelStyle()
  }
}

// MARK: - Previews

#Preview {
  NavigationStack {
    PresetOnboardingSheet(isPresented: .constant(true))
  }
}
