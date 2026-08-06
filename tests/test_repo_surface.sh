#!/usr/bin/env bash

it "both READMEs and the hub template exist"
for f in README.md README.it.md CLAUDE.md.template; do
  assert_eq "yes" "$([ -f "$REPO_ROOT/$f" ] && echo yes || echo no)" "$f exists"
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

it "the account and tenant templates are not swallowed by the data/exports ignore (C2 regression guard)"
# templates/tenant/data and templates/tenant/exports ship a tracked .gitkeep; the widened
# pattern must not retroactively make the templates directory itself look untracked.
assert_eq "yes" "$([ -f "$REPO_ROOT/templates/tenant/data/.gitkeep" ] && echo yes || echo no)" "data/.gitkeep present on disk"
assert_eq "yes" "$([ -f "$REPO_ROOT/templates/tenant/exports/.gitkeep" ] && echo yes || echo no)" "exports/.gitkeep present on disk"
assert_contains "$(cd "$REPO_ROOT" && git ls-files templates/tenant)" "data/.gitkeep" "data/.gitkeep is still tracked in git"
