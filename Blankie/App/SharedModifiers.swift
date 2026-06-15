//
//  SharedModifiers.swift
//  Blankie
//
//  Created by Cody Bromley on 6/17/25.
//

import SwiftUI
import os

/// Shared view modifiers for all platforms
struct SharedAppModifiers: ViewModifier {
  let appSetup: AppSetup
  var globalSettings: GlobalSettings
  @StateObject private var audioFileImporter = AudioFileImporter.shared

  /// The degraded store state to show a one-time notice for this launch, or nil
  /// when the store opened healthy (or the notice was already shown/dismissed).
  @State private var degradedStoreNotice: AppSetup.StoreState?
  @State private var didEvaluateStoreNotice = false

  func body(content: Content) -> some View {
    content
      .onAppear {
        Task { @MainActor in
          appSetup.setupManagers()
        }
      }
      .task {
        // Surface a one-time notice if the persistent store opened in a degraded
        // mode this launch. Evaluate once per view lifetime so dismissing it
        // doesn't re-trigger while the static state stays non-healthy.
        guard !didEvaluateStoreNotice else { return }
        didEvaluateStoreNotice = true
        if AppSetup.storeState != .healthy {
          degradedStoreNotice = AppSetup.storeState
        }
      }
      .alert(
        degradedStoreTitle(),
        isPresented: Binding(
          get: { degradedStoreNotice != nil },
          set: { if !$0 { degradedStoreNotice = nil } }
        )
      ) {
        Button("OK", role: .cancel) { degradedStoreNotice = nil }
      } message: {
        degradedStoreMessage()
      }
      .tint(globalSettings.customAccentColor ?? .accentColor)
      .onOpenURL { url in
        if url.pathExtension == "blankie" {
          // Handle preset import
          Task { @MainActor in
            do {
              let importedPreset = try await PresetImporter.shared.importArchive(from: url)
              Logger.app.debug(
                "Imported preset '\(importedPreset.name)' from \(url.lastPathComponent)")
            } catch {
              Logger.app.error("Failed to import presets: \(error, privacy: .public)")
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
      #if os(macOS)
        // Preset archive import is async with no sheet of its own, so show a
        // global processing indicator while it runs.
        .overlay {
          if audioFileImporter.isProcessingImport {
            SoundSheetProcessingOverlay(progressMessage: "Importing")
          }
        }
      #endif
  }

  /// Title for the degraded-store notice. Built from string literals in `Text`
  /// so both strings are picked up for localization.
  private func degradedStoreTitle() -> Text {
    switch degradedStoreNotice {
    case .recoveredFreshStore:
      return Text(
        "Library Rebuilt",
        comment:
          "Alert title shown once at launch after the app rebuilt its data store following a problem opening it."
      )
    default:
      return Text(
        "Storage Unavailable",
        comment:
          "Alert title shown once at launch when the app couldn't open its data store this session."
      )
    }
  }

  @ViewBuilder
  private func degradedStoreMessage() -> some View {
    switch degradedStoreNotice {
    case .recoveredFreshStore:
      Text(
        "Blankie had to rebuild its library after a problem opening it. Your presets and saved artwork were restored, and your imported sounds were recovered from a backup copy where possible.",
        comment:
          "Alert message after the data store was rebuilt; reassures the user their content was restored."
      )
    default:
      Text(
        "Blankie couldn't open its library this time, so your custom sounds are unavailable for this session. Your data is safe — Blankie will try again next time you open it.",
        comment:
          "Alert message when the data store couldn't open this session; reassures the user no data was lost."
      )
    }
  }
}

extension View {
  func sharedAppModifiers(appSetup: AppSetup, globalSettings: GlobalSettings) -> some View {
    modifier(SharedAppModifiers(appSetup: appSetup, globalSettings: globalSettings))
  }
}
