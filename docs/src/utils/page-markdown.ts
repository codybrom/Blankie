// Builds the Markdown twin of a rendered page, served at the page's URL with
// .md in place of the trailing slash (/guides/sleep-timer/ is served as
// /guides/sleep-timer.md).

import { NodeHtmlMarkdown } from "node-html-markdown";
import { parse } from "node-html-parser";

const converter = new NodeHtmlMarkdown({
  // In-page nav is jump links only (FAQ and guide index tables of contents).
  ignore: [
    "script",
    "style",
    "svg",
    "video",
    "noscript",
    "button",
    "form",
    "nav",
  ],
  maxConsecutiveNewlines: 2,
});

export { markdownPathFor } from "./markdown-path";

/** Points agents reading any page at the site index. */
export const LLMS_TXT_DIRECTIVE =
  "> For an index of every page on this site, see [llms.txt](https://blankie.rest/llms.txt). Every page also has a Markdown version like this one.";

/**
 * Converts a built page's <main> to Markdown with a frontmatter block (title,
 * description and canonical URL) and the llms.txt directive, or returns null
 * for pages that shouldn't get a twin (redirects, noindex pages and pages
 * without <main>).
 */
export function pageToMarkdown(html: string, url: string): string | null {
  const root = parse(html);
  if (root.querySelector('meta[http-equiv="refresh"]')) return null;
  const robots = root.querySelector('meta[name="robots"]');
  if (robots?.getAttribute("content")?.includes("noindex")) return null;

  const main = root.querySelector("main");
  if (!main) return null;

  // Decorative layers (background video, poster art) carry no content, and
  // data-markdown="skip" marks screen reader text that only describes them.
  for (const el of main.querySelectorAll(
    '[aria-hidden="true"], [data-markdown="skip"]',
  ))
    el.remove();

  // Absolute URLs keep links working when the Markdown is read on its own.
  const origin = new URL(url).origin;
  for (const [selector, attr] of [
    ["a[href]", "href"],
    ["img[src]", "src"],
  ] as const) {
    for (const el of main.querySelectorAll(selector)) {
      const value = el.getAttribute(attr);
      if (value?.startsWith("/") && !value.startsWith("//"))
        el.setAttribute(attr, `${origin}${value}`);
    }
  }

  let body = converter
    .translate(main.innerHTML)
    // Images with empty alt text are decorative.
    .replace(/^!\[\]\([^)]*\)\s*$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  const title = root.querySelector("title")?.text.trim();
  if (!/^# /m.test(body) && title) body = `# ${title}\n\n${body}`;

  const description = root
    .querySelector('meta[name="description"]')
    ?.getAttribute("content");
  const canonical =
    root.querySelector('link[rel="canonical"]')?.getAttribute("href") ?? url;
  const frontmatter = [
    title && `title: ${JSON.stringify(title)}`,
    description && `description: ${JSON.stringify(description)}`,
    `canonical: ${JSON.stringify(canonical)}`,
  ].filter(Boolean);

  return `---\n${frontmatter.join("\n")}\n---\n\n${LLMS_TXT_DIRECTIVE}\n\n${body}\n\nSource: ${url}\n`;
}

/** A page twin without its frontmatter and directive, for llms-full.txt. */
export function markdownBody(markdown: string): string {
  return markdown
    .replace(/^---\n[\s\S]*?\n---\n\n/, "")
    .replace(`${LLMS_TXT_DIRECTIVE}\n\n`, "");
}
