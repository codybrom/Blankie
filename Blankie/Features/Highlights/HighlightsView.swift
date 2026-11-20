//
//  HighlightsView.swift
//  Blankie
//
//  Created by Cody Bromley on 10/28/26.
//

import SwiftUI
import Translation
import os

/// Release highlights in English, translated on device when the app runs in another
/// language. An installed language translates on open. Otherwise a button asks
/// first, since translating starts the system's language download prompt.
struct HighlightsView: View {
  private let globalSettings = GlobalSettings.shared
  @State private var translations: [String: String] = [:]
  @State private var showsOriginal = false
  @State private var availability: LanguageAvailability.Status?
  @State private var configuration: TranslationSession.Configuration?
  @State private var translationFailed = false

  private let appLanguage = Bundle.main.appLanguage

  private var isTranslated: Bool { !translations.isEmpty && !showsOriginal }

  private var accent: Color { globalSettings.customAccentColor ?? .accentColor }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        translationControl
        ForEach(Highlights.releases) { release in
          releaseSection(release)
        }
      }
      .padding(24)
      .frame(maxWidth: 600, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Highlights")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task { await prepareTranslation() }
    // Off the main actor: the session isn't Sendable and translates concurrently.
    .translationTask(configuration) {
      @concurrent [
        sources = Array(Set(Highlights.allText)), translations = $translations,
        failed = $translationFailed
      ] session in
      let requests = sources.map {
        TranslationSession.Request(sourceText: $0, clientIdentifier: $0)
      }
      do {
        var result: [String: String] = [:]
        for response in try await session.translations(from: requests) {
          if let source = response.clientIdentifier { result[source] = response.targetText }
        }
        await MainActor.run { translations.wrappedValue = result }
      } catch {
        // A declined download or unsupported pair leaves the English in place,
        // and the Translate button comes back.
        Logger.ui.error("Highlights translation failed: \(error, privacy: .public)")
        await MainActor.run { failed.wrappedValue = true }
      }
    }
    .onAppear { globalSettings.setLastSeenHighlightsVersion(Highlights.latestVersion) }
  }

  private func releaseSection(_ release: HighlightsRelease) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(verbatim: "Blankie \(release.version)")
        .font(.title2.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ForEach(release.items) { item in
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: item.systemImage)
            .font(.system(size: 22))
            .foregroundStyle(accent)
            .frame(width: 32)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: shown(item.title))
              .font(.headline)
            Text(verbatim: shown(item.detail))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  @ViewBuilder
  private var translationControl: some View {
    if !translations.isEmpty {
      HStack(spacing: 6) {
        Image(systemName: "translate")
          .accessibilityHidden(true)
        Text(isTranslated ? "Translated on your device" : "Original English")
        Button(isTranslated ? "Show Original" : "Show Translation") {
          showsOriginal.toggle()
        }
        .buttonStyle(.borderless)
        .handCursor()
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    } else if translationFailed || (availability == .supported && configuration == nil) {
      Button {
        translationFailed = false
        if configuration == nil {
          configuration = TranslationSession.Configuration(
            source: .english, target: appLanguage)
        } else {
          // Runs the translation task again with the same languages.
          configuration?.invalidate()
        }
      } label: {
        Label(
          "Translate to \(Locale.current.localizedString(forIdentifier: appLanguage.minimalIdentifier) ?? appLanguage.minimalIdentifier)",
          systemImage: "translate")
      }
      .buttonStyle(.bordered)
      .handCursor()
    } else if availability == .unsupported {
      // Apple can't translate this language (Hungarian today), so say the English is on purpose.
      Label("Original English", systemImage: "translate")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func shown(_ text: String) -> String {
    isTranslated ? translations[text] ?? text : text
  }

  private func prepareTranslation() async {
    guard let status = await Bundle.main.englishTranslationStatus() else { return }
    availability = status
    if status == .installed {
      configuration = TranslationSession.Configuration(source: .english, target: appLanguage)
    }
  }
}

extension Locale.Language {
  nonisolated static let english = Locale.Language(identifier: "en")
}

extension Bundle {
  /// Whether Apple can translate English into the app's language. Nil when the app runs
  /// in English.
  func englishTranslationStatus() async -> LanguageAvailability.Status? {
    guard appLanguage.languageCode != .english else { return nil }
    return await LanguageAvailability().status(from: .english, to: appLanguage)
  }
}

#Preview {
  NavigationStack { HighlightsView() }
}
