#!/usr/bin/env python3
"""Compute worked hours for a day from Claude Code transcripts.

Usage:
  python3 workday-hours.py [YYYY-MM-DD] [--prefix PATH] [--gap MINUTES]

  YYYY-MM-DD     day to count, default today in local time
  --prefix PATH  only count projects whose working directory is under PATH
                 (for example ~/work). Default: every project.
  --gap MIN      split activity blocks on gaps longer than this, default 20

Every message in a transcript has a timestamp. The script collects the
timestamps from that day across all sessions, merges them into one timeline
(so parallel sessions never double count) and splits it into blocks on gaps.
Projects live in $CLAUDE_CONFIG_DIR/projects, else ~/.claude/projects.
"""
import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone


def encode(path):
    """Claude Code names a project folder after its path, non-alphanumerics -> '-'."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(os.path.expanduser(path)))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Worked hours from Claude Code transcripts")
    ap.add_argument("date", nargs="?", default=datetime.now().astimezone().date().isoformat())
    ap.add_argument("--prefix", help="only count projects under this directory")
    ap.add_argument("--gap", type=float, default=20, help="minutes of quiet that end a block")
    args = ap.parse_args(argv)

    try:
        datetime.strptime(args.date, "%Y-%m-%d")
    except ValueError:
        print(f"Bad date '{args.date}', expected YYYY-MM-DD.", file=sys.stderr)
        return 2

    config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    root = os.path.join(config, "projects")
    if not os.path.isdir(root):
        print(f"No transcripts folder at {root}.", file=sys.stderr)
        return 1

    want = encode(args.prefix) if args.prefix else None
    projects = [os.path.join(root, d) for d in sorted(os.listdir(root))
                if os.path.isdir(os.path.join(root, d)) and (want is None or d.startswith(want))]

    stamps = set()
    for path in (f for d in projects for f in glob.glob(os.path.join(d, "*.jsonl"))):
        try:
            with open(path, "r", errors="replace") as fh:
                for line in fh:
                    if '"timestamp"' not in line:
                        continue
                    try:
                        ts = json.loads(line).get("timestamp")
                        dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
                    except (ValueError, AttributeError, TypeError):
                        continue
                    if dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    local = dt.astimezone()
                    if local.date().isoformat() == args.date:
                        stamps.add(local.replace(microsecond=0))
        except OSError:
            continue

    if not stamps:
        print(f"No transcript activity found for {args.date}.")
        return 1

    gap = timedelta(minutes=args.gap)
    ts = sorted(stamps)
    blocks, start, prev = [], ts[0], ts[0]
    for t in ts[1:]:
        if t - prev > gap:
            blocks.append((start, prev))
            start = t
        prev = t
    blocks.append((start, prev))

    total = timedelta()
    print(f"Date: {args.date}   events: {len(ts)}   projects scanned: {len(projects)}")
    print(f"Blocks (local time, split on gaps over {args.gap:g} min):")
    for a, b in blocks:
        total += b - a
        print(f"  {a:%H:%M} -> {b:%H:%M}   {(b - a).total_seconds() / 3600:.2f} h")
    active = total.total_seconds() / 3600
    wall = (ts[-1] - ts[0]).total_seconds() / 3600
    print(f"ACTIVE {active:.2f} h   WALL {wall:.2f} h")
    print(f"SUGGEST {max(0.25, round(active * 4) / 4):.2f} h  (nearest quarter hour)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
