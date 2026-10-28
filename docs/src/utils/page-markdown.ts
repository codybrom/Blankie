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

/** Output path for a page's Markdown twin, relative to the build directory. */
export function markdownPathFor(pathname: string): string {
  const trimmed = pathname.replace(/^\/+|\/+$/g, "");
  return `${trimmed || "index"}.md`;
}

/**
 * Converts a built page's <main> to Markdown, or returns null for pages that
 * shouldn't get a twin (redirects, noindex pages and pages without <main>).
 */
export function pageToMarkdown(html: string, url: string): string | null {
  const root = parse(html);
  if (root.querySelector('meta[http-equiv="refresh"]')) return null;
  const robots = root.querySelector('meta[name="robots"]');
  if (robots?.getAttribute("content")?.includes("noindex")) return null;

  const main = root.querySelector("main");
  if (!main) return null;

  // Decorative layers (background video, poster art) carry no content.
  for (const el of main.querySelectorAll('[aria-hidden="true"]')) el.remove();

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

  if (!/^# /m.test(body)) {
    const title = root.querySelector("title")?.text.trim();
    if (title) body = `# ${title}\n\n${body}`;
  }

  return `${body}\n\nSource: ${url}\n`;
}
