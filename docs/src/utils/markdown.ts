import { marked } from "marked";
import markedAlert from "marked-alert";

// Shared, single marked configuration for the site. This module is evaluated
// once (ESM singleton), so the extensions below are registered exactly once
// even when imported by multiple pages.

// GitHub-style alerts ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]).
// Icons are stripped and titles uppercased to match the site's existing alert
// design; the markup is styled via `.markdown-alert` / `.markdown-alert-title`
// in global.css.
marked.use(
  markedAlert({
    variants: [
      { type: "note", icon: "", title: "NOTE" },
      { type: "tip", icon: "", title: "TIP" },
      { type: "important", icon: "", title: "IMPORTANT" },
      { type: "warning", icon: "", title: "WARNING" },
      { type: "caution", icon: "", title: "CAUTION" },
    ],
  }),
);

// Strip inline `{#id}` markers from heading text.
marked.use({
  walkTokens: (token) => {
    if (token.type === "heading") {
      token.tokens?.forEach((t) => {
        if (t.type === "text") {
          t.text = t.text.replace(/\{#[\w-]+\}/, "");
        }
      });
    }
  },
});

/** Render a Markdown string to HTML using the shared marked configuration. */
export function renderMarkdown(markdown: string): string {
  return marked(markdown) as string;
}
