import star from "lucide-static/icons/star.svg?raw";

/** One App Store review, quoted verbatim. The quote and translation are the
 * reviewer's words: never rewrite them during a voice pass. Where a review
 * continues past the quoted part, the trim is marked with an ellipsis. */
export interface Testimonial {
  id: string;
  /** Verbatim quote in the reviewer's original language, kept as the record. */
  quote: string;
  /** English translation. When present it replaces the original on the page,
   * with a "translated from X" note in the byline. */
  translation?: string;
  /** Language the review was written in, for the translation note. */
  language?: string;
  /** Star rating the reviewer left (1 to 5). */
  stars: 1 | 2 | 3 | 4 | 5;
  /** Storefront the review was left on, displayed as written. */
  store: string;
  /** Reviewer nickname, kept only when it reads like a name. Otherwise the
   * attribution falls back to "App Store review". */
  author?: string;
}

// Curated from public App Store reviews (App Store Connect export, Oct 2026).
export const testimonials: Testimonial[] = [
  {
    id: "straightforward",
    quote:
      "I want rain sounds, it makes rain sounds. I don’t want anything else, I don’t have to have anything else. I wish more software was this straightforward.",
    stars: 5,
    store: "United States",
  },
  {
    id: "carplay-standout",
    quote:
      "Car Play feature seems to be what makes this app really stand out, especially once I realized I didn’t have to pay for any subscriptions anymore. Very cool.",
    stars: 5,
    store: "United States",
    author: "KC.Linda",
  },
  {
    id: "no-paywall-sleep",
    quote:
      "I really appreciate that you provide it without a paywall or subscription. It’s rare to find developers who care about accessibility like this. The sounds are beautiful and perfect for winding down. Thank you for helping me relax and sleep better every night!",
    stars: 5,
    store: "Russia",
  },
  {
    id: "youtube-tabs",
    quote:
      "Wish I could rate it higher, perfect lightweight solution compared to having several YouTube tabs open",
    stars: 5,
    store: "United States",
    author: "Lily Caba",
  },
  {
    id: "mix-five-sounds",
    quote:
      "…this is exactly what I was looking for : a simple app , no ads, great sleep sounds and able to mix 5 sounds together!",
    stars: 5,
    store: "Canada",
  },
  {
    id: "custom-soundscapes",
    quote:
      "Very slick and easy to mix together custom soundscapes. And incredibly customizable to make it your own. I can’t believe it’s free!",
    stars: 5,
    store: "United States",
    author: "Old Man Nik",
  },
  {
    id: "grounded-at-work",
    quote:
      "Turn it on, grab your tools and forget everything else outside. It helps me focus at work and remain grounded when idle.",
    stars: 5,
    store: "India",
  },
  {
    id: "nightly-mixes",
    quote:
      "I love this app and the flexibility of mixing the sounds. Each night I can try something different to see what works the best for me. I enjoy using it to read to as well. Gives the perfect sounds to block out the rest of my surroundings.",
    stars: 5,
    store: "United States",
  },
  {
    id: "pencil-neighbor",
    quote:
      "Absolute silence lets you hear everything, like the pencil of your neighbor, and silent noises can become loud in comparison. This app plays relaxing background noises, even several at the same time, that allow you to sink in and thus help concentrating on what you are doing.",
    stars: 5,
    store: "Germany",
  },
  {
    id: "einfach-genial",
    quote:
      "Ich mag Regen und Gewitters sehr und mit dieser App kann ich mich besser konzentrieren. Super einfach in der Anwendung zudem ohne Kosten. Absolute Empfehlung",
    translation:
      "I really like rain and thunderstorms, and with this app I can concentrate better. Super easy to use and free of charge. Absolute recommendation.",
    language: "German",
    stars: 5,
    store: "Germany",
  },
  {
    id: "simple-effective",
    quote:
      "It does exactly what it is meant to do in a simple, intuitive and effective way. Easy 5 stars.",
    stars: 5,
    store: "United States",
    author: "Jeyxero",
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
    author: "Brad Haynes",
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
    id: "free-quality",
    quote:
      "Super tolle App. 1. Kostenfrei ohne In-App-Käufe. :D 2. Qualitativ echt hochwertige Geräusche. :) 3. Nach belieben einstellbar. :D",
    translation:
      "Super great app. 1. Free with no in-app purchases. :D 2. Genuinely high-quality sounds. :) 3. Adjustable however you like. :D",
    language: "German",
    stars: 5,
    store: "Germany",
    author: "Lex G.",
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

/** Look up a testimonial, failing the build on an unknown id. */
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

/** Render a testimonial as a `.review-quote` <figure>, shared by the
 * Testimonial component and the `{{review:id}}` markdown extension. */
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
