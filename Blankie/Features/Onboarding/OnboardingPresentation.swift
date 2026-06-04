//
//  OnboardingPresentation.swift
//  Blankie
//
//  Created by Cody Bromley on 10/23/25.
//

import SwiftUI
import os

/// A wrapper that automatically presents the PresetOnboardingSheet when appropriate.
struct PresetOnboardingPresenter<Content: View>: View {
  private let content: () -> Content
  private let force: Bool
  @Binding var showOnboarding: Bool

  init(
    force: Bool = false, showOnboarding: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.force = force
    _showOnboarding = showOnboarding
    self.content = content
  }

  @StateObject private var onboardingManager = OnboardingManager.shared
  @StateObject private var presetManager = PresetManager.shared

  var body: some View {
    content()
      .sheet(isPresented: $showOnboarding) {
        PresetOnboardingSheet(isPresented: $showOnboarding)
      }
      .onChange(of: presetManager.isLoading) { oldValue, newValue in
        if oldValue != newValue, newValue == false {
          let shouldShow = onboardingManager.checkAndShowOnboarding(
            hasCustomPresets: presetManager.hasCustomPresets
          )
          Logger.ui.debug(
            "OnboardingPresenter: isLoading->false, shouldShowOnboarding=\(onboardingManager.shouldShowOnboarding), hasCustomPresets=\(presetManager.hasCustomPresets), result=\(shouldShow)"
          )
          showOnboarding = force ? true : shouldShow
        }
      }
      .onAppear {
        if force {
          Logger.ui.debug("OnboardingPresenter: force=true, presenting onboarding")
          showOnboarding = true
          return
        }
        if !presetManager.isLoading {
          let shouldShow = onboardingManager.checkAndShowOnboarding(
            hasCustomPresets: presetManager.hasCustomPresets
          )
          Logger.ui.debug(
            "OnboardingPresenter: onAppear, isLoading=false, shouldShowOnboarding=\(onboardingManager.shouldShowOnboarding), hasCustomPresets=\(presetManager.hasCustomPresets), result=\(shouldShow)"
          )
          showOnboarding = shouldShow
        } else {
          Logger.ui.debug("OnboardingPresenter: onAppear, waiting for presets to finish loading...")
        }
      }
  }
}

extension View {
  /// Presents the PresetOnboardingSheet when onboarding should be shown.
  /// Apply this to your root view (e.g., MixerView())
  func withPresetOnboarding(showOnboarding: Binding<Bool>) -> some View {
    PresetOnboardingPresenter(showOnboarding: showOnboarding) { self }
  }

  func withPresetOnboarding(force: Bool, showOnboarding: Binding<Bool>) -> some View {
    PresetOnboardingPresenter(force: force, showOnboarding: showOnboarding) { self }
  }
}
