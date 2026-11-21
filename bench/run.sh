#!/usr/bin/env bash
# Optional A/B comparison of reply formats. Arm A: Claude Code defaults. Arm B: only
# this package's --format files. Every task runs in a fresh copy of bench/fixture.
# See bench/README.md. This makes real `claude -p` calls on your own login.
set -euo pipefail

BENCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$BENCH")"
RUNS=3 MODEL="" CLAUDE_BIN="claude" ISOLATION="config-dir" OUT="" ONLY="" YES=0

usage() {
  cat <<'EOF'
Usage: bench/run.sh --model MODEL [options]
  --model M          model alias or id, same for both arms (required)
  --runs N           runs per task per arm (default 3)
  --isolation MODE   config-dir (default): each arm gets its own empty CLAUDE_CONFIG_DIR
                     flags: --setting-sources project,local and project-level files
  --claude PATH      claude binary (default: claude)
  --only ID[,ID]     run only these task ids
  --out DIR          results folder (default bench/results/<date>)
  --yes              skip the "this uses your Claude plan" confirmation
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift ;;
    --runs) RUNS="$2"; shift ;;
    --isolation) ISOLATION="$2"; shift ;;
    --claude) CLAUDE_BIN="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    --yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; echo "✗ unknown option $1" >&2; exit 1 ;;
  esac
  shift
done
[[ -n "$MODEL" ]] || { usage >&2; echo "✗ --model is required so both arms use the same model" >&2; exit 1; }
[[ "$ISOLATION" == config-dir || "$ISOLATION" == flags ]] || { echo "✗ --isolation must be config-dir or flags" >&2; exit 1; }
[[ "$CLAUDE_BIN" == */* && "$CLAUDE_BIN" != /* ]] && CLAUDE_BIN="$PWD/$CLAUDE_BIN"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { echo "✗ $CLAUDE_BIN not found" >&2; exit 1; }
DATE="$(date +%Y-%m-%d)"
OUT="${OUT:-$BENCH/results/$DATE}"

ids="$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["tasks"]; o=sys.argv[2].split(",") if sys.argv[2] else []; print(" ".join(x["id"] for x in t if not o or x["id"] in o))' "$BENCH/prompts.json" "$ONLY")"
n_tasks="$(wc -w <<<"$ids" | tr -d ' ')"
calls=$((n_tasks * RUNS * 2 + 2))
if [[ $YES -eq 0 ]]; then
  read -r -p "This makes $calls real '$CLAUDE_BIN -p' calls on model $MODEL. Continue? [y/N] " ans </dev/tty || ans=""
  [[ "$ans" =~ ^[Yy] ]] || { echo "○ cancelled"; exit 0; }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/A" "$OUT/B"

# ---------- arm setup ----------
# config-dir: A gets an empty config dir, B gets one filled by setup.sh --format.
# flags: both arms skip user settings and memory via --setting-sources, B gets the same
# files at project level (.claude/output-styles, .claude/settings.json, CLAUDE.md).
mkdir -p "$WORK/cfg-A" "$WORK/cfg-B"
CLAUDE_CONFIG_DIR="$WORK/cfg-B" SETUP_NO_TTY=1 "$REPO/setup.sh" --yes --format --name "the user" >/dev/null

workspace() { # workspace arm dir: fresh fixture copy, plus B's project files in flags mode
  rm -rf "$2"; cp -R "$BENCH/fixture" "$2"
  if [[ "$ISOLATION" == flags && "$1" == B ]]; then
    mkdir -p "$2/.claude/output-styles"
    cp "$WORK/cfg-B/output-styles/adhd-friendly.md" "$2/.claude/output-styles/"
    printf '{"outputStyle": "adhd-friendly"}\n' >"$2/.claude/settings.json"
    cp "$WORK/cfg-B/CLAUDE.md" "$2/CLAUDE.md"
  fi
}

ask() { # ask arm workdir prompt -> JSON envelope on stdout
  local arm="$1" dir="$2" prompt="$3" args
  args=(-p --model "$MODEL" --output-format json --no-session-persistence
        --allowedTools "Read,Grep,Glob,Edit,Write,Bash(python3 -m pytest:*),Bash(./deploy.sh:*),Bash(ls:*),Bash(cat:*)")
  if [[ "$ISOLATION" == flags ]]; then
    args+=(--setting-sources project,local)
    (cd "$dir" && "$CLAUDE_BIN" "${args[@]}" "$prompt" </dev/null)
  else
    (cd "$dir" && CLAUDE_CONFIG_DIR="$WORK/cfg-$arm" "$CLAUDE_BIN" "${args[@]}" "$prompt" </dev/null)
  fi
}

save() { # save arm id run envelope_file
  python3 - "$@" "$MODEL" "$DATE" "$ISOLATION" <<'PY'
import json, sys
arm, tid, run, env, out, model, date, iso = sys.argv[1:9]
raw = open(env).read()
try:
    d = json.loads(raw)
    text = d.get("result", "") if isinstance(d, dict) else ""
    used = sorted((d.get("modelUsage") or {}).keys()) if isinstance(d, dict) else []
except json.JSONDecodeError:
    text, used = raw, []
json.dump({"arm": arm, "id": tid, "run": int(run), "model": model, "models_used": used,
           "date": date, "isolation": iso, "text": text}, open(out, "w"), indent=1, ensure_ascii=False)
PY
}

# ---------- probe: A must not see the format, B must ----------
PROBE="Before anything else: do you have any instructions about how to format your replies? If yes, quote the first two of them word for word. If no, reply with exactly NONE."
for arm in A B; do
  workspace "$arm" "$WORK/ws-probe-$arm"
  ask "$arm" "$WORK/ws-probe-$arm" "$PROBE" >"$WORK/probe-$arm.json" || { echo "✗ probe for arm $arm failed. If this is a login prompt, re-run with --isolation flags" >&2; exit 1; }
  save "$arm" probe 0 "$WORK/probe-$arm.json" "$OUT/probe-$arm.json"
done
python3 - "$OUT" <<'PY' || { echo "✗ probe failed: the arms are not isolated as designed. See $OUT/probe-*.json" >&2; exit 1; }
import json, sys
a = json.load(open(f"{sys.argv[1]}/probe-A.json"))["text"]
b = json.load(open(f"{sys.argv[1]}/probe-B.json"))["text"]
marks = ("Actionables", "Line 1", "Recommend:")
ok_a = not any(m in a for m in marks)
ok_b = any(m in b for m in marks)
print(f"probe: arm A sees the format: {not ok_a}, arm B sees it: {ok_b}")
sys.exit(0 if ok_a and ok_b else 1)
PY

# ---------- runs ----------
i=0 total=$((n_tasks * RUNS * 2))
for tid in $ids; do
  prompt="$(python3 -c 'import json,sys; print(next(t["prompt"] for t in json.load(open(sys.argv[1]))["tasks"] if t["id"] == sys.argv[2]))' "$BENCH/prompts.json" "$tid")"
  for run in $(seq 1 "$RUNS"); do
    for arm in A B; do
      i=$((i + 1))
      dest="$OUT/$arm/$tid-r$run.json"
      if [[ -s "$dest" ]]; then echo "○ $i/$total $arm $tid r$run (kept)"; continue; fi
      workspace "$arm" "$WORK/ws"
      if ask "$arm" "$WORK/ws" "$prompt" >"$WORK/env.json"; then
        save "$arm" "$tid" "$run" "$WORK/env.json" "$dest"
        echo "✓ $i/$total $arm $tid r$run"
      else
        echo "✗ $i/$total $arm $tid r$run failed, re-run to retry" >&2
      fi
    done
  done
done
echo "Results in $OUT. Score with: python3 bench/score.py $OUT"
