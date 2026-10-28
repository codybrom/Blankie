import { describe, expect, it } from "vitest";
import {
  LLMS_TXT_DIRECTIVE,
  markdownBody,
  markdownPathFor,
  pageToMarkdown,
} from "./page-markdown";

describe("markdownPathFor", () => {
  it("swaps the trailing slash for .md", () => {
    expect(markdownPathFor("guides/sleep-timer/")).toBe(
      "guides/sleep-timer.md",
    );
    expect(markdownPathFor("faq/")).toBe("faq.md");
  });

  it("maps the homepage to index.md", () => {
    expect(markdownPathFor("")).toBe("index.md");
    expect(markdownPathFor("/")).toBe("index.md");
  });
});

const page = (head: string, main: string) =>
  `<!doctype html><html><head>${head}</head><body><header>Site nav</header><main>${main}</main><footer>Footer</footer></body></html>`;

const URL = "https://blankie.rest/guides/sleep-timer/";

describe("pageToMarkdown", () => {
  it("converts only the main content and appends the source URL", () => {
    const md = pageToMarkdown(
      page(
        "<title>Blankie - Sleep Timer</title>",
        "<h1>Sleep Timer</h1><p>Set it.</p>",
      ),
      URL,
    );
    expect(md).toContain("# Sleep Timer");
    expect(md).toContain("Set it.");
    expect(md).not.toContain("Site nav");
    expect(md).not.toContain("Footer");
    expect(md?.trimEnd().endsWith(`Source: ${URL}`)).toBe(true);
  });

  it("falls back to the page title when main has no h1", () => {
    const md = pageToMarkdown(
      page("<title>Blankie - Credits</title>", "<p>Thanks.</p>"),
      URL,
    );
    expect(markdownBody(md ?? "").startsWith("# Blankie - Credits")).toBe(true);
  });

  it("opens with frontmatter and the llms.txt directive", () => {
    const md = pageToMarkdown(
      page(
        '<title>Blankie - Sleep Timer</title><meta name="description" content="Stop on its own."><link rel="canonical" href="https://blankie.rest/guides/sleep-timer/">',
        "<h1>Sleep Timer</h1>",
      ),
      URL,
    );
    expect(
      md?.startsWith(`---
title: "Blankie - Sleep Timer"
description: "Stop on its own."
canonical: "https://blankie.rest/guides/sleep-timer/"
---

${LLMS_TXT_DIRECTIVE}

# Sleep Timer`),
    ).toBe(true);
    expect(markdownBody(md ?? "").startsWith("# Sleep Timer")).toBe(true);
  });

  it("makes site-relative links and images absolute", () => {
    const md = pageToMarkdown(
      page(
        "<title>t</title>",
        '<h1>t</h1><a href="/faq/">FAQ</a><img src="/_astro/a.webp" alt="Mixer">',
      ),
      URL,
    );
    expect(md).toContain("(https://blankie.rest/faq/)");
    expect(md).toContain("![Mixer](https://blankie.rest/");
  });

  it("drops decorative and non-content elements", () => {
    const md = pageToMarkdown(
      page(
        "<title>t</title>",
        '<h1>t</h1><div aria-hidden="true"><div><p>Decor</p></div></div><span class="sr-only" data-markdown="skip">Video of waves</span><nav><a href="#a">Jump</a></nav><script>x()</script><img src="/bg.webp" alt=""><p>Kept</p>',
      ),
      URL,
    );
    expect(md).toContain("Kept");
    expect(md).not.toContain("Decor");
    expect(md).not.toContain("Video of waves");
    expect(md).not.toContain("Jump");
    expect(md).not.toContain("x()");
    expect(md).not.toContain("bg.webp");
  });

  it("skips redirect pages", () => {
    expect(
      pageToMarkdown(
        '<html><head><meta http-equiv="refresh" content="0;url=/"></head><body><main>x</main></body></html>',
        URL,
      ),
    ).toBeNull();
  });

  it("skips noindex pages", () => {
    expect(
      pageToMarkdown(
        page('<meta name="robots" content="noindex, follow">', "<h1>x</h1>"),
        URL,
      ),
    ).toBeNull();
  });

  it("skips pages without main", () => {
    expect(
      pageToMarkdown("<html><body><p>x</p></body></html>", URL),
    ).toBeNull();
  });
});
