#!/usr/bin/env bash
# Non-destructive diagnostics for the hub.
#
# Contract:
#   input:  .env (GCP_PROJECT_ID, ADC_FILE, GSC_MCP_MODE, GSC_MCP_PATH)
#   output: one "OK:/WARN:/FAIL:" line per check, summary last
#   exit:   0 no failures, 1 at least one FAIL or a bad argument
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/checks.sh"

usage() {
  cat <<'EOF'
Usage: doctor.sh [--only <check-id>] [--account <email>]

Runs the diagnostic checks and reports OK / WARN / FAIL for each one,
pointing failures at the matching section of docs/99-troubleshooting.md.

  --only <check-id>   run a single check
  --account <email>   diagnose that account's own credentials: points ADC_FILE and
                      CLOUDSDK_CONFIG at .secrets/gcloud/<email>/, the same isolated
                      directory reconnect.sh --account <email> writes to
  --help              show this message

Check ids: node, gcloud, analytics-mcp, adc-file, adc-scopes, gcp-apis, gsc-server
EOF
}

ONLY=""
ACCOUNT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --only) ONLY="${2-}"; [ -n "$ONLY" ] || die "--only needs a check id"; shift 2 ;;
    --account) ACCOUNT="${2-}"; [ -n "$ACCOUNT" ] || die "--account needs an email"; shift 2 ;;
    *) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

# Validate the account argument exactly as setup.sh/reconnect.sh/new-tenant.sh do, so
# all four scripts agree on what a valid account directory name looks like.
if [ -n "$ACCOUNT" ]; then
  case "$ACCOUNT" in
    *$'\n'*)
      printf 'error: account must be a valid email address\n' >&2
      printf '       valid format: local@domain.tld\n' >&2
      printf '       no embedded newlines allowed\n' >&2
      exit "$EXIT_USER"
      ;;
  esac
  if ! printf '%s' "$ACCOUNT" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    printf 'error: account must be a valid email address\n' >&2
    printf '       valid format: local@domain.tld\n' >&2
    printf '       local part: letters, digits, . _ %% + -\n' >&2
    printf '       domain: letters, digits, . -\n' >&2
    printf '       TLD: at least 2 letters\n' >&2
    printf '       got: %q\n' "$ACCOUNT" >&2
    exit "$EXIT_USER"
  fi
fi

load_env

if [ -n "$ACCOUNT" ]; then
  ROOT="$(repo_root)"
  CLOUDSDK_CONFIG="$ROOT/.secrets/gcloud/$ACCOUNT"
  ADC_FILE="$CLOUDSDK_CONFIG/application_default_credentials.json"
  export CLOUDSDK_CONFIG ADC_FILE
fi

if [ -n "$ONLY" ]; then
  found=1
  for row in "${CHECKS[@]}"; do
    IFS='|' read -r id _ _ _ <<< "$row"
    [ "$id" = "$ONLY" ] && found=0
  done
  [ "$found" -eq 0 ] || die "unknown check id: $ONLY (try --help)"
fi

failures=0
for row in "${CHECKS[@]}"; do
  IFS='|' read -r id desc fn anchor <<< "$row"
  [ -z "$ONLY" ] || [ "$ONLY" = "$id" ] || continue
  detail=""
  status=0
  detail="$("$fn" 2>&1)" || status=$?
  case "$status" in
    0) log_ok   "$desc — $detail" ;;
    3) log_warn "$desc — $detail" ;;
    *) log_fail "$desc — $detail" "$anchor"; failures=$((failures + 1)) ;;
  esac
done

printf '\n%d check(s) failed\n' "$failures"
[ "$failures" -eq 0 ]
