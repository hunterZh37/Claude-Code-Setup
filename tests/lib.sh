# Shared test helpers, sourced by tests/run-tests.sh.

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unset CLAUDE_CONFIG_DIR
export SETUP_NO_TTY=1  # never prompt, even when run from a terminal
PASS=0 FAIL=0

check() { # check "description" command...
  if "${@:2}"; then PASS=$((PASS + 1)); printf '✓ %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '✗ %s\n' "$1"; fi
}
has() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }
json_eq() { python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) == json.loads(sys.argv[2]) else 1)' "$1" "$2"; }
json_get() { python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2:]: d = d[k]
print(json.dumps(d))' "$@"; }
snapshot() { (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$(cksum <"$f")" "$f"; done); }
count_baks() { find "$1" -name '*.bak-*' | wc -l | tr -d ' '; }


# Migrate helpers, used by migrate.sh and stress.sh.
FIX="$REPO/tests/fixtures"
FAKE="$REPO/tests/fakes/claude"

new_migrate_home() { # new_migrate_home dir: user CLAUDE.md with conflicts + a project
  rm -rf "$1"; mkdir -p "$1/home/.claude"
  cp "$FIX/user/CLAUDE.md" "$1/home/.claude/CLAUDE.md"
  cp -R "$FIX/project" "$1/proj"
}
mig() { # mig dir [flags...]
  local d="$1"; shift
  (cd "$d" && HOME="$d/home" "$REPO/setup.sh" --migrate --name Sam "$@" </dev/null)
}

# Fake rtk so the --rtk path can be tested without installing anything.
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/rtk"
chmod +x "$WORK/bin/rtk"
