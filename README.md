# analytics-mcp-blueprint

Italiano: [README.it.md](README.it.md)

A repo template for a local, multi-tenant analytics hub: GA4 and Google Search Console,
driven by [Claude Code](https://claude.com/claude-code) through two MCP servers
(`analytics-mcp` and `search-console-mcp`). Clone it, run the setup script, and start
asking Claude about your sites' organic traffic.

This is a **blueprint to clone**, not a library to install. Fork or `git clone` it, make
it yours, and keep your tenants' data in your own copy — nothing here talks to a shared
backend.

## What you need

- A Google account with GA4 and Search Console access (Viewer is enough) to the sites you
  want to analyze.
- A Google Cloud project you control, to host an OAuth client and enable three APIs.
- [Node.js 22+](https://nodejs.org) and [gcloud](https://cloud.google.com/sdk/docs/install).
- [Python 3](https://www.python.org/) with [pipx](https://pipx.pypa.io/), to install the
  GA4 MCP server: `pipx install analytics-mcp==0.7.0`. `setup.sh` checks for it and stops with
  this exact command if it's missing — see `docs/02-mcp-servers.md`.

## Quickstart

```
git clone https://github.com/<you>/analytics-mcp-blueprint.git my-hub
cd my-hub
rm -rf .git && git init
cp CLAUDE.md.template CLAUDE.md
./scripts/setup.sh
# paste the printed MCP config block into ~/.claude.json, then in Claude Code: /mcp
./scripts/new-tenant.sh acme --account me@example.com --ga4 <id> --gsc <url>
```

`setup.sh` walks you through the rest interactively: checking prerequisites, creating
`.env`, enabling the Google Cloud APIs, generating credentials, and printing the MCP
config block to paste into `~/.claude.json`.

### Make it yours

This clone becomes your working hub — the folder where client data will live. `rm -rf
.git && git init` above detaches it from the blueprint's own repository, so an
absent-minded `git push` later can't publish client work there; removing the `origin`
remote (`git remote remove origin`) does the same job if you'd rather keep the history.
Using git for the hub at all is optional — the filesystem is the primary channel this is
designed around, see `docs/04-multi-tenant.md` — but if you do keep it in git, the
repository must be private.

## The `accounts/<email>/<tenant>/` hierarchy

Credentials are per Google account, and the same tenant name may legitimately exist under
two different accounts — so tenants live nested under the account they're accessed with,
not in a single flat `tenants/` folder. Each `accounts/<email>/` folder owns its own
`CLAUDE.md` listing that account's tenants; the hub's own `CLAUDE.md` (from
`CLAUDE.md.template`) lists accounts, not tenants. Details: `docs/04-multi-tenant.md`.

## The daily cost: a ~24h re-login

gcloud forces the `cloud-platform` scope, which activates Google's RAPT policy: roughly
every 24 hours, both MCP servers start answering with `invalid_rapt`, `invalid_grant`,
`reauthentication needed`, or `401`, and the fix is to run `./scripts/reconnect.sh`
(it opens a browser — this is a step only you can do) and then `/mcp` in Claude Code.
This is expected, not a bug. Full explanation: `docs/03-auth-and-rapt.md`.

## Documentation

- `docs/01-google-cloud-setup.md` — creating the Google Cloud project, APIs, OAuth client.
- `docs/02-mcp-servers.md` — installing and configuring both MCP servers.
- `docs/03-auth-and-rapt.md` — shared ADC, the three scopes, RAPT, multi-account setups.
- `docs/04-multi-tenant.md` — the `accounts/<email>/<tenant>/` layout in full.
- `docs/05-usage.md` — the MCP tool surface: GSC's 7 fluent domain tools, GA4 report fields.
- `docs/06-bing-future.md` — the bundled Bing Webmaster Tools surface, out of scope for now.
- `docs/07-windows.md` — running under WSL today, what a native port would need.
- `docs/99-troubleshooting.md` — one section per `doctor.sh` check.

## Contributing

Run the test suite before opening a PR:

```
bash tests/run.sh
```

It has no external dependencies — plain Bash assertions, no test framework to install.
Scripts are POSIX-ish Bash for portability (see the constraints in
`docs/07-windows.md`): no `sed -i ''`, `realpath`, `readlink -f`, `jq`, or `eval`.

## License

MIT — see `LICENSE`.
