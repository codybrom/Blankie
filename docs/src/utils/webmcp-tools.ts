// The site's WebMCP tools, kept free of DOM registration so they can be tested.
// Each one reads files the site already serves: llms.txt is the page index and
// every page has a Markdown twin.

import { markdownPathFor } from "./markdown-path";

const SITE = "https://blankie.rest";

export interface IndexedPage {
  title: string;
  url: string;
  description: string;
  section: string;
}

/** Every page link in llms.txt, with the section it's listed under. */
export function parseLlmsIndex(llms: string): IndexedPage[] {
  const pages: IndexedPage[] = [];
  let section = "";
  for (const line of llms.split("\n")) {
    if (line.startsWith("## ")) section = line.slice(3).trim();
    const link = line.match(
      /^- \[([^\]]+)\]\((https:\/\/blankie\.rest\/[^)\s]*)\)(?::\s*(.*))?$/,
    );
    if (link)
      pages.push({
        title: link[1],
        url: link[2],
        description: link[3]?.trim() ?? "",
        section,
      });
  }
  return pages;
}

/** Pages whose title, description or section contain every word of the query. */
export function findPages(pages: IndexedPage[], query = ""): IndexedPage[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return pages;
  return pages.filter((page) => {
    const text =
      `${page.title} ${page.description} ${page.section}`.toLowerCase();
    return words.every((word) => text.includes(word));
  });
}

/**
 * Resolves a page path or blankie.rest URL to a same-site path, or null for
 * anything off the site or pointing at a file rather than a page.
 */
export function sitePath(input: string): string | null {
  let url: URL;
  try {
    url = new URL(input, SITE);
  } catch {
    return null;
  }
  if (url.origin !== SITE) return null;
  if (/\.[a-z0-9]+$/i.test(url.pathname)) return null;
  return url.pathname.endsWith("/") ? url.pathname : `${url.pathname}/`;
}

/** Where a page's Markdown twin is served. */
export function markdownUrlFor(path: string): string {
  return `/${markdownPathFor(path)}`;
}

export const DOWNLOADS = {
  appStore: {
    url: "https://apps.apple.com/app/blankie/id6740096581",
    platforms: "iPhone, iPad, Mac and CarPlay",
    requires: "iOS or iPadOS 26.4 or later, or macOS 26 or later",
  },
  homebrew: {
    command: "brew install --cask blankie",
    url: "https://formulae.brew.sh/cask/blankie",
    platforms: "Mac",
  },
  github: {
    url: "https://github.com/codybrom/blankie/releases/latest",
    platforms: "Mac",
  },
  testFlight: {
    url: "https://testflight.apple.com/join/XgpBpWv8",
    note: "Public beta for trying new features before they ship.",
  },
  price: "Free, with no in-app purchases, ads, subscriptions or accounts.",
};
