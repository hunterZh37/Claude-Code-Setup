#!/usr/bin/env python3
"""Score bench results: python3 bench/score.py RESULTS_DIR [--judge] [--claude BIN] [--model M]

Per reply (all deterministic unless --judge):
  words                 total words
  words_to_answer       words before the first line that answers the task (key "answer")
  words_to_action       words before the first line naming the user's required action
  fact                  the planted fact is surfaced anywhere (key "fact")
  action_last           the required action appears in the final section
  skim                  fact and action both appear in the first 40 words
  skim_judge            (--judge) a separate `claude -p` reads only the first 40 words and
                        says what happened and what to do, scored against the key
Writes RESULTS_DIR/summary.json and RESULTS_DIR/summary.md.
"""
import argparse
import glob
import json
import os
import re
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKIM_WORDS = 40


def words(text):
    return text.split()


def matches(text, groups):
    t = text.lower()
    return any(all(w.lower() in t for w in g) for g in groups or [])


def words_before(text, groups):
    """Words before the first sentence or line matching a keyword group, or None.
    Splitting on sentences too keeps a one-paragraph reply from scoring 0."""
    if not groups:
        return None
    count = 0
    for piece in re.split(r"(?<=[.!?])\s+|\n", text):
        if matches(piece, groups):
            return count
        count += len(piece.split())
    return None


def final_section(text):
    lines = [ln for ln in text.strip().splitlines()]
    for i in range(len(lines) - 1, -1, -1):
        s = lines[i].strip()
        if s.startswith("#") or (s.startswith("**") and s.rstrip(":*").endswith(("Actionables", "Next steps", "Your action", "Next"))) \
                or re.match(r"^\*\*[^*]+\*\*:?$", s):
            return "\n".join(lines[i:])
    paras = re.split(r"\n\s*\n", text.strip())
    return paras[-1] if paras else ""


def judge(claude_bin, model, task, first):
    prompt = (
        "You see only the first 40 words of an assistant's reply. From them alone, answer in JSON "
        '{"happened": "...", "todo": "..."} with what happened and what the reader must do. '
        'Use "unknown" when the words do not say.\n\nFirst 40 words:\n' + first)
    args = [claude_bin, "-p", "--output-format", "text", "--no-session-persistence", "--tools", ""]
    if model:
        args += ["--model", model]
    r = subprocess.run(args, input=prompt, capture_output=True, text=True, timeout=300)
    m = re.search(r"\{.*\}", r.stdout, re.S)
    try:
        d = json.loads(m.group(0)) if m else {}
    except json.JSONDecodeError:
        d = {}
    said = f"{d.get('happened', '')} {d.get('todo', '')}"
    ok_fact = matches(said, task["fact"])
    ok_action = task["action"] is None or matches(str(d.get("todo", "")), task["action"])
    return ok_fact and ok_action


def spread(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return {"n": 0, "mean": None, "min": None, "max": None}
    return {"n": len(vals), "mean": round(statistics.mean(vals), 1), "min": min(vals), "max": max(vals)}


def rate(vals):
    vals = [v for v in vals if v is not None]
    return {"n": len(vals), "yes": sum(1 for v in vals if v)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--judge", action="store_true")
    ap.add_argument("--claude", default="claude")
    ap.add_argument("--model", default="")
    a = ap.parse_args()

    tasks = {t["id"]: t for t in json.load(open(os.path.join(HERE, "prompts.json")))["tasks"]}
    rows = []
    for path in sorted(glob.glob(os.path.join(a.results, "[AB]", "*.json"))):
        r = json.load(open(path))
        t = tasks.get(r["id"])
        if not t:
            continue
        text = r["text"] or ""
        first = " ".join(words(text)[:SKIM_WORDS])
        row = {
            "arm": r["arm"], "id": r["id"], "type": t["type"], "run": r["run"], "model": r["model"],
            "words": len(words(text)),
            "words_to_answer": words_before(text, t["answer"]),
            "words_to_action": words_before(text, t["action"]),
            "fact": matches(text, t["fact"]),
            "action_last": None if t["action"] is None else matches(final_section(text), t["action"]),
            "skim": matches(first, t["fact"]) and (t["action"] is None or matches(first, t["action"])),
        }
        if a.judge:
            row["skim_judge"] = judge(a.claude, a.model or r["model"], t, first)
        rows.append(row)
    if not rows:
        sys.exit(f"no results in {a.results}")

    def summarize(sel):
        out = {
            "words": spread([r["words"] for r in sel]),
            "words_to_answer": spread([r["words_to_answer"] for r in sel]),
            "answer_not_found": sum(1 for r in sel if r["words_to_answer"] is None),
            "words_to_action": spread([r["words_to_action"] for r in sel]),
            "action_not_found": sum(1 for r in sel if tasks[r["id"]]["action"] and r["words_to_action"] is None),
            "fact": rate([r["fact"] for r in sel]),
            "action_last": rate([r["action_last"] for r in sel]),
            "skim": rate([r["skim"] for r in sel]),
        }
        if a.judge:
            out["skim_judge"] = rate([r.get("skim_judge") for r in sel])
        return out

    summary = {"runs": len(rows), "models": sorted({r["model"] for r in rows}), "arms": {}, "by_type": {},
               "consistency": {}}
    for arm in ("A", "B"):
        sel = [r for r in rows if r["arm"] == arm]
        summary["arms"][arm] = summarize(sel)
        summary["by_type"][arm] = {ty: summarize([r for r in sel if r["type"] == ty])
                                   for ty in sorted({r["type"] for r in sel})}
        cvs, agree = [], []
        for tid in sorted({r["id"] for r in sel}):
            runs = [r for r in sel if r["id"] == tid]
            w = [r["words"] for r in runs]
            if len(w) > 1 and statistics.mean(w):
                cvs.append(statistics.pstdev(w) / statistics.mean(w))
            agree.append(len({r["fact"] for r in runs}) == 1)
        summary["consistency"][arm] = {
            "word_count_cv_mean": round(statistics.mean(cvs), 2) if cvs else None,
            "tasks_with_same_fact_result_every_run": f"{sum(agree)}/{len(agree)}"}

    with open(os.path.join(a.results, "summary.json"), "w") as fh:
        json.dump({"summary": summary, "rows": rows}, fh, indent=1)

    def fmt_spread(s):
        return "n/a" if s["mean"] is None else f"{s['mean']} ({s['min']}–{s['max']}), n={s['n']}"

    def fmt_rate(s):
        return f"{s['yes']}/{s['n']}"

    lines = ["# Bench summary", "", f"Runs: {summary['runs']}. Models: {', '.join(summary['models'])}.", "",
             "| Metric | A: default | B: Claude-Code-Setup |", "|---|---|---|"]
    A, B = summary["arms"]["A"], summary["arms"]["B"]
    for key, label in (("words", "Total words, mean (min–max)"), ("words_to_answer", "Words before the answer"),
                       ("words_to_action", "Words before your action")):
        lines.append(f"| {label} | {fmt_spread(A[key])} | {fmt_spread(B[key])} |")
    lines.append(f"| Answer not found | {A['answer_not_found']} | {B['answer_not_found']} |")
    lines.append(f"| Action not found | {A['action_not_found']} | {B['action_not_found']} |")
    for key, label in (("fact", "Planted fact surfaced"), ("action_last", "Action in the final section"),
                       ("skim", "Fact + action in first 40 words"), ("skim_judge", "40-word skim judge")):
        if key in A:
            lines.append(f"| {label} | {fmt_rate(A[key])} | {fmt_rate(B[key])} |")
    cA, cB = summary["consistency"]["A"], summary["consistency"]["B"]
    lines.append(f"| Word-count spread across runs (CV, lower is steadier) | {cA['word_count_cv_mean']} | {cB['word_count_cv_mean']} |")
    lines.append(f"| Tasks with the same fact result every run | {cA['tasks_with_same_fact_result_every_run']} | "
                 f"{cB['tasks_with_same_fact_result_every_run']} |")
    lines += ["", "## By task type", "", "| Type | Arm | Words | Words before action | Fact | Skim |", "|---|---|---|---|---|---|"]
    for ty in sorted(summary["by_type"]["A"]):
        for arm in ("A", "B"):
            s = summary["by_type"][arm].get(ty)
            if s:
                lines.append(f"| {ty} | {arm} | {fmt_spread(s['words'])} | {fmt_spread(s['words_to_action'])} | "
                             f"{fmt_rate(s['fact'])} | {fmt_rate(s['skim'])} |")
    with open(os.path.join(a.results, "summary.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
