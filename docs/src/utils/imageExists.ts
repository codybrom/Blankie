import fs from "node:fs";
import path from "node:path";

/**
 * True when a site-absolute /images/... path has a real file behind it in
 * public/. Lets guide content reference screenshots ahead of capture: the
 * article shows a "Screenshot" placeholder until the file lands, then picks it
 * up on the next build. Build-time only (static output). Resolved from the
 * project root (the bundled module's import.meta.url is useless after the SSR
 * build).
 */
export function imageExists(src: string | undefined): src is string {
  if (!src) return false;
  return fs.existsSync(path.join(process.cwd(), "public", src));
}
