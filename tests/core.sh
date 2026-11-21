# Core install, re-run, uninstall and hours-script tests. Sourced by run-tests.sh.
# Fake rtk so the --rtk path can be tested without installing anything.
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/rtk"
chmod +x "$WORK/bin/rtk"

echo "1. Dry run writes nothing"
H1="$WORK/home-dry"; mkdir -p "$H1"
out="$(HOME="$H1" "$REPO/setup.sh" --yes --dry-run --format --commands --plugins </dev/null)"
check "dry run creates no files" test -z "$(find "$H1" -mindepth 1 -print -quit)"
check "dry run says what it would do" grep -q "would create" <<<"$out"

echo "2. Install into a HOME with existing config"
H2="$WORK/home"; C="$H2/.claude"; mkdir -p "$C/output-styles"
ORIG_SETTINGS='{"model": "sonnet", "outputStyle": "Explanatory", "enabledPlugins": {"foo@bar": true}, "env": {"KEEP": "1"}}'
printf '%s\n' "$ORIG_SETTINGS" >"$C/settings.json"
printf '# My rules\nkeep me\n' >"$C/CLAUDE.md"
printf 'old style\n' >"$C/output-styles/adhd-friendly.md"
cp "$C/CLAUDE.md" "$WORK/orig-CLAUDE.md"
run() { HOME="$H2" PATH="$WORK/bin:$PATH" "$REPO/setup.sh" --yes --name Alex --format --commands --plugins --extra-plugins --rtk "$@" </dev/null; }
run >"$WORK/run1.log"
check "output style installed" has "$C/output-styles/adhd-friendly.md" "name: adhd-friendly"
check "output style uses the name" has "$C/output-styles/adhd-friendly.md" "Alex reads these replies"
check "CLAUDE.md keeps user text" has "$C/CLAUDE.md" "keep me"
check "CLAUDE.md gets the rules" has "$C/CLAUDE.md" "# Replies to Alex"
check "CLAUDE.md imports RTK.md" has "$C/CLAUDE.md" "@RTK.md"
check "RTK.md installed" test -f "$C/RTK.md"
check "command installed" has "$C/commands/worked-hours.md" "Never guess or estimate hours"
check "script installed and executable" test -x "$C/scripts/workday-hours.py"
check "no template tokens left" bash -c "! grep -rq '{{NAME' '$C'"
check "settings keep model" test "$(json_get "$C/settings.json" model)" = '"sonnet"'
check "settings keep env" test "$(json_get "$C/settings.json" env KEEP)" = '"1"'
check "settings keep user plugin" test "$(json_get "$C/settings.json" enabledPlugins foo@bar)" = true
check "settings keep chosen outputStyle" test "$(json_get "$C/settings.json" outputStyle)" = '"Explanatory"'
check "progress-bar enabled" test "$(json_get "$C/settings.json" enabledPlugins progress-bar@progress-bar)" = true
check "extra plugin enabled" test "$(json_get "$C/settings.json" enabledPlugins frontend-design@claude-plugins-official)" = true
check "marketplace added" has "$C/settings.json" "hunterZh37/progress-bar-plugin"
check "settings backed up" test "$(find "$C" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" = 1
check "CLAUDE.md backed up" test "$(find "$C" -name 'CLAUDE.md.bak-*' | wc -l | tr -d ' ')" = 1
check "old style backed up" test "$(find "$C/output-styles" -name '*.bak-*' | wc -l | tr -d ' ')" = 1

echo "3. Re-run is idempotent"
before="$(snapshot "$C")"; baks="$(count_baks "$C")"
sleep 1
run >"$WORK/run2.log"
check "re-run changes no file" test "$before" = "$(snapshot "$C")"
check "re-run makes no new backups" test "$baks" = "$(count_baks "$C")"
check "re-run reports unchanged" grep -q "unchanged" "$WORK/run2.log"

echo "4. --force-style switches outputStyle"
sleep 1
run --force-style >"$WORK/run3.log"
check "outputStyle switched" test "$(json_get "$C/settings.json" outputStyle)" = '"adhd-friendly"'

echo "5. Uninstall restores the original state"
HOME="$H2" "$REPO/uninstall.sh" >"$WORK/uninstall.log"
check "settings back to original" json_eq "$C/settings.json" "$ORIG_SETTINGS"
check "CLAUDE.md back to original" cmp -s "$C/CLAUDE.md" "$WORK/orig-CLAUDE.md"
check "old output style restored" has "$C/output-styles/adhd-friendly.md" "old style"
check "command removed" test ! -e "$C/commands/worked-hours.md"
check "script removed" test ! -e "$C/scripts/workday-hours.py"
check "RTK.md removed" test ! -e "$C/RTK.md"
check "setup record removed" test ! -e "$C/.claude-code-setup"
check "uninstall again is a no-op" bash -c "HOME='$H2' '$REPO/uninstall.sh' | grep -q 'Nothing to undo'"

echo "6. Fresh HOME install then uninstall leaves no files"
H3="$WORK/home-fresh"; mkdir -p "$H3"
HOME="$H3" "$REPO/setup.sh" --yes --format --commands --plugins </dev/null >"$WORK/run4.log"
check "default name used" has "$H3/.claude/CLAUDE.md" "# Replies to the user"
check "default name capitalized" has "$H3/.claude/output-styles/adhd-friendly.md" "The user reads these replies"
check "no RTK import without rtk" lacks "$H3/.claude/CLAUDE.md" "@RTK.md"
check "outputStyle set when unset" test "$(json_get "$H3/.claude/settings.json" outputStyle)" = '"adhd-friendly"'
HOME="$H3" "$REPO/uninstall.sh" >/dev/null
check "no files left after uninstall" test -z "$(find "$H3" -type f -print -quit)"

echo "7. Errors are clear"
check "no components and no terminal fails" bash -c "! HOME='$WORK/x' '$REPO/setup.sh' </dev/null >/dev/null 2>&1"
check "unknown flag fails" bash -c "! HOME='$WORK/x' '$REPO/setup.sh' --nope >/dev/null 2>&1"
mkdir -p "$WORK/bad/.claude"; echo '{not json' >"$WORK/bad/.claude/settings.json"
check "invalid settings.json fails without changes" bash -c "! HOME='$WORK/bad' '$REPO/setup.sh' --yes --plugins </dev/null >/dev/null 2>&1 && grep -q 'not json' '$WORK/bad/.claude/settings.json'"

echo "8. workday-hours.py"
P="$WORK/hours/.claude/projects"
mkdir -p "$P/-Users-sam-work-app" "$P/-Users-sam-play"
day="2026-01-15"
python3 - "$P" "$day" <<'PY'
import json, sys
from datetime import datetime
root, day = sys.argv[1], sys.argv[2]
def row(t): return json.dumps({"timestamp": datetime.fromisoformat(f"{day}T{t}").astimezone().isoformat()})
with open(f"{root}/-Users-sam-work-app/a.jsonl", "w") as f:
    f.write("\n".join(row(t) for t in ["09:00:00", "09:15:00", "09:30:00", "09:45:00", "10:00:00"]) + "\n")
with open(f"{root}/-Users-sam-play/b.jsonl", "w") as f:
    f.write("\n".join(row(t) for t in ["14:00:00", "14:15:00", "14:30:00"]) + "\nnot json\n")
PY
HOURS="$REPO/templates/scripts/workday-hours.py"
check "counts all projects" bash -c "HOME='$WORK/hours' python3 '$HOURS' $day | grep -q 'ACTIVE 1.50 h'"
check "prefix filters projects" bash -c "HOME='$WORK/hours' python3 '$HOURS' $day --prefix /Users/sam/work | grep -q 'ACTIVE 1.00 h'"
check "empty day exits 1" bash -c "! HOME='$WORK/hours' python3 '$HOURS' 2020-01-01 >/dev/null"

