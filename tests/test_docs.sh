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
# Patterns come from a gitignored local file, never from this script: hardcoding real
# identifiers here would make the leak check itself the leak once this repo is public.
# See .leak-patterns.example for the format. Anyone who hasn't created .leak-patterns
# (the normal case for a fresh clone) gets an honest, visible skip, not a fake pass.
_leak_file="$REPO_ROOT/.leak-patterns"
if [ -f "$_leak_file" ]; then
  _pattern=""
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|'#'*) continue ;;
    esac
    if [ -z "$_pattern" ]; then _pattern="$_line"; else _pattern="$_pattern|$_line"; fi
  done < "$_leak_file"
  if [ -n "$_pattern" ]; then
    # Scan the whole tree, not just docs/ and scripts/ — README*.md, templates/,
    # playbooks/ and .claude/skills/ are exactly where a real client name would get
    # typed by accident. Exclude .git (not source), .superpowers and docs/superpowers
    # (vendored skill docs, not ours to scan).
    _leaks="$(cd "$REPO_ROOT" && grep -rEl "$_pattern" . \
      --exclude-dir=.git --exclude-dir=.superpowers --exclude-dir=superpowers 2>/dev/null \
      | grep -v '^\./docs/superpowers/' || true)"
    assert_eq "" "$_leaks" "no real ids, sites or accounts anywhere"
  else
    printf '  skip no leak patterns: %s has no active lines (only blanks/comments)\n' "$_leak_file"
  fi
else
  printf '  skip %s not found - anti-leak scan not run (copy .leak-patterns.example to enable it)\n' "$_leak_file"
fi
