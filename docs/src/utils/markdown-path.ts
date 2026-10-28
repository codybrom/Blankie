/**
 * Path of a page's Markdown twin, relative to the site root: the trailing
 * slash becomes .md (guides/sleep-timer/ is guides/sleep-timer.md) and the
 * homepage is index.md. Shared by the build step and the Worker.
 */
export function markdownPathFor(pathname: string): string {
  const trimmed = pathname.replace(/^\/+|\/+$/g, "");
  return `${trimmed || "index"}.md`;
}
