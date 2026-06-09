//
//  AIPresetNameGenerator.swift
//  Blankie
//
//  Created by Cody Bromley on 11/24/25.
//

import Foundation
import os

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Generates preset names using Apple's Foundation Models.
public enum AIPresetNameGenerator {
  #if canImport(FoundationModels)
    @Generable(description: "A short, memorable preset name")
    struct AIPresetName {
      @Guide(description: "2-4 word preset name based on mood and atmosphere")
      var name: String
    }

    @Generable(description: "A clean display name for an ambient sound")
    struct AISoundName {
      @Guide(
        description:
          "1-3 word Title Case display name without extensions, numbers, dates, or underscores")
      var name: String
    }
  #endif

  #if canImport(FoundationModels)
    /// Locale guidance per Apple's "Supporting languages and locales" article:
    /// the exact trained locale phrase (skipped for U.S. English) plus an
    /// explicit output-language directive.
    private static var localeInstructions: String {
      let locale = Locale.current
      guard !Locale.Language(identifier: "en_US").isEquivalent(to: locale.language) else {
        return ""
      }
      // Keep the script for Chinese ("Chinese, Simplified" vs "Chinese,
      // Traditional" — the bare language name lets the model emit the wrong
      // glyphs); every other shipping language reads fine without it.
      let script = locale.language.script?.identifier
      let languageID =
        (script == "Hans" || script == "Hant")
        ? "\(locale.language.languageCode?.identifier ?? "zh")-\(script ?? "")"
        : locale.language.minimalIdentifier
      let language =
        Locale(identifier: "en_US").localizedString(forIdentifier: languageID)
        ?? locale.identifier
      return """
        The person's locale is \(locale.identifier).
        You MUST respond in \(language).
        """
    }
  #endif

  /// Checks if Foundation Models are available on this device.
  public static var isAvailable: Bool {
    #if canImport(FoundationModels)
      let model = SystemLanguageModel(useCase: .general)
      return model.isAvailable && model.supportsLocale(Locale.current)
    #else
      return false
    #endif
  }

  /// Generates a preset name using Foundation Models, or returns empty string.
  /// - Parameters:
  ///   - selectedSounds: Array of sound names that are selected
  ///   - allowVariation: If true, generates a varied/creative name
  /// - Returns: AI-generated preset name or empty string
  public static func generateName(from selectedSounds: [String], allowVariation: Bool = false) async
    -> String
  {
    guard !selectedSounds.isEmpty else {
      return ""
    }

    #if canImport(FoundationModels)
      // Initialize model for general content generation
      let model = SystemLanguageModel(useCase: .general)

      // Check if Foundation Models are available on this device
      guard model.isAvailable, case .available = model.availability else {
        return ""
      }

      // Verify locale is supported
      let currentLocale = Locale.current
      guard model.supportsLocale(currentLocale) else {
        Logger.ui.debug("AIPresetNameGenerator: Locale \(currentLocale.identifier) not supported")
        return ""
      }

      do {
        // Create session with instructions including locale
        let session = LanguageModelSession(
          model: model,
          instructions: Instructions {
            """
            Create short preset names (2-4 words) based on sound combinations.
            Focus on mood and atmosphere.
            \(localeInstructions)
            """
          }
        )

        // Build prompt
        let soundList = selectedSounds.joined(separator: ", ")
        let prompt = "Generate a\(allowVariation ? " creative" : "") preset name for: \(soundList)"

        // Generate structured response with default settings
        let response = try await session.respond(
          to: prompt,
          generating: AIPresetName.self
        )

        // Validate and return
        let name = response.content.name
        guard !name.isEmpty, name.count <= 40 else {
          return ""
        }

        return name
      } catch let error as LanguageModelSession.GenerationError {
        // Handle specific Foundation Models errors
        switch error {
        case .refusal(let refusal, _):
          Logger.ui.debug("AIPresetNameGenerator: Model refused request")
          if let explanation = try? await refusal.explanation {
            Logger.ui.debug("   Reason: \(String(describing: explanation))")
          }
        case .guardrailViolation:
          Logger.ui.debug("AIPresetNameGenerator: Guardrail violation detected")
        case .unsupportedLanguageOrLocale(let locale):
          Logger.ui.debug(
            "AIPresetNameGenerator: Unsupported locale: \(String(describing: locale))")
        case .exceededContextWindowSize(let size):
          Logger.ui.debug(
            "AIPresetNameGenerator: Context too large: \(String(describing: size)) tokens")
        case .assetsUnavailable(let reason):
          Logger.ui.debug(
            "AIPresetNameGenerator: Model assets unavailable: \(String(describing: reason))")
        case .unsupportedGuide(let guide):
          Logger.ui.debug("AIPresetNameGenerator: Unsupported guide: \(String(describing: guide))")
        case .decodingFailure(let description):
          Logger.ui.error(
            "AIPresetNameGenerator: Decoding failure: \(String(describing: description), privacy: .public)"
          )
        case .rateLimited(let retryAfter):
          Logger.ui.debug(
            "AIPresetNameGenerator: Rate limited, retry after: \(String(describing: retryAfter))")
        case .concurrentRequests:
          Logger.ui.debug(
            "AIPresetNameGenerator: Concurrent requests detected - session already responding")
        @unknown default:
          Logger.ui.error("AIPresetNameGenerator: Unknown error: \(error, privacy: .public)")
        }
        return ""
      } catch {
        Logger.ui.error("AIPresetNameGenerator: Unexpected error: \(error, privacy: .public)")
        return ""
      }
    #else
      return ""
    #endif
  }

  /// Clean display name (+ optionally an icon) for an imported sound, derived
  /// from its raw file name ("WoodThrushinMorningShawneeForestMay272012.wav" →
  /// ("Wood Thrush", "bird.fill")). `includingIcon: false` skips the icon
  /// passes entirely (edit mode renames without touching a deliberately
  /// chosen icon). Returns ("", nil) on failure.
  public static func generateSoundDetails(
    fromFileName fileName: String, includingIcon: Bool = true
  ) async -> (name: String, icon: String?) {
    guard !fileName.isEmpty else { return ("", nil) }

    #if canImport(FoundationModels)
      let model = SystemLanguageModel(useCase: .general)
      guard model.isAvailable, case .available = model.availability,
        model.supportsLocale(Locale.current)
      else { return ("", nil) }

      do {
        let session = LanguageModelSession(
          model: model,
          instructions: Instructions {
            """
            Given an ambient sound's raw file name, produce a clean
            human-readable display name: strip extensions, underscores,
            numbers, dates, locations, and technical jargon — keep what the
            sound is.
            \(localeInstructions)
            """
          }
        )

        Logger.ui.debug(
          "AIPresetNameGenerator: naming from file '\(fileName)' (icon: \(includingIcon))"
        )
        let name = try await session.respond(
          to: "Name this sound file: \(fileName)",
          generating: AISoundName.self
        ).content.name
        Logger.ui.debug(
          "AIPresetNameGenerator: name for '\(fileName)' = '\(name)'"
        )
        guard !name.isEmpty, name.count <= 40 else {
          Logger.ui.debug("AIPresetNameGenerator: name rejected (empty or > 40 chars)")
          return ("", nil)
        }

        return (name, includingIcon ? try await pickIcon(for: name) : nil)
      } catch {
        // Secondary nicety — a debug line beats the preset path's full error
        // taxonomy here.
        Logger.ui.debug(
          "AIPresetNameGenerator: Sound detail generation failed: \(error, privacy: .public)")
        return ("", nil)
      }
    #else
      return ("", nil)
    #endif
  }

  /// Picks the catalog SF Symbol that best depicts a sound name, or nil.
  public static func generateSoundIcon(for soundName: String) async -> String? {
    let name = soundName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }

    #if canImport(FoundationModels)
      let model = SystemLanguageModel(useCase: .general)
      guard model.isAvailable, case .available = model.availability,
        model.supportsLocale(Locale.current)
      else { return nil }

      do {
        return try await pickIcon(for: name)
      } catch {
        Logger.ui.debug(
          "AIPresetNameGenerator: Icon generation failed: \(error, privacy: .public)")
        return nil
      }
    #else
      return nil
    #endif
  }

  #if canImport(FoundationModels)
    /// Two constrained picks — category (18 options), then a symbol from that
    /// category's icons (staged because all 1,440 symbols at once would blow
    /// the context window). Each pick uses Apple's documented runtime-choice
    /// pattern: a DynamicGenerationSchema property whose anyOf lists the
    /// options, serialized into the prompt by the framework in the canonical
    /// format the model is trained on. (Hand-rolled variants both failed:
    /// hiding the schema picked the alphabetically-first option, and a bare
    /// top-level string enum sent "Fire" to Tools symbols.) Default sampling
    /// on purpose — the re-roll button should offer a different take, not
    /// the same answer forever.
    ///
    /// Context budget: each stage runs in a FRESH session (transcripts
    /// accumulate — the carried-over session blew the 4,096-token window at
    /// 5,238 once Nature's 278-symbol enum was injected; dotted symbol names
    /// tokenize expensively), and ".fill" twins are deduped from the choices
    /// to roughly halve the enum.
    private static func pickIcon(for name: String) async throws -> String? {
      let model = SystemLanguageModel(useCase: .general)
      // Deliberately no localeInstructions: the choices are English SF Symbol
      // and category names, so steering output toward another language would
      // fight the constrained pick.
      func freshSession() -> LanguageModelSession {
        LanguageModelSession(
          model: model,
          instructions: Instructions {
            "You pick icons for sounds in an ambient sound app."
          }
        )
      }

      func choiceSchema(property: String, choices: [String]) throws -> GenerationSchema {
        try GenerationSchema(
          root: DynamicGenerationSchema(
            name: "Choice",
            properties: [
              DynamicGenerationSchema.Property(
                name: property,
                schema: DynamicGenerationSchema(name: property, anyOf: choices)
              )
            ]
          ),
          dependencies: []
        )
      }

      Logger.ui.debug(
        "AIPresetNameGenerator: picking category for '\(name)' from \(IconData.categoryNames.count) options"
      )
      let categoryContent = try await freshSession().respond(
        to: "Pick the icon category that best fits an ambient sound named \"\(name)\".",
        schema: try choiceSchema(property: "category", choices: IconData.categoryNames)
      ).content
      let category = try categoryContent.value(String.self, forProperty: "category")
      Logger.ui.debug(
        "AIPresetNameGenerator: category for '\(name)' = '\(category, privacy: .public)'"
      )

      guard let categoryIcons = IconData.iconCategories[category], !categoryIcons.isEmpty
      else {
        Logger.ui.debug(
          "AIPresetNameGenerator: no icons for category '\(category, privacy: .public)'")
        return nil
      }

      // Drop ".fill" variants whose base glyph is also offered — same picture,
      // half the tokens. A lone ".fill" (no base in the category) stays.
      let bases = Set(categoryIcons.filter { !$0.hasSuffix(".fill") })
      let choices = categoryIcons.filter {
        !$0.hasSuffix(".fill") || !bases.contains(String($0.dropLast(5)))
      }
      Logger.ui.debug(
        "AIPresetNameGenerator: picking symbol from \(choices.count) of \(categoryIcons.count) '\(category, privacy: .public)' icons (~\(choices.joined(separator: ",").count) chars)"
      )

      let symbolContent = try await freshSession().respond(
        to: "Pick the SF Symbol that best depicts an ambient sound named \"\(name)\".",
        schema: try choiceSchema(property: "symbol", choices: choices)
      ).content
      let symbol = try symbolContent.value(String.self, forProperty: "symbol")
      Logger.ui.debug(
        "AIPresetNameGenerator: symbol for '\(name)' = '\(symbol, privacy: .public)'"
      )

      // The constraint guarantees catalog membership; verify anyway.
      return IconData.allIcons.contains(symbol) ? symbol : nil
    }
  #endif
}
