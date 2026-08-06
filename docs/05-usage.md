# 5. Using the MCP tools

This page documents the tool surface as of `search-console-mcp` v2 and `analytics-mcp`
v0.7.0. Ask Claude Code to use these tools directly in conversation — you don't call them
yourself.

## search-console-mcp: the v2 fluent domain tools

v2 consolidated what used to be roughly 96 individual tools into **7 fluent domain
tools**, each covering one area and taking a mode/action parameter to select the specific
operation within it:

- `sites_list` — list and manage verified sites.
- `analytics_query` — Search Console performance data (clicks, impressions, CTR,
  position), sliced by page, query, country, device, date, and more.
- `seo_audit` — cannibalization, striking-distance queries, low-CTR opportunities, and
  similar analysis built on top of `analytics_query` data.
- `indexing_submit` — submit URLs for indexing/removal.
- `inspection_inspect` — URL inspection (indexing status, canonical, mobile usability).
- `sitemaps_list` — list, submit, and inspect sitemaps.
- `site_health_check` — a rollup health check across a site.

The legacy, pre-v2 tools (the ~96 narrower ones) still exist for backward compatibility,
but new work should go through the 7 domain tools above.

### `analytics_query` details worth knowing

- Row limit parameter is **`limit`**, not `rowLimit`. Default is 1000, maximum is 25,000.
- `dataState: "all"` includes fresh/preliminary Search Console data (Google's data is
  normally finalized a few days late); the default is `"final"`, i.e. finalized data only.
  Use `"all"` when you need the most recent days even if they might still shift slightly.
- Page/query filters take an `operator`: `equals`, `contains`, `includingRegex`,
  `excludingRegex`.
- `format: "csv"` returns a compact CSV instead of JSON — useful when you're pulling a
  large table and don't need nested structure.

## analytics-mcp: GA4

The main tool is `run_report`. Its fields are **snake_case**, matching the underlying GA4
Data API more closely than a typical camelCase JS wrapper would: `date_ranges`,
`dimension_filter`, `string_filter`, `match_type`.

For organic traffic by landing page, use the `landingPage` dimension together with
metrics like `sessions`, `ecommercePurchases`, and `purchaseRevenue`. A typical filter to
scope to a specific page or path uses `dimension_filter` with a `string_filter` set to
`match_type: PARTIAL_REGEXP` against `landingPage`.

Example shape (illustrative, not exhaustive):

```
run_report(property_id="123456789", date_ranges=[{"start_date":"30daysAgo","end_date":"today"}], dimensions=["landingPage"], metrics=["sessions","ecommercePurchases","purchaseRevenue"], dimension_filter={"filter":{"field_name":"landingPage","string_filter":{"match_type":"PARTIAL_REGEXP","value":"/blog/"}}})
```
