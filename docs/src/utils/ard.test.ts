import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

// Checks public/.well-known/ard.json against the ARD manifest shape
// (https://agenticresourcediscovery.org).
const catalog = JSON.parse(
  readFileSync(
    new URL("../../public/.well-known/ard.json", import.meta.url),
    "utf8",
  ),
);

describe("ard.json", () => {
  it("names the host and lists entries", () => {
    expect(catalog.specVersion).toBeTypeOf("string");
    expect(catalog.host.displayName).toBe("Blankie");
    expect(catalog.entries.length).toBeGreaterThan(0);
  });

  it("gives every entry an identifier, type, one location and queries", () => {
    for (const entry of catalog.entries) {
      expect(entry.identifier).toMatch(
        /^urn:air:blankie\.rest:[a-z-]+:[a-z-]+$/,
      );
      expect(entry.displayName).toBeTruthy();
      expect(entry.type).toMatch(/^[a-z]+\/[a-z0-9.+-]+$/);
      expect("url" in entry !== "data" in entry).toBe(true);
      expect(entry.representativeQueries.length).toBeGreaterThanOrEqual(2);
      expect(entry.representativeQueries.length).toBeLessThanOrEqual(5);
    }
  });

  it("only points at files the site serves", () => {
    for (const entry of catalog.entries)
      expect([
        "https://blankie.rest/llms.txt",
        "https://blankie.rest/llms-full.txt",
      ]).toContain(entry.url);
  });
});
