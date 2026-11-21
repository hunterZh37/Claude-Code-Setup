#!/usr/bin/env bash
# Undo setup.sh: restore the files it replaced, delete the ones it created,
# remove its block from CLAUDE.md and the settings keys it added.
# Backups (*.bak-<timestamp>) are kept so nothing is lost.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_DIR/.claude-code-setup"
MANIFEST="$STATE_DIR/manifest.tsv"
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

act() { # act "message" command...
  if [[ $DRY -eq 1 ]]; then echo "… would $1"; else "${@:2}"; echo "✓ $1"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -f "$MANIFEST" ]]; then
  while IFS=$'\t' read -r kind path bak; do
    [[ -n "$path" ]] || continue
    label="${path/#$HOME/~}"
    case "$kind" in
      block)
        if [[ -f "$path" ]]; then
          python3 "$REPO_DIR/lib/helpers.py" block-remove "$path" "$TMP/out"
          if [[ ! -s "$TMP/out" && "$bak" == NONE ]]; then
            act "delete $label (setup created it)" rm -f "$path"
          else
            act "remove the setup block from $label" cp "$TMP/out" "$path"
          fi
        fi
        ;;
      file)
        if [[ "$bak" == NONE ]]; then
          if [[ -e "$path" ]]; then act "delete $label (setup created it)" rm -f "$path"; fi
        elif [[ "$bak" == NONE-UNCHANGED ]]; then
          echo "○ left $label (it was already identical before setup)"
        elif [[ -f "$bak" ]]; then
          act "restore $label from ${bak/#$HOME/~}" cp -p "$bak" "$path"
        else
          echo "! backup ${bak/#$HOME/~} is missing, left $label as is"
        fi
        ;;
    esac
  done <"$MANIFEST"
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

act "remove the setup record ${STATE_DIR/#$HOME/~}" rm -rf "$STATE_DIR"
echo "Backups (*.bak-*) were kept. Restart Claude Code to finish."
