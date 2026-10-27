import ISO6391 from "iso-639-1-plus";
import creditsJson from "../../../Blankie/credits.json";

export function getLanguageName(localeCode: string): string {
  if (localeCode === "en") {
    return "English (Source)";
  }

  const baseCode = localeCode.split("-")[0];

  if (ISO6391.validate(baseCode)) {
    const baseName = ISO6391.getName(baseCode);

    const regionVariants: Record<string, string> = {
      "en-GB": "English (United Kingdom)",
      "pt-PT": "Portuguese (Portugal)",
      "zh-Hans": "Chinese, Simplified",
      "zh-Hant": "Chinese, Traditional",
    };

    return regionVariants[localeCode] || baseName;
  }

  return localeCode;
}

export function getNativeLanguageName(localeCode: string): string {
  const baseCode = localeCode.split("-")[0];

  if (ISO6391.validate(baseCode)) {
    const nativeName = ISO6391.getNativeName(baseCode);

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

export function getTranslatorCredits(langCode: string): string[] {
  // credits.json is keyed by native language name.
  const nativeName = getNativeLanguageName(langCode);

  const translators = creditsJson.translators as Record<string, string[]>;
  return translators[nativeName] || [];
}
