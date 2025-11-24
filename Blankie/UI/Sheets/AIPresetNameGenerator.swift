import Foundation
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
    public static func generateName(from selectedSounds: [String], allowVariation: Bool = false) async -> String {
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
                print("⚠️ AIPresetNameGenerator: Locale \(currentLocale.identifier) not supported")
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
                case let .refusal(refusal, _):
                    print("⚠️ AIPresetNameGenerator: Model refused request")
                    if let explanation = try? await refusal.explanation {
                        print("   Reason: \(explanation)")
                    }
                case .guardrailViolation:
                    print("⚠️ AIPresetNameGenerator: Guardrail violation detected")
                case let .unsupportedLanguageOrLocale(locale):
                    print("⚠️ AIPresetNameGenerator: Unsupported locale: \(locale)")
                case let .exceededContextWindowSize(size):
                    print("⚠️ AIPresetNameGenerator: Context too large: \(size) tokens")
                case let .assetsUnavailable(reason):
                    print("⚠️ AIPresetNameGenerator: Model assets unavailable: \(reason)")
                case let .unsupportedGuide(guide):
                    print("⚠️ AIPresetNameGenerator: Unsupported guide: \(guide)")
                case let .decodingFailure(description):
                    print("⚠️ AIPresetNameGenerator: Decoding failure: \(description)")
                case let .rateLimited(retryAfter):
                    print("⚠️ AIPresetNameGenerator: Rate limited, retry after: \(retryAfter)")
                case .concurrentRequests:
                    print("⚠️ AIPresetNameGenerator: Concurrent requests detected - session already responding")
                @unknown default:
                    print("⚠️ AIPresetNameGenerator: Unknown error: \(error)")
                }
                return ""
            } catch {
                print("⚠️ AIPresetNameGenerator: Unexpected error: \(error)")
                return ""
            }
        #else
            return ""
        #endif
    }
}
