import { marked, type Tokens } from "marked";
import markedAlert from "marked-alert";
import { getTestimonial, renderTestimonial } from "./testimonials";
import ellipsis from "lucide-static/icons/ellipsis.svg?raw";
import layoutGrid from "lucide-static/icons/layout-grid.svg?raw";
import list from "lucide-static/icons/list.svg?raw";
import pause from "lucide-static/icons/pause.svg?raw";
import play from "lucide-static/icons/play.svg?raw";
import plus from "lucide-static/icons/plus.svg?raw";
import settings from "lucide-static/icons/settings.svg?raw";
import share from "lucide-static/icons/share.svg?raw";
import rewind from "lucide-static/icons/rewind.svg?raw";
import fastForward from "lucide-static/icons/fast-forward.svg?raw";
import star from "lucide-static/icons/star.svg?raw";
import timer from "lucide-static/icons/timer.svg?raw";
import volume2 from "lucide-static/icons/volume-2.svg?raw";
import check from "lucide-static/icons/check.svg?raw";
import x from "lucide-static/icons/x.svg?raw";
import minus from "lucide-static/icons/minus.svg?raw";
import triangleAlert from "lucide-static/icons/triangle-alert.svg?raw";

/** Token produced by the block `{{review:...}}` testimonial extension. */
interface ReviewQuoteToken extends Tokens.Generic {
  type: "reviewQuote";
  id: string;
}

/** Token produced by the inline `{{icon:...}}` glyph extension. */
interface SfSymbolToken extends Tokens.Generic {
  type: "sfSymbol";
  icon: string;
  alt: string;
}

/** Token produced by the inline `{{kbd:...}}` keycap extension. */
interface KbdToken extends Tokens.Generic {
  type: "kbd";
  keys: string;
}

/** Token produced by the inline `{{kbdicon:...}}` glyph-keycap extension. */
interface KbdIconToken extends Tokens.Generic {
  type: "kbdIcon";
  icons: string;
}

/** Drop lucide-static's per-file license comment (attribution stays in the
 * package); the ISC notice doesn't need to ship in every page's HTML. */
const normalize = (svg: string) => svg.replace(/<!--[\s\S]*?-->/g, "").trim();

/** Lucide is stroke-only; fill the shape for glyphs iOS draws solid. */
const filled = (svg: string) =>
  svg.replace('fill="none"', 'fill="currentColor"');

/** Composed play/pause glyph (triangle + two bars) in Lucide's filled style.
 * Lucide ships play and pause separately but no combined symbol, and the media
 * key prints both; one glyph keeps the keycap the same width as the others. */
const playPause = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"><path d="M4 6 4 18 12 12 Z"/><rect x="15" y="6" width="2.6" height="12" rx="1.1"/><rect x="19.4" y="6" width="2.6" height="12" rx="1.1"/></svg>`;

/** Tint a glyph by setting its CSS color. Lucide strokes with currentColor, so
 * the stroke follows. var() resolves here because it's a style property, not an
 * XML presentation attribute. Used for the semantic yes/no icons in tables. */
const tinted = (svg: string, color: string) =>
  svg.replace(/<svg(\s)/, `<svg style="color:${color}"$1`);

// Inline glyph registry for `{{icon:name}}`: Lucide SVGs (ISC), keyed by the
// names the guides use, which mirror the iOS controls they reference. Note:
// SF Symbols themselves may NOT be redistributed as web assets — that's why
// these are Lucide equivalents and not symbol renders.
const symbolSvgs: Record<string, string> = Object.fromEntries(
  Object.entries({
    plus,
    share,
    star,
    "star-fill": filled(star),
    timer,
    settings,
    more: ellipsis,
    play: filled(play),
    pause: filled(pause),
    rewind: filled(rewind),
    "fast-forward": filled(fastForward),
    "play-pause": playPause,
    grid: layoutGrid,
    list,
    speaker: volume2,
    // Semantic status glyphs for comparison tables: green check (free), red x
    // (no), muted dash for "not an issue" (e.g. credit isn't required), and an
    // amber caution for "allowed, but with a condition attached" (e.g. sharealike).
    yes: tinted(check, "var(--color-green-500)"),
    no: tinted(x, "var(--color-red-500)"),
    optional: tinted(minus, "var(--color-mid-gray)"),
    caveat: tinted(triangleAlert, "var(--color-amber-400)"),
  }).map(([name, svg]) => [name, normalize(svg)]),
);

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

// Inline UI glyphs: `{{icon:name}}` or `{{icon:name|Label}}` renders the
// matching SVG inline with the text, like the button glyphs in Apple's support
// guides. Without a label the glyph is decorative (the surrounding copy names
// the button), so it's hidden from screen readers.
marked.use({
  extensions: [
    {
      name: "sfSymbol",
      level: "inline",
      start(src: string) {
        return src.indexOf("{{icon:");
      },
      tokenizer(src: string): SfSymbolToken | undefined {
        const match = /^\{\{icon:([a-z0-9-]+)(?:\|([^}|]+))?\}\}/.exec(src);
        if (!match) return undefined;
        return {
          type: "sfSymbol",
          raw: match[0],
          icon: match[1],
          alt: match[2]?.trim() ?? "",
        };
      },
      renderer(token) {
        const { icon, alt } = token as SfSymbolToken;
        const svg = symbolSvgs[icon];
        if (!svg) {
          // Fail the build loudly on a typo'd icon name instead of rendering nothing.
          throw new Error(
            `Unknown {{icon:${icon}}} — no src/assets/symbols/${icon}.svg`,
          );
        }
        const a11yAttrs = alt
          ? `role="img" aria-label="${alt}"`
          : `aria-hidden="true"`;
        return svg.replace(
          /<svg(\s)/,
          `<svg class="inline-icon" ${a11yAttrs}$1`,
        );
      },
    },
  ],
});

// Keyboard shortcuts: `{{kbd:⌘ I}}` renders each space-separated key as a
// physical-looking keycap, so shortcuts stand out from the surrounding copy.
// Styled via `.kbd-combo` / `kbd` in global.css.
marked.use({
  extensions: [
    {
      name: "kbd",
      level: "inline",
      start(src: string) {
        return src.indexOf("{{kbd:");
      },
      tokenizer(src: string): KbdToken | undefined {
        const match = /^\{\{kbd:([^}]+)\}\}/.exec(src);
        if (!match) return undefined;
        return { type: "kbd", raw: match[0], keys: match[1] };
      },
      renderer(token) {
        const esc = (s: string) =>
          s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const caps = (token as KbdToken).keys
          .trim()
          .split(/\s+/)
          .map((key) => `<kbd>${esc(key)}</kbd>`)
          .join("");
        return `<span class="kbd-combo">${caps}</span>`;
      },
    },
  ],
});

// Glyph keycaps: `{{kbdicon:skip-back}}` renders a Lucide glyph inside a keycap,
// for keys printed with a symbol rather than a letter (the media keys). Multiple
// space-separated names sit in one cap, so `{{kbdicon:play pause}}` reads as the
// play/pause key. Reuses the {{icon:...}} registry; styled via `.kbd-iconcap`.
marked.use({
  extensions: [
    {
      name: "kbdIcon",
      level: "inline",
      start(src: string) {
        return src.indexOf("{{kbdicon:");
      },
      tokenizer(src: string): KbdIconToken | undefined {
        const match = /^\{\{kbdicon:([a-z0-9- ]+)\}\}/.exec(src);
        if (!match) return undefined;
        return { type: "kbdIcon", raw: match[0], icons: match[1] };
      },
      renderer(token) {
        const glyphs = (token as KbdIconToken).icons
          .trim()
          .split(/\s+/)
          .map((name) => {
            const svg = symbolSvgs[name];
            if (!svg) {
              throw new Error(
                `Unknown {{kbdicon:${name}}} — not in the {{icon}} registry`,
              );
            }
            return svg.replace(
              /<svg(\s)/,
              `<svg class="kbd-glyph" aria-hidden="true"$1`,
            );
          })
          .join("");
        return `<span class="kbd-combo"><kbd class="kbd-iconcap">${glyphs}</kbd></span>`;
      },
    },
  ],
});

// Verbatim App Store review quotes: `{{review:id}}` on its own line renders
// the matching testimonial from utils/testimonials.ts as a card-styled
// <figure>, the same markup the Testimonial component emits on .astro pages.
marked.use({
  extensions: [
    {
      name: "reviewQuote",
      level: "block",
      start(src: string) {
        return src.indexOf("{{review:");
      },
      tokenizer(src: string): ReviewQuoteToken | undefined {
        const match = /^\{\{review:([a-z0-9-]+)\}\}(?:\n+|$)/.exec(src);
        if (!match) return undefined;
        return { type: "reviewQuote", raw: match[0], id: match[1] };
      },
      renderer(token) {
        // getTestimonial fails the build loudly on a typo'd id.
        return renderTestimonial(
          getTestimonial((token as ReviewQuoteToken).id),
        );
      },
    },
  ],
});

// Images: `![alt](src "caption")` renders as <figure> with a <figcaption>
// (styled by the typography plugin); without a caption it stays a plain <img>.
// A paragraph that is only an image is hoisted out of its <p> wrapper, since
// <figure> can't legally nest inside <p>.
const escapeAttr = (s: string) =>
  s
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

marked.use({
  renderer: {
    paragraph(token: Tokens.Paragraph) {
      const inner = token.tokens;
      if (inner?.length === 1 && inner[0].type === "image") {
        return this.parser.parseInline(inner);
      }
      return false; // defer to the default paragraph renderer
    },
    image({ href, title, text }: Tokens.Image) {
      const img = `<img src="${escapeAttr(href)}" alt="${escapeAttr(text)}" loading="lazy" decoding="async" />`;
      if (!title) return img;
      return `<figure>${img}<figcaption>${escapeAttr(title)}</figcaption></figure>`;
    },
  },
});

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
