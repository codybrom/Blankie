// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import playformCompress from "@playform/compress";
import sitemap from "@astrojs/sitemap";
import react from "@astrojs/react";

// Get current build time
const buildTime = new Date().toISOString();

// https://astro.build/config
export default defineConfig({
  integrations: [
    sitemap({
      serialize(item) {
        // Add lastmod to all pages based on build time
        item.lastmod = buildTime;
        return item;
      },
    }),
    playformCompress(),
    react(),
  ],
  site: "https://blankie.rest",
  output: "static",
  trailingSlash: "always",
  redirects: {
    "/contributing":
      "https://github.com/codybrom/Blankie/tree/main?tab=contributing-ov-file#contributing-to-blankie",
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
