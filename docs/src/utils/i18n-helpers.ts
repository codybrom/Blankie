import ISO6391 from "iso-639-1-plus";
import creditsJson from "../../../Blankie/credits.json";

// Get human-readable language name from locale code
export function getLanguageName(localeCode: string): string {
  // Special case for source language
  if (localeCode === "en") {
    return "English (Source)";
  }

  // Extract base language code for validation
  const baseCode = localeCode.split("-")[0];

  // Try to get the name from ISO6391 using base code
  if (ISO6391.validate(baseCode)) {
    const baseName = ISO6391.getName(baseCode);

    // Add region/variant information for specific codes
    const regionVariants: Record<string, string> = {
      "en-GB": "English (United Kingdom)",
      "pt-PT": "Portuguese (Portugal)",
      "zh-Hans": "Chinese, Simplified",
      "zh-Hant": "Chinese, Traditional",
    };

    return regionVariants[localeCode] || baseName;
  }

  // Fallback for unrecognized codes
  return localeCode;
}

// Get native language name from locale code
export function getNativeLanguageName(localeCode: string): string {
  // Extract base language code
  const baseCode = localeCode.split("-")[0];

  // Try to get the native name from ISO6391
  if (ISO6391.validate(baseCode)) {
    const nativeName = ISO6391.getNativeName(baseCode);

    // Add specific native names for variants
    const nativeVariants: Record<string, string> = {
      en: "English",
      "en-GB": "English",
      "pt-PT": "Português",
      "zh-Hans": "简体中文",
      "zh-Hant": "繁體中文",
    };

    return nativeVariants[localeCode] || nativeName;
  }

  return localeCode;
}

// Get translator credits for a language code
export function getTranslatorCredits(langCode: string): string[] {
  // Use native name to match credits.json format
  const nativeName = getNativeLanguageName(langCode);

  const translators = creditsJson.translators as Record<string, string[]>;
  return translators[nativeName] || [];
}
