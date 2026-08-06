#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/checks.sh"

it "the checks table is data, one row per check"
assert_eq "7" "${#CHECKS[@]}" "seven checks are declared"
assert_contains "${CHECKS[0]}" "|" "rows are pipe-separated"

it "every check row names a function that exists"
_missing=""
for _row in "${CHECKS[@]}"; do
  IFS='|' read -r _id _desc _fn _anchor <<< "$_row"
  command -v "$_fn" >/dev/null 2>&1 || _missing="$_missing $_fn"
done
assert_eq "" "$_missing" "no check row points at a missing function"

it "every check row carries a troubleshooting anchor"
_bad=""
for _row in "${CHECKS[@]}"; do
  IFS='|' read -r _id _desc _fn _anchor <<< "$_row"
  case "$_anchor" in 99-troubleshooting.md#*) ;; *) _bad="$_bad $_id" ;; esac
done
assert_eq "" "$_bad" "all anchors point into the troubleshooting doc"

it "doctor.sh --help exits 0 and explains itself"
assert_exit 0 bash "$REPO_ROOT/scripts/doctor.sh" --help
assert_contains "$(bash "$REPO_ROOT/scripts/doctor.sh" --help)" "--only" "help documents --only"

it "doctor.sh --only rejects an unknown check id"
assert_exit 1 bash "$REPO_ROOT/scripts/doctor.sh" --only no-such-check

it "doctor.sh reports FAIL and exits 1 when a check fails"
# Use ENV_FILE pointed at a temp .env, like every other test file — setting ADC_FILE
# directly in the environment would be silently overwritten by load_env re-exporting a
# real .env at the repo root, if one exists (that was the I5 bug: this test used to pass
# only on a machine that had never run setup.sh).
_tmp_doctor="$(mktemp -d)"
printf 'ADC_FILE=/no/such/path/adc.json\n' > "$_tmp_doctor/.env"
_out="$(ENV_FILE="$_tmp_doctor/.env" bash "$REPO_ROOT/scripts/doctor.sh" --only adc-file 2>&1)"
assert_exit 1 env ENV_FILE="$_tmp_doctor/.env" bash "$REPO_ROOT/scripts/doctor.sh" --only adc-file
assert_contains "$_out" "FAIL:" "a FAIL line is printed"
assert_contains "$_out" "99-troubleshooting.md#adc-missing" "the FAIL line carries the check's anchor"

it "doctor.sh --help documents --account (I2)"
assert_contains "$(bash "$REPO_ROOT/scripts/doctor.sh" --help)" "--account" "help documents --account"

it "doctor.sh --account points adc-file at that account's isolated ADC (I2)"
_tmp_acct="$(mktemp -d)"
mkdir -p "$_tmp_acct/.secrets/gcloud/dana@example.com"
printf 'fake-adc\n' > "$_tmp_acct/.secrets/gcloud/dana@example.com/application_default_credentials.json"
# doctor.sh resolves .secrets/gcloud/<email>/ off repo_root(), not off --root or ENV_FILE,
# so exercise the real repo root here rather than a synthetic tree.
mkdir -p "$REPO_ROOT/.secrets/gcloud/dana@example.com"
printf 'fake-adc\n' > "$REPO_ROOT/.secrets/gcloud/dana@example.com/application_default_credentials.json"
_out_acct="$(bash "$REPO_ROOT/scripts/doctor.sh" --only adc-file --account dana@example.com 2>&1)"
assert_exit 0 bash "$REPO_ROOT/scripts/doctor.sh" --only adc-file --account dana@example.com
assert_contains "$_out_acct" "OK:" "the per-account ADC file is found"
rm -rf "$REPO_ROOT/.secrets/gcloud/dana@example.com" "$_tmp_acct"

it "doctor.sh --account rejects a malformed email the same way the other scripts do (I2)"
assert_exit 1 bash "$REPO_ROOT/scripts/doctor.sh" --account 'not an email'

it "doctor.sh reports WARN and exits 0 when a check warns"
printf '' > "$_tmp_doctor/.env-empty"
_out="$(env -u GCP_PROJECT_ID ENV_FILE="$_tmp_doctor/.env-empty" bash "$REPO_ROOT/scripts/doctor.sh" --only gcp-apis 2>&1)"
assert_exit 0 env -u GCP_PROJECT_ID ENV_FILE="$_tmp_doctor/.env-empty" bash "$REPO_ROOT/scripts/doctor.sh" --only gcp-apis
assert_contains "$_out" "WARN:" "a WARN line is printed"
rm -rf "$_tmp_doctor"
