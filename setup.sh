#!/usr/bin/env bash
# Set up Claude Code with an adhd-friendly reply format and a progress panel. Run: ./setup.sh
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

# ---------- output helpers ----------
say()  { printf '%s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
skip() { printf '○ %s\n' "$*"; }
warn() { printf '! %s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# ---------- options ----------
# setup.sh takes no flags: a plain run sets up everything. The SETUP_* variables below
# are hooks for the plugin's /adhd-friendly:setup command and for tests/, not for users.
on() { case "${1:-}" in ""|0|false|no|off) return 1 ;; *) return 0 ;; esac; }
[[ $# -eq 0 ]] || die "setup.sh takes no options. Run it as: ./setup.sh"
DO_FORMAT=1 DO_PLUGINS=1 DO_MIGRATE=1 DO_WEB=1
if [[ -n "${SETUP_ONLY:-}" ]]; then  # tests: install only these parts
  DO_FORMAT=0 DO_PLUGINS=0 DO_MIGRATE=0 DO_WEB=0
  read -r -a parts <<<"${SETUP_ONLY//,/ }"
  [[ ${#parts[@]} -gt 0 ]] || die "SETUP_ONLY is empty"
  for part in "${parts[@]}"; do
    case "$part" in
      format) DO_FORMAT=1 ;; plugins) DO_PLUGINS=1 ;; migrate) DO_MIGRATE=1 ;; web) DO_WEB=1 ;;
      *) die "SETUP_ONLY: unknown part: $part" ;;
    esac
  done
fi
NAME="${SETUP_NAME:-}" PROJECT="${SETUP_PROJECT:-}"
YES=0 DRY=0 FORCE_STYLE=0 NO_LLM=0
on "${SETUP_YES:-}" && YES=1
on "${SETUP_DRY_RUN:-}" && DRY=1
on "${SETUP_FORCE_STYLE:-}" && FORCE_STYLE=1
on "${SETUP_NO_LLM:-}" && NO_LLM=1

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

if [[ -z "$NAME" && ( $DO_FORMAT -eq 1 || $DO_MIGRATE -eq 1 || $DO_WEB -eq 1 ) ]]; then
  # A re-run keeps the name from the installed block, so it never resets to "the user".
  prev_name="$(awk '/claude-code-setup:begin/ {b=1; next} b && /^# Replies to / {sub(/^# Replies to /, ""); sub(/\r$/, ""); print; exit}' \
    "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null || true)"
  NAME="$(ask_text "Name Claude should use for you in replies and rules?" "${prev_name:-the user}")"
fi
NAME="${NAME:-the user}"
[[ "$NAME" != *$'\n'* ]] || die "the name must be one line"

if [[ -n "$PROJECT" ]]; then
  [[ -d "$PROJECT" ]] || die "SETUP_PROJECT: no such folder: $PROJECT"
  PROJECT="$(cd "$PROJECT" && pwd)"
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
  [[ $DRY -eq 1 || -w "$SETTINGS" ]] || die "$SETTINGS is read-only. Make it writable (chmod u+w)."
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
if [[ $DO_FORMAT -eq 1 ]]; then
  say ""; say "Reply format"
  install_template "$REPO_DIR/templates/output-styles/adhd-friendly.md.tmpl" "$CLAUDE_DIR/output-styles/adhd-friendly.md"

  block="$TMP/block.md"
  helper render "$REPO_DIR/templates/CLAUDE.md.tmpl" "$block" "$NAME"
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
    warn "claude not found, so migrating without a model: block added, conflicts listed"
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

WEB_NOTE="${WEB_NOTE:-0}"

# ---------- checklist ----------
say ""
say "Next steps (only you can do these)"
command -v claude >/dev/null 2>&1 || say "! Install Claude Code: https://code.claude.com/docs/en/setup"
say "! Sign in: run 'claude' and follow the login prompt (~1 min)"
say "! Claude in Chrome (optional): install the extension from https://claude.ai/chrome (~2 min)"
[[ $DO_PLUGINS -eq 1 ]] && say "! Plugins: on first start, accept the progress-bar marketplace prompt, or run '/plugin install progress-bar@progress-bar'"
if [[ "$WEB_NOTE" == 1 ]]; then
  say "! claude.ai, every chat: open Settings, Your Claude, the Instructions box, paste (the text is on your clipboard): $(tilde "$WEB_DIR/preferences.md")"
  say "! claude.ai, a Style you can switch on: create a custom Style from the Styles menu and paste $(tilde "$WEB_DIR/style.md")"
  say "! claude.ai, one Project: open the Project, edit its instructions, paste $(tilde "$WEB_DIR/project-instructions.md")"
  say "  (menu names on claude.ai may change. Nothing here opens a browser or signs in for you.)"
fi
say "! Restart Claude Code so the output style and plugins load"
[[ $DO_FORMAT -eq 1 ]] && say "! Verify: run '/output-style' in Claude Code and check adhd-friendly is selected"
if [[ $DO_MIGRATE -eq 1 ]]; then
  say "! Migrate: fix any conflicting lines listed above by hand, or re-run './setup.sh' with claude installed so a model can rewrite them"
  [[ -f "$CLAUDE_DIR/output-styles/adhd-friendly.md" ]] || say "! Migrate: the rules point to the adhd-friendly output style. Install it with './setup.sh'"
fi
[[ $DRY -eq 1 ]] && say "(dry run: nothing was written)"
say "Undo everything: ./uninstall.sh"
