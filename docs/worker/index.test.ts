import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { prefersMarkdown } from "./index";

// Stand-in for the static assets binding: serves a few files, 404s the rest.
const files: Record<string, { body: string; type: string }> = {
  "/": { body: "<h1>Blankie</h1>", type: "text/html; charset=utf-8" },
  "/faq/": { body: "<h1>FAQ</h1>", type: "text/html; charset=utf-8" },
  "/index.md": { body: "# Blankie", type: "text/markdown" },
  "/faq.md": { body: "# FAQ", type: "text/markdown" },
  "/llms.txt": { body: "# Blankie", type: "text/plain" },
};
const pressKit = new Map<string, string>();
const env = {
  BLANKIE_ASSETS: {
    async get(key: string) {
      const data = pressKit.get(key);
      if (data === undefined) return null;
      return {
        body: new Blob([data]).stream(),
        httpEtag: '"abc"',
        writeHttpMetadata(headers: Headers) {
          headers.set("Content-Type", "application/zip");
        },
      };
    },
  },
  ASSETS: {
    async fetch(input: Request | URL | string) {
      const { pathname } = new URL(
        input instanceof Request ? input.url : input,
      );
      const file = files[pathname];
      return file
        ? new Response(file.body, { headers: { "Content-Type": file.type } })
        : new Response("<h1>Page not found</h1>", {
            status: 404,
            headers: { "Content-Type": "text/html; charset=utf-8" },
          });
    },
  },
};

const get = (path: string, accept?: string, host = "blankie.rest") =>
  worker.fetch(
    new Request(`https://${host}${path}`, {
      headers: accept ? { Accept: accept } : {},
    }),
    env,
  );

describe("prefersMarkdown", () => {
  it("accepts an explicit text/markdown request", () => {
    expect(prefersMarkdown("text/markdown")).toBe(true);
    expect(prefersMarkdown("text/markdown, text/html;q=0.9")).toBe(true);
  });

  it("keeps HTML for browsers and wildcards", () => {
    expect(prefersMarkdown(null)).toBe(false);
    expect(prefersMarkdown("*/*")).toBe(false);
    expect(
      prefersMarkdown(
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ),
    ).toBe(false);
    expect(prefersMarkdown("text/html, text/markdown;q=0.5")).toBe(false);
    expect(prefersMarkdown("text/markdown;q=0")).toBe(false);
  });
});

describe("worker", () => {
  it("serves the homepage's Markdown twin with Vary: Accept", async () => {
    const res = await get("/", "text/markdown");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe(
      "text/markdown; charset=utf-8",
    );
    expect(res.headers.get("Vary")).toContain("Accept");
    expect(await res.text()).toBe("# Blankie");
  });

  it("serves HTML to browsers with Vary: Accept", async () => {
    const res = await get("/faq/", "text/html");
    expect(res.headers.get("Content-Type")).toContain("text/html");
    expect(res.headers.get("Vary")).toContain("Accept");
    expect(await res.text()).toBe("<h1>FAQ</h1>");
  });

  it("finds the twin for paths without a trailing slash", async () => {
    const res = await get("/faq", "text/markdown");
    expect(await res.text()).toBe("# FAQ");
  });

  it("returns a Markdown 404 body for missing pages", async () => {
    const res = await get("/nope/", "text/markdown");
    expect(res.status).toBe(404);
    expect(res.headers.get("Content-Type")).toBe(
      "text/markdown; charset=utf-8",
    );
    const body = await res.text();
    expect(body).toContain("# Page not found");
    expect(body).toContain("https://blankie.rest/llms.txt");
  });

  it("keeps the HTML 404 page for browsers", async () => {
    const res = await get("/nope/", "text/html");
    expect(res.status).toBe(404);
    expect(await res.text()).toContain("Page not found");
  });

  it("passes files with extensions straight through", async () => {
    const res = await get("/llms.txt", "text/markdown");
    expect(res.headers.get("Content-Type")).toBe("text/plain");
    expect(res.headers.get("Vary")).toBeNull();
  });

  it("serves the press kit zip from R2 as a download", async () => {
    pressKit.set("press/blankie-press-kit.zip", "zipdata");
    const res = await get("/blankie-press-kit.zip");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/zip");
    expect(res.headers.get("Content-Disposition")).toContain("attachment");
    expect(res.headers.get("ETag")).toBe('"abc"');
    expect(await res.text()).toBe("zipdata");
    pressKit.clear();
  });

  it("falls back to the 404 page when the press kit isn't in R2", async () => {
    const res = await get("/blankie-press-kit.zip");
    expect(res.status).toBe(404);
  });

  it("redirects www to the apex domain", async () => {
    const res = await get("/faq/?x=1", undefined, "www.blankie.rest");
    expect(res.status).toBe(301);
    expect(res.headers.get("Location")).toBe("https://blankie.rest/faq/?x=1");
  });
});

describe("request logging", () => {
  afterEach(() => vi.restoreAllMocks());

  // Everything Cloudflare knows about a visitor, as seen in invocation logs.
  const identifying = {
    ip: "203.0.113.7",
    userAgent: "Mozilla/5.0 (Macintosh) Safari/605.1.15",
    city: "Leesburg",
    postalCode: "20176",
    latitude: "39.11566",
    tlsClientCiphersSha1: "HAKT1k2tVJh0v8vnncdY2lcyZ00=",
  };

  const visit = (path: string, accept = "text/html") => {
    const request = Object.assign(
      new Request(`https://blankie.rest${path}?utm_source=x`, {
        headers: {
          Accept: accept,
          "cf-connecting-ip": identifying.ip,
          "x-real-ip": identifying.ip,
          "user-agent": identifying.userAgent,
        },
      }),
      {
        cf: {
          country: "US",
          asn: 209366,
          asOrganization: "SEMrush CY LTD",
          city: identifying.city,
          postalCode: identifying.postalCode,
          latitude: identifying.latitude,
          tlsClientCiphersSha1: identifying.tlsClientCiphersSha1,
          botManagement: { score: 99, verifiedBot: false },
          verifiedBotCategory: "Search Engine Optimization",
        },
      },
    );
    return worker.fetch(request, env);
  };

  it("logs one line of network- and bot-level fields only", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    await visit("/faq/");
    expect(log).toHaveBeenCalledTimes(1);
    const entry = log.mock.calls[0][0] as Record<string, unknown>;
    expect(Object.keys(entry).sort()).toEqual(
      [
        "asOrganization",
        "asn",
        "botScore",
        "country",
        "markdown",
        "message",
        "method",
        "path",
        "status",
        "verifiedBot",
        "verifiedBotCategory",
      ].sort(),
    );
    expect(entry).toMatchObject({
      method: "GET",
      path: "/faq/",
      status: 200,
      markdown: false,
      country: "US",
      asOrganization: "SEMrush CY LTD",
      verifiedBotCategory: "Search Engine Optimization",
    });
  });

  it("never logs anything that identifies the visitor", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    await visit("/faq/");
    await visit("/nope/", "text/markdown");
    const logged = JSON.stringify(log.mock.calls);
    for (const value of Object.values(identifying))
      expect(logged).not.toContain(value);
    expect(logged).not.toContain("utm_source");
  });

  it("marks Markdown responses for agents", async () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    await visit("/", "text/markdown");
    expect(log.mock.calls[0][0]).toMatchObject({ markdown: true, path: "/" });
  });
});
