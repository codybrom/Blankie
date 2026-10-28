// Writes a Markdown twin of every built page (/faq/ gets /faq.md) so agents can
// read clean text instead of parsing HTML.

import type { AstroIntegration } from "astro";
import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { markdownPathFor, pageToMarkdown } from "../utils/page-markdown";

export default function markdownPages(): AstroIntegration {
  let site = "";

  return {
    name: "markdown-pages",
    hooks: {
      "astro:config:done": ({ config }) => {
        site = (config.site ?? "").replace(/\/$/, "");
      },
      "astro:build:done": async ({ dir, pages, logger }) => {
        let written = 0;
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
          written++;
        }
        logger.info(`Wrote ${written} Markdown page twins`);
      },
    },
  };
}
