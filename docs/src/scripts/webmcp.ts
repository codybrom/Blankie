// Registers the site's WebMCP tools so a browser agent can search, read and
// navigate blankie.rest. Does nothing in browsers without WebMCP.
// Spec: https://webmachinelearning.github.io/webmcp/

import {
  DOWNLOADS,
  findPages,
  markdownUrlFor,
  parseLlmsIndex,
  sitePath,
} from "@/utils/webmcp-tools";

interface ModelContextTool {
  name: string;
  title?: string;
  description: string;
  inputSchema?: object;
  annotations?: { readOnlyHint?: boolean };
  execute: (input: Record<string, unknown>) => Promise<unknown>;
}

interface ModelContext {
  registerTool(
    tool: ModelContextTool,
    options?: { signal?: AbortSignal },
  ): Promise<void> | void;
}

// The spec puts modelContext on document. Early Chrome builds used navigator.
const modelContext =
  (document as Document & { modelContext?: ModelContext }).modelContext ??
  (navigator as Navigator & { modelContext?: ModelContext }).modelContext;

async function fetchText(path: string): Promise<string> {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`${path} returned ${res.status}`);
  return res.text();
}

const tools: ModelContextTool[] = [
  {
    name: "find_pages",
    title: "Find pages",
    description:
      "Search blankie.rest for guides and pages about Blankie, the free ambient sound mixer for iPhone, iPad, Mac and CarPlay. Returns each match's title, URL and summary. Leave the query empty to list every page.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Words to match, such as 'sleep timer' or 'import'.",
        },
      },
    },
    annotations: { readOnlyHint: true },
    async execute({ query }) {
      const pages = parseLlmsIndex(await fetchText("/llms.txt"));
      return findPages(pages, typeof query === "string" ? query : "");
    },
  },
  {
    name: "read_page",
    title: "Read a page",
    description:
      "Return a blankie.rest page as Markdown. Pass a path like /guides/sleep-timer/ or a full blankie.rest URL.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Page path or URL." },
      },
      required: ["path"],
    },
    annotations: { readOnlyHint: true },
    async execute({ path }) {
      const page = sitePath(String(path ?? ""));
      if (!page) return { error: "Only pages on blankie.rest can be read." };
      return { path: page, markdown: await fetchText(markdownUrlFor(page)) };
    },
  },
  {
    name: "open_page",
    title: "Open a page",
    description:
      "Navigate this tab to a page on blankie.rest, such as /guides/get-started/.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Page path or URL." },
      },
      required: ["path"],
    },
    async execute({ path }) {
      const page = sitePath(String(path ?? ""));
      if (!page) return { error: "Only pages on blankie.rest can be opened." };
      // Respond before the page unloads.
      setTimeout(() => window.location.assign(page), 0);
      return { opening: page };
    },
  },
  {
    name: "get_download_links",
    title: "Get download links",
    description:
      "Where to download Blankie: the App Store, Homebrew, GitHub releases and the public TestFlight beta, with platforms and system requirements.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
    async execute() {
      return DOWNLOADS;
    },
  },
];

if (modelContext) {
  for (const tool of tools) {
    try {
      await modelContext.registerTool(tool);
    } catch {
      // Registration fails without the tools permission. The page still works.
    }
  }
}
