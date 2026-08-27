#!/usr/bin/env bash
_tmp="$(mktemp -d)"
printf 'ADC_FILE=%s/adc.json\nGSC_MCP_MODE=npx\n' "$_tmp" > "$_tmp/.env"

it "setup.sh --help exits 0 and lists the steps"
assert_exit 0 bash "$REPO_ROOT/scripts/setup.sh" --help
assert_contains "$(bash "$REPO_ROOT/scripts/setup.sh" --help)" "--print-mcp-config" "help documents the flag"

it "the printed MCP config is valid JSON"
_cfg="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg"

it "the config declares both servers and the configured ADC path"
assert_contains "$_cfg" "search-console-mcp" "GSC server declared"
assert_contains "$_cfg" "analytics-mcp" "GA4 server declared"
assert_contains "$_cfg" "$_tmp/adc.json" "ADC path comes from .env"

it "the config pins the search-console-mcp version rather than a bare package name (audit fix 4)"
_gsc_arg1="$(node -e "const c=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(c.mcpServers['search-console-mcp'].args[1])" <<< "$_cfg")"
assert_eq "search-console-mcp@2.1.1" "$_gsc_arg1" "npx arg carries the pinned version spec"

it "--account suffixes the server names and points at that account's ADC"
_cfg_a="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config --account me@example.com)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg_a"
assert_contains "$_cfg_a" "search-console-mcp-me@example.com" "server name carries the account"
assert_contains "$_cfg_a" ".secrets/gcloud/me@example.com/application_default_credentials.json" "per-account ADC path"

it "GSC_MCP_MODE=local switches the command to the local build"
printf 'ADC_FILE=%s/adc.json\nGSC_MCP_MODE=local\nGSC_MCP_PATH=%s/dist/index.js\n' "$_tmp" "$_tmp" > "$_tmp/.env-local"
_cfg_l="$(ENV_FILE="$_tmp/.env-local" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_contains "$_cfg_l" "$_tmp/dist/index.js" "local path is used"

it "an ADC_FILE containing a double quote is escaped, not corrupted"
printf 'ADC_FILE=%s/adc "quoted".json\nGSC_MCP_MODE=npx\n' "$_tmp" > "$_tmp/.env-dquote"
_cfg_dq="$(ENV_FILE="$_tmp/.env-dquote" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg_dq"
_parsed_dq="$(node -e "const c=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(c.mcpServers['analytics-mcp'].env.GOOGLE_APPLICATION_CREDENTIALS)" <<< "$_cfg_dq")"
assert_eq "$_tmp/adc \"quoted\".json" "$_parsed_dq" "parsed ADC path matches original with embedded quote"

it "an ADC_FILE containing a backslash (Windows path) is escaped, not corrupted"
printf 'ADC_FILE=C:\\Users\\me\\adc.json\nGSC_MCP_MODE=npx\n' > "$_tmp/.env-bslash"
_cfg_bs="$(ENV_FILE="$_tmp/.env-bslash" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg_bs"
_parsed_bs="$(node -e "const c=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(c.mcpServers['analytics-mcp'].env.GOOGLE_APPLICATION_CREDENTIALS)" <<< "$_cfg_bs")"
assert_eq 'C:\Users\me\adc.json' "$_parsed_bs" "parsed ADC path matches original with backslashes"

it "a GSC_MCP_PATH containing a backslash (Windows path) is escaped, not corrupted"
printf 'ADC_FILE=%s/adc.json\nGSC_MCP_MODE=local\nGSC_MCP_PATH=C:\\repo\\dist\\index.js\n' "$_tmp" > "$_tmp/.env-gscbslash"
_cfg_gbs="$(ENV_FILE="$_tmp/.env-gscbslash" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg_gbs"
_parsed_gbs="$(node -e "const c=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(c.mcpServers['search-console-mcp'].args[0])" <<< "$_cfg_gbs")"
assert_eq 'C:\repo\dist\index.js' "$_parsed_gbs" "parsed GSC path matches original with backslashes"

it "prerequisites step fails with the exact pipx install command when analytics-mcp is missing (C1)"
# Strip whichever PATH directory currently resolves analytics-mcp, so setup.sh's own
# prerequisite check is exercised regardless of whether this machine happens to have
# analytics-mcp installed via pipx. Keep every other PATH entry (coreutils, git, node,
# gcloud all still need to resolve).
_amc_path="$(command -v analytics-mcp 2>/dev/null || true)"
_amc_dir="$(dirname "$_amc_path" 2>/dev/null || true)"
_filtered_path="$PATH"
if [ -n "$_amc_dir" ]; then
  _filtered_path=""
  _oldifs="$IFS"; IFS=':'
  for _p in $PATH; do
    [ "$_p" = "$_amc_dir" ] && continue
    _filtered_path="${_filtered_path:+$_filtered_path:}$_p"
  done
  IFS="$_oldifs"
fi
_prereq_out="$(PATH="$_filtered_path" ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/setup.sh" 2>&1)"
_prereq_status=0
PATH="$_filtered_path" ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/setup.sh" >/dev/null 2>&1 || _prereq_status=$?
assert_eq "2" "$_prereq_status" "missing analytics-mcp is a missing-prerequisite exit"
assert_contains "$_prereq_out" "pipx install analytics-mcp" "the exact install command is printed"

it "README lists analytics-mcp/pipx as a prerequisite (C1)"
assert_contains "$(cat "$REPO_ROOT/README.md")" "pipx install analytics-mcp" "README mentions the install command"

it "checks.sh declares an analytics-mcp check with its own troubleshooting anchor (C1)"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/checks.sh"
_found_amc=0
for _row in "${CHECKS[@]}"; do
  case "$_row" in analytics-mcp\|*) _found_amc=1 ;; esac
done
assert_eq "1" "$_found_amc" "an analytics-mcp row exists in CHECKS"

it "the ADC path setup.sh --print-mcp-config --account emits matches where reconnect.sh --account writes (I1)"
_tmp_i1="$(mktemp -d)"
printf 'OAUTH_CLIENT_FILE=%s/client.json\nGSC_MCP_MODE=npx\n' "$_tmp_i1" > "$_tmp_i1/.env"
printf '{"installed":{"client_id":"x"}}\n' > "$_tmp_i1/client.json"
_reconnect_cmd="$(ENV_FILE="$_tmp_i1/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --account carol@example.com)"
# reconnect.sh --account writes its ADC at $ROOT/.secrets/gcloud/<email>/application_default_credentials.json
# (derived from CLOUDSDK_CONFIG in the printed command), where $ROOT is the repo root —
# reconnect.sh itself always resolves paths off repo_root(), never off ENV_FILE's directory.
_expected_adc="$REPO_ROOT/.secrets/gcloud/carol@example.com/application_default_credentials.json"
assert_contains "$_reconnect_cmd" "$REPO_ROOT/.secrets/gcloud/carol@example.com" "reconnect.sh's CLOUDSDK_CONFIG matches repo_root-derived path"
_setup_cfg="$(ENV_FILE="$_tmp_i1/.env" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config --account carol@example.com)"
_setup_adc="$(node -e "const c=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(c.mcpServers['analytics-mcp-carol@example.com'].env.GOOGLE_APPLICATION_CREDENTIALS)" <<< "$_setup_cfg")"
assert_eq "$_expected_adc" "$_setup_adc" "setup.sh's emitted ADC path is exactly the one reconnect.sh --account writes to"
rm -rf "$_tmp_i1"

it "setup.sh --account propagates to reconnect.sh, not just to --print-mcp-config (I1)"
assert_contains "$(cat "$REPO_ROOT/scripts/setup.sh")" 'bash "$HERE/reconnect.sh" --account "$ACCOUNT"' \
  "step 5 passes --account through to reconnect.sh"

rm -rf "$_tmp"
