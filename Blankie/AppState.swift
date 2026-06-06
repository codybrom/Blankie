//
//  AppState.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

class AppState: ObservableObject {
  static let shared = AppState()

  /// Drives the macOS "Manage Sounds" sheet from the toolbar menu.
  @Published var showingManageSounds = false
  /// Drives the macOS menu-bar import file picker (ContentView hosts it).
  @Published var showingImport = false
  /// Drives the macOS Debug menu's onboarding sheet (ContentView hosts it).
  @Published var showingOnboarding = false
  /// macOS: Settings takes over the detail pane (sidebar gear toggles it).
  @Published var showingSettingsPane = false
  /// macOS: the Settings pane's About sub-page (the About row and the menu
  /// bar's About Blankie both land here). Reset by the pane's onDisappear —
  /// not when the pane flag flips — so Done doesn't flash the settings root
  /// while the pane fades out.
  @Published var showingSettingsAboutPage = false
  /// Onboarding just created (and applied) a preset — each platform's root
  /// navigates to it (iPhone pushes the mixer, macOS closes the Settings
  /// pane) and resets the flag.
  @Published var onboardingCreatedPreset = false

  private init() {}
}
