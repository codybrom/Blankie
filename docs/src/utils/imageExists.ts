import fs from "node:fs";
import path from "node:path";

/**
 * True when a site-absolute /images/... path has a file in public/, so guides can
 * show a placeholder until a screenshot lands. Build-time only; resolved from the
 * project root because import.meta.url doesn't survive the SSR bundle.
 */
export function imageExists(src: string | undefined): src is string {
  if (!src) return false;
  return fs.existsSync(path.join(process.cwd(), "public", src));
}
