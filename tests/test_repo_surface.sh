#!/usr/bin/env bash

it "both READMEs and the hub template exist"
for f in README.md README.it.md CLAUDE.md.template; do
  assert_eq "yes" "$([ -f "$REPO_ROOT/$f" ] && echo yes || echo no)" "$f exists"
done

it "AGENTS.md states the rules that prevent a leak, and the hub template routes agents to it"
# These rules are the difference between an inconvenience and a published client dataset,
# so they are pinned rather than left to good intentions. Sections 1-3 are the load-bearing
# ones: no publishing, no touching credentials, no self-authenticating.
_agents="$(cat "$REPO_ROOT/AGENTS.md" 2>/dev/null || true)"
assert_contains "$_agents" "Never publish, upload, or transmit" "rule 1: nothing leaves the hub"
assert_contains "$_agents" "Never read, print, or move credentials" "rule 2: credentials are off limits"
assert_contains "$_agents" "Never authenticate on the user's behalf" "rule 3: the browser login is the human's"
assert_contains "$_agents" ".secrets/" "credentials are named concretely, not gestured at"
# A rules file nothing loads protects nothing: the hub template must send agents to it.
assert_contains "$(cat "$REPO_ROOT/CLAUDE.md.template")" "AGENTS.md" "hub template points at AGENTS.md"

it "both READMEs document the agent rules, and stay in step with each other"
for f in README.md README.it.md; do
  assert_contains "$(cat "$REPO_ROOT/$f")" "AGENTS.md" "$f mentions AGENTS.md"
done

it "the account template carries the tenants marker new-tenant.sh needs"
assert_contains "$(cat "$REPO_ROOT/templates/account/CLAUDE.md")" "<!-- tenants -->" "marker present"

it "the account template doesn't assert a single ADC location as fact (I3)"
# The single-account quickstart (setup.sh with no --account) leaves the ADC at the
# default gcloud location, not under .secrets/gcloud/<email>/ — the template must cover
# both cases and point at doctor.sh to disambiguate, not assert the multi-account path
# unconditionally (that was the I3 bug: day-2 users following it created a second,
# unused ADC).
_acct_tpl="$(cat "$REPO_ROOT/templates/account/CLAUDE.md")"
assert_contains "$_acct_tpl" "doctor.sh" "template points at doctor.sh to disambiguate"
assert_contains "$_acct_tpl" "default gcloud location" "template describes the single-account case"

it "the hub template describes the accounts hierarchy, not a flat tenant list"
assert_contains "$(cat "$REPO_ROOT/CLAUDE.md.template")" "accounts/" "hub template points at accounts/"

it "the playbook tree has its guide and the example recipe"
assert_eq "yes" "$([ -f "$REPO_ROOT/playbooks/README.md" ] && echo yes || echo no)" "guide exists"
assert_eq "yes" "$([ -f "$REPO_ROOT/playbooks/organic-traffic-drop.md" ] && echo yes || echo no)" "recipe exists"

it "every skill declares a name and a description"
for s in new-tenant reconnect health-check; do
  _f="$REPO_ROOT/.claude/skills/$s/SKILL.md"
  assert_eq "yes" "$([ -f "$_f" ] && echo yes || echo no)" "$s SKILL.md exists"
  assert_contains "$(cat "$_f")" "name: $s" "$s declares its name"
  assert_contains "$(cat "$_f")" "description:" "$s declares a description"
done

it "the whole test suite is referenced from the English README"
assert_contains "$(cat "$REPO_ROOT/README.md")" "tests/run.sh" "contributors can find the tests"

it ".gitignore actually ignores nested tenant data/exports paths (C2)"
# Real paths are accounts/<email>/<tenant>/data/... (two levels down), not one level —
# a single-star */data/ pattern only matches one level and silently fails to ignore them.
_tmp_gi="$(mktemp -d)"
git init -q "$_tmp_gi"
cp "$REPO_ROOT/.gitignore" "$_tmp_gi/.gitignore"
mkdir -p "$_tmp_gi/accounts/me@example.com/acme/data" "$_tmp_gi/accounts/me@example.com/acme/exports"
touch "$_tmp_gi/accounts/me@example.com/acme/data/export.csv" \
      "$_tmp_gi/accounts/me@example.com/acme/exports/report.csv"
assert_exit 0 git -C "$_tmp_gi" check-ignore -q accounts/me@example.com/acme/data/export.csv
assert_exit 0 git -C "$_tmp_gi" check-ignore -q accounts/me@example.com/acme/exports/report.csv
rm -rf "$_tmp_gi"

it "both READMEs tell you to detach the clone from the blueprint before adding client data (fix 1)"
assert_contains "$(cat "$REPO_ROOT/README.md")" "rm -rf .git && git init" "README.md documents detaching git"
assert_contains "$(cat "$REPO_ROOT/README.md")" "private" "README.md says the repo must be private if kept in git"
assert_contains "$(cat "$REPO_ROOT/README.it.md")" "rm -rf .git && git init" "README.it.md documents detaching git"
assert_contains "$(cat "$REPO_ROOT/README.it.md")" "privata" "README.it.md says the repo must be private if kept in git"

it "docs/04-multi-tenant.md explains detaching, the filesystem channel and the credentials rule (fixes 1-3)"
_mt="$(cat "$REPO_ROOT/docs/04-multi-tenant.md")"
assert_contains "$_mt" "rm -rf .git && git init" "detach instructions present"
assert_contains "$_mt" "zip" "filesystem-as-channel section present"
assert_contains "$_mt" "Credentials never live in a tenant or account folder" "credentials rule stated"

it "docs/03-auth-and-rapt.md states the credentials-never-in-tenant rule (fix 3)"
assert_contains "$(cat "$REPO_ROOT/docs/03-auth-and-rapt.md")" "Credentials never live in a tenant or account folder" "rule present"

it "both tenant and account templates carry a one-line credentials reminder (fix 3)"
assert_contains "$(cat "$REPO_ROOT/templates/tenant/CLAUDE.md")" "Never put credentials in this folder" "tenant template reminder"
assert_contains "$(cat "$REPO_ROOT/templates/account/CLAUDE.md")" "Never put credentials in this folder" "account template reminder"

it "accounts/, the root CLAUDE.md and analysis/ are not gitignored (owner decision)"
_gi="$(cat "$REPO_ROOT/.gitignore")"
for _pattern in '^accounts/$' '^/CLAUDE\.md$' '^\*\*/analysis/$'; do
  assert_eq "" "$(printf '%s\n' "$_gi" | grep -E "$_pattern" || true)" "gitignore has no rule matching $_pattern"
done

it "MCP server versions are pinned everywhere they're invoked or documented (fix 4)"
assert_contains "$(cat "$REPO_ROOT/README.md")" "analytics-mcp==0.7.0" "README pins analytics-mcp"
assert_contains "$(cat "$REPO_ROOT/docs/01-google-cloud-setup.md")" "analytics-mcp==0.7.0" "01 pins analytics-mcp"
assert_contains "$(cat "$REPO_ROOT/docs/02-mcp-servers.md")" "analytics-mcp==0.7.0" "02 pins analytics-mcp"
assert_contains "$(cat "$REPO_ROOT/docs/02-mcp-servers.md")" "search-console-mcp@2.0.1" "02 pins search-console-mcp"
assert_contains "$(cat "$REPO_ROOT/docs/99-troubleshooting.md")" "analytics-mcp==0.7.0" "99 pins analytics-mcp"
assert_contains "$(cat "$REPO_ROOT/scripts/setup.sh")" "search-console-mcp@2.0.1" "setup.sh pins search-console-mcp in emitted config"
assert_contains "$(cat "$REPO_ROOT/scripts/setup.sh")" "analytics-mcp==0.7.0" "setup.sh pins analytics-mcp in the prereq error"
assert_contains "$(cat "$REPO_ROOT/scripts/lib/checks.sh")" "search-console-mcp@2.0.1" "checks.sh pins search-console-mcp"
assert_contains "$(cat "$REPO_ROOT/scripts/lib/checks.sh")" "analytics-mcp==0.7.0" "checks.sh pins analytics-mcp"

it "the account and tenant templates are not swallowed by the data/exports ignore (C2 regression guard)"
# templates/tenant/data and templates/tenant/exports ship a tracked .gitkeep; the widened
# pattern must not retroactively make the templates directory itself look untracked.
assert_eq "yes" "$([ -f "$REPO_ROOT/templates/tenant/data/.gitkeep" ] && echo yes || echo no)" "data/.gitkeep present on disk"
assert_eq "yes" "$([ -f "$REPO_ROOT/templates/tenant/exports/.gitkeep" ] && echo yes || echo no)" "exports/.gitkeep present on disk"
assert_contains "$(cd "$REPO_ROOT" && git ls-files templates/tenant)" "data/.gitkeep" "data/.gitkeep is still tracked in git"
