// Serves the built site from Workers static assets. Agents that ask for
// Markdown (Accept: text/markdown or ?mode=agent) get each page's .md twin,
// including a Markdown body for 404s, and the homepage with ?mode=agent gets
// llms.txt. HTML pages carry Vary: Accept so caches keep the two
// representations apart, and Link headers that point agents at the Markdown
// twin, llms.txt and the sitemap. Files too large for static assets (the press kit
// zip) are served from the blankie-assets R2 bucket. Each request is logged
// with network- and bot-level fields only, never anything about the visitor.

import { markdownPathFor } from "../src/utils/markdown-path";

interface R2ObjectBody {
  body: ReadableStream;
  httpEtag: string;
  writeHttpMetadata(headers: Headers): void;
}

interface Env {
  ASSETS: { fetch(input: Request | URL | string): Promise<Response> };
  BLANKIE_ASSETS: { get(key: string): Promise<R2ObjectBody | null> };
}

const MARKDOWN = "text/markdown; charset=utf-8";
const PRESS_KIT_PATH = "/blankie-press-kit.zip";
// The ARD manifest, also served at its older ai-catalog.json name. Agents
// fetch it cross-origin, so it carries an open CORS header.
const ARD_PATH = "/.well-known/ard.json";
const AI_CATALOG_PATH = "/.well-known/ai-catalog.json";
const PRESS_KIT_KEY = "press/blankie-press-kit.zip";

/** True when Accept names text/markdown and ranks it above text/html. */
export function prefersMarkdown(accept: string | null): boolean {
  if (!accept) return false;
  let markdown = 0;
  let html = 0;
  for (const part of accept.split(",")) {
    const [type, ...params] = part.trim().toLowerCase().split(";");
    const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
    const weight = q ? Number(q.slice(2)) : 1;
    if (type === "text/markdown") markdown = weight;
    else if (type === "text/html") html = weight;
  }
  return markdown > 0 && markdown > html;
}

/** Page URLs end in a slash or have no file extension. */
function isPage(pathname: string): boolean {
  return !/\.[a-z0-9]+$/i.test(pathname.split("/").pop() ?? "");
}

/** Canonical HTML URL for a page path, with the trailing slash. */
function canonicalFor(url: URL): string {
  const trimmed = url.pathname.replace(/^\/+|\/+$/g, "");
  return `${url.origin}/${trimmed ? `${trimmed}/` : ""}`;
}

/** RFC 8288 Link header for an HTML page. */
function pageLinks(url: URL): string {
  return [
    `</${markdownPathFor(url.pathname)}>; rel="alternate"; type="text/markdown"`,
    '</llms.txt>; rel="describedby"; type="text/plain"',
    '</sitemap-index.xml>; rel="sitemap"; type="application/xml"',
  ].join(", ");
}

function withHeaders(response: Response, headers: Record<string, string>) {
  const out = new Response(response.body, response);
  for (const [name, value] of Object.entries(headers)) {
    if (name === "Vary") out.headers.append(name, value);
    else out.headers.set(name, value);
  }
  return out;
}

interface RequestCf {
  country?: string;
  asn?: number;
  asOrganization?: string;
  botManagement?: { score?: number; verifiedBot?: boolean };
  verifiedBotCategory?: string;
}

/**
 * One anonymous line per request for Workers Logs. It names the network and bot
 * class, never the person: no IP, user agent, city or TLS fingerprint.
 */
export function logRequest(request: Request, response: Response): void {
  const cf = (request as Request & { cf?: RequestCf }).cf;
  console.log({
    message: "request",
    method: request.method,
    path: new URL(request.url).pathname,
    status: response.status,
    markdown:
      response.headers.get("Content-Type")?.startsWith("text/markdown") ??
      false,
    country: cf?.country,
    asn: cf?.asn,
    asOrganization: cf?.asOrganization,
    botScore: cf?.botManagement?.score,
    verifiedBot: cf?.botManagement?.verifiedBot,
    verifiedBotCategory: cf?.verifiedBotCategory || undefined,
  });
}

function markdownNotFound(url: URL): Response {
  const body = `# Page not found

There's nothing at ${url.origin}${url.pathname}. The page may have moved, or the link may have a typo.

A summary of the site with links to every guide is at ${url.origin}/llms.txt.
`;
  return new Response(body, {
    status: 404,
    headers: { "Content-Type": MARKDOWN, Vary: "Accept" },
  });
}

async function serve(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);

  if (url.hostname === "www.blankie.rest") {
    url.hostname = "blankie.rest";
    return Response.redirect(url.toString(), 301);
  }

  const readable = request.method === "GET" || request.method === "HEAD";

  if (readable && url.pathname === PRESS_KIT_PATH) {
    const zip = await env.BLANKIE_ASSETS.get(PRESS_KIT_KEY);
    if (!zip) return env.ASSETS.fetch(request);
    const headers = new Headers();
    zip.writeHttpMetadata(headers);
    headers.set("ETag", zip.httpEtag);
    headers.set(
      "Content-Disposition",
      'attachment; filename="blankie-press-kit.zip"',
    );
    return new Response(request.method === "HEAD" ? null : zip.body, {
      headers,
    });
  }

  if (
    readable &&
    (url.pathname === AI_CATALOG_PATH || url.pathname === ARD_PATH)
  ) {
    const catalog = await env.ASSETS.fetch(new URL(ARD_PATH, url));
    return withHeaders(catalog, {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    });
  }

  if (!readable || !isPage(url.pathname)) return env.ASSETS.fetch(request);

  const agentMode = url.searchParams.get("mode") === "agent";
  const canonical = `<${canonicalFor(url)}>; rel="canonical"`;

  if (agentMode && url.pathname === "/") {
    const index = await env.ASSETS.fetch(new URL("/llms.txt", url));
    return withHeaders(index, { "Content-Type": MARKDOWN, Link: canonical });
  }

  if (agentMode || prefersMarkdown(request.headers.get("Accept"))) {
    const twin = await env.ASSETS.fetch(
      new URL(`/${markdownPathFor(url.pathname)}`, url),
    );
    if (!twin.ok) return markdownNotFound(url);
    return withHeaders(twin, {
      "Content-Type": MARKDOWN,
      Vary: "Accept",
      Link: canonical,
    });
  }

  const page = await env.ASSETS.fetch(request);
  if (page.status !== 200) return withHeaders(page, { Vary: "Accept" });
  return withHeaders(page, { Vary: "Accept", Link: pageLinks(url) });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const response = await serve(request, env);
    logRequest(request, response);
    return response;
  },
};
