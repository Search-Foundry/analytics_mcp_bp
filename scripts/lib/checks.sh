#!/usr/bin/env bash
# The diagnostic checks, expressed as data plus one function each.
# Adding a check means adding a row and a function — no control flow to edit.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Each check function returns: 0 = OK, 1 = FAIL, 3 = WARN.
# It may print a detail line; doctor.sh wraps it with the OK/WARN/FAIL prefix.

check_node() {
  command -v node >/dev/null 2>&1 || { echo "node is not installed"; return 1; }
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -lt 22 ]; then
    echo "node $major is too old, 22 or newer is required"
    return 1
  fi
  echo "node $(node -v)"
}

check_gcloud() {
  command -v gcloud >/dev/null 2>&1 || { echo "gcloud is not installed"; return 1; }
  echo "gcloud $(gcloud version --format='value(core)' 2>/dev/null | head -n 1)"
}

check_analytics_mcp() {
  command -v analytics-mcp >/dev/null 2>&1 || {
    echo "analytics-mcp is not installed — run: pipx install analytics-mcp==0.7.0"
    return 1
  }
  echo "analytics-mcp is on PATH"
}

check_adc_file() {
  local adc="${ADC_FILE:-$HOME/.config/gcloud/application_default_credentials.json}"
  [ -f "$adc" ] || { echo "no ADC file at $adc"; return 1; }
  echo "ADC file present"
}

check_adc_scopes() {
  local adc="${ADC_FILE:-$HOME/.config/gcloud/application_default_credentials.json}"
  [ -f "$adc" ] || { echo "no ADC file to inspect"; return 1; }
  local token missing=""
  token="$(json_get "$adc" refresh_token)"
  [ -n "$token" ] || { echo "ADC has no refresh token — it is not a user OAuth credential"; return 1; }
  # The granted scopes are reported by the tokeninfo endpoint, not stored in the file.
  local granted
  granted="$(gcloud auth application-default print-access-token 2>/dev/null \
    | while IFS= read -r at; do
        node -e '
          const https = require("https");
          https.get("https://oauth2.googleapis.com/tokeninfo?access_token=" + process.argv[1],
            r => { let b = ""; r.on("data", d => b += d);
                   r.on("end", () => { try { process.stdout.write(JSON.parse(b).scope || ""); }
                                       catch { process.stdout.write(""); } }); })
            .on("error", () => process.stdout.write(""));
        ' "$at"
      done)"
  [ -n "$granted" ] || { echo "could not read the token scopes (expired or offline?)"; return 3; }
  for want in analytics.readonly webmasters.readonly cloud-platform; do
    case "$granted" in *"$want"*) ;; *) missing="$missing $want" ;; esac
  done
  [ -z "$missing" ] || { echo "ADC is missing scopes:$missing"; return 1; }
  echo "all three scopes granted"
}

check_gcp_apis() {
  [ -n "${GCP_PROJECT_ID:-}" ] || { echo "GCP_PROJECT_ID is not set in .env"; return 3; }
  local enabled missing=""
  enabled="$(gcloud services list --enabled --project="$GCP_PROJECT_ID" \
    --format='value(config.name)' 2>/dev/null)" || { echo "could not query the project"; return 3; }
  for api in analyticsadmin.googleapis.com analyticsdata.googleapis.com searchconsole.googleapis.com; do
    case "$enabled" in *"$api"*) ;; *) missing="$missing $api" ;; esac
  done
  [ -z "$missing" ] || { echo "disabled APIs:$missing"; return 1; }
  echo "all three APIs enabled"
}

check_gsc_server() {
  local mode="${GSC_MCP_MODE:-npx}"
  local budget=15
  if [ "$mode" = "local" ]; then
    [ -n "${GSC_MCP_PATH:-}" ] || { echo "GSC_MCP_MODE=local but GSC_MCP_PATH is empty"; return 1; }
    budget=3
  fi

  local workdir
  workdir="$(mktemp -d)" || { echo "could not create a temp directory"; return 1; }
  local out_file="$workdir/out.log"
  local pid_file="$workdir/pid"

  # Run the server in its own process group (job control enabled with `set -m`
  # inside this subshell) so that when we are done we can signal it and every
  # child it spawned in one shot, instead of only the direct child (`kill %1`
  # in the previous version left grandchildren — e.g. npx's node child —
  # running with the output pipe held open, which could hang the caller).
  (
    set -m
    if [ "$mode" = "local" ]; then
      GOOGLE_APPLICATION_CREDENTIALS="${ADC_FILE:-}" node "$GSC_MCP_PATH" >"$out_file" 2>&1 &
    else
      GOOGLE_APPLICATION_CREDENTIALS="${ADC_FILE:-}" npx -y search-console-mcp@2.1.3 >"$out_file" 2>&1 &
    fi
    echo "$!" > "$pid_file"
    wait
  ) &
  local runner_pid=$!

  # Poll instead of a fixed sleep so we return as soon as the outcome is
  # known, and never wait past the budget (no GNU `timeout` available).
  local elapsed=0 out=""
  while [ "$elapsed" -lt "$budget" ]; do
    out="$(cat "$out_file" 2>/dev/null || true)"
    case "$out" in
      *"Cannot find module"*|*"✔ Google"*) break ;;
    esac
    sleep 1
    elapsed=$((elapsed + 1))
  done
  out="$(cat "$out_file" 2>/dev/null || true)"

  # Clean up on every path: kill the whole process group, reap the runner,
  # remove the temp dir. Nothing is left running or on disk afterward.
  if [ -f "$pid_file" ]; then
    local child_pid
    child_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$child_pid" ]; then
      kill -TERM -- "-$child_pid" 2>/dev/null || kill "$child_pid" 2>/dev/null || true
    fi
  fi
  kill "$runner_pid" 2>/dev/null || true
  wait "$runner_pid" 2>/dev/null || true
  rm -rf "$workdir"

  case "$out" in
    *"Cannot find module"*) echo "a native module failed to load: $out"; return 1 ;;
    *"✔ Google"*) echo "server starts and authenticates against Google" ; return 0 ;;
    *) echo "server did not report a healthy Google connection"; return 1 ;;
  esac
}

# id|description|function|troubleshooting anchor
CHECKS=(
  "node|Node.js 22 or newer|check_node|99-troubleshooting.md#node-version"
  "gcloud|Google Cloud SDK|check_gcloud|99-troubleshooting.md#gcloud-missing"
  "analytics-mcp|analytics-mcp installed (pipx)|check_analytics_mcp|99-troubleshooting.md#analytics-mcp-missing"
  "adc-file|ADC credentials file exists|check_adc_file|99-troubleshooting.md#adc-missing"
  "adc-scopes|ADC carries all three scopes|check_adc_scopes|99-troubleshooting.md#missing-scopes"
  "gcp-apis|Required GCP APIs enabled|check_gcp_apis|99-troubleshooting.md#apis-not-enabled"
  "gsc-server|Search Console MCP server starts|check_gsc_server|99-troubleshooting.md#native-module"
)
