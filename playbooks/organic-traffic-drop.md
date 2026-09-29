# Organic traffic drop

## Context

Use this when a tenant's organic sessions or clicks show a visible drop — someone noticed
it in a dashboard, a client asked "why did traffic fall", or a scheduled check flags a
period-over-period decline. It does not assume the cause; it's the procedure for finding
one before proposing a fix.

## Questions

Answer these, in order, before writing anything down:

1. Is the drop in **brand** search, **non-brand** search, or both? These have different
   causes and different owners, so this split happens before anything else.
2. Is the drop **sitewide** or concentrated in specific queries / pages?
3. Did **clicks and impressions** fall together (a visibility problem) or did clicks fall
   while impressions held (a CTR / SERP-feature problem)?
4. Does the GSC drop show up as a matching drop in **GA4 sessions on the same landing
   pages** — or does GSC show a click drop that GA4 doesn't corroborate (a tracking
   problem), or the reverse (a GA4-only drop, meaning GSC still sees the clicks)?
5. Is there a plausible **non-SEO explanation** — seasonality, a site change, a tracking
   change, a bot traffic spike or cleanup — before reaching for "we lost rankings"?

## Queries

Replace `<site>`, `<property-id>` and the date ranges with the tenant's actual values —
never hardcode real ones in this file.

**1. Brand vs non-brand split, current vs prior period**, in GSC:

`analytics_query` takes **one** date range per call, so run it twice — once per period:

```
mcp__search-console-mcp__analytics_query
  siteUrl: <site>
  dimensions: [query]
  startDate: <period-start>
  endDate: <period-end>
  engine: google
```

Bucket queries into brand (containing the tenant's brand terms) and non-brand, sum
clicks/impressions per bucket per period, and compare.

Two caveats, both documented in `docs/05-usage.md`:

- **The freshest days are missing.** This tool hardcodes `dataState: "final"`, so the
  last few days are excluded and can read as a false drop. Confirm any recent-looking
  drop with `analytics_compare` (`mode: "drop_attribution"`), which does include fresh
  data, before you believe it.
- **Ask for enough rows.** The default is 1000; pass `rowLimit` (up to 25,000) on a
  large site, or the query long tail is truncated and the brand vs non-brand split skews.

**2. Drill to page level** for whichever bucket dropped:

```
mcp__search-console-mcp__analytics_query
  siteUrl: <site>
  dimensions: [page]
  startDate: <period-start>
  endDate: <period-end>
  engine: google
  filters: [{dimension: query, operator: contains|excludingRegex, expression: <brand terms>}]
```

Again once per period. `filters` is a flat array of `{dimension, operator, expression}`
objects — the server wraps each one in its own `dimensionFilterGroups` entry, so multiple
filters are joined by AND.

This tells you whether the drop is sitewide (many pages down a little) or concentrated
(a few pages down a lot) — different next steps for each.

**3. Cross-check against GA4 landing pages**, for the same pages and periods:

```
mcp__analytics-mcp__run_report
  property_id: <property-id>
  date_ranges: [{start_date: <period-start>, end_date: <period-end>}]
  dimensions: [landingPage]
  metrics: [sessions, ecommercePurchases, purchaseRevenue]
  dimension_filter: {field_name: landingPage, string_filter: {value: <page-path>, match_type: PARTIAL_REGEXP}}
```

Compare GA4 `sessions` on the same landing pages against the GSC `clicks` trend for the
same period. They should move together; if they don't, that mismatch is itself the
diagnosis (see Interpretation).

**4. Indexing / crawl sanity check**, if pages themselves look affected:

```
mcp__search-console-mcp__inspection_inspect   siteUrl: <site>  inspectionUrl: <page>
mcp__search-console-mcp__sitemaps_list        siteUrl: <site>
mcp__search-console-mcp__seo_audit            siteUrl: <site>
```

## Interpretation

Rule out hypotheses in this order — cheapest and most common first:

1. **Broken tracking.** GSC clicks fell but GA4 sessions on the same landing pages did
   not (or vice versa). Check for a recent GTM/GA4 config change, a consent-mode change,
   or a GSC property verification issue before assuming any real traffic change happened.
2. **Bot / junk traffic.** A prior spike (not the current drop) inflated the baseline you
   are comparing against — the "drop" is really a return to normal after a scraper or
   referral-spam spike. Check the comparison period for anomalous sessions with no
   matching GSC impressions.
3. **Seasonality.** Compare against the same period last year, not just the immediately
   preceding period. B2B sites often show weekly dips (weekends) and holiday-driven
   yearly cycles that look alarming week-over-week but are routine year-over-year.
4. **Indexing and crawl.** Pages returning errors, deindexed, or newly blocked by
   robots.txt; a sitemap that stopped updating; a crawl-budget problem from a recent
   faceted-navigation or parameter change. The Step 4 queries above catch this.
5. **Ranking loss.** Impressions held but clicks and average position both fell for the
   affected queries — a real ranking drop, not a visibility or tracking artifact. Check
   whether it's isolated to specific queries/pages (content, competition, cannibalization)
   or sitewide.
6. **Algorithm update.** Sitewide ranking loss with no site-side cause found, whose timing
   in the query-level position data lines up with a known/suspected Google update. This is
   the conclusion of last resort — reach it only after 1–5 are ruled out, because it's the
   one hypothesis that offers no direct remedy.

## Output

A short note in the tenant's `analysis/` folder (e.g.
`analysis/2026-08-organic-drop.md`), stating:

- **Hypothesis**: which of the six above is supported, and whether it's brand or
  non-brand, sitewide or concentrated.
- **Evidence**: the specific numbers from the Queries section that support it (period
  comparison, brand/non-brand split, GSC vs GA4 cross-check, indexing status).
- **What would falsify it**: the check that, if it came back differently, would change the
  conclusion — so a follow-up analysis knows exactly what to re-verify if the picture
  changes.
