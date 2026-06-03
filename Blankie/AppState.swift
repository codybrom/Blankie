//
//  AppState.swift
//  Blankie
//
//  Created by Cody Bromley on 1/1/25.
//

import SwiftUI

class AppState: ObservableObject {
  static let shared = AppState()

  @Published var isAboutViewPresented = false
  /// Drives the macOS "Manage Sounds" sheet from the toolbar menu.
  @Published var showingManageSounds = false
  /// Drives the macOS menu-bar import file picker (ContentView hosts it).
  @Published var showingImport = false

  private init() {}
}
