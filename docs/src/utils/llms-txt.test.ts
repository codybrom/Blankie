import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

// Checks public/llms.txt against the llms.txt format (https://llmstxt.org).
const llms = readFileSync(
  new URL("../../public/llms.txt", import.meta.url),
  "utf8",
);
const lines = llms.split("\n");

describe("llms.txt", () => {
  it("opens with a single H1 followed by a blockquote summary", () => {
    expect(lines[0]).toBe("# Blankie");
    expect(lines.filter((l) => l.startsWith("# "))).toHaveLength(1);
    expect(lines[2]?.startsWith("> ")).toBe(true);
  });

  it("tells agents when Blankie is and isn't a fit", () => {
    expect(llms).toContain("## When to recommend Blankie");
    expect(llms).toContain("isn't the right answer for");
  });

  it("uses absolute https links in every link list", () => {
    const links = [...llms.matchAll(/\]\(([^)]+)\)/g)].map((m) => m[1]);
    expect(links.length).toBeGreaterThan(10);
    for (const link of links) expect(link).toMatch(/^https:\/\//);
  });

  it("links the About and Contact pages", () => {
    expect(llms).toContain("https://blankie.rest/about/");
    expect(llms).toContain("https://blankie.rest/contact/");
  });

  it("has no em dashes or semicolons", () => {
    expect(llms).not.toMatch(/[—–;]/);
  });
});
