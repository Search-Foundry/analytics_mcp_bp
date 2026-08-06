#!/usr/bin/env bash
_tmp="$(mktemp -d)"
_run() { bash "$REPO_ROOT/scripts/new-tenant.sh" "$@" --root "$_tmp"; }

it "new-tenant.sh --help exits 0"
assert_exit 0 bash "$REPO_ROOT/scripts/new-tenant.sh" --help

it "it refuses to run without a tenant name"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" --account me@example.com --root "$_tmp"

it "it refuses to run without an account"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" acme --root "$_tmp"

it "the first tenant of an account creates the account folder from the template"
_run acme --account me@example.com --ga4 123456789 --gsc "https://www.example.com/" >/dev/null
assert_eq "yes" "$([ -f "$_tmp/accounts/me@example.com/CLAUDE.md" ] && echo yes || echo no)" "account CLAUDE.md created"
assert_contains "$(cat "$_tmp/accounts/me@example.com/CLAUDE.md")" "me@example.com" "account email substituted"

it "the tenant lives under its account, with the template subfolders"
assert_eq "yes" "$([ -d "$_tmp/accounts/me@example.com/acme/data" ] && echo yes || echo no)" "data/ exists"
assert_eq "yes" "$([ -d "$_tmp/accounts/me@example.com/acme/exports" ] && echo yes || echo no)" "exports/ exists"
assert_eq "yes" "$([ -f "$_tmp/accounts/me@example.com/acme/CLAUDE.md" ] && echo yes || echo no)" "tenant CLAUDE.md exists"

it "placeholders are substituted, none left behind"
assert_contains "$(cat "$_tmp/accounts/me@example.com/acme/CLAUDE.md")" "123456789" "GA4 id substituted"
assert_contains "$(cat "$_tmp/accounts/me@example.com/acme/CLAUDE.md")" "https://www.example.com/" "GSC url substituted"
assert_eq "0" "$(grep -c '{{' "$_tmp/accounts/me@example.com/acme/CLAUDE.md" || true)" "no placeholder survives"

it "the tenant is registered in its account CLAUDE.md, under the marker"
assert_contains "$(cat "$_tmp/accounts/me@example.com/CLAUDE.md")" "| acme | 123456789 | https://www.example.com/ |" "row added"

it "a second tenant reuses the existing account folder and adds a second row"
_run globex --account me@example.com >/dev/null
assert_eq "2" "$(grep -c '^| acme \|^| globex ' "$_tmp/accounts/me@example.com/CLAUDE.md")" "both rows present"

it "a tenant on a different account gets its own account folder"
_run acme --account other@example.com >/dev/null
assert_eq "yes" "$([ -d "$_tmp/accounts/other@example.com/acme" ] && echo yes || echo no)" "same tenant name is fine under another account"

it "it refuses to overwrite an existing tenant"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" acme --account me@example.com --root "$_tmp"

it "it rejects an account that is not an email address"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" x --account 'not/an/email' --root "$_tmp"

it "a value containing '|' produces a well-formed table row, escaped"
_run pipey --account me@example.com --ga4 TBD --gsc 'https://example.com/a|b' >/dev/null
assert_contains "$(cat "$_tmp/accounts/me@example.com/CLAUDE.md")" '| pipey | TBD | https://example.com/a\|b | active |' "pipe escaped in row"
assert_eq "1" "$(grep -c '^| pipey ' "$_tmp/accounts/me@example.com/CLAUDE.md")" "exactly one row for pipey"

it "an account CLAUDE.md missing the marker: run fails, tenant not created, account file untouched"
mkdir -p "$_tmp/accounts/broken@example.com"
printf '# Account: broken@example.com\n\nNo marker here.\n' > "$_tmp/accounts/broken@example.com/CLAUDE.md"
_before="$(cat "$_tmp/accounts/broken@example.com/CLAUDE.md")"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" widgets --account broken@example.com --root "$_tmp"
assert_eq "yes" "$([ ! -e "$_tmp/accounts/broken@example.com/widgets" ] && echo yes || echo no)" "tenant dir not created"
assert_eq "$_before" "$(cat "$_tmp/accounts/broken@example.com/CLAUDE.md")" "account CLAUDE.md unchanged"

it "after fixing the marker, a repeat run succeeds"
printf '%s\n<!-- tenants -->\n' "$_before" > "$_tmp/accounts/broken@example.com/CLAUDE.md"
_run widgets --account broken@example.com >/dev/null
assert_eq "yes" "$([ -d "$_tmp/accounts/broken@example.com/widgets" ] && echo yes || echo no)" "tenant created on retry"

it "a failure creating a brand-new account folder leaves no account directory behind"
mkdir -p "$_tmp/accounts"
chmod 555 "$_tmp/accounts"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" acme --account newacct@example.com --root "$_tmp"
chmod 755 "$_tmp/accounts"
assert_eq "yes" "$([ ! -e "$_tmp/accounts/newacct@example.com" ] && echo yes || echo no)" "no account dir left behind"

it "it registers the account in a hub CLAUDE.md at --root, if one exists (I4)"
_tmp_hub="$(mktemp -d)"
cp "$REPO_ROOT/CLAUDE.md.template" "$_tmp_hub/CLAUDE.md"
_run_hub() { bash "$REPO_ROOT/scripts/new-tenant.sh" "$@" --root "$_tmp_hub"; }
_run_hub acme --account hub@example.com --ga4 111 --gsc "https://hub.example.com/" >/dev/null
assert_contains "$(cat "$_tmp_hub/CLAUDE.md")" "| hub@example.com | acme | active |" "account row added to hub CLAUDE.md"
_run_hub globex --account hub@example.com >/dev/null
assert_contains "$(cat "$_tmp_hub/CLAUDE.md")" "| hub@example.com | acme, globex | active |" "second tenant appends to the same row, not a duplicate row"
assert_eq "1" "$(grep -c '^| hub@example.com ' "$_tmp_hub/CLAUDE.md")" "exactly one row for this account"
rm -rf "$_tmp_hub"

it "it skips hub registration silently when --root has no CLAUDE.md (I4)"
# $_tmp (used throughout this file) never had a CLAUDE.md dropped into it, and every
# earlier case in this file already ran successfully against it — this case just makes
# that "no hub file -> no error" contract explicit.
assert_eq "yes" "$([ ! -f "$_tmp/CLAUDE.md" ] && echo yes || echo no)" "no hub CLAUDE.md was ever created at root"
_run silent --account me@example.com >/dev/null
assert_eq "yes" "$([ -d "$_tmp/accounts/me@example.com/silent" ] && echo yes || echo no)" "tenant still created with no hub file present"

it "a hub CLAUDE.md missing the accounts marker fails before any mutation (I4)"
_tmp_badhub="$(mktemp -d)"
printf '# Hub\n\nNo marker here.\n' > "$_tmp_badhub/CLAUDE.md"
_before_badhub="$(cat "$_tmp_badhub/CLAUDE.md")"
assert_exit 1 bash "$REPO_ROOT/scripts/new-tenant.sh" acme --account me@example.com --root "$_tmp_badhub"
assert_eq "yes" "$([ ! -e "$_tmp_badhub/accounts" ] && echo yes || echo no)" "no accounts dir created"
assert_eq "$_before_badhub" "$(cat "$_tmp_badhub/CLAUDE.md")" "hub CLAUDE.md left untouched"
rm -rf "$_tmp_badhub"

rm -rf "$_tmp"
