//
//  Language.swift
//  Blankie
//
//  Created by Cody Bromley on 5/21/25.
//

import Foundation
import SwiftUI
import os

struct Language: Hashable, Identifiable, Equatable {
  let id: String
  let code: String
  let displayName: String
  let icon: String

  init(code: String, displayName: String, icon: String = "flag.fill") {
    self.id = code
    self.code = code
    self.displayName = displayName
    self.icon = icon
  }

  private static var _cachedSystemLanguage: Language?

  static var system: Language {
    if let cached = _cachedSystemLanguage {
      return cached
    }

    let systemLanguageCode = Locale.preferredLanguages.first ?? "en"

    let languageCode =
      systemLanguageCode.split(separator: "-").first.map(String.init) ?? systemLanguageCode

    let systemLocale = Locale(identifier: languageCode)

    // The language's name in its own language ("Español" for es).
    let languageName = systemLocale.localizedString(forLanguageCode: languageCode) ?? languageCode

    let displayName =
      "\(String(localized:"System")) (\(languageName))"

    Logger.settings.debug("System language: code=\(languageCode), name=\(languageName)")

    let systemLanguage = Language(
      code: "system",
      displayName: displayName,
      icon: "globe")

    _cachedSystemLanguage = systemLanguage
    return systemLanguage
  }

  static func == (lhs: Language, rhs: Language) -> Bool {
    lhs.code == rhs.code
  }

  static func getAvailableLanguages() -> [Language] {
    var languages = [Language.system]

    Logger.settings.debug("Detecting available app localizations using Bundle.main.localizations")

    let bundleLocalizations = Bundle.main.localizations
    Logger.settings.debug(
      "Found \(bundleLocalizations.count) localizations in bundle: \(bundleLocalizations.joined(separator: ", "))"
    )

    for code in bundleLocalizations {
      if code == "Base" {
        continue
      }

      if !languages.contains(where: { $0.code == code }) {
        languages.append(createLanguage(for: code))
      }
    }

    if languages.count <= 1 {
      Logger.settings.debug("No localizations found in bundle, trying Localizable.xcstrings")
      tryReadXCStringsFile(into: &languages)
    }

    let languageList = languages.map { "- \($0.code): \($0.displayName)" }.joined(separator: "\n")
    Logger.settings.debug("Final language list:\n\(languageList)")

    languages.sort {
      if $0.code == "system" { return true }
      if $1.code == "system" { return false }
      return $0.displayName < $1.displayName
    }

    return languages
  }

  private static func tryReadXCStringsFile(into languages: inout [Language]) {
    guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings") else {
      Logger.settings.debug("Localizable.xcstrings not found in bundle")
      return
    }

    Logger.settings.debug("Found Localizable.xcstrings at: \(url.path)")

    let langCodes = extractLanguagesFromXCStrings(at: url)

    addLanguagesToList(codes: langCodes, languages: &languages)
  }

  private static func extractLanguagesFromXCStrings(at url: URL) -> Set<String> {
    var languageCodes = Set<String>()

    do {
      let data = try Data(contentsOf: url)
      Logger.settings.debug("Read \(data.count) bytes from file")

      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        Logger.settings.error("Failed to parse JSON from xcstrings file")
        return languageCodes
      }

      if let sourceLanguage = json["sourceLanguage"] as? String {
        Logger.settings.debug("Source language: \(sourceLanguage)")
        languageCodes.insert(sourceLanguage)
      }

      if let strings = json["strings"] as? [String: [String: Any]] {
        for (_, stringData) in strings {
          if let localizations = stringData["localizations"] as? [String: Any],
            !localizations.isEmpty
          {
            for langCode in localizations.keys {
              languageCodes.insert(langCode)
            }
          }
        }
      }

      Logger.settings.debug(
        "Found language codes in xcstrings: \(languageCodes.joined(separator: ", "))")
    } catch {
      Logger.settings.error("Error reading .xcstrings file: \(error, privacy: .public)")
    }

    return languageCodes
  }

  private static func addLanguagesToList(codes: Set<String>, languages: inout [Language]) {
    for code in codes where !languages.contains(where: { $0.code == code }) {
      languages.append(createLanguage(for: code))
    }
  }

  private static func createLanguage(for code: String) -> Language {
    let locale = Locale(identifier: code)
    let displayName = locale.localizedString(forIdentifier: code) ?? code
    return Language(code: code, displayName: displayName)
  }

  static func applyLanguage(_ language: Language) {
    Logger.settings.debug("Changing language to: \(language.code)")

    if language.code == "system" {
      Logger.settings.debug("Removing AppleLanguages key to use system default")
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    } else {
      Logger.settings.debug("Setting AppleLanguages to: [\(language.code)]")
      UserDefaults.standard.set([language.code], forKey: "AppleLanguages")
    }

    UserDefaults.standard.synchronize()
    resetBundleLocalization()
    NotificationCenter.default.post(name: Notification.Name("LanguageDidChange"), object: nil)

  }

  private static func resetBundleLocalization() {
    // Refreshes some text in place; the rest updates after a relaunch.
    let value = UserDefaults.standard.object(forKey: "AppleLanguages")
    let languages = value as? [String] ?? Locale.preferredLanguages

    Logger.settings.debug("Attempting to refresh localization with languages: \(languages)")

    _ = Bundle.main.localizations
    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
  }

  static func restartApp() {
    #if os(macOS)
      let url = Bundle.main.bundleURL
      let task = Process()
      task.launchPath = "/usr/bin/open"
      task.arguments = ["-n", url.path]

      UserDefaults.standard.set(true, forKey: "AppIsRestarting")
      UserDefaults.standard.synchronize()

      // Give UserDefaults time to sync before quitting.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        task.launch()
        NSApplication.shared.terminate(nil)
      }
    #else
      // iOS can't relaunch itself; the change applies on the next launch.
      UserDefaults.standard.set(true, forKey: "LanguageChangePending")
      UserDefaults.standard.synchronize()
    #endif
  }
}
