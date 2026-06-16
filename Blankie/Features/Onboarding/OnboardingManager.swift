//
//  OnboardingManager.swift
//  Blankie
//
//  Created by Cody Bromley on 10/23/25.
//

import SwiftUI

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
  }

  func checkAndShowOnboarding(hasCustomPresets: Bool) -> Bool {
    // Show onboarding if:
    // 1. User hasn't completed onboarding before
    // 2. User has no custom presets
    return shouldShowOnboarding && !hasCustomPresets
  }
}
