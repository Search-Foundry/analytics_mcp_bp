#!/usr/bin/env bash
# Instantiates a new tenant folder from templates/tenant/, nested under the Google
# account it is accessed with — accounts/<email>/<name>/. If that account folder
# does not exist yet, it is created first from templates/account/.
#
# Everything that can be validated up front (name, account, template presence, the
# <!-- tenants --> marker) is checked before anything is created. All copying and
# substitution happens in temp siblings under accounts/; the real paths are only
# touched by the final renames, so a failure at any point leaves the filesystem
# exactly as it found it — no half-created tenant, no half-substituted account dir,
# and nothing pre-existing gets deleted.
#
# Contract:
#   input:  <name> positional, --account <email>, optional --ga4 <id> --gsc <url> --root <path>
#   output: paths created, and the suggested next step
#   exit:   0 ok, 1 user error, 2 missing prerequisite
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: new-tenant.sh <name> --account <email> [--ga4 <id>] [--gsc <url>] [--root <path>]

Creates a new tenant folder from templates/tenant/, under accounts/<email>/<name>/.
If accounts/<email>/ does not exist yet, it is created first from templates/account/,
and the tenant is registered in its CLAUDE.md tenant table.

  <name>            tenant folder name — no '/', no leading '.'
  --account <email> Google account this tenant is accessed with (required)
  --ga4 <id>        GA4 property ID (default: TBD)
  --gsc <url>       GSC site URL (default: TBD)
  --root <path>     hub root the accounts/ folder lives under (default: $PWD)
  --help            show this message
EOF
}

NAME=""
ACCOUNT=""
GA4="TBD"
GSC="TBD"
ROOT="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --account) ACCOUNT="${2-}"; [ -n "$ACCOUNT" ] || die "--account needs an email"; shift 2 ;;
    --ga4) GA4="${2-}"; [ -n "$GA4" ] || die "--ga4 needs a value"; shift 2 ;;
    --gsc) GSC="${2-}"; [ -n "$GSC" ] || die "--gsc needs a value"; shift 2 ;;
    --root) ROOT="${2-}"; [ -n "$ROOT" ] || die "--root needs a path"; shift 2 ;;
    -*) printf 'error: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 1 ;;
    *)
      [ -z "$NAME" ] || die "unexpected extra argument: $1"
      NAME="$1"
      shift
      ;;
  esac
done

[ -n "$NAME" ] || die "missing tenant name. Usage: new-tenant.sh <name> --account <email> (try --help)"
[ -n "$ACCOUNT" ] || die "missing --account <email> (try --help)"

# Validate the tenant name: a simple folder name, no path separators, no leading dot.
case "$NAME" in
  */*) die "tenant name must not contain '/': $NAME" ;;
  .*) die "tenant name must not start with '.': $NAME" ;;
esac

# Validate the account: same email shape and rejection rules as reconnect.sh, so the
# two scripts never disagree about what a valid account directory name looks like.
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

REPO="$(repo_root)"
ACCOUNT_DIR="$ROOT/accounts/$ACCOUNT"
TENANT_DIR="$ACCOUNT_DIR/$NAME"

[ ! -e "$TENANT_DIR" ] || die "tenant already exists: $TENANT_DIR"

[ -d "$REPO/templates/account" ] || die "templates/account not found — corrupted checkout?"
[ -d "$REPO/templates/tenant" ] || die "templates/tenant not found — corrupted checkout?"

ACCOUNT_EXISTS=0
[ -d "$ACCOUNT_DIR" ] && ACCOUNT_EXISTS=1

# Validate the <!-- tenants --> marker before creating anything: against the existing
# account CLAUDE.md if the account folder already exists, otherwise against the template
# that will be used to create it. This is the fix for the class of bug where a missing
# marker was only discovered after the tenant folder had already been copied and
# substituted, leaving it stranded and unregisterable.
if [ "$ACCOUNT_EXISTS" -eq 1 ]; then
  MARKER_SRC="$ACCOUNT_DIR/CLAUDE.md"
else
  MARKER_SRC="$REPO/templates/account/CLAUDE.md"
fi
[ -f "$MARKER_SRC" ] || die "account CLAUDE.md not found: $MARKER_SRC"
grep -qF -- '<!-- tenants -->' "$MARKER_SRC" \
  || die "no <!-- tenants --> marker found in $MARKER_SRC — add it under the Tenants table and retry"

# If a hub CLAUDE.md exists at --root, it must carry the <!-- accounts --> marker (checked
# up front, before any mutation, same as the account marker above). If there's no hub
# CLAUDE.md at all — e.g. --root points at a plain test directory — hub registration is
# simply skipped; that is not an error.
HUB_CLAUDE="$ROOT/CLAUDE.md"
HUB_HAS_FILE=0
if [ -f "$HUB_CLAUDE" ]; then
  HUB_HAS_FILE=1
  grep -qF -- '<!-- accounts -->' "$HUB_CLAUDE" \
    || die "no <!-- accounts --> marker found in $HUB_CLAUDE — add it under the Accounts table and retry"
fi

# Substitute a single placeholder in a file: write to a sibling file, then rename.
# No sed -i (not portable), plain string replacement done in node.
substitute_placeholder() {
  local file="$1" placeholder="$2" value="$3" tmp
  tmp="$file.tmp.$$"
  node -e '
    const fs = require("fs");
    const [file, tmp, placeholder, value] = process.argv.slice(1);
    const text = fs.readFileSync(file, "utf8").split(placeholder).join(value);
    fs.writeFileSync(tmp, text);
  ' "$file" "$tmp" "$placeholder" "$value"
  mv "$tmp" "$file"
}

# Insert the "| name | ga4 | gsc | active |" row right below the marker. Pipe
# characters in the values are escaped as \| so a value like a GSC URL containing
# '|' cannot inject an extra column boundary into the Markdown table.
insert_tenant_row() {
  local file="$1" name="$2" ga4="$3" gsc="$4"
  node -e '
    const fs = require("fs");
    const [file, name, ga4, gsc] = process.argv.slice(1);
    const esc = (s) => String(s).replace(/\|/g, "\\|");
    const marker = "<!-- tenants -->";
    const row = `| ${esc(name)} | ${esc(ga4)} | ${esc(gsc)} | active |`;
    const text = fs.readFileSync(file, "utf8");
    const idx = text.indexOf(marker);
    if (idx === -1) {
      process.stderr.write("error: marker not found in " + file + "\n");
      process.exit(1);
    }
    const after = idx + marker.length;
    const updated = text.slice(0, after) + "\n" + row + text.slice(after);
    fs.writeFileSync(file, updated);
  ' "$file" "$name" "$ga4" "$gsc"
}

# Everything from here on works on temp siblings under accounts/, never on the final
# paths, until the last step. On any failure the trap below removes only what this
# invocation created — a pre-existing account folder is never touched by cleanup.
TENANT_TMP=""
ACCOUNT_TMP=""
ACCOUNT_CLAUDE_TMP=""

cleanup_on_failure() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    [ -z "$TENANT_TMP" ] || rm -rf "$TENANT_TMP"
    [ -z "$ACCOUNT_TMP" ] || rm -rf "$ACCOUNT_TMP"
    [ -z "$ACCOUNT_CLAUDE_TMP" ] || rm -f "$ACCOUNT_CLAUDE_TMP"
  fi
  exit "$status"
}
trap cleanup_on_failure EXIT

mkdir -p "$ROOT/accounts" || die "cannot create $ROOT/accounts — check permissions"

TENANT_TMP="$ROOT/accounts/.new-tenant.$$"
cp -R "$REPO/templates/tenant" "$TENANT_TMP"
for f in "$TENANT_TMP/CLAUDE.md" "$TENANT_TMP/README.md"; do
  substitute_placeholder "$f" '{{TENANT_NAME}}' "$NAME"
  substitute_placeholder "$f" '{{GA4_PROPERTY_ID}}' "$GA4"
  substitute_placeholder "$f" '{{GSC_SITE_URL}}' "$GSC"
  substitute_placeholder "$f" '{{ACCOUNT_EMAIL}}' "$ACCOUNT"
done

CREATED_ACCOUNT_DIR=0
if [ "$ACCOUNT_EXISTS" -eq 0 ]; then
  ACCOUNT_TMP="$ROOT/accounts/.new-account.$$"
  cp -R "$REPO/templates/account" "$ACCOUNT_TMP"
  substitute_placeholder "$ACCOUNT_TMP/CLAUDE.md" '{{ACCOUNT_EMAIL}}' "$ACCOUNT"
  insert_tenant_row "$ACCOUNT_TMP/CLAUDE.md" "$NAME" "$GA4" "$GSC"
  mkdir -p "$(dirname "$ACCOUNT_DIR")"
  mv "$ACCOUNT_TMP" "$ACCOUNT_DIR"
  ACCOUNT_TMP=""
  CREATED_ACCOUNT_DIR=1
else
  ACCOUNT_CLAUDE_TMP="$ACCOUNT_DIR/CLAUDE.md.tmp.$$"
  cp "$ACCOUNT_DIR/CLAUDE.md" "$ACCOUNT_CLAUDE_TMP"
  insert_tenant_row "$ACCOUNT_CLAUDE_TMP" "$NAME" "$GA4" "$GSC"
  mv "$ACCOUNT_CLAUDE_TMP" "$ACCOUNT_DIR/CLAUDE.md"
  ACCOUNT_CLAUDE_TMP=""
fi

mv "$TENANT_TMP" "$TENANT_DIR"
TENANT_TMP=""

if [ "$CREATED_ACCOUNT_DIR" -eq 1 ]; then
  printf 'Created account folder: %s\n' "$ACCOUNT_DIR"
fi
printf 'Created tenant folder: %s\n' "$TENANT_DIR"
printf 'Registered tenant %s in %s\n' "$NAME" "$ACCOUNT_DIR/CLAUDE.md"

# Register (or update) this account's row in the hub CLAUDE.md, if one exists at --root.
# The whole update happens in memory and lands via a single atomic rename, so a failure
# here (e.g. a permissions problem) never leaves a half-written hub CLAUDE.md — it can
# only fail before anything is written, or succeed completely.
if [ "$HUB_HAS_FILE" -eq 1 ]; then
  node -e '
    const fs = require("fs");
    const [file, tmp, account, name] = process.argv.slice(1);
    const marker = "<!-- accounts -->";
    const text = fs.readFileSync(file, "utf8");
    const idx = text.indexOf(marker);
    if (idx === -1) {
      process.stderr.write("error: marker not found in " + file + "\n");
      process.exit(1);
    }
    const after = idx + marker.length;
    const head = text.slice(0, after);
    const tail = text.slice(after);

    // Existing account rows are lines of the form "| email | tenant, tenant | active |".
    const lines = tail.split("\n");
    const prefix = "| " + account + " | ";
    let found = false;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].startsWith(prefix)) {
        const cells = lines[i].split("|").map((c) => c.trim());
        // cells[0] is "", [1]=account, [2]=tenants, [3]=status, [4]=""
        const existing = cells[2] ? cells[2].split(",").map((s) => s.trim()).filter(Boolean) : [];
        if (!existing.includes(name)) existing.push(name);
        lines[i] = `| ${account} | ${existing.join(", ")} | active |`;
        found = true;
        break;
      }
    }
    let newTail;
    if (found) {
      newTail = lines.join("\n");
    } else {
      const row = `| ${account} | ${name} | active |`;
      newTail = "\n" + row + tail;
    }
    fs.writeFileSync(tmp, head + newTail);
  ' "$HUB_CLAUDE" "$HUB_CLAUDE.tmp.$$" "$ACCOUNT" "$NAME"
  mv "$HUB_CLAUDE.tmp.$$" "$HUB_CLAUDE"
  printf 'Registered account %s in %s\n' "$ACCOUNT" "$HUB_CLAUDE"
fi

printf '\nNext step: fill in %s with the "What this site is" and "Known quirks" sections.\n' "$TENANT_DIR/CLAUDE.md"
