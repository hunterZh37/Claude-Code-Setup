# Plugin + marketplace tests. Sourced by run-tests.sh. Uses the claude CLI only for
# `plugin validate` and an install into a throwaway CLAUDE_CONFIG_DIR, never ~/.claude.
check "plugin files are generated from templates (in sync)" python3 "$REPO/lib/build-plugin.py" --check
check "plugin.json and marketplace.json agree" python3 - "$REPO" <<'PY'
import json, os, sys
r = sys.argv[1]
p = json.load(open(os.path.join(r, ".claude-plugin/plugin.json")))
m = json.load(open(os.path.join(r, ".claude-plugin/marketplace.json")))
e = m["plugins"][0]
ok = e["name"] == p["name"] and e["source"] == "./" and m["owner"]["name"] and "claude" not in p["name"]
for key in ("commands", "outputStyles"):
    for path in p[key]:
        ok = ok and path.startswith("./") and os.path.exists(os.path.join(r, path))
sys.exit(0 if ok else 1)
PY
check "plugin setup calls setup.sh through CLAUDE_PLUGIN_ROOT" bash -c "grep -q '\"\${CLAUDE_PLUGIN_ROOT}/setup.sh\" --format --plugins --web --migrate --dry-run' '$REPO/plugin/commands/setup.md'"
check "plugin output style is named adhd-friendly" bash -c "head -3 '$REPO/plugin/output-styles/adhd-friendly.md' | grep -q '^name: adhd-friendly'"
H="$WORK/h-pfmt"; mkdir -p "$H/.claude"; printf 'mine\n' >"$H/.claude/CLAUDE.md"
out="$(HOME="$H" "$REPO/setup.sh" --format --dry-run --yes --name Sam </dev/null)"
check "plugin setup preview shows a diff and writes nothing" bash -c "grep -q '^+# Replies to Sam' <<<\"\$1\" && printf 'mine\n' | cmp -s - '$H/.claude/CLAUDE.md'" _ "$out"
if command -v claude >/dev/null 2>&1; then
  check "claude plugin validate passes" bash -c "claude plugin validate '$REPO' 2>&1 | grep -q 'Validation passed'"
  PC="$WORK/plugin-cfg"; mkdir -p "$PC"
  check "install from the local marketplace in an isolated config" bash -c "export CLAUDE_CONFIG_DIR='$PC'; claude plugin marketplace add '$REPO' >/dev/null 2>&1 && claude plugin install adhd-friendly@adhd-friendly >/dev/null 2>&1 && claude plugin details adhd-friendly 2>&1 | grep -q 'setup'"
else
  echo "○ claude CLI not found, plugin validate and install skipped"
fi
