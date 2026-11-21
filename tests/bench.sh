# Bench harness tests with a stub claude. Makes zero real model calls. Sourced by run-tests.sh.
BFAKE="$REPO/tests/fakes/bench-claude"
for iso in config-dir flags; do
  OUTB="$WORK/bench-$iso"; export FAKE_LOG="$WORK/bench-$iso.log"; : >"$FAKE_LOG"
  "$REPO/bench/run.sh" --model stub-model --runs 2 --yes --claude "$BFAKE" --isolation "$iso" --out "$OUTB" >"$WORK/bench-$iso.out" 2>&1 || true
  check "bench $iso: probe passes" grep -q 'arm A sees the format: False, arm B sees it: True' "$WORK/bench-$iso.out"
  check "bench $iso: 48 results saved" test "$(find "$OUTB" -path '*/[AB]/*.json' | wc -l | tr -d ' ')" = 48
  check "bench $iso: model recorded" grep -q '"model": "stub-model"' "$OUTB/A/build-1-r1.json"
  check "bench $iso: only the stub was called (50 calls)" test "$(wc -l <"$FAKE_LOG" | tr -d ' ')" = 50
done
check "bench flags mode passes --setting-sources" grep -q 'setting-sources' "$WORK/bench-flags.log"
python3 "$REPO/bench/score.py" "$WORK/bench-config-dir" --judge --claude "$BFAKE" >"$WORK/score.out" || true
check "score writes summary.md" test -s "$WORK/bench-config-dir/summary.md"
check "score: B reaches the action sooner" python3 -c "
import json,sys; s=json.load(open(sys.argv[1]))['summary']['arms']
sys.exit(0 if s['B']['words_to_action']['mean'] < s['A']['words_to_action']['mean'] else 1)" "$WORK/bench-config-dir/summary.json"
check "score: skim judge scored" grep -q '40-word skim judge' "$WORK/score.out"
before="$(wc -l <"$FAKE_LOG")"
"$REPO/bench/run.sh" --model stub-model --runs 2 --yes --claude "$BFAKE" --isolation flags --out "$WORK/bench-flags" >/dev/null 2>&1 || true
check "bench re-run keeps finished results (probe only)" test "$(( $(wc -l <"$FAKE_LOG") - before ))" = 2
check "bench without --model refuses" bash -c "! '$REPO/bench/run.sh' --claude '$BFAKE' --yes >/dev/null 2>&1"
