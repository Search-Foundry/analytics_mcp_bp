# 1. Google Cloud setup

This project reads GA4 and Google Search Console data through two MCP servers. Both
authenticate as a Google user, via a Google Cloud project you control. This page walks
through creating that project once.

## Why a user OAuth flow, not a service account

GA4 and Search Console grant access to *people* (or to a service account you explicitly
add as a user/viewer on each property). Search Console in particular has no concept of
"grant this service account read access" in its normal sharing UI — you would have to add
the service account's email as a verified owner or user of every site, which most people
never bother to do and which does not scale across tenants. The simpler and more common
path is to let the MCP servers act as *you*: they read Application Default Credentials
(ADC) produced by a normal `gcloud auth application-default login`, scoped to your Google
account. Whatever GA4 properties and GSC sites your account can already see, the servers
can see too — no separate sharing step per property.

The trade-off is that this flow is subject to Google's RAPT re-login policy — see
`03-auth-and-rapt.md`.

## Reducing the blast radius

The ADC this hub generates necessarily carries `cloud-platform` alongside the two
readonly scopes — gcloud forces it, see `03-auth-and-rapt.md`, and that's not
optional. What *is* under your control is how much that broad credential can reach:

- **Use a Google Cloud project dedicated to this hub**, not an existing production
  project — the project below, "1. Create or choose a Google Cloud project", should be
  one you'd be unbothered losing, not one that also hosts production infrastructure.
- **Consider a dedicated Google account** for the login in `03-auth-and-rapt.md`,
  granted only Viewer on the specific GA4 properties and Search Console sites it needs
  — not your own primary account with broader access across the organization.
- **Grant the minimum GA4/GSC privileges that still allow reading** — Viewer, not
  Editor or Owner, on each property and site.

The reasoning in one sentence: an ADC carrying `cloud-platform` is a broad credential by
construction, so what it can reach should be kept small.

## 1. Create or choose a Google Cloud project

Any project works, including a free-tier one with no billing enabled — this project only
calls read-only Analytics and Search Console APIs, not billed compute. If you don't have
one yet, create it in the [Google Cloud console](https://console.cloud.google.com/projectcreate)
or with the CLI:

```
gcloud projects create my-analytics-hub --name="My Analytics Hub"
```

Note the project ID — you'll put it in `.env` as `GCP_PROJECT_ID`.

## 2. Enable the three required APIs

```
gcloud services enable analyticsadmin.googleapis.com analyticsdata.googleapis.com searchconsole.googleapis.com --project=my-analytics-hub
```

`scripts/setup.sh` runs this same command for you as part of its bootstrap sequence, once
`.env` has `GCP_PROJECT_ID` filled in. `scripts/doctor.sh` checks it afterward
(`gcp-apis` — see `99-troubleshooting.md#apis-not-enabled`).

## 3. Configure the OAuth consent screen

In the console: **APIs & Services > OAuth consent screen**.

- **Internal** — if your Google account belongs to a Google Workspace organization, choose
  this. Internal apps don't need Google's review and their refresh tokens don't expire on
  a fixed schedule.
- **External** — available to anyone, but while the app is in *testing* mode (the default,
  before you submit it for verification), refresh tokens issued under it expire after
  **7 days**. For a personal or small-team setup that's usually fine — you'll just be
  re-running `reconnect.sh` more often — but it's worth knowing why credentials that used
  to work suddenly stop.

Either way, add your own Google account (and any teammate's) under **Test users** if the
screen is External and still in testing.

## 4. Create a Desktop app OAuth client

Still under **APIs & Services**, go to **Credentials > Create credentials > OAuth client
ID**.

- **Application type: Desktop app.** Not "Web application" — a desktop client is designed
  for exactly this pattern (a CLI tool opening a browser for consent, then storing tokens
  locally), and it doesn't require you to register redirect URIs.
- Give it any name, e.g. `analytics-mcp-blueprint`.
- Click **Create**, then **Download JSON**.

## 5. Save the client JSON

Save the downloaded file where `.env`'s `OAUTH_CLIENT_FILE` expects it — by default
`.secrets/oauth-client.json`, relative to the repo root:

```
mkdir -p .secrets && mv ~/Downloads/client_secret_*.json .secrets/oauth-client.json
```

The `.secrets/` directory is gitignored. Never commit this file — it's your OAuth client
credential, not a per-user token, but it's still not meant to be public.

## Next

Before running setup, install the GA4 MCP server — it's a separate Python package, not
something `setup.sh` installs for you:

```
pipx install analytics-mcp==0.7.0
```

See `02-mcp-servers.md` for details on both servers. Then run `./scripts/setup.sh`. It
checks prerequisites (including `analytics-mcp` above — it stops with this same command
if it's missing), creates `.env` from `.env.example` if missing, enables the three APIs,
and — once it finds the OAuth client JSON in place — generates your first ADC credentials
by calling `reconnect.sh`.
