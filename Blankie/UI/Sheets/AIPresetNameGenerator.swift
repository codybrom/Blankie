import Foundation

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
        debugLog("AIPresetNameGenerator: Locale \(currentLocale.identifier) not supported")
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
          debugLog("AIPresetNameGenerator: Model refused request")
          if let explanation = try? await refusal.explanation {
            debugLog("   Reason: \(explanation)")
          }
        case .guardrailViolation:
          debugLog("AIPresetNameGenerator: Guardrail violation detected")
        case .unsupportedLanguageOrLocale(let locale):
          debugLog("AIPresetNameGenerator: Unsupported locale: \(locale)")
        case .exceededContextWindowSize(let size):
          debugLog("AIPresetNameGenerator: Context too large: \(size) tokens")
        case .assetsUnavailable(let reason):
          debugLog("AIPresetNameGenerator: Model assets unavailable: \(reason)")
        case .unsupportedGuide(let guide):
          debugLog("AIPresetNameGenerator: Unsupported guide: \(guide)")
        case .decodingFailure(let description):
          debugLog("AIPresetNameGenerator: Decoding failure: \(description)")
        case .rateLimited(let retryAfter):
          debugLog("AIPresetNameGenerator: Rate limited, retry after: \(retryAfter)")
        case .concurrentRequests:
          debugLog(
            "AIPresetNameGenerator: Concurrent requests detected - session already responding")
        @unknown default:
          debugLog("AIPresetNameGenerator: Unknown error: \(error)")
        }
        return ""
      } catch {
        debugLog("AIPresetNameGenerator: Unexpected error: \(error)")
        return ""
      }
    #else
      return ""
    #endif
  }
}
