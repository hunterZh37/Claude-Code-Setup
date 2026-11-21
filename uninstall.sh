#!/usr/bin/env bash
# Undo setup.sh: restore the files it replaced or migrated, delete the ones it created,
# remove its block from CLAUDE.md and the settings keys it added.
# Backups (*.bak-<timestamp>) are kept so nothing is lost. A file you edited after
# setup is saved as <file>.bak-uninstall-<timestamp> before it is restored or deleted.
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
DRY=0

case "${1:-}" in
  --dry-run) DRY=1 ;;
  -h|--help) echo "Usage: ./uninstall.sh [--dry-run]"; exit 0 ;;
  "") ;;
  *) echo "✗ unknown option: $1" >&2; exit 1 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "✗ python3 is required" >&2; exit 1; }
if [[ ! -d "$STATE_DIR" ]]; then
  echo "○ Nothing to undo: no setup record in $STATE_DIR"
  exit 0
fi

helper() { python3 "$REPO_DIR/lib/helpers.py" "$@"; }

act() { # act "message" command...
  if [[ $DRY -eq 1 ]]; then echo "… would $1"; else "${@:2}"; echo "✓ $1"; fi
}

keep_edits() { # keep_edits path installed_hash: save the file if it changed since setup wrote it
  local path="$1" want="$2"
  [[ -f "$path" && -n "$want" && "$want" != "-" ]] || return 0
  if [[ "$(helper hash "$path")" != "$want" ]]; then
    act "save your edits to $(tilde "$path").bak-uninstall-$STAMP" cp -p "$path" "$path.bak-uninstall-$STAMP"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -f "$MANIFEST" ]]; then
  # Newest entries first, so a file touched twice ends at its original state.
  awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) print line[i] }' "$MANIFEST" >"$TMP/manifest"
  while IFS=$'\t' read -r kind path bak hash; do
    [[ -n "${path:-}" ]] || continue
    hash="${hash:--}"
    label="$(tilde "$path")"
    case "$kind" in
      block)
        if [[ -f "$path" ]]; then
          helper block-remove "$path" "$TMP/out"
          if [[ ! -s "$TMP/out" && "$bak" == NONE ]]; then
            act "delete $label (setup created it)" rm -f "$path"
          elif ! cmp -s "$TMP/out" "$path"; then
            act "remove the setup block from $label" helper write "$TMP/out" "$path"
          fi
        fi
        ;;
      file|migrate)
        if [[ "$bak" == NONE ]]; then
          if [[ -e "$path" ]]; then
            keep_edits "$path" "$hash"
            act "delete $label (setup created it)" rm -f "$path"
          fi
        elif [[ "$bak" == NONE-UNCHANGED ]]; then
          echo "○ left $label (it was already identical before setup)"
        elif [[ -f "$bak" ]]; then
          keep_edits "$path" "$hash"
          act "restore $label from $(tilde "$bak")" helper write "$bak" "$path"
        else
          echo "! backup $(tilde "$bak") is missing, left $label as is"
        fi
        ;;
    esac
  done <"$TMP/manifest"
else
  echo "! no file record in $STATE_DIR, only settings will be undone"
fi

if [[ -f "$STATE_DIR/settings-state.json" ]]; then
  dry_flag=()
  [[ $DRY -eq 1 ]] && dry_flag=(--dry-run)
  python3 "$REPO_DIR/lib/settings.py" unmerge --settings "$CLAUDE_DIR/settings.json" \
    --state "$STATE_DIR/settings-state.json" ${dry_flag[@]+"${dry_flag[@]}"} |
    while IFS= read -r line; do
      case "$line" in
        REMOVE*|RESTORE*) if [[ $DRY -eq 1 ]]; then echo "… would ${line}"; else echo "✓ settings: ${line}"; fi ;;
        *) echo "○ settings: ${line}" ;;
      esac
    done
fi

act "remove the setup record $(tilde "$STATE_DIR")" rm -rf "$STATE_DIR"
echo "Backups (*.bak-*) were kept. Restart Claude Code to finish."
