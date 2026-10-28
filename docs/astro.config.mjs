// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";
import react from "@astrojs/react";
import markdownPages from "./src/integrations/markdown-pages.ts";

const buildTime = new Date().toISOString();

// https://astro.build/config
export default defineConfig({
  integrations: [
    sitemap({
      // Per-language translation-status pages are contributor tools, kept out
      // of search with noindex.
      filter: (page) => !/\/i18n\/[^/]+\/$/.test(page),
      serialize(item) {
        item.lastmod = buildTime;
        return item;
      },
    }),
    react(),
    markdownPages(),
  ],
  site: "https://blankie.rest",
  output: "static",
  trailingSlash: "always",
  redirects: {
    "/features": "/",
    "/contributing":
      "https://github.com/codybrom/Blankie/tree/main?tab=contributing-ov-file#contributing-to-blankie",
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
