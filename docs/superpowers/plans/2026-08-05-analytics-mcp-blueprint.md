# analytics-mcp-blueprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Costruire un repository blueprint open source che permetta a chiunque di replicare un hub locale multi-tenant per analisi GA4 + Google Search Console guidate da Claude Code via MCP.

**Architecture:** Repo-template senza codice applicativo. Quattro script bash guidati (`setup`, `reconnect`, `doctor`, `new-tenant`) che condividono una libreria comune `scripts/lib/common.sh` per config, logging e check di portabilità; documentazione numerata in `docs/`; template di tenant, playbook estendibili e skill Claude Code. Tutta la configurazione locale passa da `.env`: zero path assoluti hardcodati.

**Tech Stack:** bash (POSIX-ish, no GNU-isms né BSD-isms), `node >= 22` (già prerequisito, usato anche per il parsing JSON al posto di `jq`), `gcloud`, Markdown.

## Global Constraints

Copiati verbatim dalla spec. Valgono per **ogni** task.

- **Nessun path assoluto hardcodato.** Tutta la configurazione locale passa da `.env` (non committato), letto dagli script.
- **Nessun dato reale.** Nessun property ID, client ID, sito, nome cliente o `.secrets/` proveniente dall'hub privato. Solo placeholder.
- **Portabilità Windows (vincolante).** Niente `sed -i ''`, `realpath`, `readlink -f`, `mktemp -t`, `grep -P`, `date -j`. Niente `jq`: il parsing JSON passa da `node -e`.
- **Contratto di script esplicito** in testa a ogni script: input (variabili `.env` lette), output (stdout strutturato), exit code — `0` OK, `1` errore utente, `2` prerequisito mancante.
- **Logica in dati, non nel flusso di controllo**: ordine dei check, messaggi ed errore → sezione di troubleshooting vivono in tabelle/array, così la porta PowerShell è meccanica.
- **Ogni script**: `set -euo pipefail`, supporta `--help`, fallisce con un messaggio che dice cosa fare — mai in silenzio.
- **Nessuna scrittura automatica di `~/.claude.json`**: si stampa il blocco da incollare.
- **Versioni upstream target**: `search-console-mcp` **2.0.1** (npm, senza `re2`, 7 fluent domain tools), `analytics-mcp` **0.7.0** (PyPI).
- **Scope OAuth** (sempre questi tre, in quest'ordine): `https://www.googleapis.com/auth/analytics.readonly`, `https://www.googleapis.com/auth/webmasters.readonly`, `https://www.googleapis.com/auth/cloud-platform`.
- **API GCP** da abilitare: `analyticsadmin.googleapis.com`, `analyticsdata.googleapis.com`, `searchconsole.googleapis.com`.
- **Lingua**: `README.md` EN, `README.it.md` IT, `docs/` in EN. Il codice e i messaggi degli script in EN.
- **Modello multi-account** (revisione 2026-08-05, spec §6 e §15): i tenant vivono in
  `accounts/<email-account-google>/<tenant>/`. Le credenziali sono per account:
  `reconnect.sh --account <email>` esegue il login con `CLOUDSDK_CONFIG` puntato a
  `.secrets/gcloud/<email>/`, e l'ADC finisce in
  `.secrets/gcloud/<email>/application_default_credentials.json`. Senza `--account` si usa la
  posizione ADC di default. **Mai** `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`: serve solo in
  lettura e non redirige la scrittura del login.
- **Mai `eval` per costruire comandi.** I comandi hanno forma fissa: si usano array bash eseguiti
  direttamente, così nessun valore proveniente da `.env` o dalla riga di comando può essere
  interpretato come shell.

## File Structure

Rispetto alla §4 della spec, il piano aggiunge due cartelle che la spec non nominava ma che i suoi vincoli implicano: `scripts/lib/` (per tenere la logica in dati condivisi e rendere la porta PowerShell meccanica) e `tests/` (per poter verificare gli script senza dipendenze esterne).

| File | Responsabilità |
|---|---|
| `scripts/lib/common.sh` | Caricamento `.env`, risoluzione path, logging `OK/WARN/FAIL`, exit code, `require_cmd`. Nessun side effect all'import. |
| `scripts/lib/checks.sh` | Tabella dei check diagnostici (id, descrizione, comando, sezione di troubleshooting). Dati, non flusso. |
| `scripts/doctor.sh` | Esegue la tabella dei check, stampa il report, exit code aggregato. |
| `scripts/reconnect.sh` | Rigenera l'ADC con gli scope corretti. Supporta `--account <email>`. |
| `scripts/setup.sh` | Bootstrap in 8 passi. Orchestratore: delega a `doctor.sh` e `reconnect.sh`. |
| `scripts/new-tenant.sh` | Copia `templates/tenant/` in `accounts/<email>/<tenant>/`, sostituisce placeholder, registra la riga nel `CLAUDE.md` di quell'account. |
| `tests/run.sh` | Runner + assert in puro bash. Nessuna dipendenza (no bats). |
| `tests/test_*.sh` | Un file per script testato. |
| `docs/*.md` | Documentazione numerata, EN. |
| `templates/tenant/*` | Scaffolding di un tenant. |
| `templates/account/*` | Scaffolding di una cartella account (il suo `CLAUDE.md` con la tabella tenant). |
| `playbooks/*` | Albero estendibile + 1 ricetta d'esempio. |
| `.claude/skills/*/SKILL.md` | Skill sottili che chiamano gli script e ne interpretano l'output. |

---

### Task 1: Scaffolding, .gitignore e test harness

**Files:**
- Create: `.gitignore`, `LICENSE`, `.env.example`, `tests/run.sh`, `tests/test_harness.sh`

**Interfaces:**
- Consumes: niente (primo task).
- Produces: `tests/run.sh` (runner, eseguibile senza argomenti, scopre `tests/test_*.sh`); le funzioni `assert_eq <atteso> <ottenuto> <messaggio>`, `assert_contains <aiaco> <ago> <messaggio>`, `assert_exit <codice-atteso> <comando...>`, e `it <descrizione>` per aprire un caso. Ogni `test_*.sh` è uno script bash sorgente-ato dal runner.

- [ ] **Step 1: Scrivere il test del harness (che fallisce perché il harness non esiste)**

`tests/test_harness.sh`:

```bash
#!/usr/bin/env bash
# Verifies the assertion helpers themselves.

it "assert_eq passes on equal values"
assert_eq "a" "a" "identical strings are equal"

it "assert_contains finds a substring"
assert_contains "hello world" "world" "substring is found"

it "assert_exit captures a non-zero exit code"
assert_exit 3 bash -c 'exit 3'
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `bash: tests/run.sh: No such file or directory`

- [ ] **Step 3: Scrivere il runner**

`tests/run.sh`:

```bash
#!/usr/bin/env bash
# Minimal test runner. No external dependencies by design (see Global Constraints).
#
# Contract:
#   input:  none (discovers tests/test_*.sh relative to this file)
#   output: one line per assertion, summary on the last line
#   exit:   0 all passed, 1 at least one failed
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export REPO_ROOT

_pass=0
_fail=0
_current="(no case)"

it() { _current="$1"; }

_ok()   { _pass=$((_pass + 1)); printf '  ok   %s: %s\n' "$_current" "$1"; }
_notok() { _fail=$((_fail + 1)); printf '  FAIL %s: %s\n' "$_current" "$1"; }

assert_eq() {
  if [ "$1" = "$2" ]; then _ok "$3"; else _notok "$3 (expected '$1', got '$2')"; fi
}

assert_contains() {
  case "$1" in
    *"$2"*) _ok "$3" ;;
    *)      _notok "$3 (expected to find '$2')" ;;
  esac
}

assert_exit() {
  local expected="$1"; shift
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$expected" -eq "$actual" ]; then
    _ok "exit code $expected"
  else
    _notok "exit code (expected $expected, got $actual)"
  fi
}

for f in "$TESTS_DIR"/test_*.sh; do
  [ -e "$f" ] || continue
  printf '%s\n' "$(basename "$f")"
  # shellcheck disable=SC1090
  . "$f"
done

printf '\n%d passed, %d failed\n' "$_pass" "$_fail"
[ "$_fail" -eq 0 ]
```

- [ ] **Step 4: Eseguire per verificare che passi**

Run: `bash tests/run.sh`
Expected: PASS — `3 passed, 0 failed`

- [ ] **Step 5: Scrivere `.gitignore`**

```gitignore
# Local configuration and secrets — never commit
.env
.secrets/
*application_default_credentials.json

# Tenant data belongs to clients, not to this repo
*/data/
*/exports/

# Locally built MCP server (troubleshooting fallback only)
gsc-mcp/
node_modules/

.DS_Store
```

- [ ] **Step 6: Scrivere `.env.example`**

```bash
# Copy to .env and fill in. Never commit .env.
# Every script in scripts/ reads its configuration from here.

# Google Cloud project hosting the OAuth client and the enabled APIs.
GCP_PROJECT_ID=

# Google account expected at login. Used for a coherence warning, not enforced.
GOOGLE_ACCOUNT=

# Desktop OAuth client JSON downloaded from the Google Cloud console.
OAUTH_CLIENT_FILE=.secrets/oauth-client.json

# Application Default Credentials file both MCP servers read.
# macOS/Linux default below. On Windows see docs/07-windows.md.
ADC_FILE=$HOME/.config/gcloud/application_default_credentials.json

# How the Search Console MCP server is launched: npx (default) or local.
# "local" is a troubleshooting fallback only — see docs/99-troubleshooting.md.
GSC_MCP_MODE=npx

# Path to dist/index.js when GSC_MCP_MODE=local. Leave empty otherwise.
GSC_MCP_PATH=
```

- [ ] **Step 7: Scrivere `LICENSE`**

Testo integrale della licenza MIT, `Copyright (c) 2026 analytics-mcp-blueprint contributors`.

- [ ] **Step 8: Commit**

```bash
git add .gitignore LICENSE .env.example tests/
git commit -m "chore: scaffolding, gitignore and dependency-free test harness"
```

---

### Task 2: `scripts/lib/common.sh` — config, logging, portabilità

**Files:**
- Create: `scripts/lib/common.sh`, `tests/test_common.sh`

**Interfaces:**
- Consumes: `tests/run.sh` e i suoi assert (Task 1); `.env.example` (Task 1).
- Produces, tutte sorgente-abili da altri script:
  - `repo_root` → stampa la root del repo (risolta senza `realpath`).
  - `load_env` → carica `.env` se esiste; espande `$HOME` nei valori; non fallisce se manca.
  - `require_env <NOME>` → exit `1` con messaggio se la variabile è vuota.
  - `require_cmd <comando> <hint-installazione>` → exit `2` se il comando manca.
  - `log_ok <msg>` / `log_warn <msg>` / `log_fail <msg> <sezione-troubleshooting>` → stdout `OK: ` / `WARN: ` / `FAIL: ` + rimando.
  - `die <msg>` → stderr + exit `1`.
  - `EXIT_OK=0`, `EXIT_USER=1`, `EXIT_PREREQ=2`.
  - `json_get <file> <chiave-dotted>` → stampa un valore da un JSON usando `node -e` (mai `jq`).

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_common.sh`:

```bash
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
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `scripts/lib/common.sh: No such file or directory`

- [ ] **Step 3: Implementare `scripts/lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for every script in scripts/.
#
# Contract:
#   input:  .env (path overridable via ENV_FILE)
#   output: OK:/WARN:/FAIL: lines on stdout, errors on stderr
#   exit:   0 ok, 1 user error, 2 missing prerequisite
#
# Portability: no realpath, readlink -f, sed -i, grep -P, jq. JSON goes through node.
# A PowerShell port must reproduce this contract, not this implementation.

EXIT_OK=0
EXIT_USER=1
EXIT_PREREQ=2

repo_root() {
  # Resolved without realpath: cd + pwd works on macOS, Linux and Git Bash.
  ( cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd )
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit "$EXIT_USER"
}

log_ok()   { printf 'OK:   %s\n' "$1"; }
log_warn() { printf 'WARN: %s\n' "$1"; }

log_fail() {
  # $1 message, $2 troubleshooting anchor
  printf 'FAIL: %s\n      see docs/%s\n' "$1" "$2"
}

require_cmd() {
  # $1 command, $2 installation hint
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n       %s\n' "$1" "$2" >&2
    exit "$EXIT_PREREQ"
  fi
}

require_env() {
  local name="$1"
  local value="${!name-}"
  [ -n "$value" ] || die "$name is not set. Fill it in .env (see .env.example)."
}

load_env() {
  local env_file="${ENV_FILE:-$(repo_root)/.env}"
  [ -f "$env_file" ] || return 0
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    [ "$key" = "$line" ] && continue
    # Expand $HOME and friends without eval'ing arbitrary command substitution.
    value="${value//\$HOME/$HOME}"
    value="${value//\$\{HOME\}/$HOME}"
    export "$key=$value"
  done < "$env_file"
}

json_get() {
  # $1 json file, $2 dotted key. Uses node because jq is not a project prerequisite.
  node -e '
    const [file, key] = process.argv.slice(1);
    const data = JSON.parse(require("fs").readFileSync(file, "utf8"));
    const value = key.split(".").reduce((o, k) => (o == null ? o : o[k]), data);
    process.stdout.write(value == null ? "" : String(value));
  ' "$1" "$2"
}
```

- [ ] **Step 4: Eseguire per verificare che passi**

Run: `bash tests/run.sh`
Expected: PASS — tutte le asserzioni di `test_common.sh` verdi.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/common.sh tests/test_common.sh
git commit -m "feat(scripts): shared config, logging and portable JSON helpers"
```

---

### Task 3: `scripts/lib/checks.sh` e `scripts/doctor.sh`

**Files:**
- Create: `scripts/lib/checks.sh`, `scripts/doctor.sh`, `tests/test_doctor.sh`

**Interfaces:**
- Consumes: da `common.sh` — `load_env`, `log_ok`, `log_warn`, `log_fail`, `json_get`, `EXIT_*`.
- Produces:
  - `CHECKS` (array in `checks.sh`): righe `id|descrizione|funzione|ancora-troubleshooting`.
  - Funzioni di check, ognuna esce `0` OK, `1` FAIL, `3` WARN: `check_node`, `check_gcloud`, `check_adc_file`, `check_adc_scopes`, `check_gcp_apis`, `check_gsc_server`.
  - `scripts/doctor.sh` — esegue tutti i check; exit `0` se nessun FAIL, `1` altrimenti. Supporta `--help` e `--only <id>`.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_doctor.sh`:

```bash
#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/checks.sh"

it "the checks table is data, one row per check"
assert_eq "6" "${#CHECKS[@]}" "six checks are declared"
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
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `scripts/lib/checks.sh: No such file or directory`

- [ ] **Step 3: Implementare `scripts/lib/checks.sh`**

```bash
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
  local out
  if [ "${GSC_MCP_MODE:-npx}" = "local" ]; then
    [ -n "${GSC_MCP_PATH:-}" ] || { echo "GSC_MCP_MODE=local but GSC_MCP_PATH is empty"; return 1; }
    out="$(GOOGLE_APPLICATION_CREDENTIALS="${ADC_FILE:-}" node "$GSC_MCP_PATH" 2>&1 & sleep 3; kill %1 2>/dev/null; true)"
  else
    out="$(GOOGLE_APPLICATION_CREDENTIALS="${ADC_FILE:-}" npx -y search-console-mcp 2>&1 & sleep 15; kill %1 2>/dev/null; true)"
  fi
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
  "adc-file|ADC credentials file exists|check_adc_file|99-troubleshooting.md#adc-missing"
  "adc-scopes|ADC carries all three scopes|check_adc_scopes|99-troubleshooting.md#missing-scopes"
  "gcp-apis|Required GCP APIs enabled|check_gcp_apis|99-troubleshooting.md#apis-not-enabled"
  "gsc-server|Search Console MCP server starts|check_gsc_server|99-troubleshooting.md#native-module"
)
```

- [ ] **Step 4: Implementare `scripts/doctor.sh`**

```bash
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
Usage: doctor.sh [--only <check-id>]

Runs the diagnostic checks and reports OK / WARN / FAIL for each one,
pointing failures at the matching section of docs/99-troubleshooting.md.

  --only <check-id>   run a single check
  --help              show this message

Check ids: node, gcloud, adc-file, adc-scopes, gcp-apis, gsc-server
EOF
}

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --only) ONLY="${2-}"; [ -n "$ONLY" ] || die "--only needs a check id"; shift 2 ;;
    *) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

load_env

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
```

- [ ] **Step 5: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — le cinque asserzioni di `test_doctor.sh` verdi.

- [ ] **Step 6: Commit**

```bash
chmod +x scripts/doctor.sh
git add scripts/lib/checks.sh scripts/doctor.sh tests/test_doctor.sh
git commit -m "feat(scripts): data-driven diagnostics with doctor.sh"
```

---

### Task 4: `scripts/reconnect.sh`

**Files:**
- Create: `scripts/reconnect.sh`, `tests/test_reconnect.sh`

**Interfaces:**
- Consumes: da `common.sh` — `load_env`, `require_env`, `require_cmd`, `die`, `EXIT_*`.
- Produces: `scripts/reconnect.sh`, che supporta `--help`, `--account <email>` e `--print-command` (stampa il comando `gcloud` senza eseguirlo — è ciò che rende lo script testabile e la porta PowerShell verificabile). Con `--account`, il comando è preceduto dall'assegnazione di `CLOUDSDK_CONFIG` a `.secrets/gcloud/<email>/`. Il comando è costruito come array bash ed eseguito direttamente: mai `eval`.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_reconnect.sh`:

```bash
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

it "--profile redirects the credentials to a per-profile ADC file"
_cmd_p="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command --profile acme)"
assert_contains "$_cmd_p" ".secrets/adc/acme.json" "profile path is used"

it "a missing OAuth client file is a user error, not a crash"
printf 'OAUTH_CLIENT_FILE=%s/nope.json\n' "$_tmp" > "$_tmp/.env-bad"
assert_exit 1 env ENV_FILE="$_tmp/.env-bad" bash "$REPO_ROOT/scripts/reconnect.sh" --print-command

rm -rf "$_tmp"
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `scripts/reconnect.sh: No such file or directory`

- [ ] **Step 3: Implementare `scripts/reconnect.sh`**

```bash
#!/usr/bin/env bash
# Refreshes the Application Default Credentials both MCP servers read.
# Run it when the servers answer with invalid_rapt, invalid_grant,
# "reauthentication needed" or 401 — see docs/03-auth-and-rapt.md.
#
# Contract:
#   input:  .env (OAUTH_CLIENT_FILE, GOOGLE_ACCOUNT), optional --profile
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
Usage: reconnect.sh [--profile <name>] [--print-command]

Regenerates the ADC credentials with the three scopes both MCP servers need.
Afterwards, run /mcp inside Claude Code to reconnect the servers.

  --profile <name>   write to .secrets/adc/<name>.json instead of the gcloud
                     default location — for tenants on a different Google account
  --print-command    print the gcloud command and exit, without running it
  --help             show this message
EOF
}

PROFILE=""
PRINT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --profile) PROFILE="${2-}"; [ -n "$PROFILE" ] || die "--profile needs a name"; shift 2 ;;
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

CMD="gcloud auth application-default login --client-id-file=\"$CLIENT\" --scopes=\"$SCOPES\""
if [ -n "$PROFILE" ]; then
  CMD="CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=\"$ROOT/.secrets/adc/$PROFILE.json\" $CMD"
fi

if [ "$PRINT_ONLY" -eq 1 ]; then
  printf '%s\n' "$CMD"
  exit 0
fi

require_cmd gcloud "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
[ -z "${GOOGLE_ACCOUNT:-}" ] || printf 'Expected account at login: %s\n\n' "$GOOGLE_ACCOUNT"
[ -z "$PROFILE" ] || mkdir -p "$ROOT/.secrets/adc"

printf '%s\n\n' "$CMD"
eval "$CMD"

printf '\nDone. Now run /mcp inside Claude Code to reconnect the servers.\n'
```

- [ ] **Step 4: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — le sei asserzioni di `test_reconnect.sh` verdi.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/reconnect.sh
git add scripts/reconnect.sh tests/test_reconnect.sh
git commit -m "feat(scripts): reconnect.sh with profile support and printable command"
```

---

### Task 5: `templates/account/`, `templates/tenant/` e `scripts/new-tenant.sh`

**Files:**
- Create: `templates/account/CLAUDE.md`, `templates/tenant/CLAUDE.md`, `templates/tenant/README.md`, `templates/tenant/data/.gitkeep`, `templates/tenant/exports/.gitkeep`, `templates/tenant/analysis/.gitkeep`, `scripts/new-tenant.sh`, `tests/test_new_tenant.sh`

**Interfaces:**
- Consumes: da `common.sh` — `load_env`, `die`, `repo_root`, `EXIT_*`.
- Produces: `scripts/new-tenant.sh <name> --account <email> [--ga4 <id>] [--gsc <url>] [--root <path>]`.
  - `--account` è obbligatorio. Il tenant viene creato in `<root>/accounts/<email>/<name>/`, dove `<root>` è la radice dell'hub e vale `$PWD` salvo `--root`.
  - Se `accounts/<email>/` non esiste, viene creata da `templates/account/` — così il primo tenant di un account porta con sé la cartella dell'account.
  - I placeholder sostituiti sono esattamente `{{TENANT_NAME}}`, `{{GA4_PROPERTY_ID}}`, `{{GSC_SITE_URL}}`, `{{ACCOUNT_EMAIL}}`.
  - Il marcatore nel `CLAUDE.md` dell'account è la riga letterale `<!-- tenants -->`: le righe di tabella vengono inserite subito sotto.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_new_tenant.sh`:

```bash
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

rm -rf "$_tmp"
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `scripts/new-tenant.sh: No such file or directory`

- [ ] **Step 3: Scrivere i template**

`templates/account/CLAUDE.md`:

```markdown
# Account: {{ACCOUNT_EMAIL}}

Every tenant in this folder is accessed with the Google account above. Claude loads this file
when working anywhere under it.

## Tenants

| Tenant | GA4 property ID | GSC site | Status |
|---|---|---|---|
<!-- tenants -->

Add one: `./scripts/new-tenant.sh <name> --account {{ACCOUNT_EMAIL}} --ga4 <id> --gsc <url>`

## Credentials

This account has its own credentials, separate from every other account in this hub:

- gcloud config directory: `.secrets/gcloud/{{ACCOUNT_EMAIL}}/`
- ADC file: `.secrets/gcloud/{{ACCOUNT_EMAIL}}/application_default_credentials.json`

Renew them with `./scripts/reconnect.sh --account {{ACCOUNT_EMAIL}}`, then `/mcp` in Claude Code.

Because MCP servers take a fixed environment, this account needs its own server entries in
`~/.claude.json` pointing at the ADC file above — see `docs/03-auth-and-rapt.md`.
```

`templates/tenant/CLAUDE.md`:

```markdown
# {{TENANT_NAME}}

Project-specific context for this tenant. Claude Code loads this file when working in
this folder. Keep it short and factual: it is read on every session.

## Identity

| Property | Value |
|---|---|
| Google account | {{ACCOUNT_EMAIL}} |
| GA4 property ID | {{GA4_PROPERTY_ID}} |
| GSC site | {{GSC_SITE_URL}} |

## What this site is

<!-- One paragraph: what the business does, who the audience is, what "good" looks like. -->

## Known quirks

<!-- Seasonality, bot traffic, tracking gaps, migrations - anything that would make an
     analyst misread the numbers. Add to this list as you learn. -->

## Folder conventions

- `data/` - raw exports, gitignored
- `exports/` - generated CSV/reports, gitignored
- `analysis/` - written findings, committed
```

`templates/tenant/README.md`:

```markdown
# {{TENANT_NAME}}

Working folder for this tenant, under the Google account {{ACCOUNT_EMAIL}}.
See `CLAUDE.md` for the identity and context Claude reads.

`data/` and `exports/` are gitignored: they hold client data.
```

I tre `.gitkeep` sono file vuoti.

- [ ] **Step 4: Implementare `scripts/new-tenant.sh`**

Requisiti (il codice va scritto rispettandoli, non c'è un blocco da copiare):

- Contratto in testa, `set -euo pipefail`, `--help`, exit `0`/`1`/`2` come gli altri script, sorgente `lib/common.sh`.
- Argomenti: `<name>` posizionale obbligatorio; `--account <email>` obbligatorio; `--ga4`, `--gsc` opzionali con default `TBD`; `--root <path>` opzionale, default `$PWD`.
- Validazione: il nome del tenant deve essere un nome di cartella semplice (niente `/`, niente iniziale `.`); l'account deve avere forma di indirizzo email e non contenere `/`. Entrambi gli errori escono `1` con un messaggio che dice cosa fare.
- Se `<root>/accounts/<email>/` non esiste, crearla copiando `templates/account/` e sostituendo `{{ACCOUNT_EMAIL}}`.
- Copiare `templates/tenant/` in `<root>/accounts/<email>/<name>/` e sostituire i quattro placeholder in `CLAUDE.md` e `README.md`. La sostituzione avviene scrivendo su un file affiancato e rinominando: `sed -i` è vietato.
- Rifiutare con exit `1` se la cartella del tenant esiste già, senza toccare nulla.
- Inserire la riga `| <name> | <ga4> | <gsc> | active |` subito sotto la riga `<!-- tenants -->` nel `CLAUDE.md` dell'account, usando `node -e` per la manipolazione del file.
- Stampare cosa è stato creato e il passo successivo suggerito.

- [ ] **Step 5: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — tutte le asserzioni di `test_new_tenant.sh` verdi.- [ ] **Step 5: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — le otto asserzioni di `test_new_tenant.sh` verdi.

- [ ] **Step 6: Commit**

```bash
chmod +x scripts/new-tenant.sh
git add templates/ scripts/new-tenant.sh tests/test_new_tenant.sh
git commit -m "feat(scripts): account and tenant scaffolding with new-tenant.sh"
```

---

### Task 6: `scripts/setup.sh`

**Files:**
- Create: `scripts/setup.sh`, `tests/test_setup.sh`

**Interfaces:**
- Consumes: `common.sh` (`load_env`, `require_cmd`, `die`), `doctor.sh`, `reconnect.sh`, `.env.example`.
- Produces: `scripts/setup.sh` con `--help`, `--non-interactive` (salta i prompt, fallisce se `.env` manca) e `--print-mcp-config [--account <email>]` (stampa solo il blocco JSON per `~/.claude.json` ed esce — testabile e utile da solo). Con `--account`, i nomi dei server sono suffissati con l'account e `GOOGLE_APPLICATION_CREDENTIALS` punta a `.secrets/gcloud/<email>/application_default_credentials.json`.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_setup.sh`:

```bash
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

it "--account suffixes the server names and points at that account's ADC"
_cfg_a="$(ENV_FILE="$_tmp/.env" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config --account me@example.com)"
assert_exit 0 node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" <<< "$_cfg_a"
assert_contains "$_cfg_a" "search-console-mcp-me@example.com" "server name carries the account"
assert_contains "$_cfg_a" ".secrets/gcloud/me@example.com/application_default_credentials.json" "per-account ADC path"

it "GSC_MCP_MODE=local switches the command to the local build"
printf 'ADC_FILE=%s/adc.json\nGSC_MCP_MODE=local\nGSC_MCP_PATH=%s/dist/index.js\n' "$_tmp" "$_tmp" > "$_tmp/.env-local"
_cfg_l="$(ENV_FILE="$_tmp/.env-local" bash "$REPO_ROOT/scripts/setup.sh" --print-mcp-config)"
assert_contains "$_cfg_l" "$_tmp/dist/index.js" "local path is used"

rm -rf "$_tmp"
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `scripts/setup.sh: No such file or directory`

- [ ] **Step 3: Implementare `scripts/setup.sh`**

```bash
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
Usage: setup.sh [--non-interactive] [--print-mcp-config]

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
  --account <email>    with --print-mcp-config, emit per-account server entries
                       reading that account's own ADC file
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
  local gsc_cmd gsc_args
  if [ "${GSC_MCP_MODE:-npx}" = "local" ]; then
    [ -n "${GSC_MCP_PATH:-}" ] || die "GSC_MCP_MODE=local but GSC_MCP_PATH is empty"
    gsc_cmd="node"; gsc_args="\"$GSC_MCP_PATH\""
  else
    gsc_cmd="npx"; gsc_args="\"-y\", \"search-console-mcp\""
  fi
  cat <<EOF
{
  "mcpServers": {
    "analytics-mcp$suffix": {
      "type": "stdio",
      "command": "analytics-mcp",
      "args": [],
      "env": { "GOOGLE_APPLICATION_CREDENTIALS": "$adc" }
    },
    "search-console-mcp$suffix": {
      "type": "stdio",
      "command": "$gsc_cmd",
      "args": [$gsc_args],
      "env": { "GOOGLE_APPLICATION_CREDENTIALS": "$adc" }
    }
  }
}
EOF
}

if [ "$PRINT_CONFIG_ONLY" -eq 1 ]; then
  print_mcp_config
  exit 0
fi

printf '== 1. Prerequisites ==\n'
require_cmd git "Install git: https://git-scm.com/downloads"
require_cmd node "Install Node.js 22 or newer: https://nodejs.org"
require_cmd gcloud "Install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
bash "$HERE/doctor.sh" --only node
bash "$HERE/doctor.sh" --only gcloud

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
bash "$HERE/reconnect.sh"

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
```

- [ ] **Step 4: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — le sei asserzioni di `test_setup.sh` verdi.

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/setup.sh
git add scripts/setup.sh tests/test_setup.sh
git commit -m "feat(scripts): guided setup.sh bootstrap"
```

---

### Task 7: Documentazione `docs/`

**Files:**
- Create: `docs/01-google-cloud-setup.md`, `docs/02-mcp-servers.md`, `docs/03-auth-and-rapt.md`, `docs/04-multi-tenant.md`, `docs/05-usage.md`, `docs/06-bing-future.md`, `docs/07-windows.md`, `docs/99-troubleshooting.md`, `tests/test_docs.sh`

**Interfaces:**
- Consumes: le ancore usate in `checks.sh` (Task 3) — `#node-version`, `#gcloud-missing`, `#adc-missing`, `#missing-scopes`, `#apis-not-enabled`, `#native-module`.
- Produces: la documentazione referenziata da script e README.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_docs.sh`:

```bash
#!/usr/bin/env bash
_docs="$REPO_ROOT/docs"

it "every documentation file exists"
for f in 01-google-cloud-setup 02-mcp-servers 03-auth-and-rapt 04-multi-tenant \
         05-usage 06-bing-future 07-windows 99-troubleshooting; do
  assert_eq "yes" "$([ -f "$_docs/$f.md" ] && echo yes || echo no)" "$f.md exists"
done

it "every troubleshooting anchor referenced by checks.sh has a heading"
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/lib/checks.sh"
_ts="$(cat "$_docs/99-troubleshooting.md")"
for _row in "${CHECKS[@]}"; do
  IFS='|' read -r _id _desc _fn _anchor <<< "$_row"
  _slug="${_anchor#*#}"
  assert_contains "$_ts" "<a id=\"$_slug\"></a>" "anchor $_slug is defined"
done

it "no leaked identifiers from the private hub"
# Patterns are read from a gitignored .leak-patterns (see .leak-patterns.example), never
# hardcoded here — hardcoding real identifiers in a public repo's test file would be the
# leak the test exists to prevent. Absent .leak-patterns, the check skips visibly instead
# of silently passing.
assert_eq "" "$_leaks" "no real ids, sites or accounts anywhere"
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — i file `docs/*.md` non esistono.

- [ ] **Step 3: Scrivere i documenti**

Ognuno in inglese. Contenuti obbligatori:

`01-google-cloud-setup.md` — creare/scegliere il progetto GCP; abilitare le tre API; OAuth consent screen con la spiegazione **Internal vs External** (External in testing fa scadere i refresh token ogni 7 giorni); creare un **OAuth client di tipo Desktop app**; dove salvare il JSON; perché OAuth utente e non service account (GA4 e GSC concedono l'accesso a persone, non a service account, salvo aggiungerne l'indirizzo come utente).

`02-mcp-servers.md` — installare `analytics-mcp` (PyPI 0.7.0, via `pipx install analytics-mcp`) e `search-console-mcp` (npm 2.0.1, via `npx -y search-console-mcp`, nessun `re2`); il blocco `~/.claude.json` prodotto da `setup.sh --print-mcp-config`; nota che `@napi-rs/keyring` è un modulo nativo e cosa fare se non carica; nota che v2 offre anche un transport HTTP/SSE (`search-console-mcp --transport=sse --port=3000`) non usato dal blueprint; come verificare con `/mcp`.

`03-auth-and-rapt.md` — ADC condiviso fra i due server; i tre scope; perché `cloud-platform` è imposto da gcloud e attiva **RAPT**, con re-login ~24h; i sintomi (`invalid_rapt`, `invalid_grant`, `reauthentication needed`, `401`); la procedura in due passi (`./scripts/reconnect.sh` poi `/mcp`); il rapporto fra il portachiavi di sistema usato da `@napi-rs/keyring` e l'ADC (il portachiavi serve al flusso OAuth interno del server, l'ADC resta la sorgente di verità quando `GOOGLE_APPLICATION_CREDENTIALS` è impostata nel blocco MCP); la sezione **multi-account**: `reconnect.sh --account <email>` esegue il login con `CLOUDSDK_CONFIG` puntato a `.secrets/gcloud/<email>/`, quindi l'ADC di quell'account finisce in `.secrets/gcloud/<email>/application_default_credentials.json`; spiegare che `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` **non** serve a questo, perché indica solo quale file leggere e non redirige la scrittura del login; e che, avendo i server MCP env statiche, **ogni account richiede il proprio blocco** in `~/.claude.json` (es. `search-console-mcp-me@example.com`), generabile con `setup.sh --print-mcp-config --account <email>`; l'avvertenza di non esportare mai `GOOGLE_APPLICATION_CREDENTIALS` globalmente in `.zshrc`.

`04-multi-tenant.md` — la gerarchia `accounts/<email>/<tenant>/`: un tenant vive dentro la cartella dell'account Google con cui vi si accede, e ogni cartella account ha il proprio `CLAUDE.md` con la tabella dei suoi tenant; l'hub tiene solo strumenti, credenziali e runbook; `new-tenant.sh <name> --account <email>`; perché la gerarchia è per account e non piatta (le credenziali sono per account, e lo stesso nome di tenant può esistere sotto account diversi); cosa è gitignorato e perché; rimando a `03` per le credenziali per account.

`05-usage.md` — scritto per **v2**: i 7 fluent domain tools (`sites_list`, `analytics_query`, `seo_audit`, `indexing_submit`, `inspection_inspect`, `sitemaps_list`, `site_health_check`), con nota che i ~96 tool legacy restano per compatibilità. GSC: parametro righe `limit` (**non** `rowLimit`), default 1000 / max 25.000; `dataState: "all"` per i dati preliminari; operatori di filtro `equals`, `contains`, `includingRegex`, `excludingRegex`; `format: "csv"` per output compatti. GA4: campi in `snake_case` (`date_ranges`, `dimension_filter`, `string_filter`, `match_type`); `landingPage` per l'organico per pagina; metriche `sessions`, `ecommercePurchases`, `purchaseRevenue`; filtri `PARTIAL_REGEXP`.

`06-bing-future.md` — il server GSC espone anche una superficie Bing Webmaster Tools, fuori scope qui; per attivarla basta `export BING_API_KEY="..."` (chiave da bing.com/webmasters/settings/api); cosa andrebbe aggiunto al blueprint per supportarla davvero (una variabile in `.env`, un check in `checks.sh`, una sezione in `05-usage.md`).

`07-windows.md` — i punti che una porta PowerShell deve gestire: ADC in `%APPDATA%\gcloud\application_default_credentials.json`, posizione di `~/.claude.json`, `gcloud` come `gcloud.cmd`, il Credential Manager usato da `@napi-rs/keyring`; il contratto degli script (input `.env`, output stdout, exit `0`/`1`/`2`) come specifica da rispettare; la nota che **WSL è la via più semplice** se non si vuole portare nulla; il rimando a `scripts/windows/` come collocazione prevista per le porte.

`99-troubleshooting.md` — una sezione per ancora, ognuna aperta da un `<a id="..."></a>` esplicito:
- `#node-version` — Node troppo vecchio; come installare 22+.
- `#gcloud-missing` — SDK assente o non in PATH.
- `#adc-missing` — nessun file ADC; lanciare `reconnect.sh`.
- `#missing-scopes` — l'ADC non ha i tre scope; rigenerarlo; nota che gli scope non stanno nel file ma si leggono da tokeninfo.
- `#apis-not-enabled` — le tre API GCP; comando `gcloud services list --enabled --project=...`.
- `#native-module` — un modulo nativo non carica. Oggi il candidato è `@napi-rs/keyring`. Rimedi in ordine: usare una versione LTS di Node; pulire la cache `npx`; come ultima risorsa il **build locale da sorgenti** (`git clone` + `npm install` + `npm run build`, poi `GSC_MCP_MODE=local` e `GSC_MCP_PATH` in `.env`). Nota storica: fino a v1.14.x il colpevole era `re2`, che non ha prebuild per Node 25 — rimosso in v2 (PR #81).

- [ ] **Step 4: Eseguire i test**

Run: `bash tests/run.sh`
Expected: PASS — tutte le asserzioni di `test_docs.sh` verdi, incluso il controllo anti-leak.

- [ ] **Step 5: Commit**

```bash
git add docs/ tests/test_docs.sh
git commit -m "docs: setup, auth, multi-tenant, usage, windows and troubleshooting guides"
```

---

### Task 8: README bilingui, `CLAUDE.md.template`, playbook e skill

**Files:**
- Create: `README.md`, `README.it.md`, `CLAUDE.md.template`, `playbooks/README.md`, `playbooks/organic-traffic-drop.md`, `.claude/skills/new-tenant/SKILL.md`, `.claude/skills/reconnect/SKILL.md`, `.claude/skills/health-check/SKILL.md`, `tests/test_repo_surface.sh`

**Interfaces:**
- Consumes: gli script dei Task 3-6 e i docs del Task 7. Il marcatore `<!-- tenants -->` atteso da `new-tenant.sh` (Task 5) è definito qui.
- Produces: la superficie pubblica del repo.

- [ ] **Step 1: Scrivere il test che fallisce**

`tests/test_repo_surface.sh`:

```bash
#!/usr/bin/env bash

it "both READMEs and the hub template exist"
for f in README.md README.it.md CLAUDE.md.template; do
  assert_eq "yes" "$([ -f "$REPO_ROOT/$f" ] && echo yes || echo no)" "$f exists"
done

it "the account template carries the tenants marker new-tenant.sh needs"
assert_contains "$(cat "$REPO_ROOT/templates/account/CLAUDE.md")" "<!-- tenants -->" "marker present"

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
```

- [ ] **Step 2: Eseguire per verificare che fallisca**

Run: `bash tests/run.sh`
Expected: FAIL — `README.md` non esiste.

- [ ] **Step 3: Scrivere `CLAUDE.md.template`**

```markdown
# <your hub name> - Analytics & Search Console hub

This folder is the operational hub from which several SEO/traffic projects are managed,
through the `analytics-mcp` (GA4) and `search-console-mcp` (Google Search Console) MCP servers.

Work is organised by Google account, because credentials are per account:

```
accounts/
  me@example.com/       <- one folder per Google account, with its own CLAUDE.md
    acme/               <- a tenant, accessed with that account
    globex/
```

> Claude loads this file at the start of every session, and the account's own CLAUDE.md
> when working under it. Keep both current and short.

## Accounts

| Google account | Tenants | Status |
|---|---|---|
<!-- accounts -->

To add a tenant: `./scripts/new-tenant.sh <name> --account <email> --ga4 <id> --gsc <url>`
It creates the account folder too, if this is that account's first tenant.

## Authentication

Both MCP servers read an ADC credentials file, created by OAuth with three scopes.
Because gcloud forces the `cloud-platform` scope, Google's RAPT policy requires a
re-login roughly every 24 hours, per account. When a server answers with `invalid_rapt`,
`invalid_grant`, `reauthentication needed` or `401`:

1. the user runs `./scripts/reconnect.sh --account <email>` (it opens a browser - Claude cannot
   do this, and must not try)
2. the user runs `/mcp` in Claude Code to reconnect the servers

While waiting, work on anything that does not need the MCP servers.

Health check: `./scripts/doctor.sh`

## Conventions

- Tenant files live in that tenant's folder, under its account. The hub holds only shared tooling.
- `.secrets/` and any ADC file are never committed and never pasted into chat.
- Tool usage notes: `docs/05-usage.md`. Problems: `docs/99-troubleshooting.md`.
```

- [ ] **Step 4: Scrivere `README.md` (EN) e `README.it.md` (IT)**

Entrambi coprono, nell'ordine: cos'è (un blueprint da clonare, non una libreria); cosa serve (account Google con accessi GA4/GSC, un progetto Google Cloud, Node 22+, gcloud); quickstart in cinque comandi (`git clone`, `cp CLAUDE.md.template CLAUDE.md`, `./scripts/setup.sh`, incollare il blocco MCP, `./scripts/new-tenant.sh acme --account me@example.com`); la gerarchia `accounts/<email>/<tenant>/` spiegata in tre righe, con il motivo (le credenziali sono per account); il costo operativo noto del re-login ~24h con rimando a `docs/03-auth-and-rapt.md`; l'indice dei `docs/`; come contribuire, con `bash tests/run.sh` per la suite; licenza MIT. Ogni README linka l'altro in testa.

- [ ] **Step 5: Scrivere `playbooks/README.md`**

Spiega cos'è un playbook e la struttura attesa — **Context** (quando si usa), **Questions** (cosa si sta cercando di stabilire), **Queries** (le chiamate MCP, con i parametri), **Interpretation** (come si leggono i risultati, quali ipotesi si escludono e in che ordine), **Output** (cosa si consegna) — e come aggiungerne uno: copiare la ricetta d'esempio, rinominarla, sostituire il contenuto. Nota esplicita: i playbook non contengono dati di clienti, solo placeholder.

- [ ] **Step 6: Scrivere `playbooks/organic-traffic-drop.md`**

La ricetta d'esempio, senza alcun dato reale. Segue la struttura sopra e diagnostica un calo di traffico organico:
- separare **brand vs non-brand** in GSC prima di qualsiasi altra cosa, perché un calo brand e un calo non-brand hanno cause diverse;
- confrontare i periodi in GSC (`analytics_query` con due intervalli, `dataState: "all"` per i giorni recenti);
- scendere a livello di query e di pagina per capire se il calo è diffuso o concentrato;
- incrociare con le landing page GA4 (`landingPage`, `sessions`) per distinguere un calo di ranking da un calo di conversione o da un problema di tracciamento;
- escludere le ipotesi in ordine: tracciamento rotto → traffico bot/junk → stagionalità → indicizzazione e crawl → perdita di ranking → aggiornamento dell'algoritmo;
- output: una nota in `analysis/` con l'ipotesi sostenuta, l'evidenza, e cosa la falsificherebbe.

- [ ] **Step 7: Scrivere le tre skill**

Ognuna è un `SKILL.md` con frontmatter `name:` e `description:`, e istruzioni brevi:
- `new-tenant` — raccogli nome, GA4 property ID e sito GSC; esegui `./scripts/new-tenant.sh`; poi aiuta l'utente a compilare la sezione "What this site is" del `CLAUDE.md` del tenant.
- `reconnect` — riconosci i sintomi (`invalid_rapt`, `invalid_grant`, `reauthentication needed`, `401`); **chiedi all'utente** di eseguire `./scripts/reconnect.sh` (apre un browser, non eseguirlo tu) e poi `/mcp`; nel frattempo prosegui con ciò che non richiede gli MCP.
- `health-check` — esegui `./scripts/doctor.sh`, traduci ogni `FAIL` in un'azione concreta usando la sezione di troubleshooting indicata.

- [ ] **Step 8: Eseguire la suite completa**

Run: `bash tests/run.sh`
Expected: PASS — tutti i file di test verdi, `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add README.md README.it.md CLAUDE.md.template playbooks/ .claude/ tests/test_repo_surface.sh
git commit -m "docs: bilingual READMEs, hub template, playbook tree and Claude Code skills"
```

---

## Verifica finale

- [ ] `bash tests/run.sh` → `0 failed`
- [ ] `grep -rn '/Users/' scripts/ docs/ templates/ playbooks/ README*.md` → nessun risultato (nessun path assoluto)
- [ ] grep dei pattern anti-leak elencati in `tests/test_docs.sh` (identificativi reali del hub privato) su tutto il repo → nessun risultato fuori da `docs/superpowers/` (nessun dato del cliente)
- [ ] `grep -rn "sed -i\|realpath\|readlink -f\|grep -P\|jq " scripts/` → nessun risultato (vincolo di portabilità)
- [ ] `bash scripts/setup.sh --help`, `doctor.sh --help`, `reconnect.sh --help`, `new-tenant.sh --help` → tutti exit 0
- [ ] `git status` pulito
