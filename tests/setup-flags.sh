#!/usr/bin/env bash
# Test-only shim: turns the old setup.sh flags into the SETUP_* hooks, then runs the
# setup.sh next to tests/. setup.sh itself takes no flags. Uses only bash builtins, so
# it works with a PATH that lacks python3 or coreutils.
only="" args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format|--plugins|--migrate|--web) only+="${1#--} " ;;
    --yes) export SETUP_YES=1 ;;
    --dry-run) export SETUP_DRY_RUN=1 ;;
    --force-style) export SETUP_FORCE_STYLE=1 ;;
    --no-llm) export SETUP_NO_LLM=1 ;;
    --name) export SETUP_NAME="$2"; shift ;;
    --project) export SETUP_PROJECT="$2"; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
[[ -n "$only" ]] && export SETUP_ONLY="$only"
here="${BASH_SOURCE[0]%/*}"
exec "${BASH:-bash}" "$here/../setup.sh" ${args[@]+"${args[@]}"}
