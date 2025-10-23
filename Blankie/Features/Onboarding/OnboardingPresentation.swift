import SwiftUI

/// A wrapper that automatically presents the PresetOnboardingSheet when appropriate.
struct PresetOnboardingPresenter<Content: View>: View {
    private let content: () -> Content
    private let force: Bool

    init(force: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.force = force
        self.content = content
    }

    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var presetManager = PresetManager.shared

    @State private var showOnboarding = false

    var body: some View {
        content()
            .sheet(isPresented: $showOnboarding) {
                PresetOnboardingSheet(isPresented: $showOnboarding)
            }
            .onChange(of: presetManager.isLoading) { oldValue, newValue in
                if oldValue != newValue, newValue == false {
                    #if DEBUG
                    if presetManager.hasCustomPresets {
                        print("🧭 OnboardingPresenter[DEBUG]: Forcing onboarding despite existing presets")
                        showOnboarding = true
                        return
                    }
                    #endif
                    let shouldShow = onboardingManager.checkAndShowOnboarding(
                        hasCustomPresets: presetManager.hasCustomPresets
                    )
                    print("🧭 OnboardingPresenter: isLoading->false, shouldShowOnboarding=\(onboardingManager.shouldShowOnboarding), hasCustomPresets=\(presetManager.hasCustomPresets), result=\(shouldShow)")
                    showOnboarding = force ? true : shouldShow
                }
            }
            .onAppear {
                if force {
                    print("🧭 OnboardingPresenter: force=true, presenting onboarding")
                    showOnboarding = true
                    return
                }
                #if DEBUG
                if presetManager.hasCustomPresets {
                    print("🧭 OnboardingPresenter[DEBUG]: Forcing onboarding on appear despite existing presets")
                    showOnboarding = true
                    return
                }
                #endif
                if !presetManager.isLoading {
                    let shouldShow = onboardingManager.checkAndShowOnboarding(
                        hasCustomPresets: presetManager.hasCustomPresets
                    )
                    print("🧭 OnboardingPresenter: onAppear, isLoading=false, shouldShowOnboarding=\(onboardingManager.shouldShowOnboarding), hasCustomPresets=\(presetManager.hasCustomPresets), result=\(shouldShow)")
                    showOnboarding = shouldShow
                } else {
                    print("🧭 OnboardingPresenter: onAppear, waiting for presets to finish loading...")
                }
            }
    }
}

extension View {
    /// Presents the PresetOnboardingSheet when onboarding should be shown.
    /// Apply this to your root view (e.g., AdaptiveContentView())
    func withPresetOnboarding() -> some View {
        PresetOnboardingPresenter { self }
    }

    func withPresetOnboarding(force: Bool) -> some View {
        PresetOnboardingPresenter(force: force) { self }
    }
}
