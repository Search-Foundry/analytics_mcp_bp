---
name: health-check
description: Use when the user asks to check the hub's health, diagnose setup problems, or verify prerequisites/credentials/MCP servers are working before starting analysis work.
---

# Health check

1. Run `./scripts/doctor.sh`. It checks: Node.js version, gcloud presence, the ADC file,
   ADC scopes, the enabled Google Cloud APIs, and whether the Search Console MCP server
   starts cleanly — printing one `OK:` / `WARN:` / `FAIL:` line per check.
2. If every line is `OK`, report that briefly and stop.
3. For each `FAIL`, translate it into a concrete action instead of just repeating the
   line:
   - it points at a section of `docs/99-troubleshooting.md` (the anchor after `#`) —
     open that section and follow its fix.
   - if it's an expired/missing ADC credential, that's the `reconnect` skill's job:
     ask the user to run `./scripts/reconnect.sh` (optionally `--account <email>`), then
     `/mcp`.
   - if it's a missing prerequisite (Node, gcloud), point the user at the install link
     `doctor.sh` printed.
4. `WARN` lines are not blocking — mention them, but don't treat them as failures.
5. To narrow the check to one thing, use `./scripts/doctor.sh --only <check-id>` (ids:
   `node`, `gcloud`, `adc-file`, `adc-scopes`, `gcp-apis`, `gsc-server`).
