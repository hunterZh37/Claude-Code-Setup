#!/usr/bin/env python3
"""Merge keys into Claude Code's settings.json without clobbering, and undo it.

  settings.py merge   --settings FILE --state FILE --patch FILE [--dry-run] [--stamp TS]
  settings.py unmerge --settings FILE --state FILE [--dry-run]

Patch file: {"set": [{"path": ["a", "b"], "value": ..., "force": false}, ...]}
* A missing path is added.
* A path already holding a different value is kept, unless "force" is true.
* Every change is recorded in the state file, so unmerge removes exactly what
  merge added (or puts back the earlier value), and only while the value is
  still the one merge wrote. Keys the user changed later are left alone.
Output lines: ADD, FORCE, KEEP, SAME, REMOVE, RESTORE, SKIP, BACKUP <path>.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime

MISSING = object()


def load(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as fh:
        text = fh.read()
    if not text.strip():
        return default
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        sys.exit(f"error: {path} is not valid JSON ({e}). Fix it or move it aside, then re-run.")


def write_atomic(path, data):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-settings-")
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def get(obj, path):
    for k in path:
        if not isinstance(obj, dict) or k not in obj:
            return MISSING
        obj = obj[k]
    return obj


def dotted(path):
    return ".".join(path)


def merge(a):
    settings = load(a.settings, {})
    if not isinstance(settings, dict):
        sys.exit(f"error: {a.settings} must hold a JSON object.")
    state = load(a.state, {"added": []})
    if not os.path.exists(a.state):
        state["created_file"] = not os.path.exists(a.settings)
    patch = load(a.patch, {"set": []})
    recorded = {tuple(e["path"]) for e in state["added"]}
    changed = False

    for item in patch["set"]:
        path, value, force = item["path"], item["value"], item.get("force", False)
        cur = get(settings, path)
        if cur == value:
            print(f"SAME   {dotted(path)}")
            continue
        if cur is not MISSING and not force:
            print(f"KEEP   {dotted(path)} (yours: {json.dumps(cur)[:60]})")
            continue
        # walk and create parents, remembering the first one we created
        node, created_at = settings, None
        for i, k in enumerate(path[:-1]):
            if not isinstance(node.get(k), dict):
                if k in node:
                    sys.exit(f"error: {dotted(path[:i + 1])} in {a.settings} is not an object.")
                node[k] = {}
                if created_at is None:
                    created_at = i
            node = node[k]
        node[path[-1]] = value
        changed = True
        print(f"{'FORCE ' if cur is not MISSING else 'ADD   '} {dotted(path)}")
        if tuple(path) not in recorded:
            entry = {"path": path, "value": value, "created_at": created_at}
            if cur is not MISSING:
                entry["previous"] = cur
            state["added"].append(entry)
            recorded.add(tuple(path))
        else:
            for e in state["added"]:
                if tuple(e["path"]) == tuple(path):
                    e["value"] = value

    if changed and not a.dry_run:
        if os.path.exists(a.settings):
            bak = f"{a.settings}.bak-{a.stamp}"
            shutil.copy2(a.settings, bak)
            print(f"BACKUP {bak}")
        write_atomic(a.settings, settings)
        write_atomic(a.state, state)
    return 0


def unmerge(a):
    if not os.path.exists(a.state):
        print("SKIP   no settings were recorded by setup")
        return 0
    settings = load(a.settings, {})
    state = load(a.state, {"added": []})
    changed = False
    for e in reversed(state["added"]):
        path = e["path"]
        cur = get(settings, path)
        if cur != e["value"]:
            print(f"SKIP   {dotted(path)} (changed since setup, left as is)")
            continue
        parent = get(settings, path[:-1]) if len(path) > 1 else settings
        if "previous" in e:
            parent[path[-1]] = e["previous"]
            print(f"RESTORE {dotted(path)}")
        else:
            del parent[path[-1]]
            print(f"REMOVE {dotted(path)}")
            # prune parents setup created, if now empty
            if e.get("created_at") is not None:
                for depth in range(len(path) - 1, e["created_at"], -1):
                    sub = get(settings, path[:depth])
                    if sub == {}:
                        holder = get(settings, path[:depth - 1]) if depth > 1 else settings
                        del holder[path[depth - 1]]
        changed = True
    if not a.dry_run:
        if settings == {} and state.get("created_file"):
            if os.path.exists(a.settings):
                os.remove(a.settings)
            print("REMOVE settings.json (setup created it)")
        elif changed:
            write_atomic(a.settings, settings)
        os.remove(a.state)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["merge", "unmerge"])
    ap.add_argument("--settings", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--patch")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--stamp", default=datetime.now().strftime("%Y%m%d-%H%M%S"))
    a = ap.parse_args()
    if a.cmd == "merge":
        if not a.patch:
            sys.exit("error: merge needs --patch")
        return merge(a)
    return unmerge(a)


if __name__ == "__main__":
    sys.exit(main())
