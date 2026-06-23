import { defineCollection } from "astro:content";
import { z } from "astro/zod";
import { glob } from "astro/loaders";

const guideSchema = z.object({
  title: z.string(),
  description: z.string(),
  category: z.enum(["basics", "import", "find", "presets"]),
  order: z.number().default(0),
  // Last meaningful content/fact check. Shown on the page and emitted as
  // dateModified in structured data.
  updated: z.coerce.date().optional(),
  // Optional device line for the article meta row, e.g. "iPhone, iPad and Mac".
  // Shown next to the read time and updated date when present.
  platforms: z.string().optional(),
});

// The FAQ is its own top-level page (src/pages/faq.astro), parsed from the
// repo-root FAQ.md. It is intentionally NOT part of this collection.
const guides = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/guides" }),
  schema: guideSchema,
});

export const collections = { guides };
