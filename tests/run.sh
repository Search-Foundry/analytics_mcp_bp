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
