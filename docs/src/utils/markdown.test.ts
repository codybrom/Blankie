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

  it("strips {#id} markers from headings", () => {
    const html = renderMarkdown("## Install {#install-section}");
    expect(html).toContain("Install");
    expect(html).not.toContain("{#install-section}");
  });
});
