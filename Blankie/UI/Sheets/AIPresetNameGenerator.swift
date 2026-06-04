//
//  AIPresetNameGenerator.swift
//  Blankie
//
//  Created by Cody Bromley on 11/24/25.
//

import Foundation
import os

#if canImport(FoundationModels) && !os(macOS)
  import FoundationModels
#endif

/// Generates preset names using Apple's Foundation Models.
public enum AIPresetNameGenerator {
  #if canImport(FoundationModels) && !os(macOS)
    @Generable(description: "A short, memorable preset name")
    struct AIPresetName {
      @Guide(description: "2-4 word preset name based on mood and atmosphere")
      var name: String
    }
  #endif

  /// Checks if Foundation Models are available on this device.
  public static var isAvailable: Bool {
    #if canImport(FoundationModels) && !os(macOS)
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

    #if canImport(FoundationModels) && !os(macOS)
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
            The person's locale is \(currentLocale.identifier).
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
}
