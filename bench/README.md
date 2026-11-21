# Bench: compare reply formats

An optional A/B test of what this package changes. It runs the same coding tasks with Claude Code's default replies (arm A) and with this package's format (arm B), then scores how fast each reply gets to the point.

**No results are published yet.** The harness is tested only with a stub `claude` (see `tests/bench.sh`), so it makes zero model calls in CI. Run it yourself to get real numbers.

## Run it

```bash
bench/run.sh --model sonnet --runs 3          # 12 tasks x 3 runs x 2 arms = 72 calls, plus 2 probes
python3 bench/score.py bench/results/<date>   # writes summary.md and summary.json
python3 bench/score.py bench/results/<date> --judge   # adds the 40-word skim judge (72 more calls)
```

It asks before spending anything. Calls use your own `claude` login and plan. Re-running keeps finished results and only retries missing ones.

## The two arms

| | Arm A: default | Arm B: Claude-Code-Setup |
|---|---|---|
| **User CLAUDE.md** | none | the managed block that `./setup.sh` writes |
| **Output style** | none (built-in default) | `adhd-friendly`, set as `outputStyle` |
| **Your own config** | not loaded | not loaded |
| **Model, tools, prompts** | same | same |

**Isolation, `--isolation config-dir` (default):** each arm runs with its own empty `CLAUDE_CONFIG_DIR`. Arm B's folder is filled by setup.sh's format part and nothing else, so your personal `~/.claude` never leaks in. If a fresh config folder asks you to log in, use the flags mode.

**Isolation, `--isolation flags`:** both arms pass `--setting-sources project,local`, which skips user settings. Arm B gets the same files at project level: `.claude/output-styles/adhd-friendly.md`, `.claude/settings.json` with `outputStyle`, and the block as `CLAUDE.md`.

**Probe:** before any task, each arm is asked to quote its formatting instructions. The run stops unless arm A shows none and arm B quotes this format. Both probe replies are saved.

**Every call:** `claude -p --model M --output-format json --no-session-persistence` in a fresh copy of `bench/fixture`, with tools limited to reading, editing and running `pytest` and `./deploy.sh` inside that copy.

## The tasks

`prompts.json` holds 12 tasks in 4 types. The fixture is a tiny shipping-rates service with planted facts a reader must notice.

| Type | Tasks | Planted facts |
|---|---|---|
| **build** | add a function, add a zone, prepare a deploy | a failing `intl` test, a missing `CARRIER_API_KEY` |
| **fix** | fix the failing test, fix deploy, fix a unit bug | the base price, a key you must export, a pounds to kg break |
| **advice** | cache choice, run a migration, test framework | nightly price changes, an irreversible migration |
| **status** | repo state, why deploy fails, what changed | the failing test, the missing key, the breaking change |

## Metrics

| Metric | How |
|---|---|
| **Words before the answer** | words before the first sentence or line with the task's answer keywords |
| **Words before your action** | same, for the action you must take, or "not found" |
| **Planted fact surfaced** | the fact's keywords appear anywhere |
| **Action in the final section** | the action appears in the last headed section, or the last paragraph |
| **Total words** | whitespace split |
| **Skim (keywords)** | fact and action both appear in the first 40 words |
| **Skim (judge)** | with `--judge`, a separate `claude -p` sees only the first 40 words and says what happened and what to do, scored against the key |
| **Consistency** | word-count spread (CV) across runs, and tasks whose fact result is the same every run |

Results are means with min and max, n, and a per-type table. To show one example pair, pick it by a rule fixed before looking, such as run 1 of the task with the median arm A word count.

## Limits

* **Small n.** 12 tasks, a few runs each. Treat differences as directional.
* **Keyword scoring** misses paraphrases. The judge is itself a model.
* **One model per run.** Results may differ on other models.
* **Format, not quality.** It measures where things appear, not whether the code is right.
