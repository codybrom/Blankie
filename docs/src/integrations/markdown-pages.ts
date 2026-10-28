// Writes a Markdown twin of every built page (/faq/ gets /faq.md) so agents can
// read clean text instead of parsing HTML, plus llms-full.txt with every page
// in one file.

import { type AstroIntegration } from "astro";
import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import {
  markdownBody,
  markdownPathFor,
  pageToMarkdown,
} from "../utils/page-markdown";

export default function markdownPages(): AstroIntegration {
  let site = "";

  return {
    name: "markdown-pages",
    hooks: {
      "astro:config:done": ({ config }) => {
        site = (config.site ?? "").replace(/\/$/, "");
      },
      "astro:build:done": async ({ dir, pages, logger }) => {
        const bodies = new Map<string, string>();
        for (const { pathname } of pages) {
          const htmlFile = fileURLToPath(new URL(`${pathname}index.html`, dir));
          if (!existsSync(htmlFile)) continue;

          const markdown = pageToMarkdown(
            await readFile(htmlFile, "utf8"),
            `${site}/${pathname}`,
          );
          if (!markdown) continue;

          await writeFile(
            fileURLToPath(new URL(markdownPathFor(pathname), dir)),
            markdown,
          );
          bodies.set(pathname, markdownBody(markdown));
        }

        // Homepage first, then every other page in path order.
        const paths = [...bodies.keys()].sort((a, b) =>
          a === "" ? -1 : b === "" ? 1 : a.localeCompare(b),
        );
        await writeFile(
          fileURLToPath(new URL("llms-full.txt", dir)),
          `# Blankie\n\n> Every page of ${site} in one file. The index is ${site}/llms.txt.\n\n${paths.map((p) => bodies.get(p)).join("\n---\n\n")}`,
        );
        logger.info(
          `Wrote ${bodies.size} Markdown page twins and llms-full.txt`,
        );
      },
    },
  };
}
