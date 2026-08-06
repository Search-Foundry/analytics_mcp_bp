#!/usr/bin/env bash
# Refreshes the Application Default Credentials both MCP servers read.
# Run it when the servers answer with invalid_rapt, invalid_grant,
# "reauthentication needed" or 401 — see docs/03-auth-and-rapt.md.
#
# The three OAuth scopes are:
#   - analytics.readonly (GA4 read access)
#   - webmasters.readonly (Google Search Console read access)
#   - cloud-platform (required by gcloud; activates RAPT re-login policy ~24h)
#
# Without --account, the login writes to the default ADC location.
# With --account <email>, it writes to .secrets/gcloud/<email>/application_default_credentials.json,
# and sets CLOUDSDK_CONFIG to isolate all that account's config there. This allows
# multiple accounts on the same machine: each runs its own MCP server, and each points
# at its own account's ADC via the MCP config in ~/.claude.json.
#
# Contract:
#   input:  .env (OAUTH_CLIENT_FILE, GOOGLE_ACCOUNT), optional --account <email>
#   output: the gcloud command, then its output
#   exit:   0 ok, 1 user error, 2 missing prerequisite
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

# gcloud forces the cloud-platform scope and it cannot be removed. That scope is
# what activates Google's RAPT policy, which mandates a re-login roughly every
# 24 hours. This is policy, not a bug: there is no gcloud-side workaround.
SCOPES="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/webmasters.readonly,https://www.googleapis.com/auth/cloud-platform"

usage() {
  cat <<'EOF'
Usage: reconnect.sh [--account <email>] [--print-command]

Regenerates the ADC credentials with the three scopes both MCP servers need.
Afterwards, run /mcp inside Claude Code to reconnect the servers.

  --account <email>  isolate this account in .secrets/gcloud/<email>/ — use this
                     for multi-account setups. After login, run setup.sh with the
                     same --account to generate the MCP server config for it
  --print-command    print the gcloud command and exit, without running it
  --help             show this message
EOF
}

ACCOUNT=""
PRINT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --account) ACCOUNT="${2-}"; [ -n "$ACCOUNT" ] || die "--account needs an email"; shift 2 ;;
    --print-command) PRINT_ONLY=1; shift ;;
    *) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

load_env
require_env OAUTH_CLIENT_FILE

ROOT="$(repo_root)"
CLIENT="$OAUTH_CLIENT_FILE"
case "$CLIENT" in /*) ;; *) CLIENT="$ROOT/$CLIENT" ;; esac
[ -f "$CLIENT" ] || die "OAuth client file not found: $CLIENT
       Create a desktop OAuth client and download it — see docs/01-google-cloud-setup.md"

# Validate account argument if present: must match a conservative email pattern.
# Pattern: local@domain.tld where local=[a-zA-Z0-9._%+-]+ and domain has at least one dot.
if [ -n "$ACCOUNT" ]; then
  # Reject embedded newlines explicitly (grep's ^ and $ apply per-line, not whole-string).
  case "$ACCOUNT" in
    *$'\n'*)
      printf 'error: account must be a valid email address\n' >&2
      printf '       valid format: local@domain.tld\n' >&2
      printf '       local part: letters, digits, . _ %% + -\n' >&2
      printf '       domain: letters, digits, . -\n' >&2
      printf '       TLD: at least 2 letters\n' >&2
      printf '       no embedded newlines allowed\n' >&2
      printf '       got: %q\n' "$ACCOUNT" >&2
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

# Build the gcloud command as an array, never as a string to be eval'd.
cmd=(gcloud auth application-default login)
cmd+=(--client-id-file="$CLIENT")
cmd+=(--scopes="$SCOPES")

# Prepare environment for --account isolation.
declare -a env_prefix
if [ -n "$ACCOUNT" ]; then
  env_prefix+=(CLOUDSDK_CONFIG="$ROOT/.secrets/gcloud/$ACCOUNT")
fi

if [ "$PRINT_ONLY" -eq 1 ]; then
  # Print the command in a form humans can copy-paste and that's injection-safe.
  # For --print-command, show the environment variable (if any) then the gcloud command.
  # Quote both the CLIENT path and the ACCOUNT value (in CLOUDSDK_CONFIG) with %q for safety.
  if [ -n "$ACCOUNT" ]; then
    printf 'CLOUDSDK_CONFIG=%q ' "$ROOT/.secrets/gcloud/$ACCOUNT"
  fi
  printf 'gcloud auth application-default login --client-id-file=%q --scopes=%s\n' "$CLIENT" "$SCOPES"
  exit 0
fi

require_cmd gcloud "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
[ -z "${GOOGLE_ACCOUNT:-}" ] || printf 'Expected account at login: %s\n\n' "$GOOGLE_ACCOUNT"

# Create the gcloud config directory only if --account was specified.
if [ -n "$ACCOUNT" ]; then
  mkdir -p "$ROOT/.secrets/gcloud/$ACCOUNT"
fi

# Print the command (for debugging) before running it.
# Quote the ACCOUNT value (in CLOUDSDK_CONFIG) with %q for safety.
if [ -n "$ACCOUNT" ]; then
  printf 'CLOUDSDK_CONFIG=%q ' "$ROOT/.secrets/gcloud/$ACCOUNT"
fi
printf '%s\n\n' "${cmd[*]}"

# Execute the command with the environment prefix.
if [ ${#env_prefix[@]} -gt 0 ]; then
  env "${env_prefix[@]}" "${cmd[@]}"
else
  "${cmd[@]}"
fi

# Report the ADC location and next steps.
if [ -n "$ACCOUNT" ]; then
  ADC_PATH="$ROOT/.secrets/gcloud/$ACCOUNT/application_default_credentials.json"
  printf '\nDone. ADC saved to: %s\n' "$ADC_PATH"
  printf 'Now run: scripts/setup.sh --print-mcp-config --account %q\n' "$ACCOUNT"
  printf 'and add its output to ~/.claude.json\n'
else
  printf '\nDone. Now run /mcp inside Claude Code to reconnect the servers.\n'
fi
