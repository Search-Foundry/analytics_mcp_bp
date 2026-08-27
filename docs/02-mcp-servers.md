# 2. The MCP servers

Two MCP servers do the actual work. Claude Code talks to both over stdio; you never call
them directly.

## analytics-mcp (GA4)

- Package: `analytics-mcp` on PyPI, version **0.7.0**.
- Upstream repo: [googleanalytics/google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp).
- Install with [pipx](https://pipx.pypa.io/), which keeps it in its own isolated
  environment instead of polluting your system Python:

```
pipx install analytics-mcp==0.7.0
```

After installing, the `analytics-mcp` command is on your PATH — that's what the MCP
config block below runs.

## search-console-mcp (GSC)

- Package: [`search-console-mcp`](https://www.npmjs.com/package/search-console-mcp) on npm, version **2.1.1**.
- Upstream repo: [saurabhsharma2u/search-console-mcp](https://github.com/saurabhsharma2u/search-console-mcp)
  (docs: <https://searchconsolemcp.saurabh.app/>).
- Run via `npx`, which downloads and caches it on first use — no separate install step:

```
npx -y search-console-mcp@2.1.1
```

Version 2 dropped the native `re2` dependency that plagued earlier releases (see
`99-troubleshooting.md#native-module` for that history). It does still use one native
module, `@napi-rs/keyring`, for talking to your OS credential store — if that fails to
load, see the same troubleshooting section.

v2 also exposes an HTTP/SSE transport (`search-console-mcp --transport=sse --port=3000`)
for running the server standalone and reachable over the network. This blueprint doesn't
use it — everything here runs the server as a local stdio subprocess, launched by Claude
Code itself, which is simpler to set up and doesn't require exposing a port.

## Versions are pinned on purpose

Every install and run command in this repo names an exact version:
`analytics-mcp==0.7.0` and `search-console-mcp@2.1.1`. That's deliberate, not an
oversight — `npx -y search-console-mcp` with no version would silently fetch whatever
is newest at run time, and `search-console-mcp` went from 1.14.x to 2.0.0 as a breaking
change: v2 replaced roughly 96 individual tools with 7 fluent domain tools, which is
exactly the tool surface `docs/05-usage.md` documents. An unpinned install could hand
you a different tool surface than the docs describe, with no warning.

Upgrading is a conscious act, not something that happens on the next `npx` call. To move
to a newer version: update the version string everywhere it's invoked or documented —
`scripts/setup.sh` (`print_mcp_config`), `scripts/lib/checks.sh`, this file, and
`docs/01-google-cloud-setup.md` / `docs/99-troubleshooting.md` for `analytics-mcp` — then
re-read that version's changelog and re-check `docs/05-usage.md` against it before telling
anyone to upgrade. A major-version jump (like 1.x to 2.x) can invalidate what that page
describes.

## The `~/.claude.json` config block

Both servers need `GOOGLE_APPLICATION_CREDENTIALS` pointed at your ADC file so they read
the same credentials. Rather than writing `~/.claude.json` by hand, generate the block:

```
./scripts/setup.sh --print-mcp-config
```

This prints something like:

```json
{
  "mcpServers": {
    "analytics-mcp": {
      "type": "stdio",
      "command": "analytics-mcp",
      "args": [],
      "env": { "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/application_default_credentials.json" }
    },
    "search-console-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "search-console-mcp@2.1.1"],
      "env": { "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/application_default_credentials.json" }
    }
  }
}
```

Back up `~/.claude.json`, then merge this block into it — either at the top level or
under a specific project, per Claude Code's own config scoping. `setup.sh` never edits
that file for you; merging is a manual step by design, so you don't lose whatever else is
already configured there.

If `.env` has `GSC_MCP_MODE=local` set (a troubleshooting fallback — see
`99-troubleshooting.md#native-module`), the printed block runs the locally built server
with `node` instead of `npx`.

For multi-account setups, add `--account <email>` — see `03-auth-and-rapt.md` for why each
account needs its own server entries.

## Verifying the connection

After merging the config and restarting Claude Code (or running `/mcp` inside a running
session), check that both servers show as connected:

```
/mcp
```

You should see `analytics-mcp` and `search-console-mcp` (or their `-<email>` suffixed
variants, in a multi-account setup) listed as connected, with their tools available.
`scripts/doctor.sh` also smoke-tests the Search Console server directly, independent of
Claude Code — useful when you want to know whether the problem is the server or the
Claude Code connection.
