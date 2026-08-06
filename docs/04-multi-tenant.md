# 4. Multi-tenant layout

## Make it yours: detach from the blueprint

The moment you clone this repo to start a real hub, the clone's `origin` remote still
points at the blueprint's own public repository. If you start putting client data into
that clone and later run a plain `git push` out of habit, you publish client work to the
blueprint's repository, not your own. Before any client data goes in, detach it:

```
rm -rf .git && git init
```

or, if you'd rather keep the local history:

```
git remote remove origin
```

Using git for the hub at all is optional — see "The filesystem is the primary channel"
below, this hub is designed to work fine without it. But if you do keep the hub under
git, treat that as a decision with a consequence: the repository must be private. Nothing
in `accounts/` is gitignored (see below), so a public repository at this point means
public client data.

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

`accounts/` itself, the root `CLAUDE.md`, and `analysis/` are deliberately **not**
gitignored. That's not an oversight: see "The filesystem is the primary channel" below for
why, and "Credentials never live in a tenant or account folder" for the one thing that
must never end up in them regardless.

## The filesystem is the primary channel

Most people using this blueprint never push it anywhere — they clone it, adapt it, and
run it locally. For them, git is tooling, not the safety mechanism for client data: the
real way a tenant's work moves around is the filesystem itself. Someone zips
`accounts/me@example.com/acme/` and emails it to a colleague; a company backup job picks
up the whole hub directory on its normal schedule; a laptop gets replaced and the folder
is copied over wholesale. None of that touches git.

This works because a tenant folder is self-contained. Everything needed to make sense of
`accounts/<email>/<tenant>/` on its own — away from the hub, on someone else's machine —
lives inside it:

- **`CLAUDE.md`** — the tenant's identity (Google account, GA4 property ID, GSC site),
  what the business is, and known quirks that would make an analyst misread the numbers.
  This is what lets the folder stand alone: open it in Claude Code by itself and the
  context is still there.
- **`data/`** — raw GA4/GSC exports, regenerated on demand, gitignored.
- **`exports/`** — generated CSV/reports, regenerated on demand, gitignored.
- **`analysis/`** — written findings and conclusions, the one subfolder meant to be
  committed if you keep the hub in git at all.

Before zipping or handing off a tenant folder, check two things: that no credential file
has been dropped into it for convenience (see the rule below — it should never happen,
but a folder about to leave your machine is exactly when it's worth a second look), and
that `data/`/`exports/` don't contain anything you didn't mean to share (they're
gitignored, not access-controlled — gitignore doesn't stop a zip from including them).

## Credentials never live in a tenant or account folder

This is already true by construction — `reconnect.sh` writes ADC either to gcloud's
default location or under `.secrets/gcloud/<email>/` at the hub root (see
`03-auth-and-rapt.md`) — but it's worth stating as a rule, because a tenant folder about
to be zipped and handed to a colleague is exactly the situation where someone is tempted
to drop a credential JSON next to the data "for convenience." Don't. Credentials live only
at the hub root under `.secrets/`, or in gcloud's own config directory — never inside
`accounts/<email>/<tenant>/` or `accounts/<email>/`. A tenant folder must be safe to zip
and send without a second thought about what's mixed in with it.

## See also

`03-auth-and-rapt.md` for how per-account credentials are generated and wired into
`~/.claude.json` — the multi-tenant folder layout here mirrors that same per-account split.
