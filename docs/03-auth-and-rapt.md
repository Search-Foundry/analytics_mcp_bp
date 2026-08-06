# 3. Authentication and RAPT

## Shared ADC

Both MCP servers read the same Application Default Credentials (ADC) file, pointed to by
`GOOGLE_APPLICATION_CREDENTIALS` in the `~/.claude.json` config block (see
`02-mcp-servers.md`). ADC is a JSON file gcloud writes containing a refresh token and
client details; it is not a service account key, it's a stand-in for your own logged-in
Google identity.

## The three scopes

`reconnect.sh` requests exactly:

- `analytics.readonly` — read access to GA4.
- `webmasters.readonly` — read access to Search Console.
- `cloud-platform` — required by gcloud itself; not something either MCP server actually
  needs for its API calls, but gcloud won't omit it.

## Why credentials expire roughly every 24 hours

`cloud-platform` is forced into the scope list by `gcloud auth application-default login`
and cannot be dropped. Granting that scope activates Google's **RAPT** (Reauth) policy,
which requires you to re-authenticate roughly every 24 hours regardless of how long the
refresh token would otherwise last. This is Google account security policy, not a bug in
this project or in gcloud, and there is no gcloud-side flag to disable it. Budget for a
daily re-login as part of normal operation.

Symptoms when it's expired: the MCP servers start returning `invalid_rapt`,
`invalid_grant`, a message like "reauthentication needed", or a bare `401`.

## Renewing it: two steps

1. From the repo root, run:

   ```
   ./scripts/reconnect.sh
   ```

   This opens a browser for you to sign in again and re-grants the three scopes above.

2. Inside Claude Code, run:

   ```
   /mcp
   ```

   to reconnect the servers to the refreshed credentials. Restarting Claude Code entirely
   also works, but `/mcp` is faster.

## The OS keyring vs. ADC

`search-console-mcp` uses `@napi-rs/keyring`, a native module, to talk to your operating
system's credential store (Keychain on macOS, Credential Manager on Windows, a
libsecret-backed store on Linux). That keyring is for the server's *own* internal OAuth
flow when it's run standalone, without an externally supplied credential file. In this
blueprint's setup, `GOOGLE_APPLICATION_CREDENTIALS` is always set in the MCP config block,
so the server reads that ADC file directly and the keyring path is not exercised for
day-to-day queries. If `@napi-rs/keyring` still fails to load at startup (see
`99-troubleshooting.md#native-module`), it's a module-loading problem, not a credentials
problem — the fixes are different.

## Multi-account setups

If you work across Google accounts (each with its own access to different GA4 properties
and GSC sites), isolate each account's credentials:

```
./scripts/reconnect.sh --account me@example.com
```

This sets `CLOUDSDK_CONFIG` to `.secrets/gcloud/me@example.com/` for the duration of the
login, so gcloud treats that as a fully separate configuration directory — its own ADC
file ends up at:

```
.secrets/gcloud/me@example.com/application_default_credentials.json
```

Note what this is *not*: `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` is a different
environment variable that tells gcloud which credential file to *read* for
authenticating gcloud's own commands — it does not redirect where
`gcloud auth application-default login` *writes* the ADC it produces. `--account` here
works by isolating the whole config directory via `CLOUDSDK_CONFIG`, not by overriding a
single file path.

Because each MCP server process is launched with a fixed, static environment (you can't
hand it a different `GOOGLE_APPLICATION_CREDENTIALS` value per query), each account needs
its own pair of entries in `~/.claude.json` — e.g. `search-console-mcp-me@example.com` and
`analytics-mcp-me@example.com`, each pointing at that account's own ADC file. Generate
that block with:

```
./scripts/setup.sh --print-mcp-config --account me@example.com
```

You cannot switch a single running MCP server between accounts at runtime — if you need to
query a second account's properties, you talk to its own, separately configured server
entry.

To diagnose a specific account's credentials, pass the same `--account` to `doctor.sh`:

```
./scripts/doctor.sh --account me@example.com
```

Without `--account`, `doctor.sh` only ever looks at the default ADC location (or
`.env`'s `ADC_FILE`) — it has no way to know about `.secrets/gcloud/<email>/` on its own.
If you only ever run `reconnect.sh --account`, always pass the matching `--account` to
`doctor.sh` too, or its `adc-file`/`adc-scopes` checks will report a false FAIL against a
file that was never meant to exist at the default path.

## One thing not to do

Never export `GOOGLE_APPLICATION_CREDENTIALS` globally in your `.zshrc` (or equivalent
shell profile). It's tempting since it would apply everywhere, but it will silently
override the per-account paths set in `~/.claude.json`'s MCP env blocks, other tools that
read the same variable will start reading credentials you didn't intend for them, and a
multi-account setup collapses back into whichever one shell-level value happens to be set.
Keep `GOOGLE_APPLICATION_CREDENTIALS` scoped to the MCP server config, nowhere else.
