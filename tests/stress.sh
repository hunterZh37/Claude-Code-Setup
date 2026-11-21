# Stress tests: odd environments, odd configs, interrupts. Sourced by run-tests.sh.
inst() { local h="$1"; shift; HOME="$h" "$REPO/setup.sh" --yes "$@" </dev/null; }
uninst() { HOME="$1" "$REPO/uninstall.sh" "${@:2}"; }
files_in() { find "$1" -type f | wc -l | tr -d ' '; }
STUB="$WORK/stubs"; mkdir -p "$STUB"
PY3="$(command -v python3)"

echo "S1. Environments"
mkdir -p "$STUB/nopy"; for c in dirname date uname; do ln -sf "$(command -v $c)" "$STUB/nopy/$c"; done
out="$(PATH="$STUB/nopy" /bin/bash "$REPO/setup.sh" --format 2>&1 || true)"
check "no python3: clear error" grep -q 'python3 is required' <<<"$out"
mkdir -p "$STUB/py37"; cp "$STUB/nopy/"* "$STUB/py37/" 2>/dev/null || true
printf '#!/bin/sh\nexit 1\n' >"$STUB/py37/python3"; chmod +x "$STUB/py37/python3"
out="$(PATH="$STUB/py37" /bin/bash "$REPO/setup.sh" --format 2>&1 || true)"
check "python 3.7: clear error" grep -q '3.8 or newer' <<<"$out"

mkdir -p "$STUB/nobrew"; ln -sf "$PY3" "$STUB/nobrew/python3"
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' >"$STUB/nobrew/claude"; chmod +x "$STUB/nobrew/claude"
out="$(HOME="$WORK/h-nobrew" PATH="$STUB/nobrew:/usr/bin:/bin" "$REPO/setup.sh" --yes --tools </dev/null 2>&1)"
check "no brew: points to brew.sh" grep -q 'https://brew.sh' <<<"$out"
check "no brew: run still succeeds" grep -q 'Undo everything' <<<"$out"

mkdir -p "$STUB/brew"; cp "$STUB/nobrew/"* "$STUB/brew/"
printf '#!/bin/sh\necho "$@" >>"%s"\n' "$WORK/brew.log" >"$STUB/brew/brew"; chmod +x "$STUB/brew/brew"
: >"$WORK/brew.log"
HOME="$WORK/h-brew" PATH="$STUB/brew:/usr/bin:/bin" "$REPO/setup.sh" --yes --tools </dev/null >/dev/null
check "macOS: brew bundle uses the Brewfile" grep -q "bundle --file $REPO/Brewfile" "$WORK/brew.log"
mkdir -p "$STUB/linux"; cp "$STUB/brew/"* "$STUB/linux/"; printf '#!/bin/sh\necho Linux\n' >"$STUB/linux/uname"; chmod +x "$STUB/linux/uname"
: >"$WORK/brew.log"
HOME="$WORK/h-linux" PATH="$STUB/linux:/usr/bin:/bin" "$REPO/setup.sh" --yes --tools </dev/null >/dev/null
check "Linux: formulae only, no casks" grep -qx 'install gh jq ripgrep fd uv' "$WORK/brew.log"
HOME="$WORK/h-linux2" PATH="$STUB/linux:/usr/bin:/bin" "$REPO/setup.sh" --yes --format --commands </dev/null >/dev/null
check "Linux: format installs" test -f "$WORK/h-linux2/.claude/output-styles/adhd-friendly.md"
mkdir -p "$STUB/noclaude"; ln -sf "$PY3" "$STUB/noclaude/python3"
out="$(HOME="$WORK/h-nc" PATH="$STUB/noclaude:/usr/bin:/bin" "$REPO/setup.sh" --tools </dev/null 2>&1)"
check "no tty, no --yes: Claude Code never installed" grep -q 'Claude Code not installed (needs a yes' <<<"$out"

H="$WORK/h-zsh"; mkdir -p "$H"
check "zsh caller works" zsh -c "HOME='$H' SETUP_NO_TTY=1 '$REPO/setup.sh' --yes --format </dev/null >/dev/null"

H="$WORK/my home/ünï çødé"; mkdir -p "$H"
inst "$H" --format --commands --plugins --name "Zoë O'Neil" >/dev/null
check "space+unicode HOME: installs" has "$H/.claude/CLAUDE.md" "# Replies to Zoë O'Neil"
before="$(snapshot "$H")"; inst "$H" --format --commands --plugins --name "Zoë O'Neil" >/dev/null
check "space+unicode HOME: idempotent" test "$before" = "$(snapshot "$H")"
uninst "$H" >/dev/null
check "space+unicode HOME: uninstall leaves no files" test "$(files_in "$H")" = 0

H="$WORK/h-cfg"; mkdir -p "$H"
CLAUDE_CONFIG_DIR="$H/custom" inst "$H" --format >/dev/null
check "CLAUDE_CONFIG_DIR respected" test -f "$H/custom/output-styles/adhd-friendly.md" -a ! -e "$H/.claude"
CLAUDE_CONFIG_DIR="$H/custom" uninst "$H" >/dev/null
check "CLAUDE_CONFIG_DIR uninstall" test "$(files_in "$H")" = 0

H="$WORK/h-link"; mkdir -p "$H/dotfiles/claude"; ln -s "$H/dotfiles/claude" "$H/.claude"
printf '# dotfile rules\n' >"$H/dotfiles/claude/CLAUDE.md"
inst "$H" --format --plugins >/dev/null
check "symlinked ~/.claude: files land in the target" test -f "$H/dotfiles/claude/output-styles/adhd-friendly.md"
check "symlinked ~/.claude: link kept" test -L "$H/.claude"
uninst "$H" >/dev/null
check "symlinked ~/.claude: uninstall restores" bash -c "printf '# dotfile rules\n' | cmp -s - '$H/dotfiles/claude/CLAUDE.md'"

H="$WORK/h-filelink"; mkdir -p "$H/.claude" "$H/dot"
printf '# linked\n' >"$H/dot/CLAUDE.md"; ln -s "$H/dot/CLAUDE.md" "$H/.claude/CLAUDE.md"
printf '{"model": "opus"}\n' >"$H/dot/settings.json"; ln -s "$H/dot/settings.json" "$H/.claude/settings.json"
inst "$H" --format --plugins >/dev/null
check "symlinked CLAUDE.md stays a symlink" test -L "$H/.claude/CLAUDE.md"
check "symlinked CLAUDE.md target updated" has "$H/dot/CLAUDE.md" "claude-code-setup:begin"
check "symlinked settings.json stays a symlink" test -L "$H/.claude/settings.json"
check "symlinked settings.json target merged" has "$H/dot/settings.json" "progress-bar@progress-bar"
uninst "$H" >/dev/null
check "symlinked files restored through the link" bash -c "test -L '$H/.claude/CLAUDE.md' && printf '# linked\n' | cmp -s - '$H/dot/CLAUDE.md'"

H="$WORK/h-ro"; mkdir -p "$H/.claude"; printf 'mine\n' >"$H/.claude/CLAUDE.md"; chmod 444 "$H/.claude/CLAUDE.md"
rc=0; out="$(inst "$H" --format 2>&1)" || rc=$?
check "read-only CLAUDE.md: skipped with a warning" grep -q 'read-only' <<<"$out"
check "read-only CLAUDE.md: untouched" bash -c "printf 'mine\n' | cmp -s - '$H/.claude/CLAUDE.md'"
check "read-only CLAUDE.md: run still finishes" test "$rc" = 0
chmod 644 "$H/.claude/CLAUDE.md"
H="$WORK/h-rosettings"; mkdir -p "$H/.claude"; echo '{}' >"$H/.claude/settings.json"; chmod 444 "$H/.claude/settings.json"
check "read-only settings.json: stops before writing" bash -c "! HOME='$H' '$REPO/setup.sh' --yes --format >/dev/null 2>&1 && test ! -e '$H/.claude/output-styles'"
chmod 644 "$H/.claude/settings.json"

echo "S2. Interrupt"
H="$WORK/h-int"; mkdir -p "$H/.claude"; cp "$REPO/tests/fixtures/user/CLAUDE.md" "$H/.claude/CLAUDE.md"
printf '#!/bin/sh\nsleep 30\n' >"$STUB/slowclaude"; chmod +x "$STUB/slowclaude"
HOME="$H" SETUP_CLAUDE_BIN="$STUB/slowclaude" "$REPO/setup.sh" --yes --migrate </dev/null >"$WORK/int.log" 2>&1 &
pid=$!; sleep 2
pkill -TERM -P "$pid" 2>/dev/null || true; pkill -TERM -f "$STUB/slowclaude" 2>/dev/null || true; kill -TERM "$pid" 2>/dev/null || true
rc=0; wait "$pid" 2>/dev/null || rc=$?
check "interrupted run exits non-zero" test "$rc" != 0
check "interrupted run leaves CLAUDE.md whole" cmp -s "$H/.claude/CLAUDE.md" "$REPO/tests/fixtures/user/CLAUDE.md"
check "no temp files left behind" test -z "$(find "$H" -name '.ccs-tmp-*' -o -name '.tmp-settings-*')"

echo "S3. Settings shapes"
for bad in '{"a": 1, // comment
}' '{"a": 1,}' '[1, 2]' '{"enabledPlugins": []}'; do
  H="$WORK/h-bad$RANDOM"; mkdir -p "$H/.claude"; printf '%s\n' "$bad" >"$H/.claude/settings.json"
  out="$(inst "$H" --format --plugins 2>&1 || true)"
  check "bad settings ($(head -c 18 <<<"$bad" | tr '\n' ' ')): clear error" grep -q 'Nothing was changed' <<<"$out"
  check "bad settings: no files written" test "$(files_in "$H")" = 1
done
H="$WORK/h-empty"; mkdir -p "$H/.claude"; : >"$H/.claude/settings.json"
inst "$H" --plugins >/dev/null
check "empty settings.json is merged" has "$H/.claude/settings.json" "progress-bar@progress-bar"
H="$WORK/h-huge"; mkdir -p "$H/.claude"
python3 -c "import json,sys; json.dump({'permissions': {'allow': [f'Bash(cmd{i}:*)' for i in range(100000)]}, 'model': 'x'}, open(sys.argv[1], 'w'))" "$H/.claude/settings.json"
inst "$H" --plugins >/dev/null
check "huge settings.json keeps every key" test "$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['permissions']['allow']), d['model'], d['enabledPlugins']['progress-bar@progress-bar'])" "$H/.claude/settings.json")" = "100000 x True"
H="$WORK/h-set"; mkdir -p "$H/.claude"
printf '%s\n' '{"enabledPlugins": {"progress-bar@progress-bar": true}, "extraKnownMarketplaces": {"progress-bar": {"source": {"source": "github", "repo": "someone/fork"}}}}' >"$H/.claude/settings.json"
cp "$H/.claude/settings.json" "$WORK/set-orig.json"
out="$(inst "$H" --plugins 2>&1)"
check "different marketplace source is kept" has "$H/.claude/settings.json" "someone/fork"
check "kept key is reported" grep -q 'kept your extraKnownMarketplaces.progress-bar' <<<"$out"
check "no change means no settings backup" test "$(find "$H" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" = 0
uninst "$H" >/dev/null
check "uninstall leaves pre-set keys alone" json_eq "$H/.claude/settings.json" "$(cat "$WORK/set-orig.json")"

echo "S4. CLAUDE.md shapes"
H="$WORK/h-emptymd"; mkdir -p "$H/.claude"; : >"$H/.claude/CLAUDE.md"
inst "$H" --format >/dev/null; uninst "$H" >/dev/null
check "empty CLAUDE.md: restored empty" test -f "$H/.claude/CLAUDE.md" -a ! -s "$H/.claude/CLAUDE.md"
H="$WORK/h-crlf"; mkdir -p "$H/.claude"; printf '# Mine\r\nkeep\r\n' >"$H/.claude/CLAUDE.md"; cp "$H/.claude/CLAUDE.md" "$WORK/crlf.md"
inst "$H" --format >/dev/null
check "CRLF: block uses CRLF" bash -c "grep -q \$'claude-code-setup:end -->\r' '$H/.claude/CLAUDE.md'"
before="$(snapshot "$H")"; inst "$H" --format >/dev/null
check "CRLF: re-run idempotent" test "$before" = "$(snapshot "$H")"
uninst "$H" >/dev/null
check "CRLF: uninstall restores bytes" cmp -s "$H/.claude/CLAUDE.md" "$WORK/crlf.md"
H="$WORK/h-old"; mkdir -p "$H/.claude"
printf '# Top\n\n<!-- claude-code-setup:begin (old wording) -->\nold rules\n<!-- claude-code-setup:end -->\n\n# After\nmine\n' >"$H/.claude/CLAUDE.md"
inst "$H" --format >/dev/null
check "old block upgraded in place" bash -c "! grep -q 'old rules' '$H/.claude/CLAUDE.md' && grep -q '# Replies to the user' '$H/.claude/CLAUDE.md'"
check "text after the block kept after it" bash -c "tail -2 '$H/.claude/CLAUDE.md' | grep -q 'mine'"
check "exactly one block" test "$(grep -c 'claude-code-setup:begin' "$H/.claude/CLAUDE.md")" = 1
H="$WORK/h-dup"; mkdir -p "$H/.claude"
printf 'a\n<!-- claude-code-setup:begin x -->\n1\n<!-- claude-code-setup:end -->\nb\n<!-- claude-code-setup:begin x -->\n2\n<!-- claude-code-setup:end -->\nc\n' >"$H/.claude/CLAUDE.md"
inst "$H" --format >/dev/null
check "duplicate blocks collapse to one" test "$(grep -c 'claude-code-setup:begin' "$H/.claude/CLAUDE.md")" = 1
check "text between duplicates kept" bash -c "grep -qx b '$H/.claude/CLAUDE.md' && grep -qx c '$H/.claude/CLAUDE.md'"
H="$WORK/h-edit"; mkdir -p "$H"; inst "$H" --format >/dev/null
sed -i.tmp 's/Failures first/Failures LAST/' "$H/.claude/CLAUDE.md"; rm -f "$H/.claude/CLAUDE.md.tmp"; sleep 1
inst "$H" --format >/dev/null
check "edit inside the block is replaced" bash -c "! grep -q 'Failures LAST' '$H/.claude/CLAUDE.md'"
check "edit inside the block is backed up" bash -c "grep -l 'Failures LAST' '$H/.claude/'CLAUDE.md.bak-* >/dev/null"
H="$WORK/h-imp"; mkdir -p "$H/.claude"; printf '# Mine\n@RTK.md\n' >"$H/.claude/CLAUDE.md"
PATH="$WORK/bin:$PATH" inst "$H" --format --rtk >/dev/null
check "@RTK.md outside the block is not duplicated" test "$(grep -c '@RTK.md' "$H/.claude/CLAUDE.md")" = 1

echo "S5. Migrate edge cases"
H="$WORK/h-mnc"; mkdir -p "$H/.claude"; cp "$REPO/tests/fixtures/user/CLAUDE.md" "$H/.claude/"
out="$(HOME="$H" SETUP_CLAUDE_BIN="$WORK/nope/claude" "$REPO/setup.sh" --yes --migrate </dev/null 2>&1)"
check "claude missing: falls back to no-llm" grep -q 'claude not found' <<<"$out"
H="$WORK/h-mf"; mkdir -p "$H/.claude"; cp "$REPO/tests/fixtures/user/CLAUDE.md" "$H/.claude/"
inst "$H" --format >/dev/null; sleep 1
SETUP_CLAUDE_BIN="$REPO/tests/fakes/claude" inst "$H" --migrate >/dev/null; sleep 1
inst "$H" --format >/dev/null
check "format + migrate + format: one block" test "$(grep -c 'claude-code-setup:begin' "$H/.claude/CLAUDE.md")" = 1
uninst "$H" >/dev/null
check "format + migrate: uninstall restores the original" cmp -s "$H/.claude/CLAUDE.md" "$REPO/tests/fixtures/user/CLAUDE.md"

echo "S6. Uninstall edge cases"
H="$WORK/h-part"; mkdir -p "$H"; inst "$H" --commands >/dev/null; uninst "$H" >/dev/null
check "partial install: uninstall leaves no files" test "$(files_in "$H")" = 0
H="$WORK/h-medit"; mkdir -p "$H"; inst "$H" --commands >/dev/null
echo "my tweak" >>"$H/.claude/commands/worked-hours.md"
uninst "$H" >/dev/null
check "edited file is saved before delete" bash -c "grep -q 'my tweak' '$H/.claude/commands/'worked-hours.md.bak-uninstall-*"
H="$WORK/h-two"; mkdir -p "$H/.claude"; printf 'orig\n' >"$H/.claude/CLAUDE.md"
inst "$H" --format --name A >/dev/null; sleep 1; inst "$H" --format --name B >/dev/null
check "second install with a new name updates the block" has "$H/.claude/CLAUDE.md" "# Replies to B"
uninst "$H" >/dev/null
check "two installs: uninstall restores the original" bash -c "printf 'orig\n' | cmp -s - '$H/.claude/CLAUDE.md'"
H="$WORK/h-noman"; mkdir -p "$H"; inst "$H" --plugins --format >/dev/null; rm "$H/.claude/.claude-code-setup/manifest.tsv"
out="$(uninst "$H" 2>&1)"
check "missing manifest: says so" grep -q 'no file record' <<<"$out"
check "missing manifest: settings still undone" bash -c "test ! -e '$H/.claude/settings.json'"
H="$WORK/h-uedit"; mkdir -p "$H"; inst "$H" --plugins >/dev/null
python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['enabledPlugins']['progress-bar@progress-bar']=False; json.dump(d,open(p,'w'))" "$H/.claude/settings.json"
uninst "$H" >/dev/null
check "settings key changed by the user is left" test "$(json_get "$H/.claude/settings.json" enabledPlugins progress-bar@progress-bar)" = false

echo "S7. Hours script"
HS="$REPO/templates/scripts/workday-hours.py"
out="$(HOME="$WORK/h-none" python3 "$HS" 2026-01-01 2>&1 || true)"
check "no projects dir: clear message" grep -q 'No transcripts folder' <<<"$out"
P="$WORK/h-hrs/.claude/projects/-p"; mkdir -p "$P"
printf '%s\n' '["timestamp"]' '{"timestamp": 5}' '{"timestamp": null}' '{"timestamp": "garbage"}' '{"timestamp": "2026-03-10T23:30:00Z"}' '{"timestamp": "2026-03-10T23:45:00Z"}' '{"timestamp":' >"$P/a.jsonl"
check "odd lines ignored, UTC day counted in UTC" bash -c "TZ=UTC HOME='$WORK/h-hrs' python3 '$HS' 2026-03-10 | grep -q 'events: 2'"
check "day boundary: Tokyo puts it on the next day" bash -c "TZ=Asia/Tokyo HOME='$WORK/h-hrs' python3 '$HS' 2026-03-11 | grep -q 'events: 2'"
check "day boundary: Los Angeles keeps it on the same day" bash -c "TZ=America/Los_Angeles HOME='$WORK/h-hrs' python3 '$HS' 2026-03-10 | grep -q 'events: 2'"
check "bad date: exit 2" bash -c "HOME='$WORK/h-hrs' python3 '$HS' 2026-13-45 >/dev/null 2>&1; test \$? = 2"
python3 -c "
import json,sys
with open(sys.argv[1],'w') as f:
    for i in range(300000): f.write(json.dumps({'timestamp': '2026-03-12T10:%02d:%02dZ' % (i // 60 % 60, i % 60), 'message': {'content': 'x' * 50}}) + '\n')
" "$P/big.jsonl"
start=$SECONDS
check "300k-line transcript counted" bash -c "TZ=UTC HOME='$WORK/h-hrs' python3 '$HS' 2026-03-12 | grep -q 'ACTIVE 1.00 h'"
check "300k-line transcript under 20 s" test $((SECONDS - start)) -lt 20

echo "S8. Round 2"
H="$WORK/h-name"; mkdir -p "$H"; inst "$H" --format --name 'A&B \1 $HOME "q"' >/dev/null
check "name with & \\ \$ and quotes rendered literally" has "$H/.claude/CLAUDE.md" '# Replies to A&B \1 $HOME "q"'
H="$WORK/h-noname"; mkdir -p "$H"; inst "$H" --format --name '' >/dev/null
check "empty --name falls back to the user" has "$H/.claude/CLAUDE.md" "# Replies to the user"
H="$WORK/h-rel"; mkdir -p "$H"
check "relative path from another folder" bash -c "cd '$WORK' && HOME='$H' SETUP_NO_TTY=1 \"\$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' '$REPO/setup.sh')\" --yes --format >/dev/null"
check "sh setup.sh re-runs under bash" bash -c "sh '$REPO/setup.sh' --help | grep -q -- --migrate"
check "uninstall unknown flag fails" bash -c "! HOME='$H' '$REPO/uninstall.sh' --bogus >/dev/null 2>&1"
H="$WORK/h-uni"; mkdir -p "$H/.claude"; printf '{"zeta": "ünïcödé ✓", "alpha": 1}\n' >"$H/.claude/settings.json"
inst "$H" --plugins >/dev/null
check "unicode settings values kept" has "$H/.claude/settings.json" '"zeta": "ünïcödé ✓"'
check "settings key order kept" bash -c "python3 -c \"import json,sys; print(list(json.load(open(sys.argv[1]))))\" '$H/.claude/settings.json' | grep -q \"\\['zeta', 'alpha'\""
H="$WORK/h-bom"; mkdir -p "$H/.claude"; printf '\xef\xbb\xbf{"model": "x"}\n' >"$H/.claude/settings.json"
inst "$H" --plugins >/dev/null 2>&1 || true
check "settings.json with a BOM is merged" has "$H/.claude/settings.json" "progress-bar@progress-bar"
H="$WORK/h-dir"; mkdir -p "$H/.claude/CLAUDE.md"
rc=0; out="$(inst "$H" --format 2>&1)" || rc=$?
check "CLAUDE.md that is a folder: run finishes" test "$rc" = 0
check "CLAUDE.md that is a folder: skipped with a reason" grep -q 'not a regular file' <<<"$out"
H="$WORK/h-gone"; mkdir -p "$H"; inst "$H" --plugins >/dev/null; rm "$H/.claude/settings.json"
check "uninstall after settings.json was deleted" bash -c "HOME='$H' '$REPO/uninstall.sh' >/dev/null && test ! -e '$H/.claude/settings.json'"
H="$WORK/h-udry"; mkdir -p "$H"; inst "$H" --format --commands --plugins >/dev/null
before="$(snapshot "$H")"; uninst "$H" --dry-run >/dev/null
check "uninstall --dry-run changes nothing" test "$before" = "$(snapshot "$H")"
M="$WORK/h-mcrlf"; mkdir -p "$M/home/.claude" "$M/proj"
printf 'Use pnpm.\r\nAlways end with a summary.\r\n' >"$M/proj/AGENTS.md"; cp "$M/proj/AGENTS.md" "$WORK/agents-crlf"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/proj" </dev/null >"$WORK/mcrlf.log")
check "CRLF AGENTS.md: block uses CRLF" bash -c "grep -q \$'claude-code-setup:end -->\r' '$M/proj/AGENTS.md'"
check "CRLF AGENTS.md: conflict listed" grep -q 'AGENTS.md:2: Always end with a summary' "$WORK/mcrlf.log"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "CRLF AGENTS.md: uninstall restores bytes" cmp -s "$M/proj/AGENTS.md" "$WORK/agents-crlf"
M="$WORK/h-mcmd"; mkdir -p "$M/home/.claude/commands/team"; printf 'Review the PR.\nAlways end with a summary table.\n' >"$M/home/.claude/commands/team/review.md"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --dry-run </dev/null >"$WORK/mcmd.log")
check "nested slash command scanned" grep -q 'review.md:2: Always end with a summary' "$WORK/mcmd.log"
check "--project with a missing folder fails clearly" bash -c "HOME='$M/home' '$REPO/setup.sh' --yes --migrate --project '$WORK/nope' 2>&1 | grep -q 'no such folder'"
M="$WORK/h-msec"; mkdir -p "$M/home/.claude" "$M/proj"; : >"$WORK/sec.log"
printf 'Deploy with token ghp_%s\nAlways end with a summary.\n' "abcdefghijklmnopqrstuvwxyz1234" >"$M/proj/AGENTS.md"
(cd "$M" && HOME="$M/home" SETUP_CLAUDE_BIN="$REPO/tests/fakes/claude" FAKE_CLAUDE_LOG="$WORK/sec.log" "$REPO/setup.sh" --yes --migrate --project "$M/proj" </dev/null >"$WORK/msec.log")
check "GitHub token in a project file: never sent" test ! -s "$WORK/sec.log"
check "GitHub token not printed" bash -c "! grep -q 'abcdefghijklmnop' '$WORK/msec.log'"
P="$WORK/h-hrs2/cfg/projects/-Users-sam-work-x"; mkdir -p "$P"
printf '%s\n' '{"timestamp": "2026-04-01T10:00:00Z"}' '{"timestamp": "2026-04-01T10:10:00Z"}' '{"timestamp": "2026-04-01T10:20:00Z"}' >"$P/a.jsonl"
check "hours: CLAUDE_CONFIG_DIR respected" bash -c "TZ=UTC CLAUDE_CONFIG_DIR='$WORK/h-hrs2/cfg' python3 '$HS' 2026-04-01 | grep -q 'events: 3'"
check "hours: prefix with trailing slash" bash -c "TZ=UTC CLAUDE_CONFIG_DIR='$WORK/h-hrs2/cfg' python3 '$HS' 2026-04-01 --prefix /Users/sam/work/ | grep -q 'events: 3'"
check "hours: --gap 5 splits blocks" bash -c "TZ=UTC CLAUDE_CONFIG_DIR='$WORK/h-hrs2/cfg' python3 '$HS' 2026-04-01 --gap 5 | grep -q 'ACTIVE 0.00 h'"
P2="$WORK/h-hrs2/cfg/projects/-Users-sam-workshop"; mkdir -p "$P2"; printf '%s\n' '{"timestamp": "2026-04-01T11:00:00Z"}' >"$P2/b.jsonl"
check "hours: prefix /work does not match /workshop" bash -c "TZ=UTC CLAUDE_CONFIG_DIR='$WORK/h-hrs2/cfg' python3 '$HS' 2026-04-01 --prefix /Users/sam/work | grep -q 'events: 3'"

echo "S9. Round 3"
M="$WORK/h-alink"; mkdir -p "$M/home/.claude" "$M/proj"
printf 'Use pnpm.\nAlways end with a summary.\n' >"$M/proj/CLAUDE.md"; ln -s CLAUDE.md "$M/proj/AGENTS.md"; cp "$M/proj/CLAUDE.md" "$WORK/alink-orig"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/proj" </dev/null >"$WORK/alink.log")
check "AGENTS.md symlinked to CLAUDE.md: one block" test "$(grep -c 'claude-code-setup:begin' "$M/proj/CLAUDE.md")" = 1
check "AGENTS.md symlink kept" test -L "$M/proj/AGENTS.md"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "AGENTS.md symlink case: uninstall restores" cmp -s "$M/proj/CLAUDE.md" "$WORK/alink-orig"
M="$WORK/h-again"; new_migrate_home "$M"
mig "$M" --no-llm --yes >/dev/null; HOME="$M/home" "$REPO/uninstall.sh" >/dev/null; sleep 1
mig "$M" --no-llm --yes >/dev/null
check "migrate again after uninstall works" has "$M/home/.claude/CLAUDE.md" "claude-code-setup:begin"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "second uninstall restores the original" cmp -s "$M/home/.claude/CLAUDE.md" "$REPO/tests/fixtures/user/CLAUDE.md"
check "bench rejects a bad isolation mode" bash -c "! '$REPO/bench/run.sh' --model x --isolation nope --yes >/dev/null 2>&1"
OUTO="$WORK/bench-only"
"$REPO/bench/run.sh" --model stub-model --runs 1 --only fix-2,status-2 --yes --claude "$REPO/tests/fakes/bench-claude" --out "$OUTO" >/dev/null 2>&1 || true
check "bench --only runs just those tasks" test "$(find "$OUTO" -path '*/[AB]/*.json' | wc -l | tr -d ' ')" = 4

if [[ "$(uname -s)" == Darwin ]] && command -v script >/dev/null 2>&1; then
  pty() { local h="$1" input="$2"; shift 2; (sleep 1; printf '%b' "$input"; sleep 5) | env -u SETUP_NO_TTY HOME="$h" script -q /dev/null "$REPO/setup.sh" "$@" >"$WORK/pty.log" 2>&1 || true; }
  H="$WORK/h-pty1"; mkdir -p "$H"
  pty "$H" 'y\ny\nn\nn\nn\nn\nSam\n'
  check "interactive menu: chosen parts installed" bash -c "grep -q 'Replies to Sam' '$H/.claude/CLAUDE.md' && test -f '$H/.claude/commands/worked-hours.md'"
  check "interactive menu: declined plugins not added" bash -c "! grep -q progress-bar '$H/.claude/settings.json'"
  H="$WORK/h-pty2"; mkdir -p "$H/.claude"; echo '{"outputStyle": "Explanatory"}' >"$H/.claude/settings.json"
  pty "$H" 'y\n' --format --name Sam
  check "interactive: yes switches an existing outputStyle" test "$(json_get "$H/.claude/settings.json" outputStyle)" = '"adhd-friendly"'
  M="$WORK/h-pty3"; new_migrate_home "$M"
  pty "$M/home" 'n\n' --migrate --no-llm --name Sam
  check "interactive migrate: no means not written" cmp -s "$M/home/.claude/CLAUDE.md" "$REPO/tests/fixtures/user/CLAUDE.md"
else
  echo "○ interactive tests need macOS script(1), skipped"
fi

echo "S10. Round 4"
check "zsh uninstall.sh re-runs under bash" bash -c "zsh '$REPO/uninstall.sh' --help | grep -q Usage"
check "numbered-steps rule in the output style" has "$REPO/templates/output-styles/adhd-friendly.md.tmpl" '"1. ✓ Merge", "2. … Tests", "3. ○ Deploy"'
check "numbered-steps rule in the CLAUDE.md core rules" has "$REPO/templates/CLAUDE.md.tmpl" 'with the glyph after the number ("1. ✓ Merge")'
for f in "$REPO/setup.sh" "$REPO/uninstall.sh" "$REPO/bench/run.sh"; do
  check "$(basename "$f"): strict mode + valid syntax" bash -c "grep -q '^set -euo pipefail' '$f' && /bin/bash -n '$f'"
done
H="$WORK/h-nl"; mkdir -p "$H"; inst "$H" --format --commands >/dev/null
check "installed files: LF only, newline at end" python3 - "$H/.claude" <<'PY'
import os, sys
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        b = open(os.path.join(root, f), "rb").read()
        if b and (b"\r\n" in b or not b.endswith(b"\n")):
            sys.exit(f"bad line ending: {f}")
PY
H="$WORK/h-rtkgone"; mkdir -p "$H"; PATH="$WORK/bin:$PATH" inst "$H" --format --rtk >/dev/null
rc=0; HOME="$H" PATH="$STUB/nobrew:/usr/bin:/bin" "$REPO/setup.sh" --yes --format --rtk </dev/null >"$WORK/rtkgone.log" 2>&1 || rc=$?
check "rtk removed later: says rtk is missing" grep -q 'rtk is not installed' "$WORK/rtkgone.log"
check "rtk removed later: re-run still finishes" test "$rc" = 0
check "rtk removed later: import kept for the installed RTK.md" has "$H/.claude/CLAUDE.md" "@RTK.md"
H="$WORK/h-all"; mkdir -p "$H"; cp "$WORK/bin/rtk" "$STUB/brew/rtk"
rc=0; HOME="$H" PATH="$STUB/brew:/usr/bin:/bin" "$REPO/setup.sh" --yes --all </dev/null >"$WORK/all.log" 2>&1 || rc=$?
check "--all with stubs: finishes" test "$rc" = 0
check "--all: every part installed" bash -c "test -f '$H/.claude/RTK.md' -a -f '$H/.claude/commands/worked-hours.md' -a -f '$H/.claude/output-styles/adhd-friendly.md' && grep -q progress-bar '$H/.claude/settings.json'"
H="$WORK/h-nobak"; mkdir -p "$H/.claude"; printf 'x\n' >"$H/.claude/RTK.md"; PATH="$WORK/bin:$PATH" inst "$H" --rtk >/dev/null
rm -f "$H/.claude/"RTK.md.bak-*
rc=0; out="$(uninst "$H" 2>&1)" || rc=$?
check "missing backup: reported, uninstall finishes" bash -c "test $rc = 0" && check "missing backup: message" grep -q 'is missing, left' <<<"$out"
H="$WORK/h-empty-home"; mkdir -p "$H"
rc=0; out="$(cd "$H" && HOME="$H" "$REPO/setup.sh" --yes --migrate --no-llm </dev/null 2>&1)" || rc=$?
check "migrate with nothing to migrate: finishes" test "$rc" = 0
check "migrate with nothing to migrate: says so" grep -q 'nothing to migrate' <<<"$out"
M="$WORK/h-llmdry"; new_migrate_home "$M"
SETUP_CLAUDE_BIN="$FAKE" FAKE_CLAUDE_LOG="$WORK/llmdry.log" mig "$M" --yes --dry-run >/dev/null
check "LLM dry run: no state written in HOME" test ! -e "$M/home/.claude/.claude-code-setup"
check "LLM dry run: CLAUDE.md untouched" cmp -s "$M/home/.claude/CLAUDE.md" "$FIX/user/CLAUDE.md"
H="$WORK/h-rolink"; mkdir -p "$H/.claude" "$H/dot"; echo '{}' >"$H/dot/s.json"; chmod 444 "$H/dot/s.json"; ln -s "$H/dot/s.json" "$H/.claude/settings.json"
check "read-only settings behind a symlink: stops before writing" bash -c "! HOME='$H' '$REPO/setup.sh' --yes --plugins --format >/dev/null 2>&1 && test ! -e '$H/.claude/output-styles'"
chmod 644 "$H/dot/s.json"
mkdir -p "$WORK/h-emptyproj/.claude/projects"
check "hours: empty projects dir exits 1 with a message" bash -c "HOME='$WORK/h-emptyproj' python3 '$HS' 2026-01-01 | grep -q 'No transcript activity'; test \${PIPESTATUS[0]} = 1"
cat >"$STUB/promptcheck" <<'PYX'
#!/usr/bin/env python3
import sys
p = sys.stdin.read()
open(sys.argv[0] + ".seen", "w").write(p)
print("<migrated_file>\nx\n</migrated_file>")
PYX
chmod +x "$STUB/promptcheck"
M="$WORK/h-prompt"; new_migrate_home "$M"; SETUP_CLAUDE_BIN="$STUB/promptcheck" mig "$M" --yes --dry-run >/dev/null 2>&1 || true
check "model prompt has every placeholder filled" bash -c "test -s '$STUB/promptcheck.seen' && ! grep -q '{{' '$STUB/promptcheck.seen'"
check "model prompt carries the numbered-steps rule" grep -q 'never glyph bullets' "$STUB/promptcheck.seen"

echo "S11. Round 5"
H="$WORK/h-dryall"; mkdir -p "$H"
HOME="$H" PATH="$STUB/brew:/usr/bin:/bin" "$REPO/setup.sh" --yes --all --dry-run </dev/null >/dev/null 2>&1 || true
check "--all --dry-run writes nothing" test -z "$(find "$H" -mindepth 1 -print -quit)"
M="$WORK/h-every"; mkdir -p "$M/home/.claude" "$M/proj/.github" "$M/proj/.claude"
for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md .windsurfrules .cursorrules; do
  printf 'Fact for %s.\nAlways end with a summary.\n' "$f" >"$M/proj/$f"
done
cp -R "$M/proj" "$WORK/every-orig"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/proj" </dev/null >"$WORK/every.log")
check "all 8 project file types get a block" test "$(grep -l 'claude-code-setup:begin' "$M/proj/CLAUDE.md" "$M/proj/CLAUDE.local.md" "$M/proj/.claude/CLAUDE.md" "$M/proj/AGENTS.md" "$M/proj/GEMINI.md" "$M/proj/.github/copilot-instructions.md" "$M/proj/.windsurfrules" "$M/proj/.cursorrules" | wc -l | tr -d ' ')" = 8
check "Claude files get core rules, others the portable format" bash -c "grep -q '# Replies to' '$M/proj/CLAUDE.local.md' && grep -q '# Reply format' '$M/proj/GEMINI.md' && ! grep -q '# Reply format' '$M/proj/CLAUDE.md'"
check "8 conflicts listed" grep -q '! 8 format rule' "$WORK/every.log"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "all 8 restored by uninstall" diff -r "$M/proj" "$WORK/every-orig" -x '*.bak-*'
M="$WORK/h-noop"; new_migrate_home "$M"; : >"$WORK/noop.log"
SETUP_CLAUDE_BIN="$FAKE" FAKE_CLAUDE_LOG="$WORK/noop.log" FAKE_CLAUDE_MODE=noop mig "$M" --yes >/dev/null
n1="$(wc -l <"$WORK/noop.log")"
SETUP_CLAUDE_BIN="$FAKE" FAKE_CLAUDE_LOG="$WORK/noop.log" FAKE_CLAUDE_MODE=noop mig "$M" --yes >/dev/null
check "model found nothing to change: not asked again" test "$n1" = "$(wc -l <"$WORK/noop.log")"
check "model found nothing to change: no note" bash -c "! grep -q 'Migrated by' '$M/home/.claude/CLAUDE.md'"
M="$WORK/h-style"; mkdir -p "$M/home/.claude/output-styles"; printf -- '---\nname: chatty\n---\nAlways end with a summary.\n' >"$M/home/.claude/output-styles/chatty.md"
cp "$M/home/.claude/output-styles/chatty.md" "$WORK/chatty"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm </dev/null >"$WORK/style.log")
check "other output style: conflict listed" grep -q 'chatty.md:4: Always end with a summary' "$WORK/style.log"
check "other output style: no block added" cmp -s "$M/home/.claude/output-styles/chatty.md" "$WORK/chatty"
M="$WORK/h-medit2"; new_migrate_home "$M"; mig "$M" --no-llm --yes >/dev/null
echo "my later note" >>"$M/home/.claude/CLAUDE.md"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "edited migrated file: edits saved before restore" bash -c "grep -q 'my later note' '$M/home/.claude/'CLAUDE.md.bak-uninstall-*"
check "edited migrated file: original restored" cmp -s "$M/home/.claude/CLAUDE.md" "$FIX/user/CLAUDE.md"
H="$WORK/h-oneline"; mkdir -p "$H/.claude"; python3 -c "import sys; open(sys.argv[1],'w').write('x' * 1000000)" "$H/.claude/CLAUDE.md"
inst "$H" --format >/dev/null; uninst "$H" >/dev/null
check "1 MB single-line CLAUDE.md round-trips" test "$(wc -c <"$H/.claude/CLAUDE.md" | tr -d ' ')" = 1000001 -o "$(wc -c <"$H/.claude/CLAUDE.md" | tr -d ' ')" = 1000000
long="$(python3 -c "print('N' * 500)")"; H="$WORK/h-long"; mkdir -p "$H"; inst "$H" --format --name "$long" >/dev/null
check "500-character name works" has "$H/.claude/CLAUDE.md" "# Replies to $long"
mkdir -p "$WORK/bench-empty"
check "bench score on an empty folder fails clearly" bash -c "python3 '$REPO/bench/score.py' '$WORK/bench-empty' 2>&1 | grep -q 'no results'"

echo "S12. Round 6"
H="$WORK/h-slash"; mkdir -p "$H"; HOME="$H/" "$REPO/setup.sh" --yes --format </dev/null >"$WORK/slash.log"
check "HOME with a trailing slash: installs" test -f "$H/.claude/output-styles/adhd-friendly.md"
check "HOME with a trailing slash: paths shown with ~" grep -q 'created ~/.claude/CLAUDE.md' "$WORK/slash.log"
check "name with a newline is rejected" bash -c "! HOME='$WORK/h-nlname' '$REPO/setup.sh' --yes --format --name \$'a\nb' >/dev/null 2>&1"
H="$WORK/h-eq"; mkdir -p "$H" "$WORK/eqproj"; printf 'Always end with a summary.\n' >"$WORK/eqproj/AGENTS.md"
(cd "$H" && HOME="$H" "$REPO/setup.sh" --yes --format --migrate --no-llm --name=Sam --project="$WORK/eqproj" </dev/null >/dev/null)
check "--name=X and --project=X forms" bash -c "grep -q 'Replies to Sam' '$H/.claude/CLAUDE.md' && grep -q 'claude-code-setup:begin' '$WORK/eqproj/AGENTS.md'"
H="$WORK/h-file"; mkdir -p "$H"; printf 'not a dir\n' >"$H/.claude"
rc=0; out="$(inst "$H" --format 2>&1)" || rc=$?
check "~/.claude is a file: fails" test "$rc" != 0
check "~/.claude is a file: no traceback" bash -c "! grep -q Traceback <<<\"\$1\"" _ "$out"
check "~/.claude is a file: left alone" bash -c "printf 'not a dir\n' | cmp -s - '$H/.claude'"
H="$WORK/h-sdir"; mkdir -p "$H/.claude/settings.json"
rc=0; out="$(inst "$H" --plugins 2>&1)" || rc=$?
check "settings.json is a folder: fails" test "$rc" != 0
check "settings.json is a folder: no traceback" bash -c "! grep -q Traceback <<<\"\$1\"" _ "$out"
M="$WORK/h-emptyagents"; mkdir -p "$M/home/.claude" "$M/proj"; : >"$M/proj/AGENTS.md"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/proj" </dev/null >/dev/null)
check "empty AGENTS.md gets the portable block" has "$M/proj/AGENTS.md" "# Reply format"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "empty AGENTS.md restored empty" test -f "$M/proj/AGENTS.md" -a ! -s "$M/proj/AGENTS.md"
M="$WORK/h-blockonly"; mkdir -p "$M/home"; inst "$M/home" --format >/dev/null; : >"$WORK/bo.log"
(cd "$M" && HOME="$M/home" SETUP_CLAUDE_BIN="$FAKE" FAKE_CLAUDE_LOG="$WORK/bo.log" "$REPO/setup.sh" --yes --migrate </dev/null >/dev/null)
check "file holding only our block: model not called" test ! -s "$WORK/bo.log"
H="$WORK/h-badman"; mkdir -p "$H"; inst "$H" --commands >/dev/null
printf 'garbage-line-without-tabs\n\tonly-path\n' >>"$H/.claude/.claude-code-setup/manifest.tsv"
rc=0; uninst "$H" >/dev/null 2>&1 || rc=$?
check "malformed manifest lines are skipped" bash -c "test $rc = 0 && test ! -e '$H/.claude/commands/worked-hours.md'"
H="$WORK/h-badstate"; mkdir -p "$H"; inst "$H" --plugins >/dev/null; echo '{oops' >"$H/.claude/.claude-code-setup/settings-state.json"
rc=0; out="$(uninst "$H" 2>&1)" || rc=$?
check "corrupt settings record: clear error" grep -q 'not valid JSON' <<<"$out"
check "corrupt settings record: no traceback" bash -c "! grep -q Traceback <<<\"\$1\"" _ "$out"
P="$WORK/h-hrs3/.claude/projects/-p"; mkdir -p "$P/dir.jsonl"
printf '%s\n' '{"timestamp": "2026-05-01T10:00:00Z"}' >"$P/ok.jsonl"; printf '%s\n' '{"timestamp": "2026-05-01T10:05:00Z"}' >"$P/locked.jsonl"; chmod 000 "$P/locked.jsonl"
check "hours: unreadable file and *.jsonl folder are skipped" bash -c "TZ=UTC HOME='$WORK/h-hrs3' python3 '$HS' 2026-05-01 | grep -q 'events: 1'"
chmod 644 "$P/locked.jsonl"
H="$WORK/h-tok"; mkdir -p "$H"; inst "$H" --format --name '{{NAME}}' >/dev/null
check "name that looks like a placeholder is kept literally" has "$H/.claude/CLAUDE.md" "# Replies to {{NAME}}"
M="$WORK/h-many"; mkdir -p "$M/home/.claude/commands"
for i in $(seq 1 300); do printf 'Command %s.\nAlways end with a summary.\n' "$i" >"$M/home/.claude/commands/c$i.md"; done
start=$SECONDS; (cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --dry-run </dev/null >"$WORK/many.log")
check "300 command files scanned" grep -q '! 300 format rule' "$WORK/many.log"
check "300 command files under 20 s" test $((SECONDS - start)) -lt 20
H="$WORK/h-relun"; mkdir -p "$H"; inst "$H" --commands >/dev/null
check "uninstall via a relative path from another folder" bash -c "cd '$WORK' && HOME='$H' \"\$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' '$REPO/uninstall.sh')\" >/dev/null && test ! -e '$H/.claude/commands/worked-hours.md'"
if [[ -x /opt/homebrew/bin/bash ]]; then
  check "bash 5: setup + uninstall round trip" bash -c "H='$WORK/h-b5'; mkdir -p \"\$H/.claude\"; printf 'mine\n' >\"\$H/.claude/CLAUDE.md\"; HOME=\"\$H\" /opt/homebrew/bin/bash '$REPO/setup.sh' --yes --format --commands --plugins </dev/null >/dev/null && HOME=\"\$H\" /opt/homebrew/bin/bash '$REPO/uninstall.sh' >/dev/null && printf 'mine\n' | cmp -s - \"\$H/.claude/CLAUDE.md\""
fi

echo "S13. Round 7"
M="$WORK/h-mdry"; new_migrate_home "$M"; before="$(snapshot "$M")"
mig "$M" --no-llm --yes --dry-run --project "$M/proj" >/dev/null
check "migrate --dry-run with --project changes nothing" test "$before" = "$(snapshot "$M")"
H="$WORK/h-fm"; mkdir -p "$H"
(cd "$H" && HOME="$H" "$REPO/setup.sh" --yes --format --migrate --no-llm </dev/null >/dev/null)
check "format + migrate in one fresh run: one block" test "$(grep -c 'claude-code-setup:begin' "$H/.claude/CLAUDE.md")" = 1
uninst "$H" >/dev/null
check "format + migrate fresh: uninstall leaves no files" test "$(files_in "$H")" = 0
H="$WORK/h-gonblock"; mkdir -p "$H/.claude"; printf 'mine\n' >"$H/.claude/CLAUDE.md"; inst "$H" --format >/dev/null
printf 'mine, edited\n' >"$H/.claude/CLAUDE.md"; uninst "$H" >/dev/null
check "block removed by hand: uninstall leaves the file as is" bash -c "printf 'mine, edited\n' | cmp -s - '$H/.claude/CLAUDE.md'"
H="$WORK/h-xp"; mkdir -p "$H"; inst "$H" --extra-plugins >/dev/null
check "--extra-plugins alone also enables progress-bar" bash -c "grep -q 'progress-bar@progress-bar' '$H/.claude/settings.json' && grep -q 'frontend-design@claude-plugins-official' '$H/.claude/settings.json'"
H="$WORK/h-fs"; mkdir -p "$H"; inst "$H" --format --force-style >/dev/null
check "--force-style with no outputStyle set" test "$(json_get "$H/.claude/settings.json" outputStyle)" = '"adhd-friendly"'
H="$WORK/h-fm2"; mkdir -p "$H"; inst "$H" --format --commands >/dev/null
check "rendered output style has its frontmatter" bash -c "head -5 '$H/.claude/output-styles/adhd-friendly.md' | grep -q '^name: adhd-friendly' && head -5 '$H/.claude/output-styles/adhd-friendly.md' | grep -q '^keep-coding-instructions: true'"
check "rendered command has its frontmatter" bash -c "head -5 '$H/.claude/commands/worked-hours.md' | grep -q '^description:' && head -5 '$H/.claude/commands/worked-hours.md' | grep -q '^allowed-tools:'"
mkdir -p "$WORK/shadow"; printf 'raise SystemExit("shadowed")\n' >"$WORK/shadow/json.py"
check "hours command form (python3 -I) ignores a json.py in the cwd" bash -c "cd '$WORK/shadow' && TZ=UTC HOME='$WORK/h-hrs' python3 -I '$H/.claude/scripts/workday-hours.py' 2026-03-10 | grep -q 'events: 2'"
H="$WORK/h-same"; mkdir -p "$H/.claude"; echo '{"outputStyle": "adhd-friendly"}' >"$H/.claude/settings.json"; inst "$H" --format >/dev/null
check "outputStyle already ours: no settings backup" test "$(find "$H" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" = 0
M="$WORK/h-cdir"; mkdir -p "$M/home/.claude" "$M/proj/.cursor/rules"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/proj" </dev/null >/dev/null)
check "empty .cursor/rules gets the new rule" test -f "$M/proj/.cursor/rules/claude-code-setup-format.mdc"
HOME="$M/home" "$REPO/uninstall.sh" >/dev/null
check "new Cursor rule removed, folder kept" bash -c "test ! -e '$M/proj/.cursor/rules/claude-code-setup-format.mdc' && test -d '$M/proj/.cursor/rules'"
M="$WORK/h-secnollm"; mkdir -p "$M/home/.claude"; printf 'token=ghp_%s\nAlways end with a summary.\n' "abcdefghijklmnopqrstuvwxyz9876" >"$M/home/.claude/CLAUDE.md"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm </dev/null >"$WORK/secnollm.log")
check "secret file, no-llm: block still added locally" has "$M/home/.claude/CLAUDE.md" "claude-code-setup:begin"
check "secret file, no-llm: secret redacted in the printed diff" bash -c "! grep -q 'abcdefghijklmnop' '$WORK/secnollm.log'"
M="$WORK/h sp proj"; mkdir -p "$M/home/.claude" "$M/my proj"; printf 'Always end with a summary.\n' >"$M/my proj/AGENTS.md"
(cd "$M" && HOME="$M/home" "$REPO/setup.sh" --yes --migrate --no-llm --project "$M/my proj" </dev/null >/dev/null)
check "project path with spaces" has "$M/my proj/AGENTS.md" "claude-code-setup:begin"
BR="$WORK/bench-emptytext"; mkdir -p "$BR/A" "$BR/B"
printf '{"arm":"A","id":"fix-2","run":1,"model":"m","text":""}' >"$BR/A/fix-2-r1.json"; printf '{"arm":"B","id":"fix-2","run":1,"model":"m","text":null}' >"$BR/B/fix-2-r1.json"
check "bench score handles empty replies" bash -c "python3 '$REPO/bench/score.py' '$BR' >/dev/null"
check "bench --only with no matching task fails clearly" bash -c "'$REPO/bench/run.sh' --model x --only nope --yes --claude '$REPO/tests/fakes/bench-claude' --out '$WORK/bench-nope' 2>&1 | grep -q 'no tasks match'"

echo "S14. Round 8"
H="$WORK/h-projonly"; mkdir -p "$H" "$WORK/po"
rc=0; out="$(HOME="$H" "$REPO/setup.sh" --yes --format --project "$WORK/po" </dev/null 2>&1)" || rc=$?
check "--project without --migrate: warns and finishes" bash -c "test $rc = 0 && grep -q 'only matters with --migrate' <<<\"\$1\"" _ "$out"
for mode in adds ws; do
  M="$WORK/h-m$mode"; new_migrate_home "$M"
  SETUP_CLAUDE_BIN="$FAKE" FAKE_CLAUDE_MODE=$mode mig "$M" --yes >"$WORK/m$mode.log" 2>&1
  check "model '$mode': its version rejected" bash -c "! grep -q 'Migrated by' '$M/home/.claude/CLAUDE.md'"
done
H="$WORK/h-nullstyle"; mkdir -p "$H/.claude"; echo '{"outputStyle": null}' >"$H/.claude/settings.json"
out="$(inst "$H" --format 2>&1)"
check "outputStyle null is treated as unset: no 'kept' warning" bash -c "! grep -q \"kept your outputStyle\" <<<\"\$1\"" _ "$out"
H="$WORK/h-ws"; mkdir -p "$H/.claude"; printf '  \n\n' >"$H/.claude/CLAUDE.md"
inst "$H" --format >/dev/null; uninst "$H" >/dev/null
check "whitespace-only CLAUDE.md restored byte for byte" bash -c "printf '  \n\n' | cmp -s - '$H/.claude/CLAUDE.md'"
