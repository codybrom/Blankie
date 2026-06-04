import { describe, expect, it } from "vitest";
import {
  getLanguageName,
  getNativeLanguageName,
  getTranslatorCredits,
} from "./i18n-helpers";

describe("getLanguageName", () => {
  it("labels English as the source language", () => {
    expect(getLanguageName("en")).toBe("English (Source)");
  });

  it("resolves base language codes", () => {
    expect(getLanguageName("de")).toBe("German");
    expect(getLanguageName("fr")).toBe("French");
  });

  it("resolves region/script variants to their display names", () => {
    expect(getLanguageName("zh-Hans")).toBe("Chinese, Simplified");
    expect(getLanguageName("zh-Hant")).toBe("Chinese, Traditional");
    expect(getLanguageName("pt-PT")).toBe("Portuguese (Portugal)");
    expect(getLanguageName("en-GB")).toBe("English (United Kingdom)");
  });

  it("falls back to the raw code for unrecognized languages", () => {
    expect(getLanguageName("xx")).toBe("xx");
  });
});

describe("getNativeLanguageName", () => {
  it("returns native names for base codes", () => {
    expect(getNativeLanguageName("de")).toBe("Deutsch");
    expect(getNativeLanguageName("ko")).toBe("한국어");
  });

  it("returns native names for script variants", () => {
    expect(getNativeLanguageName("zh-Hans")).toBe("简体中文");
    expect(getNativeLanguageName("zh-Hant")).toBe("繁體中文");
  });

  it("falls back to the raw code for unrecognized languages", () => {
    expect(getNativeLanguageName("xx")).toBe("xx");
  });
});

describe("getTranslatorCredits", () => {
  it("finds credits keyed by native language name", () => {
    // credits.json keys are native names ("Deutsch"), looked up via locale code
    expect(getTranslatorCredits("de").length).toBeGreaterThan(0);
  });

  it("returns an empty list for languages without credits", () => {
    expect(getTranslatorCredits("xx")).toEqual([]);
  });
});
