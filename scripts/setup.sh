#!/usr/bin/env bash
# Guided bootstrap for a new hub. Every step either succeeds or stops and tells you
# exactly what to do. Nothing is configured behind your back — in particular,
# ~/.claude.json is never written for you.
#
# Contract:
#   input:  .env (created here if missing), interactive answers
#   output: progress on stdout, the MCP config block at the end
#   exit:   0 ok, 1 user error, 2 missing prerequisite
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: setup.sh [--non-interactive] [--print-mcp-config] [--account <email>]

Bootstraps the hub:
  1. check prerequisites (gcloud, node >= 22, git)
  2. create .env from .env.example
  3. enable the required Google Cloud APIs
  4. guide you through creating the desktop OAuth client
  5. generate the ADC credentials (via reconnect.sh)
  6. smoke-test the Search Console MCP server
  7. print the block to paste into ~/.claude.json
  8. run doctor.sh

  --non-interactive    skip prompts; fail if .env is missing
  --print-mcp-config   print step 7 only, then exit
  --account <email>    scope the whole run to this account: step 5 generates its ADC
                       via reconnect.sh --account, and step 7 (or --print-mcp-config
                       alone) emits per-account server entries reading that same file
  --help               show this message
EOF
}

NON_INTERACTIVE=0
PRINT_CONFIG_ONLY=0
ACCOUNT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --print-mcp-config) PRINT_CONFIG_ONLY=1; shift ;;
    --account) ACCOUNT="${2-}"; [ -n "$ACCOUNT" ] || die "--account needs an email"; shift 2 ;;
    *) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

# Validate account argument if present: must match a conservative email pattern.
# Pattern: local@domain.tld where local=[a-zA-Z0-9._%+-]+ and domain has at least one dot.
# Kept identical to reconnect.sh and new-tenant.sh so all three scripts agree.
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

ROOT="$(repo_root)"

print_mcp_config() {
  load_env
  local adc suffix=""
  if [ -n "${ACCOUNT:-}" ]; then
    adc="$(repo_root)/.secrets/gcloud/$ACCOUNT/application_default_credentials.json"
    suffix="-$ACCOUNT"
  else
    adc="${ADC_FILE:-$HOME/.config/gcloud/application_default_credentials.json}"
  fi
  local gsc_mode="${GSC_MCP_MODE:-npx}"
  local gsc_path=""
  if [ "$gsc_mode" = "local" ]; then
    [ -n "${GSC_MCP_PATH:-}" ] || die "GSC_MCP_MODE=local but GSC_MCP_PATH is empty"
    gsc_path="$GSC_MCP_PATH"
  fi
  # Build the JSON with node/JSON.stringify rather than string-splicing values into a
  # heredoc: adc and gsc_path are arbitrary filesystem paths (Windows ones routinely
  # contain backslashes, and any path can contain a double quote), so hand-rolled
  # interpolation risks emitting invalid JSON. Passing them as argv and letting
  # JSON.stringify escape them removes that whole class of bug.
  node -e '
    const [suffix, adc, gscMode, gscPath] = process.argv.slice(1);
    const gsc = gscMode === "local"
      ? { command: "node", args: [gscPath] }
      : { command: "npx", args: ["-y", "search-console-mcp@2.1.3"] };
    const config = {
      mcpServers: {
        ["analytics-mcp" + suffix]: {
          type: "stdio",
          command: "analytics-mcp",
          args: [],
          env: { GOOGLE_APPLICATION_CREDENTIALS: adc }
        },
        ["search-console-mcp" + suffix]: {
          type: "stdio",
          command: gsc.command,
          args: gsc.args,
          env: { GOOGLE_APPLICATION_CREDENTIALS: adc }
        }
      }
    };
    process.stdout.write(JSON.stringify(config, null, 2) + "\n");
  ' -- "$suffix" "$adc" "$gsc_mode" "$gsc_path"
}

if [ "$PRINT_CONFIG_ONLY" -eq 1 ]; then
  print_mcp_config
  exit 0
fi

printf '== 1. Prerequisites ==\n'
require_cmd git "Install git: https://git-scm.com/downloads"
require_cmd node "Install Node.js 22 or newer: https://nodejs.org"
require_cmd gcloud "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
if ! command -v analytics-mcp >/dev/null 2>&1; then
  cat <<'EOF' >&2
error: analytics-mcp is not installed.

The GA4 MCP server is a Python package, installed separately from the Node-based
search-console-mcp server. Install it with pipx (https://pipx.pypa.io/):

  pipx install analytics-mcp==0.7.0

Then re-run setup.sh. See docs/02-mcp-servers.md for details.
EOF
  exit "$EXIT_PREREQ"
fi
bash "$HERE/doctor.sh" --only node
bash "$HERE/doctor.sh" --only gcloud
bash "$HERE/doctor.sh" --only analytics-mcp

printf '\n== 2. Configuration ==\n'
if [ ! -f "$ROOT/.env" ]; then
  [ "$NON_INTERACTIVE" -eq 0 ] || die ".env is missing and --non-interactive was given"
  cp "$ROOT/.env.example" "$ROOT/.env"
  printf 'Created .env from .env.example.\n'
  printf 'Open it now, fill in GCP_PROJECT_ID and GOOGLE_ACCOUNT, then re-run setup.sh.\n'
  exit 0
fi
load_env
require_env GCP_PROJECT_ID
printf 'Using project %s\n' "$GCP_PROJECT_ID"

printf '\n== 3. Google Cloud APIs ==\n'
gcloud services enable \
  analyticsadmin.googleapis.com \
  analyticsdata.googleapis.com \
  searchconsole.googleapis.com \
  --project="$GCP_PROJECT_ID"
printf 'Enabled.\n'

printf '\n== 4. OAuth client ==\n'
require_env OAUTH_CLIENT_FILE
CLIENT="$OAUTH_CLIENT_FILE"
case "$CLIENT" in /*) ;; *) CLIENT="$ROOT/$CLIENT" ;; esac
if [ ! -f "$CLIENT" ]; then
  cat <<EOF
No OAuth client at $CLIENT.

Create one in the Google Cloud console (this part cannot be automated):
  1. APIs & Services > OAuth consent screen. Choose Internal if your account is
     part of a Workspace organisation — with External in testing mode, refresh
     tokens expire every 7 days.
  2. APIs & Services > Credentials > Create credentials > OAuth client ID.
  3. Application type: Desktop app.
  4. Download the JSON and save it as: $CLIENT

Full walkthrough: docs/01-google-cloud-setup.md
EOF
  exit "$EXIT_USER"
fi
printf 'OAuth client present.\n'

printf '\n== 5. Credentials ==\n'
if [ -n "$ACCOUNT" ]; then
  bash "$HERE/reconnect.sh" --account "$ACCOUNT"
else
  bash "$HERE/reconnect.sh"
fi

printf '\n== 6. Search Console MCP server ==\n'
bash "$HERE/doctor.sh" --only gsc-server || {
  printf 'The server did not start cleanly. See docs/99-troubleshooting.md#native-module\n'
  exit "$EXIT_USER"
}

printf '\n== 7. MCP configuration ==\n'
printf 'Back up ~/.claude.json, then merge this into it (under your project, or at top level):\n\n'
print_mcp_config

printf '\nThen restart Claude Code, or run /mcp to connect the servers.\n'

printf '\n== 8. Final check ==\n'
bash "$HERE/doctor.sh"
