#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/common.sh"

it "exit codes follow the documented contract"
assert_eq "0" "$EXIT_OK" "EXIT_OK is 0"
assert_eq "1" "$EXIT_USER" "EXIT_USER is 1"
assert_eq "2" "$EXIT_PREREQ" "EXIT_PREREQ is 2"

it "log_ok prefixes its message"
assert_contains "$(log_ok 'node found')" "OK: node found" "log_ok is prefixed"

it "log_fail points at a troubleshooting section"
assert_contains "$(log_fail 'adc missing' '99-troubleshooting.md#adc')" \
  "99-troubleshooting.md#adc" "log_fail carries the pointer"

it "require_cmd exits 2 when the command is absent"
assert_exit 2 bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; require_cmd definitely-not-a-real-cmd 'install it'"

it "load_env reads values and expands \$HOME"
_tmp="$(mktemp -d)"
printf 'GCP_PROJECT_ID=demo-project\nADC_FILE=$HOME/x/adc.json\n' > "$_tmp/.env"
_out="$(bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; ENV_FILE='$_tmp/.env' load_env; printf '%s|%s' \"\$GCP_PROJECT_ID\" \"\$ADC_FILE\"")"
assert_contains "$_out" "demo-project|" "value is read"
assert_contains "$_out" "$HOME/x/adc.json" "\$HOME is expanded"
rm -rf "$_tmp"

it "json_get reads a nested key without jq"
_tmp="$(mktemp -d)"
printf '{"installed":{"client_id":"abc.apps.googleusercontent.com"}}\n' > "$_tmp/c.json"
assert_eq "abc.apps.googleusercontent.com" \
  "$(json_get "$_tmp/c.json" installed.client_id)" "nested key is read"
rm -rf "$_tmp"

it "load_env strips CRLF line endings for Windows portability"
_tmp="$(mktemp -d)"
# Write a .env file with CRLF line endings (simulating Windows)
printf 'FOO=bar\r\nBAZ=qux\r\n' > "$_tmp/.env"
_out="$(bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; ENV_FILE='$_tmp/.env' load_env; printf '%s|%s' \"\$FOO\" \"\$BAZ\"")"
assert_eq "bar|qux" "$_out" "CRLF is stripped, values are clean"
rm -rf "$_tmp"

it "load_env unquotes double and single quoted values"
_tmp="$(mktemp -d)"
printf 'DOUBLE="value with spaces"\nSINGLE='"'"'single quoted'"'"'\nUNQUOTED=plain\n' > "$_tmp/.env"
_out="$(bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; ENV_FILE='$_tmp/.env' load_env; printf '%s|%s|%s' \"\$DOUBLE\" \"\$SINGLE\" \"\$UNQUOTED\"")"
assert_eq "value with spaces|single quoted|plain" "$_out" "quotes are removed from values"
rm -rf "$_tmp"

it "load_env trims trailing whitespace from values"
_tmp="$(mktemp -d)"
printf 'FOO=bar   \nBAZ=qux\t\n' > "$_tmp/.env"
_out="$(bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; ENV_FILE='$_tmp/.env' load_env; printf '%s|%s' \"\$FOO\" \"\$BAZ\"")"
assert_eq "bar|qux" "$_out" "trailing whitespace is trimmed"
rm -rf "$_tmp"

it "load_env skips indented comments with = safely"
_tmp="$(mktemp -d)"
printf 'FOO=good\n  # BAD=bad\n  # SKIP=this\nBAR=also-good\n' > "$_tmp/.env"
_out="$(bash -c ". '$REPO_ROOT/scripts/lib/common.sh'; ENV_FILE='$_tmp/.env' load_env 2>&1; printf '%s|%s' \"\$FOO\" \"\$BAR\"")"
# Should not contain bash errors like "not a valid identifier"
assert_contains "$_out" "good|also-good" "indented comments are skipped"
assert_contains "$_out" "good|also-good" "no bash errors from comment lines"
rm -rf "$_tmp"
