// JSON-LD builders for the content pages. Emitted via
// <script is:inline type="application/ld+json"> in the page templates.

import blankieLogo from "../assets/blankie-icon-v2.png";

const SITE = "https://blankie.rest";

const publisher = {
  "@type": "Organization",
  name: "Blankie",
  url: SITE,
  logo: { "@type": "ImageObject", url: `${SITE}${blankieLogo.src}` },
};

const author = {
  "@type": "Person",
  name: "Cody Bromley",
  url: "https://github.com/codybrom",
};

export function breadcrumbLd(items: { name: string; path: string }[]) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: items.map((item, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: item.name,
      item: `${SITE}${item.path}`,
    })),
  };
}

export function articleLd(opts: {
  type: "TechArticle" | "Article";
  title: string;
  description: string;
  path: string;
  updated?: Date;
  image?: string;
}) {
  return {
    "@type": opts.type,
    headline: opts.title,
    description: opts.description,
    mainEntityOfPage: `${SITE}${opts.path}`,
    ...(opts.image ? { image: `${SITE}${opts.image}` } : {}),
    ...(opts.updated
      ? {
          dateModified: opts.updated.toISOString().slice(0, 10),
          datePublished: opts.updated.toISOString().slice(0, 10),
        }
      : {}),
    author,
    publisher,
  };
}

/**
 * Blankie's App Store rating as of June 19, 2026
 */
export const APP_RATING = { value: 4.8, count: 57 };

/** Blankie itself, for pages whose subject is the app. */
export function softwareAppLd(opts?: { withRating?: boolean }) {
  return {
    "@type": "SoftwareApplication",
    name: "Blankie",
    operatingSystem:
      "iOS 26.0 or later, macOS 26.0 or later, iPadOS 26.0 or later",
    applicationCategory: "Ambient sound mixer",
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    ...(opts?.withRating
      ? {
          aggregateRating: {
            "@type": "AggregateRating",
            ratingValue: APP_RATING.value,
            ratingCount: APP_RATING.count,
            bestRating: 5,
          },
        }
      : {}),
    url: SITE,
    downloadUrl: "https://apps.apple.com/app/blankie/id6740096581",
    license: "https://opensource.org/license/mit",
    author,
  };
}

/** FAQPage node built from the rendered Q&A pairs (answers may contain HTML). */
export function faqPageLd(items: { question: string; answer: string }[]) {
  return {
    "@type": "FAQPage",
    mainEntity: items.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: { "@type": "Answer", text: item.answer },
    })),
  };
}

/** Wrap graph nodes in the schema.org envelope, ready for JSON.stringify. */
export function ldGraph(...nodes: object[]) {
  return { "@context": "https://schema.org", "@graph": nodes };
}

/** "June 2026" style display date for visible freshness lines. */
export function displayMonth(date: Date) {
  return date.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}
