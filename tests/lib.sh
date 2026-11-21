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
  (cd "$d" && HOME="$d/home" "$REPO/tests/setup-flags.sh" --migrate --name Sam "$@" </dev/null)
}

mkdir -p "$WORK/bin"
# Fake clipboard tools first on PATH, so a test run never overwrites your clipboard.
for c in pbcopy wl-copy xclip; do printf '#!/bin/sh\ncat >/dev/null\n' >"$WORK/bin/$c"; chmod +x "$WORK/bin/$c"; done
export PATH="$WORK/bin:$PATH"

non_format_same() { # the original's non-format lines all appear, byte for byte, in order
  python3 - "$1" "$2" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[0] and __import__("os").environ["REPO"] + "/lib")
from migrate import analyze
orig, new = open(sys.argv[1]).read(), open(sys.argv[2]).read()
fmt = {n for n, _ in analyze(orig)[0]}
want = [l for i, l in enumerate(orig.splitlines(), 1) if i not in fmt]
it = iter(new.splitlines())
sys.exit(0 if all(any(l == x for x in it) for l in want) else 1)
PY
}
export REPO
