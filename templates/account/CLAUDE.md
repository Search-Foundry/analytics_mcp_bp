# Account: {{ACCOUNT_EMAIL}}

Every tenant in this folder is accessed with the Google account above. Claude loads this file
when working anywhere under it.

## Tenants

| Tenant | GA4 property ID | GSC site | Status |
|---|---|---|---|
<!-- tenants -->

Add one: `./scripts/new-tenant.sh <name> --account {{ACCOUNT_EMAIL}} --ga4 <id> --gsc <url>`

## Credentials

Where this account's credentials live depends on how the hub was set up:

- **Single-account hub** (the quickstart default — `setup.sh` run without `--account`):
  the ADC is at the default gcloud location (`~/.config/gcloud/application_default_credentials.json`,
  or `.env`'s `ADC_FILE`). Renew it with plain `./scripts/reconnect.sh`.
- **Multi-account hub** (`setup.sh --account {{ACCOUNT_EMAIL}}` or `reconnect.sh --account`
  run directly): this account is isolated at `.secrets/gcloud/{{ACCOUNT_EMAIL}}/`, with its
  ADC at `.secrets/gcloud/{{ACCOUNT_EMAIL}}/application_default_credentials.json`. Renew it
  with `./scripts/reconnect.sh --account {{ACCOUNT_EMAIL}}`.

Not sure which applies here? Run `./scripts/doctor.sh` (single-account) or
`./scripts/doctor.sh --account {{ACCOUNT_EMAIL}}` (multi-account) — whichever reports
ADC checks as OK is the one this account is actually using. See `docs/03-auth-and-rapt.md`
for the full explanation.

Either way, after renewing, run `/mcp` in Claude Code to reconnect the servers. Because
MCP servers take a fixed environment, an account only needs its own separate server
entries in `~/.claude.json` (the `--account`-suffixed ones) once it's on the multi-account
path — see `docs/03-auth-and-rapt.md`.
