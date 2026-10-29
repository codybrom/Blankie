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
  /// macOS: the Settings pane's About sub-page (About row and menu bar both open it).
  /// Reset in the pane's onDisappear so Done doesn't flash the settings root mid-fade.
  @Published var showingSettingsAboutPage = false
  /// macOS: the Settings pane's Manage Sounds sub-page, swapped in-pane like About
  /// because a NavigationLink push escapes the pane. Same onDisappear reset.
  @Published var showingSettingsManageSoundsPage = false
  /// The Settings Highlights page: swapped in-pane on macOS, pushed in the settings
  /// sheet on iOS. `blankie://highlights` opens Settings to it.
  @Published var showingSettingsHighlightsPage = false
  /// Set when onboarding creates and applies a preset. Each platform's root navigates
  /// to it (iPhone pushes the mixer, macOS closes the Settings pane) and resets it.
  @Published var onboardingCreatedPreset = false

  private init() {}
}
