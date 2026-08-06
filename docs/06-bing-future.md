# 6. Bing Webmaster Tools (out of scope, for now)

`search-console-mcp` bundles a second surface beyond Google Search Console: a set of Bing
Webmaster Tools integrations (query stats, crawl issues, URL submission, and more). This
blueprint doesn't set that up or document it as part of the guided flow — everything above
is Google-only.

## Turning it on anyway

If you want to try the Bing tools today, the server picks them up from an environment
variable:

```
export BING_API_KEY="your-bing-webmaster-api-key"
```

Get the key from [bing.com/webmasters/settings/api](https://www.bing.com/webmasters/settings/api).
Set it in whatever environment the MCP server process inherits (e.g. add it to your shell
profile, or extend the server's `env` block in `~/.claude.json`), then restart the server.
The Bing tools should then appear alongside the Google ones.

## What real support would take

To bring Bing support properly into this blueprint (not just "it happens to work if you
set an env var"), three things would need to change:

1. A `BING_API_KEY` entry in `.env.example`, so it's discoverable the same way every other
   piece of configuration is, and `setup.sh`/`common.sh`'s `load_env` picks it up.
2. A check in `scripts/lib/checks.sh` (a `check_bing_api_key` function plus a `CHECKS` row)
   so `doctor.sh` can confirm the key is set and valid, the same way it verifies the
   Google-side prerequisites.
3. A section in `05-usage.md` documenting the Bing-specific tools, their parameters, and
   how they differ from their Google Search Console equivalents.

None of that exists yet. Treat the `BING_API_KEY` export above as an experiment, not a
supported path.
