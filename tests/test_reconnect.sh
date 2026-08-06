#!/usr/bin/env bash
_tmp="$(mktemp -d)"
printf 'GCP_PROJECT_ID=demo\nGOOGLE_ACCOUNT=me@example.com\nOAUTH_CLIENT_FILE=%s/client.json\n' "$_tmp" > "$_tmp/.env"
printf '{"installed":{"client_id":"x"}}\n' > "$_tmp/client.json"

it "reconnect.sh --help exits 0"
assert_exit 0 bash "$REPO_ROOT/scripts/reconnect.sh" --help

it "the printed command carries all three scopes, in order, on one line"
_cmd="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command)"
assert_contains "$_cmd" "gcloud auth application-default login" "it is the ADC login command"
assert_contains "$_cmd" "analytics.readonly,https://www.googleapis.com/auth/webmasters.readonly,https://www.googleapis.com/auth/cloud-platform" "scopes are complete and ordered"
assert_eq "1" "$(printf '%s' "$_cmd" | grep -c '' )" "the command is a single line"

it "the printed command points at the configured OAuth client file"
assert_contains "$_cmd" "$_tmp/client.json" "client file comes from .env"

it "--account redirects the credentials to an account-specific ADC file"
_cmd_a="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account alice@example.com)"
assert_contains "$_cmd_a" ".secrets/gcloud/alice@example.com" "account path is used"

it "a missing OAuth client file is a user error, not a crash"
printf 'OAUTH_CLIENT_FILE=%s/nope.json\n' "$_tmp" > "$_tmp/.env-bad"
assert_exit 1 env ENV_FILE="$_tmp/.env-bad" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command

it "malicious account values cannot inject shell commands"
_malicious='x"; touch /tmp/PWNED_TEST; echo "y'
assert_exit 1 env ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account "$_malicious"
# Verify the dangerous file was not created.
[ ! -f /tmp/PWNED_TEST ] && _ok "injection prevented: /tmp/PWNED_TEST does not exist" || _notok "injection vulnerability: /tmp/PWNED_TEST was created"

it "account with command substitution is rejected"
# Remove marker first to ensure test is repeatable
rm -f /tmp/RECONNECT_INJECTION_MARKER
_cmd_sub='a@b$(touch /tmp/RECONNECT_INJECTION_MARKER)c'
assert_exit 1 env ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account "$_cmd_sub"
# Verify the dangerous file was not created.
[ ! -f /tmp/RECONNECT_INJECTION_MARKER ] && _ok "injection prevented: marker not created" || _notok "injection vulnerability: marker was created"

it "account with backtick substitution is rejected"
_backtick='a@b`touch /tmp/BACKTICK_TEST`c'
assert_exit 1 env ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account "$_backtick"
[ ! -f /tmp/BACKTICK_TEST ] && _ok "backtick injection prevented" || _notok "backtick injection: marker was created"

it "account with space is rejected"
_space='alice@example.com extra'
assert_exit 1 env ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account "$_space"

it "account with embedded newline is rejected"
_newline="alice@example.com$(printf '\n')arbitrary_text"
assert_exit 1 env ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account "$_newline"

it "valid account address is accepted and output is exactly one line"
_cmd_valid="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account alice@example.com)"
assert_eq "1" "$(printf '%s' "$_cmd_valid" | grep -c '' )" "output is exactly one line"
assert_contains "$_cmd_valid" "alice@example.com" "account appears in output"
assert_contains "$_cmd_valid" "gcloud auth application-default login" "gcloud command is present"

rm -rf "$_tmp"
