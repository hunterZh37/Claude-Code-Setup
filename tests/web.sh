# claude.ai text tests: render, length, wording, clipboard (stubbed), uninstall. Sourced by run-tests.sh.
WCLIP="$WORK/clipstub"; mkdir -p "$WCLIP"
printf '#!/bin/sh\ncat >"%s"\n' "$WORK/clipboard.txt" >"$WCLIP/pbcopy"; chmod +x "$WCLIP/pbcopy"
H="$WORK/h-web"; mkdir -p "$H"; rm -f "$WORK/clipboard.txt"
HOME="$H" PATH="$WCLIP:$PATH" "$REPO/tests/setup-flags.sh" --yes --web --name Sam </dev/null >"$WORK/web.log"
W="$H/.claude/.claude-code-setup/web"
check "web: three files rendered" bash -c "test -f '$W/preferences.md' -a -f '$W/style.md' -a -f '$W/project-instructions.md'"
check "web: name filled in" bash -c "grep -q '^Sam wants to decide fast' '$W/preferences.md' && grep -q 'each step only Sam can do' '$W/style.md'"
check "web: no template tokens left" bash -c "! grep -rq '{{' '$W'"
check "web: preferences copied to the clipboard (stub)" cmp -s "$WORK/clipboard.txt" "$W/preferences.md"
check "web: paste steps printed" bash -c "grep -q 'Your Claude, the Instructions box' '$WORK/web.log' && grep -q 'Styles menu' '$WORK/web.log' && grep -q 'Project' '$WORK/web.log'"
check "web: nothing opens a browser" bash -c "! grep -qE '\\b(open|xdg-open)\\b.*https?://' '$REPO/setup.sh'"
long="$(python3 -c "print('Maximilian-Alexander ' * 2)")"
H2="$WORK/h-weblong"; mkdir -p "$H2"; HOME="$H2" PATH="$WCLIP:$PATH" "$REPO/tests/setup-flags.sh" --yes --web --name "$long" </dev/null >/dev/null
check "web: preferences under 1,500 characters, even with a 42-character name" python3 -c "import sys; n=len(open(sys.argv[1], encoding='utf-8').read()); print(f'  {n} chars'); sys.exit(0 if n <= 1500 else 1)" "$H2/.claude/.claude-code-setup/web/preferences.md"
check "web: preferences keep the 4 core rules" bash -c "grep -q '^1. Line 1 is the answer' '$W/preferences.md' && grep -q '^4. The last section is always \*\*Actionables\*\*' '$W/preferences.md'"
for f in preferences style project-instructions; do
  check "web $f: no Claude Code-only terms" bash -c "! grep -qiE 'claude code|subagent|\\btools?\\b|terminal|\\bfiles?\\b|file path|CLAUDE\\.md|output.style|slash command|npm|shell' '$REPO/web/$f.md'"
done
check "web: project instructions = style + one intro line" bash -c "diff <(tail -n +3 '$REPO/web/project-instructions.md') '$REPO/web/style.md' >/dev/null"
check "web: style ends with Actionables reminder" bash -c "tail -1 '$REPO/web/style.md' | grep -q 'last section is Actionables'"
H3="$WORK/h-webdry"; mkdir -p "$H3"; rm -f "$WORK/clipboard.txt"
HOME="$H3" PATH="$WCLIP:$PATH" "$REPO/tests/setup-flags.sh" --yes --web --dry-run </dev/null >/dev/null
check "web --dry-run: nothing written, clipboard untouched" bash -c "test -z \"\$(find '$H3' -mindepth 1 -print -quit)\" && test ! -e '$WORK/clipboard.txt'"
NOCLIP="$WORK/noclip"; mkdir -p "$NOCLIP"; ln -sf "$(command -v python3)" "$NOCLIP/python3"
H4="$WORK/h-webnoclip"; mkdir -p "$H4"
if [[ -x /usr/bin/pbcopy ]]; then
  echo "○ web: no-clipboard case skipped (/usr/bin/pbcopy exists, and the test must not touch your clipboard)"
else
  rc=0; out="$(HOME="$H4" PATH="$NOCLIP:/usr/bin:/bin" "$REPO/tests/setup-flags.sh" --yes --web </dev/null 2>&1)" || rc=$?
  check "web: no clipboard tool is a warning, not a failure" bash -c "test $rc = 0 && grep -q 'no clipboard tool' <<<\"\$1\"" _ "$out"
fi
HOME="$H" "$REPO/uninstall.sh" >/dev/null
check "web: uninstall removes the rendered text" test ! -e "$W"
check "web: uninstall leaves no files" test -z "$(find "$H" -type f -print -quit)"
H5="$WORK/h-weball"; mkdir -p "$H5"; WALL="$WORK/weball-stubs"; mkdir -p "$WALL"
ln -sf "$(command -v python3)" "$WALL/python3"
for c in brew; do printf '#!/bin/sh
exit 0
' >"$WALL/$c"; chmod +x "$WALL/$c"; done
printf '#!/bin/sh
echo "9.9.9 (Claude Code)"
' >"$WALL/claude"; chmod +x "$WALL/claude"
HOME="$H5" PATH="$WCLIP:$WALL:/usr/bin:/bin" SETUP_CLAUDE_BIN="$FAKE" "$REPO/setup.sh" </dev/null >/dev/null 2>&1 || true
check "web: included in the plain run" test -f "$H5/.claude/.claude-code-setup/web/style.md"
