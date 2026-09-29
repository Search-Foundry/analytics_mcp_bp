# 5. Using the MCP tools

This page documents the tool surface as of `search-console-mcp` 2.1.3 and `analytics-mcp`
v0.7.0. It was checked against the published package's registered tool schemas, not
against the upstream README. Ask Claude Code to use these tools directly in conversation — you don't call them
yourself.

## search-console-mcp: the v2 fluent domain tools

v2 consolidated what used to be roughly 96 individual tools into a small set of fluent
domain tools, each covering one area and taking a mode/action parameter to select the
specific operation within it. 2.1.3 registers 24; the ones this hub actually uses:

- `sites_list` / `sites_manage` — list and manage verified sites.
- `analytics_query` — Search Console performance data (clicks, impressions, CTR,
  position), sliced by page, query, country, device, date, and more.
- `analytics_compare` — period-over-period comparison, trends, drop attribution.
- `analytics_anomalies` — traffic anomaly detection.
- `seo_audit` — cannibalization, striking-distance queries, low-CTR opportunities, and
  similar analysis built on top of `analytics_query` data.
- `indexing_submit` / `indexing_status` — submit URLs for indexing and check status.
- `inspection_inspect` — URL inspection (indexing status, canonical, mobile usability).
- `sitemaps_list` / `sitemaps_submit` / `sitemaps_delete` — manage sitemaps.
- `site_health_check` — a rollup health check across a site.
- `genai_query_insights` (new in 2.1.3) — flags queries that look like AI-Mode /
  conversational fan-out. It is a heuristic over ordinary query data, not an official
  report, and it undercounts: treat its output as a lead, never as a figure for a client.

The legacy, pre-v2 tool names still resolve for backward compatibility (they are routed
onto the fluent handlers), but new work should go through the domain tools above.
2.1.x also registers `adsense_*` tools; this blueprint does not wire up AdSense, which
needs its own OAuth flow separate from the ADC credentials used here.

### `analytics_query` details worth knowing

The registered schema accepts exactly these: `siteUrl`, `startDate`, `endDate`,
`dimensions`, `filters`, `rowLimit`, `engine`. Anything else you pass is ignored.

- The row limit parameter is **`rowLimit`**: default 1000, maximum 25,000.
- **`engine` defaults to `"all"`**, which also queries Bing. Pass `engine: "google"`
  when you want Search Console alone.
- Dates default to a 28-day window ending 3 days ago if you omit them.
- Page/query filters take an `operator`: `equals`, `contains`, `includingRegex`,
  `excludingRegex`.
- There is **no `dataState` parameter**. The server hardcodes `dataState: "final"` for
  this tool, so the freshest few days of Search Console data are always excluded. Fresh
  data is reachable only through `analytics_compare` (`mode: "trends"` or
  `"drop_attribution"`), which uses `dataState: "all"` internally. Plan recent-days
  monitoring around that tool, not around `analytics_query`.
- There is **no `format` parameter**; output is JSON text.

### `rowLimit` before 2.1.3

Up to 2.1.2 the Google layer read `options.limit` while the handler forwarded `rowLimit`,
so every `analytics_query` call returned at most **1000 rows**. 2.1.3 reads
`rowLimit ?? limit ?? 1000`, so the parameter now works. If a hub still runs an older
pin, assume the 1000-row cap.

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
