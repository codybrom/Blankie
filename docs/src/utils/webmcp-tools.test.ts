import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  findPages,
  markdownUrlFor,
  parseLlmsIndex,
  sitePath,
} from "./webmcp-tools";

const llms = readFileSync(
  new URL("../../public/llms.txt", import.meta.url),
  "utf8",
);

describe("parseLlmsIndex", () => {
  const pages = parseLlmsIndex(llms);

  it("reads every page link in llms.txt with its section", () => {
    expect(pages.length).toBeGreaterThan(30);
    expect(pages).toContainEqual(
      expect.objectContaining({
        title: "Fall Asleep with the Sleep Timer",
        url: "https://blankie.rest/guides/sleep-timer/",
        section: "Guides",
      }),
    );
  });

  it("keeps links that have no description", () => {
    expect(pages).toContainEqual(
      expect.objectContaining({
        url: "https://blankie.rest/privacy/",
        description: "",
      }),
    );
  });
});

describe("findPages", () => {
  const pages = parseLlmsIndex(llms);

  it("matches every word, ignoring case", () => {
    const hits = findPages(pages, "Sleep TIMER");
    expect(hits.map((p) => p.url)).toContain(
      "https://blankie.rest/guides/sleep-timer/",
    );
    expect(findPages(pages, "sleep zzzqx")).toEqual([]);
  });

  it("lists every page for an empty query", () => {
    expect(findPages(pages, "  ")).toHaveLength(pages.length);
  });
});

describe("sitePath", () => {
  it("normalizes paths and blankie.rest URLs to a page path", () => {
    expect(sitePath("/faq")).toBe("/faq/");
    expect(sitePath("guides/sleep-timer/")).toBe("/guides/sleep-timer/");
    expect(sitePath("https://blankie.rest/press/?x=1")).toBe("/press/");
  });

  it("refuses other sites and files", () => {
    expect(sitePath("https://example.com/faq/")).toBeNull();
    expect(sitePath("//example.com/faq/")).toBeNull();
    expect(sitePath("/llms.txt")).toBeNull();
  });
});

describe("markdownUrlFor", () => {
  it("points at the page's Markdown twin", () => {
    expect(markdownUrlFor("/")).toBe("/index.md");
    expect(markdownUrlFor("/guides/sleep-timer/")).toBe(
      "/guides/sleep-timer.md",
    );
  });
});
