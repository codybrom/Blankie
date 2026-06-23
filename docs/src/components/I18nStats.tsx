import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export interface LanguageRow {
  langCode: string;
  title: string;
  subtitle: string;
  status: string;
  statusVariant: "default" | "secondary" | "outline" | "destructive";
  /** Tailwind border-color class for the mobile card accent, e.g. "border-accent". */
  accentClass: string;
  finalizedPct: number;
  reviewPct: number;
  translated: number;
  total: number;
  needsReview: number;
  detailHref: string;
}

/**
 * A single segmented progress bar: finalized (accent blue) + in-review (warm
 * gold) stacked on a contrasted track, with the remainder (needs-translation)
 * left as track. Static — widths are baked in at build time.
 */
function StackedBar({
  finalizedPct,
  reviewPct,
}: {
  finalizedPct: number;
  reviewPct: number;
}) {
  // Finalized (accent blue) + in-review (warm gold) — the site's two signature
  // accent hues, which differ in luminance so the two segments read distinctly
  // at their boundary without the edge-vibration of bright clashing colors.
  return (
    <div className="flex h-2 w-full overflow-hidden rounded-full bg-black/40">
      <div
        className="h-full shrink-0 bg-accent"
        style={{ width: `${finalizedPct}%` }}
      />
      <div
        className="h-full shrink-0 bg-warm"
        style={{ width: `${reviewPct}%` }}
      />
    </div>
  );
}

function ProgressLegend({
  finalizedPct,
  reviewPct,
  needsReview,
  className,
}: {
  finalizedPct: number;
  reviewPct: number;
  needsReview: number;
  className?: string;
}) {
  return (
    <div
      className={cn("flex flex-wrap gap-x-3 gap-y-0.5 tabular-nums", className)}
    >
      <span className="inline-flex items-center gap-1.5">
        <span className="size-2 rounded-full bg-accent" />
        {finalizedPct}% finalized
      </span>
      {needsReview > 0 && (
        <span className="text-muted-foreground inline-flex items-center gap-1.5">
          <span className="size-2 rounded-full bg-warm" />
          {reviewPct}% in review
        </span>
      )}
    </div>
  );
}

function viewButton(href: string, className = "") {
  return (
    <a
      href={href}
      className={cn(
        buttonVariants({ variant: "outline", size: "sm" }),
        className,
      )}
    >
      View Details →
    </a>
  );
}

/** Renders "12 / 100" with the slash spaced and dimmed (not the number color). */
function StringsCount({
  translated,
  total,
}: {
  translated: number;
  total: number;
}) {
  return (
    <>
      {translated}
      <span className="text-muted-foreground mx-1">/</span>
      {total}
    </>
  );
}

/**
 * Per-language translation status. Renders an information-dense table on md+
 * screens (the spreadsheet view) and reflows to readable stacked cards on
 * mobile, where a multi-column table can't fit. Static (un-hydrated) island.
 */
export function I18nStats({ rows }: { rows: LanguageRow[] }) {
  return (
    <>
      {/* Desktop / tablet: table */}
      <div className="border-border bg-card hidden overflow-hidden rounded-lg border md:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="py-3">Language</TableHead>
              <TableHead className="py-3">Status</TableHead>
              <TableHead className="w-[34%] py-3">Progress</TableHead>
              <TableHead className="py-3 text-right">Strings</TableHead>
              <TableHead className="py-3 text-right">Details</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.langCode}>
                <TableCell className="py-4 align-top">
                  <div className="font-medium">{r.title}</div>
                  <div className="text-muted-foreground mt-0.5 text-xs">
                    {r.subtitle} ·{" "}
                    <code className="text-accent-ink">{r.langCode}</code>
                  </div>
                </TableCell>
                <TableCell className="py-4 align-top">
                  <Badge variant={r.statusVariant}>{r.status}</Badge>
                </TableCell>
                <TableCell className="py-4 align-top">
                  <StackedBar
                    finalizedPct={r.finalizedPct}
                    reviewPct={r.reviewPct}
                  />
                  <ProgressLegend
                    finalizedPct={r.finalizedPct}
                    reviewPct={r.reviewPct}
                    needsReview={r.needsReview}
                    className="text-muted-foreground mt-1.5 text-xs"
                  />
                </TableCell>
                <TableCell className="py-4 text-right align-top text-sm tabular-nums">
                  <div>
                    <StringsCount translated={r.translated} total={r.total} />
                  </div>
                  {r.needsReview > 0 && (
                    <div className="text-muted-foreground text-xs">
                      {r.needsReview} need review
                    </div>
                  )}
                </TableCell>
                <TableCell className="py-4 text-right align-top">
                  {viewButton(r.detailHref)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      {/* Mobile: stacked cards (a table can't fit a phone) */}
      <div className="grid grid-cols-1 gap-4 md:hidden">
        {rows.map((r) => (
          <div
            key={r.langCode}
            className={cn(
              "border-border bg-card rounded-lg border border-l-4 p-4",
              r.accentClass,
            )}
          >
            <div className="flex items-start justify-between gap-2">
              <div>
                <div className="text-lg font-semibold">{r.title}</div>
                <div className="text-muted-foreground mt-0.5 text-sm">
                  {r.subtitle} ·{" "}
                  <code className="text-accent-ink">{r.langCode}</code>
                </div>
              </div>
              <Badge variant={r.statusVariant}>{r.status}</Badge>
            </div>

            <div className="mt-4">
              <div className="mb-1.5 flex items-center justify-between text-sm">
                <ProgressLegend
                  finalizedPct={r.finalizedPct}
                  reviewPct={r.reviewPct}
                  needsReview={r.needsReview}
                />
                <span className="tabular-nums">
                  <StringsCount translated={r.translated} total={r.total} />
                </span>
              </div>
              <StackedBar
                finalizedPct={r.finalizedPct}
                reviewPct={r.reviewPct}
              />
            </div>

            {viewButton(r.detailHref, "mt-4 w-fit")}
          </div>
        ))}
      </div>
    </>
  );
}
