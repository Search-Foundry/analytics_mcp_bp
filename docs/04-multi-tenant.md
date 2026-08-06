# 4. Multi-tenant layout

## The hierarchy

Tenants live at:

```
accounts/<email>/<tenant>/
```

A tenant folder sits inside the folder of the Google account it's accessed with — not in
a single flat `tenants/` directory. Each `accounts/<email>/` folder has its own
`CLAUDE.md`, listing that account's tenants in a table (name, GA4 property ID, GSC site,
status). The repo root itself holds only shared tooling: the `scripts/`, `templates/`,
`docs/`, and credentials under `.secrets/` — no client-specific files belong there.

## Why per-account, not flat

Credentials are per Google account (see `03-auth-and-rapt.md`): each account has its own
ADC file and its own MCP server entries in `~/.claude.json`. Nesting tenants under the
account they're accessed with keeps that relationship visible in the folder structure
itself, instead of requiring you to remember or look up which account owns which tenant.

It also resolves a naming collision that a flat layout can't: the same tenant name can
legitimately exist under two different accounts (two different clients that both happen to
be named, say, "acme" in your notes, or the same client accessed through two different
Google identities during a handover). `accounts/me@example.com/acme/` and
`accounts/other@example.com/acme/` are simply two different folders; a flat
`tenants/acme/` would force you to pick one name or the other.

## Creating a tenant

```
./scripts/new-tenant.sh acme --account me@example.com --ga4 123456789 --gsc https://example.com/
```

This copies `templates/tenant/` into `accounts/me@example.com/acme/`, substituting the
tenant name, account email, GA4 property ID and GSC site URL into its `CLAUDE.md` and
`README.md`. If `accounts/me@example.com/` doesn't exist yet, it's created first from
`templates/account/`, and the new tenant is registered as a row in that account's
`CLAUDE.md`. `--ga4` and `--gsc` are optional — omit them and the row is created with
`TBD` placeholders you fill in later.

If the hub's own `CLAUDE.md` (created from `CLAUDE.md.template`) exists at the repo root,
`new-tenant.sh` also registers this account under its `<!-- accounts -->` table — adding a
new row the first time an account gets a tenant, or appending the tenant name to that
account's existing row on subsequent runs. You never maintain that table by hand. If the
hub `CLAUDE.md` exists but is missing the `<!-- accounts -->` marker, the run fails before
touching anything (same fail-fast rule as the per-account `<!-- tenants -->` marker); if
there's no hub `CLAUDE.md` at all (e.g. running against a bare `--root` in tests), this
step is silently skipped.

Each tenant folder has three subfolders, per `templates/tenant/`:

- `data/` — raw exports, gitignored.
- `exports/` — generated CSV/reports, gitignored.
- `analysis/` — written findings, committed.

## What's gitignored and why

Anything under `.secrets/` (OAuth client JSON, per-account ADC files) is gitignored — it's
credential material, not code or documentation. Within each tenant, `data/` and `exports/`
are gitignored too: raw GA4/GSC exports and generated reports are working artifacts you
regenerate on demand, not something you want tracked and diffed in git. `analysis/` is the
one tenant subfolder meant to be committed — it's where written findings and conclusions
live, which is exactly the kind of content worth keeping in version history.

## See also

`03-auth-and-rapt.md` for how per-account credentials are generated and wired into
`~/.claude.json` — the multi-tenant folder layout here mirrors that same per-account split.
