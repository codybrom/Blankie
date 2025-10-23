//
//  OnboardingTips.swift
//  Blankie
//
//  Created by Claude Code
//

import SwiftUI
import TipKit

// MARK: - Preset Onboarding Tips

/// Tip to encourage users to create their first preset
struct CreateFirstPresetTip: Tip {
    var title: Text {
        Text("Create Your First Preset")
    }

    var message: Text? {
        Text("Save your favorite sound combinations as presets for quick access later.")
    }

    var image: Image? {
        Image(systemName: "star.circle")
    }

    var actions: [Action] {
        [
            Action(id: "create", title: "Create Preset"),
            Action(id: "dismiss", title: "Not Now"),
        ]
    }

    var rules: [Rule] {
        [
            // Show this tip only if user hasn't created any custom presets yet
            #Rule(Self.$hasCreatedPreset) { $0 == false },
        ]
    }

    @Parameter
    static var hasCreatedPreset: Bool = false
}

/// Tip to guide users on selecting sounds
struct SelectSoundsTip: Tip {
    var title: Text {
        Text("Select Sounds for Your Preset")
    }

    var message: Text? {
        Text("Choose the sounds you want to include in this preset. You can select as many as you like!")
    }

    var image: Image? {
        Image(systemName: "checkmark.circle")
    }
}

/// Tip to explain preset switching
struct SwitchPresetsTip: Tip {
    var title: Text {
        Text("Switch Between Presets")
    }

    var message: Text? {
        Text("Tap here to quickly switch between your saved presets and access your sound collections.")
    }

    var image: Image? {
        Image(systemName: "rectangle.stack")
    }

    var rules: [Rule] {
        [
            // Show this tip only after user has created at least one preset
            #Rule(CreateFirstPresetTip.$hasCreatedPreset) { $0 == true },
            // But hasn't learned how to switch yet
            #Rule(Self.$hasSwitchedPresets) { $0 == false },
        ]
    }

    @Parameter
    static var hasSwitchedPresets: Bool = false
}

/// Tip to explain editing presets
struct EditPresetTip: Tip {
    var title: Text {
        Text("Customize Your Preset")
    }

    var message: Text? {
        Text("Tap the slider icon to edit your preset's name, artwork, and settings.")
    }

    var image: Image? {
        Image(systemName: "slider.vertical.3")
    }

    var rules: [Rule] {
        [
            // Show only after user has created a preset and switched at least once
            #Rule(CreateFirstPresetTip.$hasCreatedPreset) { $0 == true },
            #Rule(SwitchPresetsTip.$hasSwitchedPresets) { $0 == true },
            #Rule(Self.$hasEditedPreset) { $0 == false },
        ]
    }

    @Parameter
    static var hasEditedPreset: Bool = false
}

/// Tip to explain Quick Mix mode
struct QuickMixTip: Tip {
    var title: Text {
        Text("Try Quick Mix")
    }

    var message: Text? {
        Text("Quickly mix sounds without saving them as a preset. Perfect for experimenting!")
    }

    var image: Image? {
        Image(systemName: "square.grid.2x2")
    }

    var rules: [Rule] {
        [
            // Show after user is comfortable with presets
            #Rule(CreateFirstPresetTip.$hasCreatedPreset) { $0 == true },
            #Rule(Self.$hasUsedQuickMix) { $0 == false },
        ]
    }

    @Parameter
    static var hasUsedQuickMix: Bool = false
}

// MARK: - Onboarding Manager

@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var shouldShowOnboarding: Bool
    @Published var onboardingStep: Int = 0

    private let hasCompletedOnboardingKey = "hasCompletedPresetOnboarding"
    private let onboardingStepKey = "currentOnboardingStep"

    private init() {
        shouldShowOnboarding = !UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        shouldShowOnboarding = false
    }

    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
        shouldShowOnboarding = true
        onboardingStep = 0

        // Reset TipKit parameters
        try? Tips.resetDatastore()
    }

    func markPresetCreated() {
        CreateFirstPresetTip.hasCreatedPreset = true
    }

    func markPresetSwitched() {
        SwitchPresetsTip.hasSwitchedPresets = true
    }

    func markPresetEdited() {
        EditPresetTip.hasEditedPreset = true
    }

    func markQuickMixUsed() {
        QuickMixTip.hasUsedQuickMix = true
    }

    func checkAndShowOnboarding(hasCustomPresets: Bool) -> Bool {
        // Show onboarding if:
        // 1. User hasn't completed onboarding before
        // 2. User has no custom presets
        return shouldShowOnboarding && !hasCustomPresets
    }
}
