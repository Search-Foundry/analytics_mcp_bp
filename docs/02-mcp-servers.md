# 2. The MCP servers

Two MCP servers do the actual work. Claude Code talks to both over stdio; you never call
them directly.

## analytics-mcp (GA4)

- Package: `analytics-mcp` on PyPI, version **0.7.0**.
- Upstream repo: [googleanalytics/google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp).
- Install with [pipx](https://pipx.pypa.io/), which keeps it in its own isolated
  environment instead of polluting your system Python:

```
pipx install analytics-mcp
```

After installing, the `analytics-mcp` command is on your PATH — that's what the MCP
config block below runs.

## search-console-mcp (GSC)

- Package: `search-console-mcp` on npm, version **2.0.1**.
- Run via `npx`, which downloads and caches it on first use — no separate install step:

```
npx -y search-console-mcp
```

Version 2 dropped the native `re2` dependency that plagued earlier releases (see
`99-troubleshooting.md#native-module` for that history). It does still use one native
module, `@napi-rs/keyring`, for talking to your OS credential store — if that fails to
load, see the same troubleshooting section.

v2 also exposes an HTTP/SSE transport (`search-console-mcp --transport=sse --port=3000`)
for running the server standalone and reachable over the network. This blueprint doesn't
use it — everything here runs the server as a local stdio subprocess, launched by Claude
Code itself, which is simpler to set up and doesn't require exposing a port.

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
      "args": ["-y", "search-console-mcp"],
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
