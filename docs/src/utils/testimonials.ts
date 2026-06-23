import star from "lucide-static/icons/star.svg?raw";

/** One App Store review, quoted verbatim. The quote and translation are the
 * reviewer's words: never rewrite them during a voice pass. Where a review
 * continues past the quoted part, the trim is marked with an ellipsis. */
export interface Testimonial {
  id: string;
  /** Verbatim quote in the reviewer's original language, kept as the record. */
  quote: string;
  /** English translation. When present it's displayed INSTEAD of the
   * original, with a "translated from X" note in the byline, so non-English
   * text never interrupts an English page. */
  translation?: string;
  /** Language the review was written in, for the translation note. */
  language?: string;
  /** Star rating the reviewer left (1 to 5). */
  stars: 1 | 2 | 3 | 4 | 5;
  /** Storefront the review was left on, displayed as written. */
  store: string;
  /** Reviewer nickname, kept only when it reads like a name; otherwise the
   * attribution falls back to "App Store review". */
  author?: string;
}

// Curated from public App Store reviews (App Store Connect export, June 2026).
export const testimonials: Testimonial[] = [
  {
    id: "straightforward",
    quote:
      "I want rain sounds, it makes rain sounds. I don’t want anything else, I don’t have to have anything else. I wish more software was this straightforward.",
    stars: 5,
    store: "United States",
  },
  {
    id: "youtube-tabs",
    quote:
      "Wish I could rate it higher, perfect lightweight solution compared to having several YouTube tabs open",
    stars: 5,
    store: "United States",
  },
  {
    id: "coworking",
    quote:
      "Anyone who works in a co-working space or office should download this immediately! So relaxing!",
    stars: 5,
    store: "United Kingdom",
  },
  {
    id: "best-tool",
    quote:
      "This app is the best I have ever seen. I am very grateful to the author of the app, you have given me an excellent tool for concentration and completing my tasks. Thank you very much!",
    stars: 5,
    store: "Russia",
  },
  {
    id: "macht-genau",
    quote: "Macht genau was es soll - ganz großes Lob ♥️",
    translation: "Does exactly what it’s supposed to. The highest praise ♥️",
    language: "German",
    stars: 5,
    store: "Germany",
  },
  {
    id: "very-apple",
    quote: "Enjoying using this a lot, it’s very 'Apple'…",
    stars: 5,
    store: "United Kingdom",
  },
  {
    id: "blanket-linux",
    quote: "So happy to have found this app as I also use Blanket on linux",
    stars: 5,
    store: "United States",
  },
  {
    id: "blanket-linux-es",
    quote:
      "Echaba de menos la app Blanket que uso en Linux, esta es perfecta para MacOS, ya que esta inspirada en ella.",
    translation:
      "I missed the Blanket app I use on Linux. This one is perfect for macOS, since it’s inspired by it.",
    language: "Spanish",
    stars: 5,
    store: "Spain",
  },
  {
    id: "noizio-mixes",
    quote: "I find the sound combinations more pleasing than even paid Noizio.",
    stars: 4,
    store: "United States",
  },
  {
    id: "free-quality",
    quote:
      "Super tolle App. 1. Kostenfrei ohne In-App-Käufe. :D 2. Qualitativ echt hochwertige Geräusche. :) 3. Nach belieben einstellbar. :D",
    translation:
      "Super great app. 1. Free with no in-app purchases. :D 2. Genuinely high-quality sounds. :) 3. Adjustable however you like. :D",
    language: "German",
    stars: 5,
    store: "Germany",
  },
  {
    id: "simple-efficace",
    quote:
      "Ce n’est pas nouveau mais cette fois c’est sobre et agréable à l’œil.",
    translation:
      "It’s not new, but this time it’s understated and easy on the eye.",
    language: "French",
    stars: 5,
    store: "France",
  },
];

const byId = new Map(testimonials.map((t) => [t.id, t]));

/** Look up a testimonial, failing the build loudly on a typo'd id. */
export function getTestimonial(id: string): Testimonial {
  const t = byId.get(id);
  if (!t) {
    throw new Error(
      `Unknown testimonial id "${id}" — see utils/testimonials.ts`,
    );
  }
  return t;
}

const esc = (s: string) =>
  s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

/** Drop lucide-static's per-file license comment, same as utils/markdown.ts. */
const starGlyph = star
  .replace(/<!--[\s\S]*?-->/g, "")
  .trim()
  .replace('fill="none"', 'fill="currentColor"');

const starsRow = (stars: number) => {
  const glyphs = Array.from({ length: 5 }, (_, i) =>
    starGlyph.replace(
      /<svg(\s)/,
      `<svg class="${i < stars ? "review-quote-star" : "review-quote-star-empty"}" aria-hidden="true"$1`,
    ),
  ).join("");
  return `<div class="review-quote-stars" role="img" aria-label="Rated ${stars} out of 5 stars">${glyphs}</div>`;
};

/** Render a testimonial as a card-styled <figure>, shared between the
 * Testimonial component and the `{{review:id}}` markdown extension so quote
 * cards look the same everywhere. Styled via `.review-quote` in global.css. */
export function renderTestimonial(t: Testimonial): string {
  const quote = t.translation ?? t.quote;
  const attribution = [
    t.author ? `${esc(t.author)} • App Store` : "App Store review",
    esc(t.store),
    ...(t.translation ? [`translated from ${esc(t.language ?? "")}`] : []),
  ].join(" • ");
  return (
    `<figure class="review-quote">` +
    starsRow(t.stars) +
    `<blockquote><p>“${esc(quote)}”</p></blockquote>` +
    `<figcaption>${attribution}</figcaption>` +
    `</figure>`
  );
}
