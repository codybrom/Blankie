//
//  SharedModifiers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import SwiftUI

/// Shared view modifiers for all platforms
struct SharedAppModifiers: ViewModifier {
  let appSetup: AppSetup
  @ObservedObject var globalSettings: GlobalSettings
  @StateObject private var audioFileImporter = AudioFileImporter.shared

  func body(content: Content) -> some View {
    content
      .onAppear {
        Task { @MainActor in
          appSetup.setupManagers()
        }
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)
      .onOpenURL { url in
        if url.pathExtension == "blankie" {
          // Handle preset import
          Task { @MainActor in
            do {
              let importedPreset = try await PresetImporter.shared.importArchive(from: url)
              debugLog("📦 Imported preset '\(importedPreset.name)' from \(url.lastPathComponent)")
            } catch {
              debugLog("❌ Failed to import presets: \(error)")
            }
          }
        } else {
          // Handle audio file import
          audioFileImporter.handleIncomingFile(url)
        }
      }
      .sheet(isPresented: $audioFileImporter.showingSoundSheet) {
        SoundSheet(mode: .add, preselectedFile: audioFileImporter.fileToImport)
          .onDisappear {
            audioFileImporter.clearImport()
          }
      }
  }
}

extension View {
  func sharedAppModifiers(appSetup: AppSetup, globalSettings: GlobalSettings) -> some View {
    modifier(SharedAppModifiers(appSetup: appSetup, globalSettings: globalSettings))
  }
}
