//
//  WhatsNewView.swift
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
struct WhatsNewView: View {
  private let globalSettings = GlobalSettings.shared
  @State private var translations: [String: String] = [:]
  @State private var showsOriginal = false
  @State private var availability: LanguageAvailability.Status?
  @State private var configuration: TranslationSession.Configuration?

  private static let english = Locale.Language(identifier: "en")

  /// The app's language, which a per-app language setting can set apart from the system's.
  private var appLanguage: Locale.Language {
    Locale.Language(identifier: Bundle.main.preferredLocalizations.first ?? "en")
  }

  private var isTranslated: Bool { !translations.isEmpty && !showsOriginal }

  private var accent: Color { globalSettings.customAccentColor ?? .accentColor }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        ForEach(WhatsNew.releases) { release in
          releaseSection(release)
        }
        translationFooter
      }
      .padding(24)
      .frame(maxWidth: 600, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("What's New")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task { await prepareTranslation() }
    // Off the main actor: the session isn't Sendable and translates concurrently.
    .translationTask(configuration) {
      @concurrent [sources = Array(Set(WhatsNew.allText)), translations = $translations] session in
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
        // A declined download or unsupported pair leaves the English in place.
        Logger.ui.error("What's New translation failed: \(error, privacy: .public)")
      }
    }
    .onAppear { globalSettings.setLastSeenWhatsNewVersion(WhatsNew.latestVersion) }
  }

  private func releaseSection(_ release: WhatsNewRelease) -> some View {
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
  private var translationFooter: some View {
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
    } else if availability == .supported, configuration == nil {
      Button {
        configuration = TranslationSession.Configuration(
          source: Self.english, target: appLanguage)
      } label: {
        Label(
          "Translate to \(Locale.current.localizedString(forIdentifier: appLanguage.minimalIdentifier) ?? appLanguage.minimalIdentifier)",
          systemImage: "translate")
      }
      .buttonStyle(.bordered)
      .handCursor()
    }
  }

  private func shown(_ text: String) -> String {
    isTranslated ? translations[text] ?? text : text
  }

  private func prepareTranslation() async {
    guard appLanguage.languageCode != .english else { return }
    let status = await LanguageAvailability().status(from: Self.english, to: appLanguage)
    availability = status
    if status == .installed {
      configuration = TranslationSession.Configuration(source: Self.english, target: appLanguage)
    }
  }
}

#Preview {
  NavigationStack { WhatsNewView() }
}
