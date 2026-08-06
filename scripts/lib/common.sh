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

log_ok()   { printf 'OK: %s\n' "$1"; }
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
    # Strip CRLF line endings (Windows portability).
    line="${line%$'\r'}"

    # Skip empty lines and comment lines (including indented comments).
    case "$line" in ''|[[:space:]]*'#'*|'#'*) continue ;; esac

    # Extract key and value.
    key="${line%%=*}"
    value="${line#*=}"

    # Skip lines without an equals sign.
    [ "$key" = "$line" ] && continue

    # Skip keys that are not valid shell identifiers.
    case "$key" in
      [a-zA-Z_][a-zA-Z0-9_]*) ;;
      *) continue ;;
    esac

    # Trim trailing whitespace from value.
    while [ -n "$value" ] && [ "${value%[[:space:]]}" != "$value" ]; do
      value="${value%[[:space:]]}"
    done

    # Unquote values: strip one matching pair of surrounding single or double quotes.
    if [ "${value#\"}" != "$value" ] && [ "${value%\"}" != "$value" ]; then
      # Value starts and ends with double quotes.
      value="${value#\"}"
      value="${value%\"}"
    elif [ "${value#\'}" != "$value" ] && [ "${value%\'}" != "$value" ]; then
      # Value starts and ends with single quotes.
      value="${value#\'}"
      value="${value%\'}"
    fi

    # Expand $HOME and friends without eval'ing arbitrary command substitution.
    value="${value//\$HOME/$HOME}"
    value="${value//\$\{HOME\}/$HOME}"
    export "$key=$value"
  done < "$env_file"
}

json_get() {
  # $1 json file, $2 dotted key. Uses node because jq is not a project prerequisite.
  # Errors are caught and reported in this library's own "error: ..." style, not as a
  # raw Node stack trace — a missing or malformed JSON file (e.g. a corrupt ADC) should
  # read as an expected failure mode of this tool, not as a bug in it.
  node -e '
    const [file, key] = process.argv.slice(1);
    try {
      const data = JSON.parse(require("fs").readFileSync(file, "utf8"));
      const value = key.split(".").reduce((o, k) => (o == null ? o : o[k]), data);
      process.stdout.write(value == null ? "" : String(value));
    } catch (e) {
      process.stderr.write("error: could not read " + key + " from " + file + ": " + e.message + "\n");
      process.exit(1);
    }
  ' "$1" "$2"
}
