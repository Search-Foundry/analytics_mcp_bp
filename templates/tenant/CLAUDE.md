# {{TENANT_NAME}}

Project-specific context for this tenant. Claude Code loads this file when working in
this folder. Keep it short and factual: it is read on every session.

## Identity

| Property | Value |
|---|---|
| Google account | {{ACCOUNT_EMAIL}} |
| GA4 property ID | {{GA4_PROPERTY_ID}} |
| GSC site | {{GSC_SITE_URL}} |

## What this site is

<!-- One paragraph: what the business does, who the audience is, what "good" looks like. -->

## Known quirks

<!-- Seasonality, bot traffic, tracking gaps, migrations - anything that would make an
     analyst misread the numbers. Add to this list as you learn. -->

## Folder conventions

- `data/` - raw exports, gitignored
- `exports/` - generated CSV/reports, gitignored
- `analysis/` - written findings, committed
