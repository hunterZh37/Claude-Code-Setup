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

