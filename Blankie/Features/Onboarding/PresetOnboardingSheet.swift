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
                if newStep != 2 { // step 2 is selectSounds
                    stopAllPreviews()
                }
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
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous).speed(0.8), isActive: step == .welcome)
                    .padding(.bottom, 8)

                // Title
                Text(step.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.leading)

                // Description
                Text(step.description)
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

            SpectrumColorPicker(selectedColor: Binding(
                get: { GlobalSettings.shared.customAccentColor ?? .blue },
                set: { GlobalSettings.shared.customAccentColor = $0 }
            ))
        }
    }

    private var soundSelectionContent: some View {
        VStack(spacing: 16) {
            Text("Pick some sounds for your first mix")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(audioManager.sounds.sorted { $0.title < $1.title }) { sound in
                        soundSelectionRow(for: sound)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 300)
        }
    }

    private func soundSelectionRow(for sound: Sound) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                if selectedSounds.contains(sound.fileName) {
                    selectedSounds.remove(sound.fileName)
                } else {
                    selectedSounds.insert(sound.fileName)
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Sound icon
                Image(systemName: sound.systemIconName)
                    .font(.system(size: 24))
                    .foregroundStyle(selectedSounds.contains(sound.fileName) ? .primary : .secondary)

                // Sound info
                VStack(alignment: .leading, spacing: 4) {
                    Text(sound.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Preview button
                Button {
                    togglePreview(for: sound)
                } label: {
                    Image(systemName: previewingSound == sound.fileName ? "stop.circle.fill" : "play.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(previewingSound == sound.fileName ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedSounds.contains(sound.fileName) ? globalSettings.customAccentColor ?? .accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private var namePresetContent: some View {
        VStack(spacing: 20) {
            Text("Give it a memorable name")
                .font(.headline)

            TextField("e.g., Morning Meditation", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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

    private var completionContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .padding(.bottom, 8)

            Text("You're all set!")
                .font(.title2)
                .fontWeight(.semibold)

            if !presetName.isEmpty {
                Text("'\(presetName)' is ready to use")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Tap the preset button to switch", systemImage: "rectangle.stack")
                Label("Edit anytime with the slider icon", systemImage: "slider.vertical.3")
                Label("Create more presets as you like", systemImage: "plus.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
        }
    }

    // MARK: - UI Components

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? (globalSettings.customAccentColor ?? .accentColor) : Color.secondary.opacity(0.3))
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
                        if currentStep == 2 && selectedSounds.isEmpty {
                            // Don't allow progression without selecting sounds
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
                .disabled((currentStep == 2 && selectedSounds.isEmpty) || (currentStep == 3 && presetName.isEmpty))
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

    private func createPreset() {
        Task {
            do {
                // Build the preset
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let orderedSounds = audioManager.sounds.sorted { $0.title < $1.title }
                let selectedSoundStates = orderedSounds
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
                    showBackgroundImage: nil,
                    useArtworkAsBackground: nil,
                    backgroundImageId: nil,
                    backgroundBlurRadius: nil,
                    backgroundOpacity: nil,
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
                print("❌ PresetOnboardingSheet: Failed to create preset: \(error)")
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
            return "Almost everything in Blankie can be customized. Let's start by choosing an accent color. You can change this anytime."
        case .selectSounds:
            return "Blankie lets you mix and save different soundscapes for different moods and activites."
        case .namePreset:
            return "What kind of mood or activity is this preset for? You can always change it later."
        case .complete:
            return "Your preset is ready! Here's what you can do next:"
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

#if DEBUG
    struct PresetOnboardingSheet_Previews: PreviewProvider {
        static var previews: some View {
            PresetOnboardingSheet(isPresented: .constant(true))
        }
    }
#endif
