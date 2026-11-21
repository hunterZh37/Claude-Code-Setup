#!/usr/bin/env bash
# Set up Claude Code with an answer-first reply format, a progress panel and useful tools.
# Safe to re-run: unchanged files are skipped and changed ones are backed up first.
# Re-run under bash if started with sh or zsh.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
[[ "$HOME" == / ]] || HOME="${HOME%/}"  # a trailing slash would break ~ shortening

tilde() { # show a path with ~ for the home folder (literal ~, never re-expanded)
  case "$1" in "$HOME"/*) printf '%s%s' '~' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_DIR/.claude-code-setup"
MANIFEST="$STATE_DIR/manifest.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)"
PROGRESS_MARKETPLACE_REPO="hunterZh37/progress-bar-plugin"

usage() {
  cat <<'EOF'
Usage: ./setup.sh [components] [options]

Components (pick any, or none to be asked one by one):
  --format         adhd-friendly output style + core rules in ~/.claude/CLAUDE.md
  --commands       /worked-hours command + workday-hours.py script
  --plugins        progress-bar plugin (status line + progress panel)
  --extra-plugins  also enable official frontend-design and mattpocock-skills
  --rtk            token-saving command output (needs rtk, installed by you)
  --tools          Brewfile tools (gh, jq, ripgrep, fd, uv, ghostty) + Claude Code
  --migrate        reformat existing CLAUDE.md, AGENTS.md, Cursor/Copilot/Gemini rules
                   to this format (shows a diff and asks before each write)
  --web            paste-ready text for claude.ai (preferences, a Style, Project
                   instructions), copied to the clipboard. Never opens a browser
  --all            format, commands, plugins, rtk, tools and web (not migrate)

Options:
  --name NAME      who reads the replies (default: "the user")
  --yes            accept defaults, never prompt
  --force-style    set outputStyle even if you already chose another one
  --dry-run        show what would change, change nothing
  --no-llm         migrate without a model: add the format block, list conflicts
  --project PATH   also migrate the agent files of this project
  -h, --help       show this help
EOF
}

# ---------- output helpers ----------
say()  { printf '%s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
skip() { printf '○ %s\n' "$*"; }
warn() { printf '! %s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# ---------- args ----------
DO_FORMAT=0 DO_COMMANDS=0 DO_PLUGINS=0 DO_EXTRA=0 DO_RTK=0 DO_TOOLS=0 DO_MIGRATE=0 DO_WEB=0
NAME="" YES=0 DRY=0 FORCE_STYLE=0 CHOSE=0 NO_LLM=0 PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) DO_FORMAT=1; CHOSE=1 ;;
    --commands) DO_COMMANDS=1; CHOSE=1 ;;
    --plugins) DO_PLUGINS=1; CHOSE=1 ;;
    --extra-plugins) DO_PLUGINS=1; DO_EXTRA=1; CHOSE=1 ;;
    --rtk) DO_RTK=1; CHOSE=1 ;;
    --tools) DO_TOOLS=1; CHOSE=1 ;;
    --migrate) DO_MIGRATE=1; CHOSE=1 ;;
    --web) DO_WEB=1; CHOSE=1 ;;
    --no-llm) NO_LLM=1 ;;
    --project) [[ $# -ge 2 ]] || die "--project needs a path"; PROJECT="$2"; shift ;;
    --project=*) PROJECT="${1#--project=}" ;;
    --all) DO_FORMAT=1; DO_COMMANDS=1; DO_PLUGINS=1; DO_RTK=1; DO_TOOLS=1; DO_WEB=1; CHOSE=1 ;;
    --name) [[ $# -ge 2 ]] || die "--name needs a value"; NAME="$2"; shift ;;
    --name=*) NAME="${1#--name=}" ;;
    --yes|-y) YES=1 ;;
    --force-style) FORCE_STYLE=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

# Prompts read from the terminal, so `curl ... | bash` style runs can still ask.
HAVE_TTY=0
if [[ $YES -eq 0 && -z "${SETUP_NO_TTY:-}" ]] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

ask_yn() { # ask_yn "question" default(y|n)
  local q="$1" def="$2" ans hint="[y/N]"
  [[ "$def" == y ]] && hint="[Y/n]"
  if [[ $HAVE_TTY -eq 0 ]]; then [[ "$def" == y ]]; return; fi
  read -r -p "$q $hint " ans </dev/tty || ans=""
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy] ]]
}

ask_strict() { # like ask_yn but a run with no terminal and no --yes always says no
  if [[ $YES -eq 1 ]]; then return 0; fi
  if [[ $HAVE_TTY -eq 0 ]]; then return 1; fi
  ask_yn "$1" "$2"
}

ask_text() { # ask_text "question" default
  local q="$1" def="$2" ans
  if [[ $HAVE_TTY -eq 0 ]]; then printf '%s' "$def"; return; fi
  read -r -p "$q [$def] " ans </dev/tty || ans=""
  printf '%s' "${ans:-$def}"
}

# ---------- prerequisites ----------
command -v python3 >/dev/null 2>&1 || die "python3 is required. macOS: run 'xcode-select --install'. Linux: install python3 with your package manager."
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' || die "python3 3.8 or newer is required."
OS="$(uname -s)"
case "$OS" in Darwin|Linux) ;; *) die "unsupported OS: $OS (macOS and Linux only)" ;; esac

if [[ $CHOSE -eq 0 ]]; then
  if [[ $HAVE_TTY -eq 0 ]]; then
    usage >&2
    die "no components chosen and no terminal to ask. Pass flags such as --format --commands --plugins."
  fi
  say "Choose what to install (Enter accepts the default):"
  ask_yn "  Reply format (output style + CLAUDE.md rules)?" y && DO_FORMAT=1
  ask_yn "  /worked-hours command?" y && DO_COMMANDS=1
  ask_yn "  progress-bar plugin (status line + panel)?" y && DO_PLUGINS=1
  ask_yn "  rtk token saving (you install rtk yourself)?" n && DO_RTK=1
  ask_yn "  CLI tools via Homebrew + Claude Code?" n && DO_TOOLS=1
  ask_yn "  Migrate your existing CLAUDE.md / AGENTS.md / Cursor rules to this format?" n && DO_MIGRATE=1
  ask_yn "  Text to paste into claude.ai so web chats use the format too?" n && DO_WEB=1
fi
if [[ $DO_PLUGINS -eq 1 && $DO_EXTRA -eq 0 ]]; then
  ask_yn "  Also enable official frontend-design and mattpocock-skills plugins?" n && DO_EXTRA=1
fi

if [[ -z "$NAME" && ( $DO_FORMAT -eq 1 || $DO_COMMANDS -eq 1 || $DO_MIGRATE -eq 1 || $DO_WEB -eq 1 ) ]]; then
  NAME="$(ask_text "Name Claude should use for you in replies and rules?" "the user")"
fi
NAME="${NAME:-the user}"
[[ "$NAME" != *$'\n'* ]] || die "--name must be one line"

if [[ -n "$PROJECT" ]]; then
  [[ -d "$PROJECT" ]] || die "--project: no such folder: $PROJECT"
  PROJECT="$(cd "$PROJECT" && pwd)"
  [[ $DO_MIGRATE -eq 1 ]] || warn "--project only matters with --migrate"
fi

[[ $DRY -eq 1 ]] && say "Dry run: nothing will be written."
say "Claude config folder: $CLAUDE_DIR"

# Check settings.json before writing anything, so a bad file stops the run cleanly.
SETTINGS="$CLAUDE_DIR/settings.json"
if [[ $DO_FORMAT -eq 1 || $DO_PLUGINS -eq 1 ]] && [[ -e "$SETTINGS" ]]; then
  [[ -f "$SETTINGS" ]] || die "$SETTINGS is not a regular file. Move it aside, then re-run. Nothing was changed."
  python3 - "$SETTINGS" <<'PY' || die "$SETTINGS cannot be merged (reason above). Comments and trailing commas are not valid JSON. Fix it or move it aside, then re-run. Nothing was changed."
import json, sys
with open(sys.argv[1], encoding="utf-8-sig") as fh:
    text = fh.read()
if text.strip():
    try:
        d = json.loads(text)
    except json.JSONDecodeError as e:
        sys.exit(f"settings.json line {e.lineno}: {e.msg}")
    if not isinstance(d, dict):
        sys.exit("settings.json must hold a JSON object")
    for k in ("enabledPlugins", "extraKnownMarketplaces"):
        if k in d and not isinstance(d[k], dict):
            sys.exit(f"settings.json key {k} must be an object")
PY
  [[ $DRY -eq 1 || -w "$SETTINGS" ]] || die "$SETTINGS is read-only. Make it writable (chmod u+w) or drop --format/--plugins."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
trap 'echo; die "interrupted. Files are written atomically, so none is half-written. Re-run to finish."' INT TERM

# ---------- file install with backup + manifest ----------
helper() { python3 "$REPO_DIR/lib/helpers.py" "$@"; }

record() { # record kind path backup hash  (first record per kind+path wins, used by uninstall)
  [[ $DRY -eq 1 ]] && return 0
  mkdir -p "$STATE_DIR"
  touch "$MANIFEST"
  if ! manifest_has "$2" "$1"; then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:--}" >>"$MANIFEST"
  fi
}

manifest_has() { # manifest_has path [kind]
  [[ -f "$MANIFEST" ]] && awk -F'\t' -v p="$1" -v k="${2:-}" \
    '$2 == p && (k == "" || $1 == k) { found = 1 } END { exit !found }' "$MANIFEST"
}

place() { # place kind rendered_file dest
  local kind="$1" src="$2" dest="$3" bak="NONE" label="$(tilde "$3")"
  if [[ -e "$dest" && ! -f "$dest" ]]; then
    warn "skipped $label: it is not a regular file"
    return 0
  fi
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    skip "$label unchanged"
    record "$kind" "$dest" "NONE-UNCHANGED"
    return 0
  fi
  if [[ $DRY -eq 1 ]]; then
    if [[ -e "$dest" ]]; then
      say "… would back up and update $label:"
      diff -u --label "$label (now)" --label "$label (new)" "$dest" "$src" | sed -n '3,80p' || true
    else
      say "… would create $label"
    fi
    return 0
  fi
  if [[ -e "$dest" && ! -w "$dest" ]]; then
    warn "skipped $label: it is read-only (chmod u+w to let setup change it)"
    return 0
  fi
  mkdir -p "$(dirname "$dest")" || die "cannot create $(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    bak="$dest.bak-$STAMP"
    cp -p "$dest" "$bak" || die "cannot back up $label"
  fi
  record "$kind" "$dest" "$bak" "$(helper hash "$src")"
  helper write "$src" "$dest" || die "cannot write $label"
  if [[ "$bak" == NONE ]]; then ok "created $label"; else ok "updated $label (backup: $(tilde "$bak"))"; fi
}

install_template() { # install_template template dest
  local out
  out="$TMP/$(basename "$2")"
  helper render "$1" "$out" "$NAME"
  place file "$out" "$2"
}

PATCH_ITEMS=()
add_setting() { PATCH_ITEMS+=("$1"); } # one JSON object per item

# ---------- components ----------
RTK_READY=0
if [[ $DO_RTK -eq 1 ]]; then
  say ""; say "rtk (token saving)"
  if command -v rtk >/dev/null 2>&1; then
    install_template "$REPO_DIR/templates/RTK.md" "$CLAUDE_DIR/RTK.md"
    RTK_READY=1
  else
    warn "rtk is not installed, so RTK.md was skipped (it would tell Claude output is condensed when it is not)."
    warn "Install it from https://github.com/rtk-ai/rtk then re-run ./setup.sh --rtk"
  fi
fi

if [[ $DO_FORMAT -eq 1 ]]; then
  say ""; say "Reply format"
  install_template "$REPO_DIR/templates/output-styles/adhd-friendly.md.tmpl" "$CLAUDE_DIR/output-styles/adhd-friendly.md"

  block="$TMP/block.md"
  helper render "$REPO_DIR/templates/CLAUDE.md.tmpl" "$block" "$NAME"
  # Import RTK.md only when this setup installed it (now or on an earlier run).
  if [[ $RTK_READY -eq 1 ]] || { [[ -f "$CLAUDE_DIR/RTK.md" ]] && manifest_has "$CLAUDE_DIR/RTK.md"; }; then
    if ! helper has-outside "$CLAUDE_DIR/CLAUDE.md" "@RTK.md"; then
      printf '\n@RTK.md\n' >>"$block"
    fi
  fi
  if [[ -e "$CLAUDE_DIR/CLAUDE.md" && ! -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
    warn "skipped $(tilde "$CLAUDE_DIR")/CLAUDE.md: it is not a regular file"
  elif helper is-text "$CLAUDE_DIR/CLAUDE.md"; then
    helper block-apply "$CLAUDE_DIR/CLAUDE.md" "$block" "$TMP/CLAUDE.md"
    place block "$TMP/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  else
    warn "skipped $(tilde "$CLAUDE_DIR")/CLAUDE.md: it is not UTF-8 text"
  fi

  style_force=false
  current_style="$(python3 - "$CLAUDE_DIR/settings.json" <<'PY'
import json, os, sys
p = sys.argv[1]
try:
    print((json.load(open(p, encoding="utf-8-sig")).get("outputStyle") or "") if os.path.exists(p) else "")
except Exception:
    print("")
PY
)"
  if [[ -n "$current_style" && "$current_style" != "adhd-friendly" ]]; then
    if [[ $FORCE_STYLE -eq 1 ]] || ask_yn "  outputStyle is already '$current_style'. Switch it to adhd-friendly?" n; then
      style_force=true
    else
      warn "kept your outputStyle '$current_style'. Switch any time with /output-style"
    fi
  fi
  add_setting "{\"path\": [\"outputStyle\"], \"value\": \"adhd-friendly\", \"force\": $style_force}"
fi

if [[ $DO_COMMANDS -eq 1 ]]; then
  say ""; say "Commands"
  install_template "$REPO_DIR/templates/commands/worked-hours.md" "$CLAUDE_DIR/commands/worked-hours.md"
  install_template "$REPO_DIR/templates/scripts/workday-hours.py" "$CLAUDE_DIR/scripts/workday-hours.py"
  if [[ $DRY -eq 0 && -w "$CLAUDE_DIR/scripts/workday-hours.py" ]]; then chmod +x "$CLAUDE_DIR/scripts/workday-hours.py"; fi
fi

if [[ $DO_WEB -eq 1 ]]; then
  say ""; say "Claude on the web (claude.ai and the desktop app)"
  WEB_DIR="$STATE_DIR/web"
  for f in preferences style project-instructions; do
    install_template "$REPO_DIR/web/$f.md" "$WEB_DIR/$f.md"
  done
  clip=""
  for c in pbcopy wl-copy xclip; do
    if command -v "$c" >/dev/null 2>&1; then clip="$c"; break; fi
  done
  if [[ $DRY -eq 1 ]]; then
    say "… would copy the preferences text to the clipboard${clip:+ with $clip}"
  elif [[ -n "$clip" && -f "$WEB_DIR/preferences.md" ]]; then
    case "$clip" in
      xclip) xclip -selection clipboard <"$WEB_DIR/preferences.md" ;;
      *) "$clip" <"$WEB_DIR/preferences.md" ;;
    esac && ok "preferences text copied to the clipboard"
  else
    warn "no clipboard tool found (pbcopy, wl-copy or xclip). Open the file and copy it by hand."
  fi
  WEB_NOTE=1
fi

if [[ $DO_MIGRATE -eq 1 ]]; then
  say ""; say "Migrate existing agent instructions"
  claude_bin="${SETUP_CLAUDE_BIN:-claude}"
  mode=llm
  if [[ $NO_LLM -eq 1 ]]; then
    mode=no-llm
  elif ! command -v "$claude_bin" >/dev/null 2>&1; then
    warn "claude not found, so migrating without a model (--no-llm): block added, conflicts listed"
    mode=no-llm
  fi
  if [[ -z "$PROJECT" && "$PWD" != "$HOME" && "$PWD" != "$REPO_DIR" ]] &&
     python3 "$REPO_DIR/lib/migrate.py" has-project "$PWD" &&
     [[ $HAVE_TTY -eq 1 ]] && ask_yn "  Also migrate the agent files in this project ($PWD)?" n; then
    PROJECT="$PWD"
  fi
  mflags=(--claude-dir "$CLAUDE_DIR" --state-dir "$STATE_DIR" --mode "$mode" --name "$NAME"
          --stamp "$STAMP" --claude-bin "$claude_bin")
  [[ -n "$PROJECT" ]] && mflags+=(--project "$PROJECT")
  [[ $DRY -eq 1 ]] && mflags+=(--dry-run)
  [[ $YES -eq 1 ]] && mflags+=(--yes)
  [[ $HAVE_TTY -eq 1 ]] && mflags+=(--tty)
  python3 "$REPO_DIR/lib/migrate.py" run "${mflags[@]}" || die "migrate failed (files written so far have backups and are in the manifest)"
fi

if [[ $DO_PLUGINS -eq 1 ]]; then
  add_setting "{\"path\": [\"extraKnownMarketplaces\", \"progress-bar\"], \"value\": {\"source\": {\"source\": \"github\", \"repo\": \"$PROGRESS_MARKETPLACE_REPO\"}}}"
  add_setting '{"path": ["enabledPlugins", "progress-bar@progress-bar"], "value": true}'
  if [[ $DO_EXTRA -eq 1 ]]; then
    add_setting '{"path": ["enabledPlugins", "frontend-design@claude-plugins-official"], "value": true}'
    add_setting '{"path": ["enabledPlugins", "mattpocock-skills@claude-plugins-official"], "value": true}'
  fi
fi

if [[ ${#PATCH_ITEMS[@]} -gt 0 ]]; then
  say ""; say "Settings (merged into $(tilde "$CLAUDE_DIR")/settings.json, your keys are kept)"
  patch="$TMP/patch.json"
  { printf '{"set": ['; (IFS=,; printf '%s' "${PATCH_ITEMS[*]}"); printf ']}\n'; } >"$patch"
  dry_flag=()
  [[ $DRY -eq 1 ]] && dry_flag=(--dry-run)
  [[ $DRY -eq 1 ]] || mkdir -p "$STATE_DIR"
  python3 "$REPO_DIR/lib/settings.py" merge --settings "$CLAUDE_DIR/settings.json" \
    --state "$STATE_DIR/settings-state.json" --patch "$patch" --stamp "$STAMP" ${dry_flag[@]+"${dry_flag[@]}"} |
    while IFS= read -r line; do
      rest="${line#* }"; rest="${rest#"${rest%%[! ]*}"}"  # text after the tag
      case "$line" in
        ADD*|FORCE*) if [[ $DRY -eq 1 ]]; then say "… would set $rest"; else ok "set $rest"; fi ;;
        SAME*) skip "$rest already set" ;;
        KEEP*) [[ "$rest" == outputStyle* ]] || warn "kept your $rest" ;;
        BACKUP*) ok "backup: $(tilde "$rest")" ;;
        *) say "$line" ;;
      esac
    done
fi

TOOLS_NOTE=""
WEB_NOTE="${WEB_NOTE:-0}"
if [[ $DO_TOOLS -eq 1 ]]; then
  say ""; say "Tools"
  if command -v brew >/dev/null 2>&1; then
    if [[ "$OS" == Darwin ]]; then
      if [[ $DRY -eq 1 ]]; then say "… would run: brew bundle --file $REPO_DIR/Brewfile"
      else brew bundle --file "$REPO_DIR/Brewfile" && ok "Brewfile tools installed"; fi
    else
      if [[ $DRY -eq 1 ]]; then say "… would run: brew install gh jq ripgrep fd uv"
      else brew install gh jq ripgrep fd uv && ok "CLI tools installed (ghostty is macOS-only here, see https://ghostty.org)"; fi
    fi
  else
    warn "Homebrew not found. Install it from https://brew.sh then re-run ./setup.sh --tools"
    [[ "$OS" == Linux ]] && warn "Or use your package manager, e.g. sudo apt install gh jq ripgrep fd-find, and uv from https://docs.astral.sh/uv/"
    TOOLS_NOTE="Homebrew missing"
  fi
  if command -v claude >/dev/null 2>&1; then
    skip "Claude Code already installed ($(claude --version 2>/dev/null | head -1))"
  elif [[ $DRY -eq 1 ]]; then
    say "… would offer the official installer: curl -fsSL https://claude.ai/install.sh | bash"
  elif ask_strict "  Install Claude Code with the official installer (https://claude.ai/install.sh)?" y; then
    curl -fsSL https://claude.ai/install.sh | bash && ok "Claude Code installed"
  else
    warn "Claude Code not installed (needs a yes or --yes). See https://code.claude.com/docs/en/setup"
  fi
fi

# ---------- checklist ----------
say ""
say "Next steps (only you can do these)"
command -v claude >/dev/null 2>&1 || say "! Install Claude Code: https://code.claude.com/docs/en/setup"
say "! Sign in: run 'claude' and follow the login prompt (~1 min)"
command -v gh >/dev/null 2>&1 && say "! GitHub CLI: run 'gh auth login' (~1 min)"
say "! Claude in Chrome (optional): install the extension from https://claude.ai/chrome (~2 min)"
if [[ $DO_RTK -eq 1 ]]; then
  if [[ $RTK_READY -eq 1 ]]; then say "! rtk: run 'rtk init -g' to add its hook, then re-run './setup.sh --rtk --format' (~1 min)"
  else say "! rtk: install from https://github.com/rtk-ai/rtk, run 'rtk init -g', then './setup.sh --rtk --format'"; fi
fi
[[ $DO_PLUGINS -eq 1 ]] && say "! Plugins: on first start, accept the progress-bar marketplace prompt, or run '/plugin install progress-bar@progress-bar'"
if [[ "$WEB_NOTE" == 1 ]]; then
  say "! claude.ai, every chat: open Settings, find the profile preferences box, paste (the text is on your clipboard): $(tilde "$WEB_DIR/preferences.md")"
  say "! claude.ai, a Style you can switch on: create a custom Style from the Styles menu and paste $(tilde "$WEB_DIR/style.md")"
  say "! claude.ai, one Project: open the Project, edit its instructions, paste $(tilde "$WEB_DIR/project-instructions.md")"
  say "  (menu names on claude.ai may change. Nothing here opens a browser or signs in for you.)"
fi
say "! Restart Claude Code so the output style and plugins load"
[[ $DO_FORMAT -eq 1 ]] && say "! Verify: run '/output-style' in Claude Code and check adhd-friendly is selected"
if [[ $DO_MIGRATE -eq 1 ]]; then
  say "! Migrate: fix any conflicting lines listed above by hand, or re-run with the model (drop --no-llm)"
  [[ -f "$CLAUDE_DIR/output-styles/adhd-friendly.md" ]] || say "! Migrate: the rules point to the adhd-friendly output style. Install it with './setup.sh --format'"
fi
[[ -n "$TOOLS_NOTE" ]] && say "! Tools skipped: $TOOLS_NOTE"
[[ $DRY -eq 1 ]] && say "(dry run: nothing was written)"
say "Undo everything: ./uninstall.sh"
