---
name: reconnect
description: Use when an MCP call to analytics-mcp or search-console-mcp fails with invalid_rapt, invalid_grant, "reauthentication needed", or a 401 — the credentials have hit Google's ~24h RAPT re-login policy.
---

# Reconnect

These errors mean the shared ADC credentials have expired, not that anything is broken:
`invalid_rapt`, `invalid_grant`, `reauthentication needed`, `401` from either MCP server.

1. Tell the user what happened, in one line: the ~24h RAPT re-login window has passed.
2. **Ask the user** to run the reconnect script themselves — do not run it yourself and
   do not try to work around it. It opens a browser for a Google consent screen, which
   Claude cannot do:
   - single-account hub: `./scripts/reconnect.sh`
   - multi-account hub, this account only: `./scripts/reconnect.sh --account <email>`
3. Ask them to run `/mcp` in Claude Code afterwards to reconnect the servers.
4. While waiting, do not sit idle. Continue with anything in the current task that
   doesn't need the MCP servers — reading/writing files, editing a playbook or analysis
   note, reviewing earlier results already in context — then resume the MCP-dependent
   work once the user confirms the reconnect is done.

Background: `docs/03-auth-and-rapt.md`.
