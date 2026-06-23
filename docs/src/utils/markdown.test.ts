import { describe, expect, it } from "vitest";
import { renderMarkdown } from "./markdown";

describe("renderMarkdown", () => {
  it("renders basic markdown", () => {
    const html = renderMarkdown("hello **world**");
    expect(html).toContain("<strong>world</strong>");
  });

  it("renders GitHub-style alerts with uppercased titles", () => {
    const html = renderMarkdown("> [!NOTE]\n> something important");
    expect(html).toContain("markdown-alert");
    expect(html).toContain("NOTE");
    expect(html).toContain("something important");
  });

  it("supports all five alert variants", () => {
    for (const variant of ["TIP", "IMPORTANT", "WARNING", "CAUTION"]) {
      const html = renderMarkdown(`> [!${variant}]\n> body`);
      expect(html).toContain(variant);
    }
  });

  it("renders a titled image as a figure with caption, unwrapped from <p>", () => {
    const html = renderMarkdown(
      '![The import sheet](/images/a.png "Pick a name.")',
    );
    expect(html).toContain("<figure>");
    expect(html).toContain('alt="The import sheet"');
    expect(html).toContain("<figcaption>Pick a name.</figcaption>");
    expect(html).not.toContain("<p><figure>");
  });

  it("renders an untitled image as a plain img", () => {
    const html = renderMarkdown("![alt text](/images/b.png)");
    expect(html).toContain('<img src="/images/b.png"');
    expect(html).not.toContain("<figure>");
  });

  it("escapes quotes in image captions and alt text", () => {
    const html = renderMarkdown('![say "hi"](/c.png "a \\"quoted\\" caption")');
    expect(html).toContain("&quot;");
    expect(html).not.toContain('alt="say "hi""');
  });

  it("strips {#id} markers from headings", () => {
    const html = renderMarkdown("## Install {#install-section}");
    expect(html).toContain("Install");
    expect(html).not.toContain("{#install-section}");
  });

  it("renders a review quote with stars and attribution", () => {
    const html = renderMarkdown("{{review:straightforward}}");
    expect(html).toContain('class="review-quote"');
    expect(html).toContain('aria-label="Rated 5 out of 5 stars"');
    expect(html).toContain("rain sounds");
    expect(html).toContain("App Store review • United States");
  });

  it("shows non-English reviews in English with a translation note", () => {
    const html = renderMarkdown("{{review:macht-genau}}");
    expect(html).toContain("Does exactly what it’s supposed to");
    expect(html).not.toContain("Macht genau was es soll");
    expect(html).toContain("translated from German");
  });

  it("throws on an unknown review id", () => {
    expect(() => renderMarkdown("{{review:nope}}")).toThrow(
      'Unknown testimonial id "nope"',
    );
  });
});
