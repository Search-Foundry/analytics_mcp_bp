---
name: new-tenant
description: Use when the user wants to add a new tenant (client site/property) to the hub — onboarding a new GA4 property and Search Console site under a Google account.
---

# New tenant

1. Ask the user for: the tenant name (a short folder-safe slug, no `/`, no leading `.`),
   the Google account this tenant is accessed with, the GA4 property ID, and the GSC
   site URL. GA4 property ID and GSC site URL can be left as `TBD` and filled in later if
   the user doesn't have them yet.
2. Run `./scripts/new-tenant.sh <name> --account <email> --ga4 <id> --gsc <url>` (omit
   `--ga4`/`--gsc` to use the `TBD` defaults). It creates
   `accounts/<email>/<name>/` from `templates/tenant/`, creating the account folder from
   `templates/account/` too if this is that account's first tenant, and registers the
   tenant in the account's `CLAUDE.md` tenant table.
3. Report the paths the script printed.
4. Open the new tenant's `CLAUDE.md` and help the user fill in the "What this site is"
   section — what the business does, who the audience is, what "good" looks like — and
   the "Known quirks" section if they already know of any (seasonality, bot traffic,
   tracking gaps, migrations). Leave both empty rather than guessing if the user doesn't
   know yet; a wrong guess here is worse than a blank placeholder.
